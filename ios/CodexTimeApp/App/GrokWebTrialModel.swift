import Foundation
import CoreFoundation
import SwiftUI
import WebKit

enum GrokTrialReadFailure: String, CaseIterable {
    case wrongPage = "wrong_page"
    case noSelection = "no_selection"
    case collapsedSelection = "collapsed_selection"
    case multipleRanges = "multiple_ranges"
    case nonTextRange = "non_text_range"
    case crossNodeRange = "cross_node_range"
    case anchorFocusMismatch = "anchor_focus_mismatch"
    case selectionLength = "selection_length"
    case noDialog = "no_dialog"
    case dialogMismatch = "dialog_mismatch"
    case editableSelection = "editable_selection"
    case formInDialog = "form_in_dialog"
    case invisibleDialog = "invisible_dialog"
    case invisibleRange = "invisible_range"
    case missingPercent = "missing_percent"
    case invalidPercentFormat = "invalid_percent_format"
    case percentOutOfRange = "percent_out_of_range"
    case scriptException = "script_exception"
    case unexpectedResult = "unexpected_result"
    case executionFailed = "execution_failed"
    case pointCancelled = "point_cancelled"
    case pointTimeout = "point_timeout"
    case untrustedEvent = "untrusted_event"
    case pointOutsideViewport = "point_outside_viewport"
    case pointNoTarget = "point_no_target"
    case pointOutsideTarget = "point_outside_target"
    case shadowStructure = "shadow_structure"
    case missingLabel = "missing_label"
    case labelLength = "label_length"
    case noUsageRegion = "no_usage_region"
    case textStructure = "text_structure"
    case textLength = "text_length"
    case meaningMismatch = "meaning_mismatch"

    var message: String {
        switch self {
        case .wrongPage: return "공식 사용량 주소가 아닙니다."
        case .noSelection: return "웹 선택 영역이 없습니다. 숫자와 %를 직접 선택해 주세요."
        case .collapsedSelection: return "앱에서 읽는 웹 선택 영역이 접혀 있습니다. 제공자 차단을 뜻하지 않습니다."
        case .multipleRanges: return "선택 영역이 하나가 아닙니다."
        case .nonTextRange: return "일반 텍스트 선택이 아닙니다."
        case .crossNodeRange: return "선택이 여러 텍스트 노드에 걸쳐 있습니다."
        case .anchorFocusMismatch: return "화면의 선택 기준과 읽기 범위가 일치하지 않습니다."
        case .selectionLength: return "선택 범위가 허용한 2~8자를 벗어났습니다."
        case .noDialog: return "선택 영역에서 지원하는 사용량 대화상자를 확인하지 못했습니다."
        case .dialogMismatch: return "선택의 양끝이 동일한 사용량 대화상자 안에 있지 않습니다."
        case .editableSelection: return "선택 범위가 입력창·폼·편집 영역과 겹칩니다."
        case .formInDialog: return "대화상자에 입력창·폼·편집 영역이 있어 현재 안전 규칙으로 중단했습니다."
        case .invisibleDialog: return "사용량 대화상자가 보이는 상태인지 확인하지 못했습니다."
        case .invisibleRange: return "선택 범위가 화면 안에 보이는지 확인하지 못했습니다."
        case .missingPercent: return "선택에 % 기호가 없습니다. 숫자와 기호를 함께 선택해 주세요."
        case .invalidPercentFormat: return "선택이 퍼센트 숫자 하나의 형식이 아닙니다."
        case .percentOutOfRange: return "선택한 퍼센트가 허용 범위를 벗어났습니다."
        case .scriptException: return "제한된 선택 검사 중 오류가 발생했습니다. 상세 웹 데이터는 가져오지 않았습니다."
        case .unexpectedResult: return "허용된 숫자·상태 형식으로 응답하지 않았습니다."
        case .executionFailed: return "웹뷰에서 제한된 숫자 검사를 실행하지 못했습니다."
        case .pointCancelled: return "숫자 위치 읽기를 취소했습니다."
        case .pointTimeout: return "15초가 지나 위치 읽기를 종료했습니다. 다시 준비한 뒤 숫자를 한 번 탭하세요."
        case .untrustedEvent: return "직접 탭한 화면 이벤트가 아니어서 읽지 않았습니다."
        case .pointOutsideViewport: return "탭한 위치가 현재 웹 화면 안에 있지 않습니다."
        case .pointNoTarget: return "탭한 위치의 화면 요소를 확인하지 못했습니다."
        case .pointOutsideTarget: return "탭한 위치와 숫자 요소의 표시 범위가 일치하지 않습니다."
        case .shadowStructure: return "탭한 숫자의 공개 웹 구성요소가 검증된 구조와 다릅니다."
        case .missingLabel: return "탭한 숫자에 지원하는 접근성 퍼센트 값이 없습니다."
        case .labelLength: return "숫자 요소의 접근성 값이 허용한 2~8자를 벗어났습니다."
        case .noUsageRegion: return "탭한 숫자가 지원하는 사용량 화면 영역 안에 있지 않습니다."
        case .textStructure: return "탭한 요소가 지원하는 짧은 퍼센트 텍스트 구조가 아닙니다. 다른 숫자를 직접 선택해 주세요."
        case .textLength: return "탭한 요소의 텍스트가 허용한 2~24자를 벗어났습니다. 더 작은 퍼센트 숫자를 직접 탭해 주세요."
        case .meaningMismatch: return "화면의 사용·잔여 문구와 선택한 숫자 의미가 다릅니다. 의미를 맞춘 뒤 다시 읽어 주세요."
        }
    }

