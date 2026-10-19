#if DEBUG
import XCTest
import JavaScriptCore
import WebKit
@testable import CodexTime

final class GrokWebTrialTests: XCTestCase {
    func testUsageURLGateAcceptsOnlyOfficialUsageRoute() {
        XCTAssertTrue(GrokWebTrialModel.isEligibleUsageURL(URL(string: "https://grok.com/?_s=usage")))
        XCTAssertTrue(GrokWebTrialModel.isEligibleUsageURL(URL(string: "https://grok.com:443/?_s=usage")))
    }

    func testUsageURLGateRejectsLoginConversationAndExternalPages() {
        for value in ["https://grok.com/login?_s=usage", "https://grok.com/chat/123?_s=usage",
                      "https://accounts.x.ai/?_s=usage", "https://grok.com.example/?_s=usage",
                      "http://grok.com/?_s=usage"] {
            XCTAssertFalse(GrokWebTrialModel.isEligibleUsageURL(URL(string: value)))
        }
    }

    func testUsageURLGateRejectsAmbiguousAndNonstandardURLs() {
        XCTAssertFalse(GrokWebTrialModel.isEligibleUsageURL(nil))
        for value in ["https://grok.com/", "https://grok.com/?_s=login", "https://grok.com/?_s=usage&_s=login",
                      "https://grok.com/?_s=usage&code=placeholder", "https://grok.com/?_s=usage#login",
                      "https://example@grok.com/?_s=usage", "https://grok.com:8443/?_s=usage"] {
            XCTAssertFalse(GrokWebTrialModel.isEligibleUsageURL(URL(string: value)))
        }
    }
    @MainActor
    func testManualSelectionReturnsOnlySinglePercentAndStatus() throws {
        for (selected, expected) in [("0%", 0.0), ("67%", 67.0), ("100%", 100.0), (" 7% ", 7.0), ("12.34%", 12.34), ("100.00%", 100.0)] {
            let context = try selectionFixture(selected: selected)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.manualSelectionScript)?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "percent"]))
            XCTAssertEqual(result["status"] as? String, "ok")
            XCTAssertEqual(result["percent"] as? Double, expected)
        }
    }

    @MainActor
    func testManualSelectionRejectsNonPercentAndOutOfRangeWithoutReturningText() throws {
        for selected in ["101%", "99.555%", "100.01%", "67% 2%", "67% text", "email", "001%", "long fixture text"] {
            let context = try selectionFixture(selected: selected)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.manualSelectionScript)?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "reason"]))
            XCTAssertEqual(result["status"] as? String, "unsupported")
            let code = try XCTUnwrap(result["reason"] as? String)
            XCTAssertNotNil(GrokTrialReadFailure(rawValue: code))
        }
        XCTAssertEqual(GrokWebTrialModel.decodeScriptResult(["status": "unsupported", "reason": "unexpected arbitrary text"]),
                       .unsupported(.unexpectedResult))
        XCTAssertEqual(GrokWebTrialModel.decodeScriptResult(["status": "ok", "percent": true]),
                       .unsupported(.unexpectedResult))
    }

    @MainActor
    func testManualSelectionRejectsUnsafeBoundariesBeforeReadingSelectedText() throws {
        let expected: [String: GrokTrialReadFailure] = [
            "outside": .noDialog, "otherDialog": .anchorFocusMismatch,
            "forbidden": .formInDialog, "hidden": .invisibleDialog,
            "offscreen": .invisibleRange, "collapsed": .collapsedSelection,
            "wrongPage": .wrongPage, "fragment": .wrongPage, "oversizedRange": .selectionLength,
            "crossNode": .crossNodeRange, "editable": .editableSelection,
            "nonText": .nonTextRange, "missingSelection": .noSelection,
            "multipleRanges": .multipleRanges
        ]
        for (rejection, failure) in expected {
            let context = try selectionFixture(selected: "67%", rejection: rejection)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.manualSelectionScript)?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "reason"]))
            XCTAssertEqual(result["status"] as? String, "unsupported")
            XCTAssertEqual(result["reason"] as? String, failure.rawValue)
            XCTAssertNil(result["percent"])
            XCTAssertEqual(context.objectForKeyedSubscript("selectedTextReads")?.toInt32(), 0)
        }
        let missingUnit = try selectionFixture(selected: "67")
        let fields = try XCTUnwrap(missingUnit.evaluateScript(GrokWebTrialModel.manualSelectionScript)?.toDictionary())
        XCTAssertEqual(fields["reason"] as? String, GrokTrialReadFailure.missingPercent.rawValue)
        XCTAssertTrue(GrokTrialReadFailure.collapsedSelection.message.contains("제공자 차단을 뜻하지"))
    }

    @MainActor
    func testIsolatedWebKitReaderReturnsActualNativeResultForLocalHTML() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loader = TrialLocalHTMLLoadDelegate()
        webView.navigationDelegate = loader
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loader.completion = { continuation.resume(with: $0) }
            // No base URL, scripts, credentials, or external resources. The reader
            // must return its unsupported result before inspecting any local DOM.
            webView.loadHTMLString("<!doctype html><html><body><p>Local fixture</p></body></html>", baseURL: nil)
        }
        let nativeResult = try await GrokWebTrialModel.evaluateSelection(in: webView)
        let fields = try XCTUnwrap(nativeResult as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]))
        XCTAssertEqual(fields["status"] as? String, "unsupported")
        XCTAssertEqual(fields["reason"] as? String, GrokTrialReadFailure.wrongPage.rawValue)
        let pointNativeResult: Any? = try await webView.callAsyncJavaScript(
            GrokWebTrialModel.pointTapScript, arguments: ["requestID": "local-fixture-request"],
            in: nil, contentWorld: .defaultClient
        )
        let pointFields = try XCTUnwrap(pointNativeResult as? [String: Any])
        XCTAssertEqual(Set(pointFields.keys), Set(["status", "reason"]))
        XCTAssertEqual(pointFields["reason"] as? String, GrokTrialReadFailure.wrongPage.rawValue)
        let claudeNativeResult: Any? = try await webView.callAsyncJavaScript(
            ProviderWebUsageModel.claudePointTapScript, arguments: ["requestID": "local-claude-fixture"],
            in: nil, contentWorld: .defaultClient
        )
        XCTAssertEqual(ProviderWebUsageModel.decodeScriptResult(claudeNativeResult), .unsupported(.wrongPage))
    }

    @MainActor
    func testPointReaderUsesOnlyVerifiedHostAttributeAndFailsBeforeGetterOnUnsafeMetadata() throws {
        for (label, expected) in [("0%", 0.0), ("67%", 67.0), ("100%", 100.0), ("12.34%", 12.34)] {
            let context = try pointFixture(label: label)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.pointReaderFunction + "; readPoint(50, 50)")?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "percent"]))
            XCTAssertEqual(result["percent"] as? Double, expected)
            XCTAssertEqual(context.objectForKeyedSubscript("labelReads")?.toInt32(), 1)
            XCTAssertEqual(context.objectForKeyedSubscript("pointLookups")?.toInt32(), 1)
        }
        let rejected: [String: GrokTrialReadFailure] = [
            "wrongPage": .wrongPage, "noTarget": .pointNoTarget, "disconnected": .pointNoTarget,
            "noDialog": .noDialog, "editable": .editableSelection, "form": .formInDialog,
            "hidden": .invisibleDialog, "pointOutsideTarget": .pointOutsideTarget,
            "noShadow": .shadowStructure, "closedShadow": .shadowStructure,
            "wrongShadowHost": .shadowStructure, "shadowForm": .editableSelection,
            "childCount": .shadowStructure, "childTag": .shadowStructure,
            "childShape": .shadowStructure, "missingLabel": .missingLabel
        ]
        for (rejection, reason) in rejected {
            let context = try pointFixture(label: "67%", rejection: rejection)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.pointReaderFunction + "; readPoint(50, 50)")?.toDictionary())
            XCTAssertEqual(result["reason"] as? String, reason.rawValue)
            XCTAssertEqual(context.objectForKeyedSubscript("labelReads")?.toInt32(), 0)
        }
        for (label, reason) in [("long fixture text", GrokTrialReadFailure.labelLength), ("67", .invalidPercentFormat), ("100.01%", .percentOutOfRange)] {
            let context = try pointFixture(label: label)
            let result = try XCTUnwrap(context.evaluateScript(GrokWebTrialModel.pointReaderFunction + "; readPoint(50, 50)")?.toDictionary())
            XCTAssertEqual(result["reason"] as? String, reason.rawValue)
            // Attr strings have no pre-read length API; only this one attribute
            // is obtained, length checked, and rejected inside JavaScript.
            XCTAssertEqual(context.objectForKeyedSubscript("labelReads")?.toInt32(), 1)
        }
    }

    func testClaudeURLGateRequiresTheOfficialUsagePage() {
        for value in ["https://claude.ai/settings/usage", "https://claude.ai:443/settings/usage"] {
            XCTAssertTrue(ProviderWebUsageModel.isEligibleUsageURL(URL(string: value), provider: .claude))
        }
        for value in ["https://claude.ai/login", "https://claude.ai/new", "https://claude.ai/settings/usage?code=fixture",
                      "https://claude.ai/settings/usage#fixture", "https://claude.ai/settings/usage/",
                      "https://claude.ai.example/settings/usage", "https://example@claude.ai/settings/usage",
                      "http://claude.ai/settings/usage", "https://claude.ai:8443/settings/usage",
                      "https://grok.com/?_s=usage"] {
            XCTAssertFalse(ProviderWebUsageModel.isEligibleUsageURL(URL(string: value), provider: .claude))
        }
        XCTAssertFalse(ProviderWebUsageModel.isEligibleUsageURL(URL(string: "https://claude.ai/settings/usage")))
    }

    @MainActor
    func testClaudeCandidateReadsOnlyBoundedDirectTextWithOnePercent() throws {
        let cases: [([String], Double, WebUsageValueKind)] = [
            (["0%"], 0, .used), (["67%"], 67, .used), (["100%"], 100, .used), (["12.34%"], 12.34, .used),
            (["67", "%"], 67, .used), ([" ", "7%", " "], 7, .used), (["67% used"], 67, .used),
            (["remaining 33%"], 33, .remaining), (["사용함 67%"], 67, .used), (["33% 남음"], 33, .remaining)
        ]
        for (pieces, expected, kind) in cases {
            let context = try claudePointFixture(pieces: pieces, kind: kind)
            let result = try XCTUnwrap(context.evaluateScript(ProviderWebUsageModel.claudePointReaderFunction + "; readPoint(50, 50, expectedKind)")?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "percent"]))
            XCTAssertEqual(result["status"] as? String, "ok")
            XCTAssertEqual(result["percent"] as? Double, expected)
            XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), Int32(pieces.count))
            XCTAssertEqual(context.objectForKeyedSubscript("pointLookups")?.toInt32(), 1)
        }
    }

    @MainActor
    func testClaudeCandidateRejectsUnsafeMetadataBeforeMaterializingText() throws {
        let cases: [String: GrokTrialReadFailure] = [
            "wrongPage": .wrongPage, "wrongOrigin": .wrongPage, "query": .wrongPage,
            "fragment": .wrongPage, "iframe": .wrongPage, "noTarget": .pointNoTarget,
            "disconnected": .pointNoTarget, "forbidden": .editableSelection,
            "editable": .editableSelection, "noRegion": .noUsageRegion,
            "hiddenRegion": .invisibleDialog, "hiddenTarget": .invisibleRange,
            "outsideTarget": .pointOutsideTarget, "shadow": .textStructure,
            "emptyChildren": .textStructure, "manyChildren": .textStructure,
            "elementChild": .textStructure, "oversized": .textLength,
            "invalidLength": .textLength
        ]
        for (rejection, reason) in cases {
            let context = try claudePointFixture(pieces: ["67%"], rejection: rejection)
            let result = try XCTUnwrap(context.evaluateScript(ProviderWebUsageModel.claudePointReaderFunction + "; readPoint(50, 50, expectedKind)")?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "reason"]))
            XCTAssertEqual(result["reason"] as? String, reason.rawValue)
            XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), 0)
        }
        for value in ["67", "101%", "100.01%", "001%", "67% 2%", "67% other", "used 67% remaining", "99.555%"] {
            let context = try claudePointFixture(pieces: [value])
            let result = try XCTUnwrap(context.evaluateScript(ProviderWebUsageModel.claudePointReaderFunction + "; readPoint(50, 50, expectedKind)")?.toDictionary())
            XCTAssertEqual(Set(result.keys.compactMap { $0 as? String }), Set(["status", "reason"]))
            XCTAssertEqual(result["status"] as? String, "unsupported")
            XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), 1)
        }
    }

    @MainActor
    func testClaudeExplicitUnitsCannotContradictTheFrozenMeaning() throws {
        for (text, kind) in [("80% remaining", WebUsageValueKind.used), ("80% 남음", .used),
                             ("80% used", .remaining), ("사용함 80%", .remaining)] {
            let context = try claudePointFixture(pieces: [text], kind: kind)
            let result = try XCTUnwrap(context.evaluateScript(ProviderWebUsageModel.claudePointReaderFunction + "; readPoint(50, 50, expectedKind)")?.toDictionary())
            XCTAssertEqual(result["reason"] as? String, GrokTrialReadFailure.meaningMismatch.rawValue)
            XCTAssertNil(result["percent"])
        }
        // A bare number has no inferred meaning: the frozen user choice applies.
        let context = try claudePointFixture(pieces: ["80%"], kind: .remaining)
        let fields = try XCTUnwrap(context.evaluateScript(ProviderWebUsageModel.claudePointReaderFunction + "; readPoint(50, 50, expectedKind)")?.toDictionary())
        XCTAssertEqual(fields["percent"] as? Double, 80)
    }

    @MainActor
    func testProviderModelDefaultsAndDisconnectDoNotOpenAWebSession() {
        let grok = ProviderWebUsageModel()
        let claude = ProviderWebUsageModel(provider: .claude)
        XCTAssertEqual(grok.metric, .grokWeekly)
        XCTAssertEqual(claude.metric, .claudeSession)
        XCTAssertEqual(claude.valueKind, .used)
        XCTAssertEqual(claude.availableMetrics, [.claudeSession, .claudeWeekly])
        XCTAssertNil(grok.webView)
        XCTAssertNil(claude.webView)
        XCTAssertFalse(claude.canReadVisibleUsage)
        var disconnections = 0
        claude.onDisconnect = { disconnections += 1 }
        claude.valueKind = .remaining
        claude.metric = .claudeWeekly
        claude.cancelPointRead()
        XCTAssertEqual(disconnections, 0)
        XCTAssertNil(claude.webView)
        claude.disconnect()
        XCTAssertEqual(disconnections, 1)
        XCTAssertNil(claude.webView)
        XCTAssertFalse(claude.userConfirmedUsageVisible)
    }

    /// A synthetic point target only. No website, WKWebView or network is used.
    @MainActor
    private func claudePointFixture(pieces: [String], rejection: String = "", kind: WebUsageValueKind = .used) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        let piecesLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(pieces), encoding: .utf8))
        let rejectionLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(rejection), encoding: .utf8))
        context.evaluateScript("""
        var textReads = 0, pointLookups = 0;
        var expectedKind = "\(kind.rawValue)";
        var rejection = \(rejectionLiteral), pieces = \(piecesLiteral);
        var Node = { ELEMENT_NODE: 1, TEXT_NODE: 3 };
        var rect = { width: 80, height: 70, top: 20, left: 20, bottom: 90, right: 100 };
        var outsideRect = { width: 10, height: 10, top: 5, left: 5, bottom: 15, right: 15 };
        var region = { getBoundingClientRect: () => rect };
        var children = pieces.map(piece => ({
          nodeType: 3, length: rejection === "oversized" ? 10000 : rejection === "invalidLength" ? -1 : piece.length,
          substringData: (start, count) => { textReads++; return piece.substring(start, start + count); }
        }));
        if (rejection === "emptyChildren") children = [];
        if (rejection === "manyChildren") children = [children[0], children[0], children[0], children[0]];
        if (rejection === "elementChild") children[0].nodeType = 1;
        var host = {
          isConnected: rejection !== "disconnected", isContentEditable: rejection === "editable",
          childNodes: children, shadowRoot: rejection === "shadow" ? {} : null,
          closest: selector => selector === 'main,[role="main"],[role="dialog"]'
            ? (rejection === "noRegion" ? null : region) : rejection === "forbidden" ? {} : null,
          getBoundingClientRect: () => rejection === "outsideTarget" ? outsideRect : rect
        };
        var document = { elementFromPoint: () => { pointLookups++; return rejection === "noTarget" ? null : host; } };
        var window = {
          innerWidth: 300, innerHeight: 500,
          location: {
            origin: rejection === "wrongOrigin" ? "https://fixture.invalid" : "https://claude.ai",
            pathname: rejection === "wrongPage" ? "/login" : "/settings/usage",
            search: rejection === "query" ? "?fixture=1" : "", hash: rejection === "fragment" ? "#fixture" : ""
          },
          getComputedStyle: node => ({ display: "block", opacity: "1",
            visibility: (rejection === "hiddenRegion" && node === region) || (rejection === "hiddenTarget" && node === host) ? "hidden" : "visible" })
        };
        window.top = rejection === "iframe" ? {} : window;
        """)
        XCTAssertNil(context.exception)
        return context
    }

    @MainActor
    private func pointFixture(label: String, rejection: String = "") throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        let labelLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(label), encoding: .utf8))
        let rejectionLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(rejection), encoding: .utf8))
        context.evaluateScript("""
        var labelReads = 0, pointLookups = 0;
        var rejection = \(rejectionLiteral);
        var Node = { ELEMENT_NODE: 1 };
        var rect = { width: 80, height: 70, top: 20, left: 20, bottom: 90, right: 100 };
        var outsideRect = { width: 10, height: 10, top: 5, left: 5, bottom: 15, right: 15 };
        var dialog = { querySelector: () => rejection === "form" ? {} : null, getBoundingClientRect: () => rect };
        var children = [
          { nodeType: 1, localName: "span", childNodes: [] },
          { nodeType: 1, localName: "span", childNodes: [{}] },
          { nodeType: 1, localName: "span", childNodes: [{}] }
        ];
        if (rejection === "childCount") children.pop();
        if (rejection === "childTag") children[0].localName = "div";
        if (rejection === "childShape") children[0].childNodes.push({});
        var root = {
          mode: rejection === "closedShadow" ? "closed" : "open",
          childNodes: children,
          querySelector: () => rejection === "shadowForm" ? {} : null
        };
        var host = {
          isConnected: rejection !== "disconnected", isContentEditable: rejection === "editable",
          closest: selector => selector === '[role="dialog"]' ? (rejection === "noDialog" ? null : dialog) : null,
          getBoundingClientRect: () => rejection === "pointOutsideTarget" ? outsideRect : rect,
          shadowRoot: rejection === "noShadow" ? null : root,
          hasAttribute: name => name === "aria-label" && rejection !== "missingLabel",
          getAttribute: name => { if (name !== "aria-label") throw new Error("fixture forbidden attribute"); labelReads++; return \(labelLiteral); }
        };
        root.host = rejection === "wrongShadowHost" ? {} : host;
        var document = { elementFromPoint: () => { pointLookups++; return rejection === "noTarget" ? null : host; } };
        var window = {
          innerWidth: 300, innerHeight: 500,
          location: { origin: "https://grok.com", pathname: rejection === "wrongPage" ? "/login" : "/", search: "?_s=usage", hash: "" },
          getComputedStyle: () => ({ display: "block", visibility: rejection === "hidden" ? "hidden" : "visible", opacity: "1" })
        };
        window.top = window;
        """)
        XCTAssertNil(context.exception)
        return context
    }

    /// Synthetic DOM metadata only; no WKWebView, page load, account, or network.
    @MainActor
    private func selectionFixture(selected: String, rejection: String = "") throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        let textLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(selected), encoding: .utf8))
        let rejectionLiteral = try XCTUnwrap(String(data: JSONEncoder().encode(rejection), encoding: .utf8))
        context.evaluateScript("""
        var selectedTextReads = 0;
        var rejection = \(rejectionLiteral);
        var Node = { ELEMENT_NODE: 1, TEXT_NODE: 3 };
        var rect = { width: 20, height: 20, top: 10, left: 10, bottom: 30, right: 30 };
        var offscreenRect = { width: 20, height: 20, top: 1000, left: 10, bottom: 1020, right: 30 };
        var dialog = {
          nodeType: 1,
          contains: node => node === anchor,
          querySelector: selector => rejection === "forbidden" ? {} : null,
          getBoundingClientRect: () => rect
        };
        function element(dialogValue) {
          return {
            nodeType: 1, dialog: dialogValue, isContentEditable: rejection === "editable",
            closest: function(selector) { return selector === '[role="dialog"]' ? this.dialog : null; },
            getBoundingClientRect: () => rect
          };
        }
        var anchor = element(rejection === "outside" ? null : dialog);
        var focus = element(rejection === "otherDialog" ? {} : dialog);
        var selectedNode = { nodeType: rejection === "nonText" ? 1 : 3, parentElement: anchor };
        var otherSelectedNode = { nodeType: 3, parentElement: focus };
        var range = {
          startContainer: selectedNode, endContainer: rejection === "crossNode" ? otherSelectedNode : selectedNode,
          startOffset: 0, endOffset: rejection === "oversizedRange" ? 10000 : \(selected.utf16.count),
          commonAncestorContainer: selectedNode,
          getClientRects: () => [rejection === "offscreen" ? offscreenRect : rect]
        };
        var selection = {
          isCollapsed: rejection === "collapsed", rangeCount: rejection === "multipleRanges" ? 2 : 1, anchorNode: selectedNode,
          focusNode: rejection === "otherDialog" ? otherSelectedNode : selectedNode,
          getRangeAt: () => range,
          toString: () => { selectedTextReads += 1; return \(textLiteral); }
        };
        var window = {
          innerHeight: 500, innerWidth: 300,
          location: { origin: "https://grok.com", pathname: rejection === "wrongPage" ? "/login" : "/", search: "?_s=usage", hash: rejection === "fragment" ? "#login" : "" },
          getSelection: () => rejection === "missingSelection" ? null : selection,
          getComputedStyle: () => ({ display: "block", visibility: rejection === "hidden" ? "hidden" : "visible", opacity: "1" })
        };
        window.top = window;
        """)
        XCTAssertNil(context.exception)
        return context
    }
}

@MainActor
private final class TrialLocalHTMLLoadDelegate: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, Error>) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    private func finish(_ result: Result<Void, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}
#endif
