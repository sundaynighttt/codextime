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
#endif