    var displayText: String {
        #if DEBUG
        return "읽기 중단: " + message + " [" + rawValue + "]"
        #else
        return "읽기 중단: " + message
        #endif
    }
}

enum GrokTrialScriptResult: Equatable {
    case value(Double)
    case unsupported(GrokTrialReadFailure)
}

@MainActor
final class ProviderWebUsageModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let usageURL = URL(string: "https://grok.com/?_s=usage")!
    let provider: WebUsageProvider
    var onReading: ((WebUsageReading) -> Void)?
    var onDisconnect: (() -> Void)?
    @Published var valueKind: WebUsageValueKind = .used {
        didSet { if valueKind != oldValue { invalidateReadingContext() } }
    }
    @Published var metric: WebUsageMetric {
        didSet { if metric != oldValue { invalidateReadingContext() } }
    }

    init(provider: WebUsageProvider = .grok) {
        self.provider = provider
        self.metric = provider == .grok ? .grokWeekly : .claudeSession
        super.init()
        self.pageHost = provider.usageURL.host ?? provider.name
    }

    var availableMetrics: [WebUsageMetric] {
        provider == .grok ? [.grokWeekly] : [.claudeSession, .claudeWeekly]
    }

    private func invalidateReadingContext() {
        cancelPointRead(clearMessage: false)
        navigationGeneration &+= 1
        selectedPercent = nil
        readMessage = "읽는 한도·숫자 의미가 바뀌었습니다. 새 조건으로 위치 지정을 준비해 주세요."
    }

    @Published private(set) var webView: WKWebView?
    @Published private(set) var pageHost = "grok.com"
    @Published private(set) var isLoading = false
    @Published private(set) var isAtUsagePage = false
    @Published var userConfirmedUsageVisible = false {
        didSet {
            if !userConfirmedUsageVisible {
                cancelPointRead(clearMessage: false)
                navigationGeneration &+= 1
                isReading = false
                selectedPercent = nil
                readMessage = "읽은 값 없음 · 위치 지정을 준비한 뒤 사용량 패널의 % 숫자를 한 번 탭하세요."
            }
        }
    }
    @Published private(set) var navigationMessage = "공식 웹 사용량 화면을 여는 중입니다."
    @Published private(set) var readMessage = "실험: 위치 지정을 준비한 뒤 공식 사용량 패널의 % 숫자를 한 번 탭하세요. 화면 구조를 확인할 수 없으면 읽기를 중단합니다."
    @Published private(set) var isReading = false
    @Published private(set) var selectedPercent: Double?
    @Published private(set) var isPointReadArmed = false

    private var urlObservation: NSKeyValueObservation?
    private var navigationGeneration: UInt64 = 0
    private var pointReadTask: Task<Void, Never>?
    private var pointReadRequestID: String?

    var canReadVisibleUsage: Bool {
        webView != nil && isAtUsagePage && userConfirmedUsageVisible && !isReading
    }

    func open() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        // Keep WebKit's standard user agent and challenge behavior unchanged.
        webView = view
        urlObservation = view.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateLocation() }
        }
        openUsagePage()
    }

    func openUsagePage() {
        guard let webView else { return }
        userConfirmedUsageVisible = false
        selectedPercent = nil
        navigationGeneration &+= 1
        webView.load(URLRequest(url: provider.usageURL))
    }

    func disconnect() { close() }

    func close() {
        cancelPointRead(clearMessage: false)
        navigationGeneration &+= 1
        selectedPercent = nil
        isReading = false
        urlObservation?.invalidate()
        urlObservation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        isLoading = false
        isAtUsagePage = false
        userConfirmedUsageVisible = false
        pageHost = "세션 종료"
        navigationMessage = "임시 웹 세션을 종료했습니다."
        onDisconnect?()
    }

    func armPointRead() {
        guard canReadVisibleUsage, let view = webView, Self.isEligibleUsageURL(view.url, provider: provider) else { return }
        let requestID = UUID().uuidString
        let generation = navigationGeneration
        let frozenKind = valueKind
        let frozenMetric = metric
        pointReadRequestID = requestID
        selectedPercent = nil
        isReading = true
        isPointReadArmed = true
        readMessage = "15초 안에 사용량 패널의 읽을 % 숫자를 한 번 탭하세요. 이 한 번의 웹 탭은 이동·버튼 동작 대신 숫자 읽기에만 사용합니다."
        pointReadTask = Task { @MainActor [weak self, weak view] in
            guard let self, let view, !Task.isCancelled, self.pointReadRequestID == requestID else { return }
            defer {
                if self.pointReadRequestID == requestID {
                    self.pointReadRequestID = nil
                    self.pointReadTask = nil
                    self.isPointReadArmed = false
                    self.isReading = false
                }
            }
            do {
                let result: Any? = try await view.callAsyncJavaScript(
                    self.provider == .grok ? Self.pointTapScript : Self.claudePointTapScript, arguments: ["requestID": requestID, "selectedValueKind": frozenKind.rawValue], in: nil, contentWorld: .defaultClient
                )
                guard !Task.isCancelled, generation == self.navigationGeneration,
                      self.pointReadRequestID == requestID, view === self.webView,
                      self.isAtUsagePage, Self.isEligibleUsageURL(view.url, provider: self.provider), self.userConfirmedUsageVisible,
                      self.valueKind == frozenKind, self.metric == frozenMetric else { return }
                self.displayScriptResult(result, kind: frozenKind, metric: frozenMetric)
            } catch {
                guard !Task.isCancelled, generation == self.navigationGeneration,
                      self.pointReadRequestID == requestID else { return }
                self.readMessage = GrokTrialReadFailure.executionFailed.displayText
            }
        }
    }

    func cancelPointRead(clearMessage: Bool = true) {
        let requestID = pointReadRequestID
        pointReadRequestID = nil
        pointReadTask?.cancel()
        pointReadTask = nil
        isPointReadArmed = false
        isReading = false
        if let requestID, let view = webView {
            // Revoke the temporary listener in the same isolated world, rather
            // than merely discarding a later result in Swift. No site state is read.
            view.callAsyncJavaScript(Self.cancelPointTapScript, arguments: ["requestID": requestID],
                                     in: nil, in: .defaultClient, completionHandler: { _ in })
        }
        if clearMessage {
            selectedPercent = nil
            readMessage = GrokTrialReadFailure.pointCancelled.displayText
        }
    }

    private func displayScriptResult(_ result: Any?, kind: WebUsageValueKind? = nil, metric: WebUsageMetric? = nil) {
        switch Self.decodeScriptResult(result) {
        case let .unsupported(failure):
            readMessage = failure.displayText
        case let .value(percent):
            let reading = WebUsageReading(provider: provider, percent: percent, valueKind: kind ?? valueKind,
                                          metric: metric ?? self.metric, updatedAt: Date())
            guard reading.isValid else {
                readMessage = GrokTrialReadFailure.unexpectedResult.displayText
                return
            }
            selectedPercent = percent
            onReading?(reading)
            let number = percent.formatted(.number.precision(.fractionLength(0...2)))
            readMessage = "화면에서 읽은 값 \(number)% · 선택한 의미: \((kind ?? valueKind) == .used ? "사용함" : "남음"). 자동 갱신하지 않습니다."
        }
    }

    func readVisibleUsage() async {
        guard canReadVisibleUsage, let view = webView,
              Self.isEligibleUsageURL(view.url, provider: provider) else {
            readMessage = "공식 사용량 주소와 화면 확인이 필요합니다."
            return
        }
        selectedPercent = nil
        isReading = true
        let generation = navigationGeneration
        defer { if generation == navigationGeneration { isReading = false } }
        do {
            let result: Any? = try await Self.evaluateSelection(in: view)
            guard generation == navigationGeneration, view === webView,
                  isAtUsagePage, Self.isEligibleUsageURL(view.url, provider: provider), userConfirmedUsageVisible else { return }
            displayScriptResult(result)
        } catch {
            guard generation == navigationGeneration else { return }
            readMessage = GrokTrialReadFailure.executionFailed.displayText
        }
    }

    nonisolated static func decodeScriptResult(_ result: Any?) -> GrokTrialScriptResult {
        guard let fields = result as? [String: Any], let status = fields["status"] as? String else {
            return .unsupported(.unexpectedResult)
        }
        if status == "ok", Set(fields.keys) == Set(["status", "percent"]),
           let number = fields["percent"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue.isFinite, (0...100).contains(number.doubleValue) {
            return .value(number.doubleValue)
        }
        if status == "unsupported", Set(fields.keys) == Set(["status", "reason"]),
           let code = fields["reason"] as? String, let failure = GrokTrialReadFailure(rawValue: code) {
            return .unsupported(failure)
        }
        return .unsupported(.unexpectedResult)
    }

    // The async WebKit overlay uses `contentWorld:`. The similarly named
    // callback overload uses `in:` and returns Void when no callback is supplied.
    static func evaluateSelection(in view: WKWebView) async throws -> Any? {
        try await view.evaluateJavaScript(manualSelectionScript, in: nil, contentWorld: .defaultClient)
    }

    /// One human-selected point, one already verified numeric host, one attribute.
    /// The attribute string is obtained before its length can be checked; it is
    /// kept in JavaScript and only a strict numeric result can leave the page.
    static let pointReaderFunction = #"""
    function readPoint(x, y) {
      const unsupported = reason => ({ status: "unsupported", reason });
      try {
        if (window !== window.top || window.location.origin !== "https://grok.com"
            || window.location.pathname !== "/" || window.location.search !== "?_s=usage"
            || window.location.hash !== "") return unsupported("wrong_page");
        if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0
            || x >= window.innerWidth || y >= window.innerHeight) return unsupported("point_outside_viewport");
        const host = document.elementFromPoint(x, y);
        if (!host || !host.isConnected) return unsupported("point_no_target");
        const dialog = host.closest('[role="dialog"]');
        if (!dialog) return unsupported("no_dialog");
        const forbidden = 'input,textarea,form,[contenteditable]';
        if (host.closest(forbidden) || host.isContentEditable) return unsupported("editable_selection");
        if (dialog.querySelector(forbidden)) return unsupported("form_in_dialog");
        const visibleRect = rect => rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0
          && rect.top < window.innerHeight && rect.left < window.innerWidth;
        const visible = node => {
          const style = window.getComputedStyle(node);
          return style.display !== "none" && style.visibility === "visible" && Number(style.opacity) > 0
            && visibleRect(node.getBoundingClientRect());
        };
        if (!visible(dialog)) return unsupported("invisible_dialog");
        if (!visible(host)) return unsupported("invisible_range");
        const rect = host.getBoundingClientRect();
        if (x < rect.left || x >= rect.right || y < rect.top || y >= rect.bottom) return unsupported("point_outside_target");
        const root = host.shadowRoot;
        if (!root || root.mode !== "open" || root.host !== host) return unsupported("shadow_structure");
        if (root.querySelector(forbidden)) return unsupported("editable_selection");
        if (root.childNodes.length !== 3) return unsupported("shadow_structure");
        const children = Array.from(root.childNodes);
        if (!children.every(node => node.nodeType === Node.ELEMENT_NODE && node.localName === "span")
            || children[0].childNodes.length !== 0 || children[1].childNodes.length !== 1
            || children[2].childNodes.length !== 1) return unsupported("shadow_structure");
        if (!host.hasAttribute("aria-label")) return unsupported("missing_label");
        const label = host.getAttribute("aria-label");
        if (typeof label !== "string" || label.length < 2 || label.length > 8) return unsupported("label_length");
        const match = /^((?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?)\s?%$/.exec(label.trim());
        if (!match) return unsupported("invalid_percent_format");
        const percent = Number(match[1]);
        if (!Number.isFinite(percent) || percent < 0 || percent > 100) return unsupported("percent_out_of_range");
        return { status: "ok", percent };
      } catch (_) { return unsupported("script_exception"); }
    }
    """#

    /// Claude candidate: only the single element at the human's trusted tap.
    /// No provider-specific DOM selector is assumed or advertised as verified.
    /// Text-node lengths are checked before any text is materialized, and no
    /// ancestor/sibling/descendant text or raw string leaves JavaScript.
    static let claudePointReaderFunction = #"""
    function readPoint(x, y, expectedKind) {
      const unsupported = reason => ({ status: "unsupported", reason });
      try {
        if (window !== window.top || window.location.origin !== "https://claude.ai"
            || window.location.pathname !== "/settings/usage" || window.location.search !== ""
            || window.location.hash !== "") return unsupported("wrong_page");
        if (expectedKind !== "used" && expectedKind !== "remaining") return unsupported("meaning_mismatch");
        if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0
            || x >= window.innerWidth || y >= window.innerHeight) return unsupported("point_outside_viewport");
        const host = document.elementFromPoint(x, y);
        if (!host || !host.isConnected) return unsupported("point_no_target");
        const forbidden = 'nav,aside,[role="navigation"],[role="complementary"],a,button,input,textarea,form,[contenteditable]';
        if (host.closest(forbidden) || host.isContentEditable) return unsupported("editable_selection");
        const region = host.closest('main,[role="main"],[role="dialog"]');
        if (!region) return unsupported("no_usage_region");
        const visibleRect = rect => rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0
          && rect.top < window.innerHeight && rect.left < window.innerWidth;
        const visible = node => {
          const style = window.getComputedStyle(node);
          return style.display !== "none" && style.visibility === "visible" && Number(style.opacity) > 0
            && visibleRect(node.getBoundingClientRect());
        };
        if (!visible(region)) return unsupported("invisible_dialog");
        if (!visible(host)) return unsupported("invisible_range");
        const rect = host.getBoundingClientRect();
        if (x < rect.left || x >= rect.right || y < rect.top || y >= rect.bottom) return unsupported("point_outside_target");
        if (host.shadowRoot) return unsupported("text_structure");
        if (host.childNodes.length < 1 || host.childNodes.length > 3) return unsupported("text_structure");
        const nodes = Array.from(host.childNodes);
        if (!nodes.every(node => node.nodeType === Node.TEXT_NODE)) return unsupported("text_structure");
        const lengths = nodes.map(node => node.length);
        if (!lengths.every(length => Number.isInteger(length) && length >= 0)) return unsupported("text_length");
        const length = lengths.reduce((sum, count) => sum + count, 0);
        if (length < 2 || length > 24) return unsupported("text_length");
        const text = nodes.map((node, index) => node.substringData(0, lengths[index])).join("").trim();
        const match = /^(?:(used|remaining|사용함|사용됨|사용량|사용|남음|잔여량|잔여)\s*)?((?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?)\s?%(?:\s*(used|remaining|사용함|사용됨|사용량|사용|남음|잔여량|잔여))?$/i.exec(text);
        if (!match || (match[1] && match[3])) return unsupported("invalid_percent_format");
        const unit = (match[1] || match[3] || "").toLowerCase();
        if (unit) {
          const actualKind = ["remaining", "남음", "잔여량", "잔여"].includes(unit) ? "remaining" : "used";
          if (actualKind !== expectedKind) return unsupported("meaning_mismatch");
        }
        const percent = Number(match[2]);
        if (!Number.isFinite(percent) || percent < 0 || percent > 100) return unsupported("percent_out_of_range");
        return { status: "ok", percent };
      } catch (_) { return unsupported("script_exception"); }
    }
    """#

    static let pointTapScript = pointReaderFunction + pointTapCoordinatorScript
    static let claudePointTapScript = claudePointReaderFunction + pointTapCoordinatorScript
        .replacingOccurrences(of: "https://grok.com", with: "https://claude.ai")
        .replacingOccurrences(of: "pathname === \"/\"", with: "pathname === \"/settings/usage\"")
        .replacingOccurrences(of: "search === \"?_s=usage\"", with: "search === \"\"")

    private static let pointTapCoordinatorScript = #"""
    const unsupported = reason => ({ status: "unsupported", reason });
    const correctPage = () => window === window.top && window.location.origin === "https://grok.com"
      && window.location.pathname === "/" && window.location.search === "?_s=usage" && window.location.hash === "";
    if (!correctPage()) return unsupported("wrong_page");
    if (typeof requestID !== "string" || requestID.length > 64) return unsupported("script_exception");
    if (window.__codexGrokTrialPointRead) window.__codexGrokTrialPointRead.cancel();
    return await new Promise(resolve => {
      let finished = false;
      let timer;
      const cleanup = () => {
        document.removeEventListener("click", click, true);
        window.removeEventListener("pagehide", cancel, true);
        window.clearTimeout(timer);
        if (window.__codexGrokTrialPointRead?.requestID === requestID) delete window.__codexGrokTrialPointRead;
      };
      const finish = result => {
        if (finished) return;
        finished = true;
        cleanup();
        resolve(result);
      };
      const cancel = () => finish(unsupported("point_cancelled"));
      const click = event => {
        if (finished) return;
        if (window.__codexGrokTrialPointRead?.requestID !== requestID) return finish(unsupported("point_cancelled"));
        if (!correctPage()) return finish(unsupported("wrong_page"));
        if (!event.isTrusted) return finish(unsupported("untrusted_event"));
        event.preventDefault();
        event.stopImmediatePropagation();
        finish(readPoint(event.clientX, event.clientY, typeof selectedValueKind === "string" ? selectedValueKind : null));
      };
      window.__codexGrokTrialPointRead = { requestID, cancel };
      document.addEventListener("click", click, true);
      window.addEventListener("pagehide", cancel, true);
      timer = window.setTimeout(() => finish(unsupported("point_timeout")), 15000);
    });
    """#

    static let cancelPointTapScript = #"""
    const active = window.__codexGrokTrialPointRead;
    if (active && active.requestID === requestID) active.cancel();
    return { status: "cancelled" };
    """#

    /// Reads only a user-created selection in one visible standard ARIA dialog.
    /// This is an experimental candidate boundary, not a verified Grok selector.
    /// Only a status and parsed number can leave the page; no selected text returns.
    static let manualSelectionScript = #"""
    (() => {
      const unsupported = reason => ({ status: "unsupported", reason });
      try {
        if (window !== window.top || window.location.origin !== "https://grok.com"
            || window.location.pathname !== "/" || window.location.search !== "?_s=usage"
            || window.location.hash !== "") return unsupported("wrong_page");
        const selection = window.getSelection();
        if (!selection) return unsupported("no_selection");
        if (selection.isCollapsed) return unsupported("collapsed_selection");
        if (selection.rangeCount !== 1) return unsupported("multiple_ranges");
        const range = selection.getRangeAt(0);
        if (!range.startContainer || !range.endContainer
            || range.startContainer.nodeType !== Node.TEXT_NODE
            || range.endContainer.nodeType !== Node.TEXT_NODE) return unsupported("non_text_range");
        if (range.startContainer !== range.endContainer) return unsupported("cross_node_range");
        if (selection.anchorNode !== range.startContainer || selection.focusNode !== range.endContainer) return unsupported("anchor_focus_mismatch");
        const length = range.endOffset - range.startOffset;
        if (!Number.isInteger(length) || length < 2 || length > 8) return unsupported("selection_length");
        const element = node => node && (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement);
        const anchor = element(selection.anchorNode);
        const focus = element(selection.focusNode);
        const ancestor = element(range.commonAncestorContainer);
        if (!anchor || !focus || !ancestor) return unsupported("non_text_range");
        const dialog = anchor.closest('[role="dialog"]');
        if (!dialog) return unsupported("no_dialog");
        if (focus.closest('[role="dialog"]') !== dialog || !dialog.contains(ancestor)) return unsupported("dialog_mismatch");
        const forbidden = 'input,textarea,form,[contenteditable]';
        if (anchor.closest(forbidden) || focus.closest(forbidden) || ancestor.closest(forbidden)
            || anchor.isContentEditable || focus.isContentEditable || ancestor.isContentEditable) return unsupported("editable_selection");
        if (dialog.querySelector(forbidden)) return unsupported("form_in_dialog");
        const visibleRect = rect => rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0
          && rect.top < window.innerHeight && rect.left < window.innerWidth;
        const visible = node => {
          const style = window.getComputedStyle(node);
          return style.display !== "none" && style.visibility === "visible" && Number(style.opacity) > 0
            && visibleRect(node.getBoundingClientRect());
        };
        if (!visible(dialog)) return unsupported("invisible_dialog");
        if (!visible(anchor) || !visible(focus)
            || !Array.from(range.getClientRects()).some(visibleRect)) return unsupported("invisible_range");
        const selected = selection.toString();
        if (typeof selected !== "string" || selected.length < 2 || selected.length > 8) return unsupported("selection_length");
        const trimmed = selected.trim();
        if (/^(?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?$/.test(trimmed)) return unsupported("missing_percent");
        const match = /^((?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?)\s?%$/.exec(trimmed);
        if (!match) return unsupported("invalid_percent_format");
        const percent = Number(match[1]);
        if (!Number.isFinite(percent) || percent < 0 || percent > 100) return unsupported("percent_out_of_range");
        return { status: "ok", percent };
      } catch (_) { return unsupported("script_exception"); }
    })()
    """#

    private func updateLocation() {
        let url = webView?.url
        pageHost = url?.host ?? provider.usageURL.host ?? provider.name
        let wasAtUsagePage = isAtUsagePage
        isAtUsagePage = Self.isEligibleUsageURL(url, provider: provider)
        if !isAtUsagePage || wasAtUsagePage != isAtUsagePage {
            userConfirmedUsageVisible = false
            selectedPercent = nil
            navigationGeneration &+= 1
        }
        navigationMessage = isAtUsagePage ? "공식 사용량 주소입니다. 실제 패널 표시를 직접 확인해 주세요." : "공식 웹 로그인 흐름은 화면에서 직접 진행해 주세요."
    }

    nonisolated static func isEligibleUsageURL(_ url: URL?, provider: WebUsageProvider = .grok) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443, components.fragment == nil else { return false }
        switch provider {
        case .grok:
            return components.host?.lowercased() == "grok.com"
                && (components.path == "/" || components.path.isEmpty)
                && components.queryItems == [URLQueryItem(name: "_s", value: "usage")]
        case .claude:
            return components.host?.lowercased() == "claude.ai" && components.path == "/settings/usage"
                && (components.queryItems == nil || components.queryItems?.isEmpty == true)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Normal HTTPS provider/SSO redirects stay inside this same temporary web view.
        // No custom-scheme callback interception or challenge bypass is attempted.
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        if scheme == "https" || navigationAction.request.url?.absoluteString == "about:blank" {
            decisionHandler(.allow)
        } else {
            navigationMessage = "이 실험은 HTTPS 웹 화면만 지원합니다. 외부 앱 인증은 처리하지 않습니다."
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        navigationGeneration &+= 1
        selectedPercent = nil
        userConfirmedUsageVisible = false
        updateLocation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateLocation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }

    private func loadingFailed(_ error: Error) {
        isLoading = false
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationMessage = "웹 화면을 불러오지 못했습니다. 제공자가 웹뷰 로그인을 제한하면 여기서 중단합니다."
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

typealias GrokWebTrialModel = ProviderWebUsageModel
