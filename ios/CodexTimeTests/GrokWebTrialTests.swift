#if DEBUG
import XCTest
import Combine
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

    func testClaudeNavigationPolicyBlocksGoogleWithoutMatchingConfusableHosts() {
        for host in ["accounts.google.com", "login.accounts.google.com", "ACCOUNTS.GOOGLE.COM", "accounts.google.com."] {
            for isNewWindow in [false, true] {
                XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: "https://" + host + "/fixture"),
                                                                           provider: .claude, isNewWindow: isNewWindow),
                               .cancel(.googleSignInUnsupported))
            }
        }
        for host in ["claude.ai", "accounts.google.com.example", "notaccounts.google.com", "accounts-google.com"] {
            XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: "https://" + host + "/fixture"),
                                                                       provider: .claude, isNewWindow: false), .allow)
        }
        for value in ["https://claude.ai/login", "about:blank"] {
            XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: value), provider: .claude,
                                                                       isNewWindow: true), .cancel(.newWindowUnsupported))
        }
        XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: "about:blank"), provider: .claude,
                                                                   isNewWindow: false), .allow)
        for value in ["http://accounts.google.com/fixture", "claude://fixture", "javascript:void(0)", "about:srcdoc"] {
            XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: value), provider: .claude,
                                                                       isNewWindow: false), .cancel(.unsupportedNavigation))
        }
        XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: nil, provider: .claude,
                                                                   isNewWindow: true), .cancel(.newWindowUnsupported))
        XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: nil, provider: .claude,
                                                                   isNewWindow: false), .cancel(.unsupportedNavigation))
    }

    func testGrokNavigationPolicyPreservesHTTPSAndKnownBlankBehavior() {
        for value in ["https://grok.com/?_s=usage", "https://accounts.google.com/fixture", "about:blank"] {
            for isNewWindow in [false, true] {
                XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: value), provider: .grok,
                                                                           isNewWindow: isNewWindow), .allow)
            }
        }
        for value in ["http://grok.com", "grok://fixture", "about:srcdoc"] {
            XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: URL(string: value), provider: .grok,
                                                                       isNewWindow: false), .cancel(.unsupportedNavigation))
        }
        XCTAssertEqual(ProviderWebUsageModel.navigationDisposition(for: nil, provider: .grok,
                                                                   isNewWindow: false), .cancel(.unsupportedNavigation))
    }

    func testNavigationErrorClassifierIgnoresOnlyTheURLCancellationDomainAndCode() {
        XCTAssertNil(ProviderWebUsageModel.navigationIssue(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        for error in [NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
                      NSError(domain: "LocalFixtureError", code: NSURLErrorCancelled),
                      NSError(domain: "WKErrorDomain", code: 1)] {
            XCTAssertEqual(ProviderWebUsageModel.navigationIssue(for: error), .loadFailed)
        }
        XCTAssertTrue(ProviderWebNavigationIssue.googleSignInUnsupported.message.contains("Claude 계정 이메일"))
        XCTAssertTrue(ProviderWebNavigationIssue.newWindowUnsupported.message.contains("자동 연결되지 않습니다"))
    }

    @MainActor
    func testClaudePopupRetainsParentAndCancelsThePendingReadWithoutLoading() {
        let model = ProviderWebUsageModel(provider: .claude)
        let parent = TrialRecordingWebView(fixtureURL: WebUsageProvider.claude.usageURL)
        model.configureWebView(parent)
        defer { model.close() }
        var readings = 0, disconnections = 0
        model.onReading = { _ in readings += 1 }
        model.onDisconnect = { disconnections += 1 }
        model.userConfirmedUsageVisible = true
        model.armPointRead()
        XCTAssertTrue(model.isReading)
        XCTAssertTrue(model.isPointReadArmed)
        model.handleNewWindowRequest(URLRequest(url: URL(string: "https://claude.ai/fixture-popup")!),
                                     isNewWindow: true, from: parent)
        XCTAssertTrue(model.webView === parent)
        XCTAssertEqual(parent.loadRequests.count, 0)
        XCTAssertEqual(model.navigationIssue, .newWindowUnsupported)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.isPointReadArmed)
        XCTAssertFalse(model.userConfirmedUsageVisible)
        XCTAssertFalse(model.isAtUsagePage)
        XCTAssertNil(model.selectedPercent)
        XCTAssertEqual(readings, 0)
        XCTAssertEqual(disconnections, 0)
        // The synchronous cancellation happens before the main-actor read task
        // can start. Its underlying local blank view never loads an account.
    }

    @MainActor
    func testClaudeBlockedGoogleNavigationPreservesTheSameSession() {
        let model = ProviderWebUsageModel(provider: .claude)
        let parent = TrialRecordingWebView(fixtureURL: WebUsageProvider.claude.usageURL)
        model.configureWebView(parent)
        defer { model.close() }
        model.userConfirmedUsageVisible = true
        XCTAssertEqual(model.navigationPolicy(for: URL(string: "https://accounts.google.com/fixture"),
                                              isNewWindow: false, from: parent), .cancel)
        XCTAssertEqual(model.navigationIssue, .googleSignInUnsupported)
        XCTAssertTrue(model.webView === parent)
        XCTAssertEqual(parent.loadRequests.count, 0)
        XCTAssertFalse(model.canReadVisibleUsage)
        XCTAssertFalse(model.userConfirmedUsageVisible)
    }

    @MainActor
    func testGrokPopupStillLoadsHTTPSIntoItsParentOnlyForNewWindows() {
        let model = ProviderWebUsageModel(provider: .grok)
        let parent = TrialRecordingWebView()
        model.configureWebView(parent)
        defer { model.close() }
        let request = URLRequest(url: URL(string: "https://grok.com/fixture-popup")!)
        model.handleNewWindowRequest(request, isNewWindow: true, from: parent)
        XCTAssertTrue(model.webView === parent)
        XCTAssertEqual(parent.loadRequests.map(\.url), [request.url])
        XCTAssertNil(model.navigationIssue)
        model.handleNewWindowRequest(request, isNewWindow: false, from: parent)
        model.handleNewWindowRequest(URLRequest(url: URL(string: "http://grok.com/fixture")!), isNewWindow: true, from: parent)
        XCTAssertEqual(parent.loadRequests.count, 1)
    }

    @MainActor
    func testLoadFailuresAndRecoveryControlsRetainTheParentView() throws {
        let model = ProviderWebUsageModel(provider: .claude)
        let parent = TrialRecordingWebView(fixtureURL: WebUsageProvider.claude.usageURL, canGoBack: true)
        model.configureWebView(parent)
        defer { model.close() }
        XCTAssertTrue(model.canGoBack)
        let navigation = try XCTUnwrap(parent.makeNavigationToken())
        model.webView(parent, didStartProvisionalNavigation: navigation)
        XCTAssertTrue(model.isLoading)
        model.webView(parent, didFailProvisionalNavigation: navigation,
                      withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.navigationIssue)
        model.webView(parent, didFail: navigation, withError: NSError(domain: "LocalFixtureError", code: NSURLErrorCancelled))
        XCTAssertEqual(model.navigationIssue, .loadFailed)
        XCTAssertFalse(model.isLoading)
        model.reload()
        XCTAssertNil(model.navigationIssue)
        XCTAssertEqual(parent.reloadCount, 1)
        model.webViewWebContentProcessDidTerminate(parent)
        XCTAssertEqual(model.navigationIssue, .webProcessTerminated)
        XCTAssertFalse(model.userConfirmedUsageVisible)
        model.goBack()
        XCTAssertNil(model.navigationIssue)
        XCTAssertEqual(parent.goBackCount, 1)
        model.navigationIssue = .loadFailed
        model.openUsagePage()
        XCTAssertNil(model.navigationIssue)
        XCTAssertEqual(parent.loadRequests.map(\.url), [WebUsageProvider.claude.usageURL])
        XCTAssertTrue(model.webView === parent)
    }

    @MainActor
    func testLateNavigationCompletionCannotOverwriteANewerNavigationOrPolicyIssue() throws {
        let model = ProviderWebUsageModel(provider: .claude)
        let parent = TrialRecordingWebView(fixtureURL: WebUsageProvider.claude.usageURL)
        model.configureWebView(parent)
        defer { model.close() }
        let first = try XCTUnwrap(parent.makeNavigationToken())
        model.webView(parent, didStartProvisionalNavigation: first)
        model.reload()
        let second = try XCTUnwrap(parent.navigationTokens.last)
        // reload() already owns the new token, before its didStart arrives.
        model.webView(parent, didFailProvisionalNavigation: first, withError: NSError(domain: "WKErrorDomain", code: 102))
        XCTAssertNil(model.navigationIssue)
        model.webView(parent, didStartProvisionalNavigation: second)
        XCTAssertTrue(model.isLoading)
        model.webView(parent, didFail: first, withError: NSError(domain: "LocalFixtureError", code: 1))
        model.webView(parent, didFinish: first)
        model.webView(parent, didFail: nil, withError: NSError(domain: "LocalFixtureError", code: 1))
        model.webView(parent, didFinish: nil)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.navigationIssue)
        XCTAssertEqual(model.navigationPolicy(for: URL(string: "https://accounts.google.com/fixture"),
                                              isNewWindow: false, from: parent), .cancel)
        model.webView(parent, didFailProvisionalNavigation: second, withError: NSError(domain: "WKErrorDomain", code: 102))
        XCTAssertEqual(model.navigationIssue, .googleSignInUnsupported)
        XCTAssertFalse(model.isLoading)
        // Even a later callback for a newly started token cannot replace the
        // precise policy issue with a generic WebKit cancellation message.
        let third = try XCTUnwrap(parent.makeNavigationToken())
        model.webView(parent, didStartProvisionalNavigation: third)
        model.webView(parent, didFail: third, withError: NSError(domain: "WKErrorDomain", code: 102))
        XCTAssertEqual(model.navigationIssue, .googleSignInUnsupported)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.webView === parent)
    }

    @MainActor
    func testObsoleteWebViewCallbacksAndQueuedHistoryCannotChangeTheCurrentModel() async throws {
        let model = ProviderWebUsageModel(provider: .claude)
        let old = TrialRecordingWebView(fixtureURL: WebUsageProvider.claude.usageURL)
        model.configureWebView(old)
        old.fixtureCanGoBack = true // Queue an observation before close().
        model.close()
        let current = TrialRecordingWebView()
        model.configureWebView(current)
        defer { model.close() }
        XCTAssertFalse(model.canGoBack)
        model.userConfirmedUsageVisible = true
        let obsoleteNavigation = try XCTUnwrap(old.makeNavigationToken())
        model.webView(old, didStartProvisionalNavigation: obsoleteNavigation)
        model.webView(old, didFinish: obsoleteNavigation)
        model.webView(old, didFail: obsoleteNavigation, withError: NSError(domain: "LocalFixtureError", code: 1))
        model.webView(old, didFailProvisionalNavigation: obsoleteNavigation, withError: NSError(domain: "LocalFixtureError", code: 1))
        model.webViewWebContentProcessDidTerminate(old)
        XCTAssertEqual(model.navigationPolicy(for: URL(string: "https://accounts.google.com/fixture"),
                                              isNewWindow: false, from: old), .cancel)
        model.handleNewWindowRequest(URLRequest(url: URL(string: "https://claude.ai/fixture")!), isNewWindow: true, from: old)
        await Task.yield()
        XCTAssertTrue(model.webView === current)
        XCTAssertTrue(model.userConfirmedUsageVisible)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canGoBack)
        XCTAssertNil(model.navigationIssue)
        XCTAssertEqual(old.loadRequests.count, 0)
        XCTAssertEqual(current.loadRequests.count, 0)
        // A live observation still updates history, unlike the detached view.
        let historyUpdated = expectation(description: "Current view updates back navigation")
        let observation = model.$canGoBack.dropFirst().filter { $0 }.prefix(1).sink { _ in historyUpdated.fulfill() }
        current.fixtureCanGoBack = true
        await fulfillment(of: [historyUpdated], timeout: 1)
        XCTAssertTrue(model.canGoBack)
        withExtendedLifetime(observation) {}
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

/// Every navigation is recorded and suppressed, including recovery methods.
/// The URL override is synthetic test metadata, never a production URL bypass.
@MainActor
private final class TrialRecordingWebView: WKWebView {
    var fixtureURL: URL?
    var fixtureCanGoBack: Bool {
        willSet { willChangeValue(forKey: #keyPath(WKWebView.canGoBack)) }
        didSet { didChangeValue(forKey: #keyPath(WKWebView.canGoBack)) }
    }
    private(set) var loadRequests: [URLRequest] = []
    private(set) var navigationTokens: [WKNavigation] = []
    private(set) var reloadCount = 0
    private(set) var goBackCount = 0
    private lazy var navigationSource: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // This separate source has no model delegate and no network resource.
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    init(fixtureURL: URL? = nil, canGoBack: Bool = false) {
        self.fixtureURL = fixtureURL
        self.fixtureCanGoBack = canGoBack
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: configuration)
    }
    required init?(coder: NSCoder) { fatalError("No storyboard fixture") }
    override var url: URL? { fixtureURL }
    override var canGoBack: Bool { fixtureCanGoBack }
    override func load(_ request: URLRequest) -> WKNavigation? {
        loadRequests.append(request)
        return recordNavigation()
    }
    override func reload() -> WKNavigation? {
        reloadCount += 1
        return recordNavigation()
    }
    override func goBack() -> WKNavigation? {
        goBackCount += 1
        return recordNavigation()
    }
    /// WKNavigation's inherited empty initializer does not create WebKit's
    /// backing navigation and crashes at deallocation. Obtain a real token from
    /// a separate offline HTML load without changing the model's parent view.
    func makeNavigationToken() -> WKNavigation? {
        let navigation = navigationSource.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        navigationSource.stopLoading()
        return navigation
    }
    private func recordNavigation() -> WKNavigation? {
        guard let navigation = makeNavigationToken() else { return nil }
        navigationTokens.append(navigation)
        return navigation
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

/// Synthetic DOM and injected native results only. No site or account is loaded.
@MainActor
final class ClaudeUsagePanelTests: XCTestCase {
    func testPanelDecoderAcceptsOnlyTwoFiniteUsageNumbers() {
        XCTAssertEqual(ClaudeUsagePanelReader.decode(["status": "ok", "sessionUsed": 32, "weeklyUsed": 64]),
                       .success(sessionUsed: 32, weeklyUsed: 64))
        XCTAssertEqual(ClaudeUsagePanelReader.decode(["status": "ok", "sessionUsed": 0.0, "weeklyUsed": 100.0]),
                       .success(sessionUsed: 0, weeklyUsed: 100))
        XCTAssertEqual(ClaudeUsagePanelReader.decode(["status": "ok", "sessionUsed": 7.0, "weeklyUsed": 32.0]),
                       .success(sessionUsed: 7, weeklyUsed: 32))
    }

    func testPanelDecoderRejectsBooleansStringsMissingValuesAndAdditionalFields() {
        let invalid: [Any?] = [
            nil, NSNull(), [Any](), "32%", ["status": "ok"],
            ["status": "ok", "sessionUsed": 32],
            ["status": "ok", "weeklyUsed": 64],
            ["status": "ok", "sessionUsed": true, "weeklyUsed": 64],
            ["status": "ok", "sessionUsed": 32, "weeklyUsed": NSNumber(value: true)],
            ["status": "ok", "sessionUsed": "32", "weeklyUsed": 64],
            ["status": "ok", "sessionUsed": 32, "weeklyUsed": NSNull()],
            ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64, "rawText": "fixture"],
            ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64, "reason": "missing_usage"],
            ["status": "unexpected", "sessionUsed": 32, "weeklyUsed": 64]
        ]
        for result in invalid {
            XCTAssertEqual(ClaudeUsagePanelReader.decode(result), .unsupported(.unexpectedResult))
        }
    }

    func testPanelDecoderRejectsNonfiniteAndOutOfRangeNumbers() {
        for value in [Double.nan, Double.infinity, -Double.infinity, -1, 100.01] {
            let invalid: [[String: Any]] = [
                ["status": "ok", "sessionUsed": value, "weeklyUsed": 64],
                ["status": "ok", "sessionUsed": 32, "weeklyUsed": value]
            ]
            for result in invalid {
                XCTAssertEqual(ClaudeUsagePanelReader.decode(result), .unsupported(.unexpectedResult))
            }
        }
    }

    func testPanelDecoderAcceptsOnlyWhitelistedFailureCodesWithExactKeys() {
        let failures: [ClaudeUsagePanelFailure] = [
            .wrongPage, .missingUsage, .ambiguousLimit, .unsafeContent,
            .unsupportedStructure, .invalidPercent, .meaningMismatch,
            .scriptException, .unexpectedResult, .executionFailed
        ]
        for failure in failures {
            XCTAssertEqual(ClaudeUsagePanelReader.decode(["status": "unsupported", "reason": failure.rawValue]),
                           .unsupported(failure))
        }
        let invalid: [[String: Any]] = [
            ["status": "unsupported", "reason": "private arbitrary label"],
            ["status": "unsupported", "reason": "missing_usage", "rawText": "fixture"],
            ["status": "unsupported", "reason": "missing_usage", "sessionUsed": 32],
            ["status": "unsupported", "reason": 32],
            ["status": "unsupported"]
        ]
        for result in invalid {
            XCTAssertEqual(ClaudeUsagePanelReader.decode(result), .unsupported(.unexpectedResult))
        }
    }

    func testPanelScriptReadsTheLinkedMeterPairInEitherLanguageAndOrder() throws {
        for scenario in ["english", "korean", "reversed", "filledMeter", "alternateRoute", "queryAndFragment", "outerSearchAndSwitch", "allModelsContext", "shortProductLabel", "unrelatedProductWrapper"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "sessionUsed", "weeklyUsed"]), scenario)
            XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .success(sessionUsed: 32, weeklyUsed: 64), scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("modelValueReads")?.toInt32(), 0, scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("wholeTextReads")?.toInt32(), 0, scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("blockedAPICalls")?.toInt32(), 0, scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("protectedReads")?.toInt32(), 0, scenario)
        }
    }

    func testPanelScriptAcceptsZeroMetersWithoutRequiringAFillChild() throws {
        let (fields, _) = try readPanelFixture("zeroMeters")
        XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .success(sessionUsed: 0, weeklyUsed: 0))
    }

    func testPanelScriptCannotSubstituteAModelLimitOrPublishAPartialPair() throws {
        for scenario in ["modelOnly", "missingSession", "missingWeekly", "hiddenSession", "hiddenWeekly", "unknownDOM", "allModelsWithoutContext", "allModelsSharedContext", "modelPrefixOnly"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]), scenario)
            XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .unsupported(.missingUsage), scenario)
            XCTAssertNil(fields["sessionUsed"], scenario)
            XCTAssertNil(fields["weeklyUsed"], scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("modelValueReads")?.toInt32(), 0, scenario)
        }
    }

    func testPanelScriptRejectsDuplicateLabelsAndTwoMetersInOneCard() throws {
        for scenario in ["duplicateSession", "duplicateWeekly", "twoMetersInCard", "duplicateWeeklyContext", "allModelsAndWeekly"] {
            let (fields, _) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]), scenario)
            XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .unsupported(.ambiguousLimit), scenario)
        }
    }

    func testPanelScriptRejectsInvalidOrInconsistentMeterValuesWithoutReturningAttributes() throws {
        for scenario in ["remaining", "barePercent", "invalidNow", "nonfiniteNow", "negativeNow", "leadingZero", "tooPrecise", "textMismatch", "twoPercentText", "unknownUnit", "wrongMinimum", "wrongMaximum"] {
            let (fields, _) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]), scenario)
            guard case .unsupported = ClaudeUsagePanelReader.decode(fields) else {
                return XCTFail("An invalid meter must not become a reading: " + scenario)
            }
            XCTAssertNotNil(ClaudeUsagePanelFailure(rawValue: try XCTUnwrap(fields["reason"] as? String)), scenario)
        }
    }

    func testPanelScriptRequiresOneBoundedLeafLabelAndAnUnambiguousLabelReference() throws {
        for scenario in ["nestedLabel", "splitTextLabel", "wrongLabelTag", "oversizedLabel", "missingLabel", "multipleLabelIDs", "oversizedLabelID", "foreignLabel", "orphanMeter", "splitModelHeading", "outerSplitModelHeading"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]), scenario)
            guard case .unsupported = ClaudeUsagePanelReader.decode(fields) else {
                return XCTFail("A label boundary must be preserved: " + scenario)
            }
            let counter = ["splitModelHeading", "outerSplitModelHeading"].contains(scenario) ? "weeklyValueReads" : "sessionValueReads"
            XCTAssertEqual(context.objectForKeyedSubscript(counter)?.toInt32(), 0, scenario)
            if scenario == "oversizedLabel" {
                XCTAssertEqual(context.objectForKeyedSubscript("sessionLabelReads")?.toInt32(), 0)
            }
        }
    }

    func testPanelScriptRejectsInputsInsideTheSelectedCardBeforeValueAttributeReads() throws {
        for scenario in ["cardForm", "cardEditable"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .unsupported(.unsafeContent), scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("sessionValueReads")?.toInt32(), 0, scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("protectedReads")?.toInt32(), 0, scenario)
        }
    }

    func testPanelScriptChecksAncestorVisibilityAndMeterCountBeforeReadingValues() throws {
        for scenario in ["hiddenAncestor", "hiddenLabel", "hiddenMeter", "tooManyMeters", "noDialog"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(Set(fields.keys), Set(["status", "reason"]), scenario)
            guard case .unsupported = ClaudeUsagePanelReader.decode(fields) else {
                return XCTFail("An unsupported scope must not become a reading: " + scenario)
            }
            XCTAssertEqual(context.objectForKeyedSubscript("sessionValueReads")?.toInt32(), 0, scenario)
            if scenario == "tooManyMeters" {
                XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), 0)
            }
        }
    }

    func testPanelScriptRejectsOtherOriginsAndChildFramesBeforeDOMQueries() throws {
        for scenario in ["wrongOrigin", "confusableOrigin", "http", "nonstandardPort", "iframe"] {
            let (fields, context) = try readPanelFixture(scenario)
            XCTAssertEqual(ClaudeUsagePanelReader.decode(fields), .unsupported(.wrongPage), scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), 0, scenario)
            XCTAssertEqual(context.objectForKeyedSubscript("domQueries")?.toInt32(), 0, scenario)
        }
    }

    func testPanelScriptReturnsOnlyAFixedCodeForDOMExceptionsAndLoginOnlyContent() throws {
        let (failed, _) = try readPanelFixture("scriptException")
        XCTAssertEqual(Set(failed.keys), Set(["status", "reason"]))
        XCTAssertEqual(ClaudeUsagePanelReader.decode(failed), .unsupported(.scriptException))
        let (login, context) = try readPanelFixture("loginOnly")
        XCTAssertEqual(ClaudeUsagePanelReader.decode(login), .unsupported(.missingUsage))
        XCTAssertEqual(context.objectForKeyedSubscript("textReads")?.toInt32(), 0)
        XCTAssertEqual(context.objectForKeyedSubscript("protectedReads")?.toInt32(), 0)
    }

    func testClaudeOneButtonPublishesAnAtomicPairWithUsedMeaningAndOneTimestamp() async throws {
        var evaluations = 0
        let model = ProviderWebUsageModel(provider: .claude, claudeEvaluator: { _ in
            evaluations += 1
            return ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64]
        })
        let view = TrialRecordingWebView(fixtureURL: URL(string: "https://claude.ai/new#settings/usage"))
        model.configureWebView(view)
        defer { model.close() }
        var callbacks: [WebUsageReading] = []
        model.onReading = { [weak model] reading in
            callbacks.append(reading)
            // Both values exist before the first observer receives a callback.
            XCTAssertEqual(Set(model?.claudeReadings.keys.map { $0 } ?? []), Set([.claudeSession, .claudeWeekly]))
        }
        XCTAssertTrue(model.canReadClaudeUsage)
        XCTAssertFalse(model.userConfirmedUsageVisible)
        await model.readClaudeUsage()
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(callbacks.map(\.metric), [.claudeSession, .claudeWeekly])
        XCTAssertEqual(callbacks.map(\.percent), [32, 64])
        XCTAssertEqual(callbacks.map(\.remainingPercent), [68, 36])
        XCTAssertTrue(callbacks.allSatisfy { $0.provider == .claude && $0.valueKind == .used })
        let first = try XCTUnwrap(callbacks.first)
        let last = try XCTUnwrap(callbacks.last)
        XCTAssertEqual(first.updatedAt, last.updatedAt)
        XCTAssertTrue(model.hasRecognizedClaudeUsage)
        XCTAssertFalse(model.isReading)
        XCTAssertEqual(view.loadRequests.count, 0)
    }

    func testClaudeFailedOrPartialRereadPreservesTheLastPairAndItsTimestamps() async throws {
        var supplied: Any? = ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64]
        let model = ProviderWebUsageModel(provider: .claude, claudeEvaluator: { _ in supplied })
        let view = TrialRecordingWebView(fixtureURL: URL(string: "https://claude.ai/new#settings/usage"))
        model.configureWebView(view)
        defer { model.close() }
        var callbacks: [WebUsageReading] = []
        model.onReading = { callbacks.append($0) }
        await model.readClaudeUsage()
        let original = model.claudeReadings
        XCTAssertEqual(original.count, 2)
        XCTAssertEqual(callbacks.count, 2)
        let failures: [[String: Any]] = [
            ["status": "unsupported", "reason": "missing_usage"],
            ["status": "ok", "sessionUsed": 7],
            ["status": "ok", "sessionUsed": 7, "weeklyUsed": true],
            ["status": "ok", "sessionUsed": 7, "weeklyUsed": 101]
        ]
        for failure in failures {
            supplied = failure
            await model.readClaudeUsage()
            XCTAssertEqual(model.claudeReadings, original)
            XCTAssertFalse(model.hasRecognizedClaudeUsage)
            XCTAssertFalse(model.isReading)
            XCTAssertEqual(callbacks.count, 2)
        }
        XCTAssertEqual(view.loadRequests.count, 0)
    }

    func testClaudeNativeOriginGateNeverInvokesTheEvaluatorForOtherProvidersOrHosts() async {
        let cases: [(WebUsageProvider, URL?)] = [
            (.grok, URL(string: "https://claude.ai/new#settings/usage")),
            (.claude, nil), (.claude, URL(string: "http://claude.ai/new")),
            (.claude, URL(string: "https://claude.ai.example/new")),
            (.claude, URL(string: "https://claude.ai:8443/new")),
            (.claude, URL(string: "https://fixture.invalid/new"))
        ]
        for (provider, url) in cases {
            var calls = 0
            let model = ProviderWebUsageModel(provider: provider, claudeEvaluator: { _ in
                calls += 1
                return ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64]
            })
            let view = TrialRecordingWebView(fixtureURL: url)
            model.configureWebView(view)
            XCTAssertFalse(model.canReadClaudeUsage)
            await model.readClaudeUsage()
            XCTAssertEqual(calls, 0)
            XCTAssertTrue(model.claudeReadings.isEmpty)
            XCTAssertEqual(view.loadRequests.count, 0)
            model.close()
        }
    }

    func testClaudeDiscardedAsyncReadsCannotPublishAfterCancellationNavigationOrDisconnect() async throws {
        for action in ["cancel", "taskCancel", "navigation", "disconnect"] {
            let began = expectation(description: "Injected evaluator began: " + action)
            var response: CheckedContinuation<Any?, Never>?
            let model = ProviderWebUsageModel(provider: .claude, claudeEvaluator: { _ in
                await withCheckedContinuation { continuation in
                    response = continuation
                    began.fulfill()
                }
            })
            let view = TrialRecordingWebView(fixtureURL: URL(string: "https://claude.ai/new#settings/usage"))
            model.configureWebView(view)
            var callbacks = 0
            model.onReading = { _ in callbacks += 1 }
            let pending = Task { await model.readClaudeUsage() }
            await fulfillment(of: [began], timeout: 1)
            XCTAssertTrue(model.isReading, action)
            switch action {
            case "cancel": model.cancelPointRead(clearMessage: false)
            case "taskCancel": pending.cancel()
            case "navigation": model.reload()
            default: model.disconnect()
            }
            let continuation = try XCTUnwrap(response, action)
            continuation.resume(returning: ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64])
            await pending.value
            XCTAssertEqual(callbacks, 0, action)
            XCTAssertTrue(model.claudeReadings.isEmpty, action)
            XCTAssertFalse(model.hasRecognizedClaudeUsage, action)
            XCTAssertFalse(model.isReading, action)
            XCTAssertEqual(view.loadRequests.count, 0, action)
            model.close()
        }
    }

    func testClaudeObserverDisconnectStopsTheSecondCallback() async {
        let model = ProviderWebUsageModel(provider: .claude, claudeEvaluator: { _ in
            ["status": "ok", "sessionUsed": 32, "weeklyUsed": 64]
        })
        let view = TrialRecordingWebView(fixtureURL: URL(string: "https://claude.ai/new#settings/usage"))
        model.configureWebView(view)
        var callbacks = 0
        model.onReading = { [weak model] _ in
            callbacks += 1
            model?.disconnect()
        }
        await model.readClaudeUsage()
        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(model.webView)
        XCTAssertTrue(model.claudeReadings.isEmpty)
        XCTAssertFalse(model.hasRecognizedClaudeUsage)
        XCTAssertFalse(model.isReading)
        XCTAssertEqual(view.loadRequests.count, 0)
    }

    func testClaudeEvaluatorErrorsReturnAFixedMessageWithoutAReading() async {
        let model = ProviderWebUsageModel(provider: .claude, claudeEvaluator: { _ in
            throw NSError(domain: "SyntheticFixture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Protected fixture error"])
        })
        let view = TrialRecordingWebView(fixtureURL: URL(string: "https://claude.ai/new#settings/usage"))
        model.configureWebView(view)
        defer { model.close() }
        var callbacks = 0
        model.onReading = { _ in callbacks += 1 }
        await model.readClaudeUsage()
        XCTAssertEqual(model.readMessage, ClaudeUsagePanelFailure.executionFailed.message)
        XCTAssertFalse(model.readMessage.contains("Protected fixture error"))
        XCTAssertEqual(callbacks, 0)
        XCTAssertTrue(model.claudeReadings.isEmpty)
        XCTAssertFalse(model.hasRecognizedClaudeUsage)
        XCTAssertFalse(model.isReading)
        XCTAssertEqual(view.loadRequests.count, 0)
    }

    private func readPanelFixture(_ scenario: String) throws -> ([String: Any], JSContext) {
        let context = try XCTUnwrap(JSContext())
        let literal = try XCTUnwrap(String(data: JSONEncoder().encode(scenario), encoding: .utf8))
        context.evaluateScript("var panelScenario = " + literal + ";" + Self.panelDOMFixture)
        XCTAssertNil(context.exception, "Synthetic DOM setup failed: " + scenario)
        let result = context.evaluateScript(ClaudeUsagePanelReader.script)
        XCTAssertNil(context.exception, "Panel script escaped its fixed error result: " + scenario)
        let raw = try XCTUnwrap(result?.toDictionary(), scenario)
        let fields = try XCTUnwrap(raw as? [String: Any], scenario)
        return (fields, context)
    }

    /// Synthetic accessibility metadata only, informed by the observed role=meter
    /// relationship. This is not a captured site DOM or proof of live operation.
    /// Parent text, settings inputs, model values, and account APIs trap if read.
    private static let panelDOMFixture = #"""
    var textReads = 0, protectedReads = 0, wholeTextReads = 0, blockedAPICalls = 0;
    var modelValueReads = 0, sessionValueReads = 0, weeklyValueReads = 0, sessionLabelReads = 0, domQueries = 0, idLookups = 0;
    var Node = { ELEMENT_NODE: 1, TEXT_NODE: 3, DOCUMENT_NODE: 9 };
    function rectangle(x, y, width, height) {
      return { x, y, left: x, top: y, right: x + width, bottom: y + height, width, height };
    }
    class FixtureText {
      constructor(text, kind = "ordinary") {
        this.nodeType = 3; this.nodeName = "#text"; this.value = text;
        this.kind = kind; this.parentElement = null; this.parentNode = null;
      }
      get length() { return this.value.length; }
      substringData(start, count) {
        textReads++;
        if (this.kind === "protected") { protectedReads++; throw new Error("Protected fixture text must not be read"); }
        if (this.kind === "sessionLabel") sessionLabelReads++;
        return this.value.substring(start, start + count);
      }
      get data() { return this.substringData(0, this.length); }
      get nodeValue() { return this.data; }
      get textContent() { return this.data; }
    }
    class FixtureElement {
      constructor(tag, children = [], box = rectangle(10, 10, 280, 20), attributes = {}) {
        this.nodeType = 1; this.localName = tag.toLowerCase(); this.tagName = tag.toUpperCase();
        this.nodeName = this.tagName; this.childNodes = []; this.parentElement = null; this.parentNode = null;
        this.box = box; this.attributes = attributes; this.isConnected = true;
        this.isContentEditable = false; this.hidden = false; this.shadowRoot = null;
        children.forEach(child => this.appendChild(child));
      }
      appendChild(child) { this.childNodes.push(child); child.parentElement = this; child.parentNode = this; return child; }
      removeChild(child) { this.childNodes = this.childNodes.filter(item => item !== child); child.parentElement = null; child.parentNode = null; return child; }
      get children() { return this.childNodes.filter(child => child.nodeType === 1); }
      get childElementCount() { return this.children.length; }
      get firstChild() { return this.childNodes[0] || null; }
      get lastChild() { return this.childNodes[this.childNodes.length - 1] || null; }
      get id() { return this.attributes.id || ""; }
      get firstElementChild() { return this.children[0] || null; }
      get lastElementChild() { return this.children[this.children.length - 1] || null; }
      get previousElementSibling() { if (!this.parentElement) return null; const items = this.parentElement.children; return items[items.indexOf(this) - 1] || null; }
      get nextElementSibling() { if (!this.parentElement) return null; const items = this.parentElement.children; return items[items.indexOf(this) + 1] || null; }
      getBoundingClientRect() { return this.box; }
      getClientRects() { return [this.box]; }
      hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
      getAttribute(name) {
        if (["aria-valuemin", "aria-valuemax", "aria-valuenow", "aria-valuetext"].includes(name)) {
          if (this.kind === "model") { modelValueReads++; throw new Error("Model-specific value must not be read"); }
          if (this.kind === "session") sessionValueReads++;
          if (this.kind === "weekly") weeklyValueReads++;
        }
        return this.hasAttribute(name) ? this.attributes[name] : null;
      }
      contains(node) { for (let current = node; current; current = current.parentNode) if (current === this) return true; return false; }
      matches(selector) {
        return selector.split(",").some(piece => {
          let remaining = piece.trim().replace(/^:scope\s*>\s*/, "");
          if (remaining === "*") return true;
          const attrs = [...remaining.matchAll(/\[([^\]=\s]+)(?:\s*=\s*["']?([^"'\]]+)["']?)?\]/g)];
          if (attrs.some(match => !this.hasAttribute(match[1]) || (match[2] !== undefined && this.getAttribute(match[1]) !== match[2]))) return false;
          remaining = remaining.replace(/\[[^\]]+\]/g, "").trim();
          if (!remaining || remaining === "*") return true;
          return remaining.toLowerCase() === this.localName;
        });
      }
      closest(selector) { for (let item = this; item; item = item.parentElement) if (item.matches(selector)) return item; return null; }
      querySelectorAll(selector) {
        const result = [];
        function visit(node) { for (const child of node.children) { if (child.matches(selector)) result.push(child); visit(child); } }
        visit(this); return result;
      }
      querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
      get textContent() { wholeTextReads++; throw new Error("Element textContent must not flatten fixture text"); }
      get innerText() { wholeTextReads++; throw new Error("Element innerText must not flatten fixture text"); }
      get innerHTML() { wholeTextReads++; throw new Error("HTML must not leave its structural boundary"); }
      get outerHTML() { wholeTextReads++; throw new Error("HTML must not leave its structural boundary"); }
    }
    var Element = FixtureElement, HTMLElement = FixtureElement;
    function text(value, kind) { return new FixtureText(value, kind); }
    function element(tag, children, y, attributes = {}, x = 10, width = 280, height = 20) {
      return new FixtureElement(tag, children, rectangle(x, y, width, height), attributes);
    }
    const korean = panelScenario === "korean";
    function meterCard(kind, value, y, suffix = "") {
      const id = "fixture-" + kind + "-heading" + suffix;
      const name = kind === "session" ? (korean ? "현재 세션" : "Current session")
        : kind === "weekly" ? (korean ? "이번 주" : "Weekly limits") : "이번 주 Fable";
      const heading = element("span", [text(name, kind === "session" ? "sessionLabel" : "ordinary")], y, { id });
      const header = element("span", [heading], y);
      const meter = element("div", [], y + 50, {
        role: "meter", "aria-labelledby": id, "aria-valuemin": "0", "aria-valuemax": "100",
        "aria-valuenow": String(value), "aria-valuetext": String(value) + (korean ? "% 사용됨" : "% used")
      });
      meter.kind = kind;
      const fill = element("div", [meter], y + 50);
      const track = element("div", [fill], y + 50);
      const content = element("div", [track], y + 40, {}, 10, 280, 90);
      const card = element("div", [header, content], y, {}, 10, 290, 140);
      return { card, header, heading, content, track, fill, meter };
    }
    var session = meterCard("session", 32, 20);
    var weekly = meterCard("weekly", 64, 220);
    var model = meterCard("model", 7, 420);
    const search = element("input", [], 5, { type: "search" });
    Object.defineProperty(search, "value", { get: () => { protectedReads++; throw new Error("No settings search value access"); } });
    const switchControl = element("button", [text("Protected switch text", "protected")], 650, { role: "switch" });
    var dialog = element("div", [search, session.card, weekly.card, model.card, switchControl], 0, { role: "dialog" }, 0, 320, 900);
    var body = element("body", [dialog], 0, {}, 0, 320, 900);
    var html = element("html", [body], 0, {}, 0, 320, 900);
    function setLabel(target, value) { target.childNodes = []; target.appendChild(text(value, "sessionLabel")); }
    function setNow(value) { session.meter.attributes["aria-valuenow"] = value; }
    switch (panelScenario) {
      case "reversed": dialog.childNodes = [switchControl, model.card, weekly.card, session.card, search]; break;
      case "filledMeter": session.meter.appendChild(element("div", [], 70)); weekly.meter.appendChild(element("div", [], 270)); break;
      case "zeroMeters": for (const item of [session, weekly]) { item.meter.attributes["aria-valuenow"] = "0"; item.meter.attributes["aria-valuetext"] = "0% used"; } break;
      case "modelOnly": dialog.removeChild(weekly.card); break;
      case "missingSession": dialog.removeChild(session.card); break;
      case "missingWeekly": dialog.removeChild(weekly.card); break;
      case "hiddenSession": session.card.hidden = true; break;
      case "hiddenWeekly": weekly.card.hidden = true; break;
      case "unknownDOM": dialog.childNodes = []; break;
      case "orphanMeter": session.card.removeChild(session.content); dialog.appendChild(session.content); break;
      case "duplicateSession": dialog.appendChild(meterCard("session", 7, 700, "-copy").card); break;
      case "duplicateWeekly": dialog.appendChild(meterCard("weekly", 7, 700, "-copy").card); break;
      case "twoMetersInCard": { const extra = meterCard("session", 7, 100, "-extra"); session.content.appendChild(extra.meter); break; }
      case "remaining": session.meter.attributes["aria-valuetext"] = "32% remaining"; break;
      case "barePercent": session.meter.attributes["aria-valuetext"] = "32%"; break;
      case "invalidNow": setNow("101"); session.meter.attributes["aria-valuetext"] = "101% used"; break;
      case "nonfiniteNow": setNow("NaN"); break;
      case "negativeNow": setNow("-1"); break;
      case "leadingZero": setNow("032"); break;
      case "tooPrecise": setNow("32.123"); break;
      case "textMismatch": session.meter.attributes["aria-valuetext"] = "64% used"; break;
      case "twoPercentText": session.meter.attributes["aria-valuetext"] = "32% 7% used"; break;
      case "unknownUnit": session.meter.attributes["aria-valuetext"] = "32% fixture"; break;
      case "wrongMinimum": session.meter.attributes["aria-valuemin"] = "1"; break;
      case "wrongMaximum": session.meter.attributes["aria-valuemax"] = "101"; break;
      case "nestedLabel": session.heading.childNodes = []; session.heading.appendChild(element("span", [text("Current session", "sessionLabel")], 20)); break;
      case "splitTextLabel": session.heading.childNodes = []; session.heading.appendChild(text("Current ", "sessionLabel")); session.heading.appendChild(text("session", "sessionLabel")); break;
      case "wrongLabelTag": session.heading.localName = "h2"; session.heading.tagName = session.heading.nodeName = "H2"; break;
      case "oversizedLabel": setLabel(session.heading, "Current session" + "x".repeat(10)); break;
      case "missingLabel": session.meter.attributes["aria-labelledby"] = "fixture-missing"; break;
      case "multipleLabelIDs": session.meter.attributes["aria-labelledby"] += " fixture-weekly-heading"; break;
      case "oversizedLabelID": session.meter.attributes["aria-labelledby"] = "x".repeat(129); break;
      case "foreignLabel": session.header.removeChild(session.heading); body.appendChild(session.heading); break;
      case "allModelsContext":
      case "allModelsWithoutContext":
      case "allModelsSharedContext":
      case "duplicateWeeklyContext": {
        weekly.heading.childNodes = [text("All models")]; weekly.heading.childNodes[0].parentElement = weekly.heading;
        weekly.heading.childNodes[0].parentNode = weekly.heading;
        if (panelScenario === "allModelsWithoutContext") break;
        dialog.removeChild(weekly.card);
        const heading = element("h2", [text("Weekly limits")], 200);
        const group = element("div", [heading, weekly.card], 195, {}, 10, 290, 200);
        if (panelScenario === "allModelsSharedContext") { dialog.removeChild(session.card); group.appendChild(session.card); }
        if (panelScenario === "duplicateWeeklyContext") group.appendChild(element("h2", [text("Weekly limits")], 200));
        dialog.appendChild(group); break;
      }
      case "allModelsAndWeekly": {
        const extra = meterCard("weekly", 7, 700, "-all-models");
        extra.heading.childNodes = []; extra.heading.appendChild(text("All models"));
        dialog.appendChild(element("div", [element("h2", [text("Weekly limits")], 680), extra.card], 680, {}, 10, 290, 200));
        break;
      }
      case "modelPrefixOnly": weekly.heading.childNodes = []; weekly.heading.appendChild(text("이번 주 Fable")); break;
      case "splitModelHeading": weekly.header.appendChild(element("span", [text("(Fable)")], 220)); break;
      case "outerSplitModelHeading": {
        weekly.card.removeChild(weekly.header);
        const heading = element("h3", [weekly.header, element("span", [text("(Fable)")], 220)], 220);
        weekly.card.childNodes.unshift(heading); heading.parentElement = heading.parentNode = weekly.card;
        break;
      }
      case "shortProductLabel": model.heading.childNodes = []; model.heading.appendChild(text("기타")); break;
      case "unrelatedProductWrapper": model.header.appendChild(element("span", [text("product")], 420)); break;
      case "cardForm": session.content.appendChild(element("form", [element("input", [], 80), text("Protected account field", "protected")], 80)); break;
      case "cardEditable": { const editor = element("div", [text("Protected editor field", "protected")], 80, { contenteditable: "true" }); editor.isContentEditable = true; session.content.appendChild(editor); break; }
      case "hiddenAncestor": session.track.opacity = "0"; break;
      case "hiddenLabel": session.heading.hidden = true; break;
      case "hiddenMeter": session.meter.hidden = true; break;
      case "tooManyMeters": for (let i = 0; i < 13; i++) dialog.appendChild(meterCard("model", 7, 700, "-" + i).card); break;
      case "noDialog": delete dialog.attributes.role; break;
      case "loginOnly": dialog.childNodes = [element("form", [element("input", [], 80), text("Protected account field", "protected")], 80)]; break;
    }
    var window = {
      innerWidth: 320, innerHeight: 1200,
      location: {
        origin: panelScenario === "wrongOrigin" ? "https://fixture.invalid" : panelScenario === "confusableOrigin" ? "https://claude.ai.example" : panelScenario === "http" ? "http://claude.ai" : panelScenario === "nonstandardPort" ? "https://claude.ai:8443" : "https://claude.ai",
        protocol: panelScenario === "http" ? "http:" : "https:", hostname: "claude.ai", port: "", host: "claude.ai",
        pathname: panelScenario === "alternateRoute" ? "/fixture-route" : "/new",
        search: panelScenario === "queryAndFragment" ? "?source=fixture" : "", hash: "#settings/usage"
      },
      getComputedStyle: node => ({ display: node.hidden ? "none" : "block", visibility: "visible", opacity: node.opacity || "1" })
    };
    window.top = panelScenario === "iframe" ? {} : window;
    window.self = window;
    var document = {
      nodeType: 9, body, documentElement: html, defaultView: window,
      querySelectorAll: selector => { domQueries++; if (panelScenario === "scriptException") throw new Error("Synthetic DOM failure"); return html.querySelectorAll(selector); },
      querySelector: selector => document.querySelectorAll(selector)[0] || null,
      getElementById: id => { idLookups++; return html.querySelectorAll('[id]').find(node => node.id === id) || null; }
    };
    window.document = document;
    Object.defineProperty(document, "cookie", { get: () => { blockedAPICalls++; throw new Error("No cookie access"); } });
    for (const key of ["localStorage", "sessionStorage"]) Object.defineProperty(window, key, { get: () => { blockedAPICalls++; throw new Error("No storage access"); } });
    window.fetch = () => { blockedAPICalls++; throw new Error("No network access"); };
    window.XMLHttpRequest = function() { blockedAPICalls++; throw new Error("No network access"); };
    """#

}
#endif
