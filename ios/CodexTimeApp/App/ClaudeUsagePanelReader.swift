import Foundation
import CoreFoundation

/// Fixed outcomes only; webpage strings never become a native error message.
enum ClaudeUsagePanelFailure: String, CaseIterable {
    case wrongPage = "wrong_page"
    case missingUsage = "missing_usage"
    case ambiguousLimit = "ambiguous_limit"
    case unsafeContent = "unsafe_content"
    case unsupportedStructure = "unsupported_structure"
    case invalidPercent = "invalid_percent"
    case meaningMismatch = "meaning_mismatch"
    case scriptException = "script_exception"
    case unexpectedResult = "unexpected_result"
    case executionFailed = "execution_failed"

    var message: String {
        switch self {
        case .wrongPage: return "Claude 공식 웹 화면에서 사용량을 열어 주세요."
        case .missingUsage: return "보이는 사용량 화면에서 현재 세션과 전체 모델 주간 한도를 함께 확인하지 못했습니다."
        case .ambiguousLimit: return "한도 라벨이나 숫자가 여러 개여서 구분하지 못했습니다. 사용량 패널을 다시 열어 주세요."
        case .unsafeContent: return "입력·인증 화면에서는 사용량을 읽지 않습니다. 로그인을 마친 뒤 사용량을 열어 주세요."
        case .unsupportedStructure: return "현재 사용량 화면 구조를 안전하게 확인하지 못했습니다."
        case .invalidPercent: return "한도별 퍼센트 숫자를 확인하지 못했습니다."
        case .meaningMismatch: return "사용됨으로 표시된 퍼센트만 읽을 수 있습니다."
        case .scriptException, .unexpectedResult, .executionFailed: return "사용량 화면을 읽지 못했습니다. 화면을 다시 연 뒤 시도해 주세요."
        }
    }
}

enum ClaudeUsagePanelResult: Equatable {
    case success(sessionUsed: Double, weeklyUsed: Double)
    case unsupported(ClaudeUsagePanelFailure)
}

enum ClaudeUsagePanelReader {
    static func decode(_ result: Any?) -> ClaudeUsagePanelResult {
        guard let fields = result as? [String: Any], let status = fields["status"] as? String else {
            return .unsupported(.unexpectedResult)
        }
        if status == "ok", Set(fields.keys) == Set(["status", "sessionUsed", "weeklyUsed"]),
           let session = percent(fields["sessionUsed"]), let weekly = percent(fields["weeklyUsed"]) {
            return .success(sessionUsed: session, weeklyUsed: weekly)
        }
        if status == "unsupported", Set(fields.keys) == Set(["status", "reason"]),
           let reason = fields["reason"] as? String, let failure = ClaudeUsagePanelFailure(rawValue: reason) {
            return .unsupported(failure)
        }
        return .unsupported(.unexpectedResult)
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, (0...100).contains(value.doubleValue) else { return nil }
        return value.doubleValue
    }

    /// Uses the labelled meter structure observed on the official desktop usage
    /// panel. iPhone/WebKit validation is separate. No controls are clicked and
    /// only an atomic pair of numbers or a fixed reason leaves JavaScript.
    static let script = #"""
    (() => {
      const unsupported = reason => ({ status: "unsupported", reason });
      const reasons = new Set(["missing_usage", "ambiguous_limit", "unsafe_content", "unsupported_structure", "invalid_percent", "meaning_mismatch"]);
      try {
        if (window !== window.top || window.location.origin !== "https://claude.ai") return unsupported("wrong_page");
        const panelSelector = '[role="dialog"],main,[role="main"]';
        const inputs = 'form,input,textarea,[contenteditable]';
        const excluded = 'nav,aside,[role="navigation"],[role="complementary"],[role="banner"],[role="menu"],a,button';
        const visible = element => {
          const r = element.getBoundingClientRect();
          if (!(r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0
                && r.left < window.innerWidth && r.top < window.innerHeight)) return false;
          let ancestor = element;
          for (let depth = 0; ancestor && depth < 32; depth++, ancestor = ancestor.parentElement) {
            const style = window.getComputedStyle(ancestor);
            if (style.display === "none" || style.visibility !== "visible"
                || !Number.isFinite(Number(style.opacity)) || Number(style.opacity) <= 0) return false;
          }
          return ancestor === null;
        };
        const meters = document.querySelectorAll('[role="meter"]');
        if (meters.length > 12) return unsupported("unsupported_structure");
        if (!meters.length) return unsupported("missing_usage");
        let visited = 0, textNodes = 0, textSize = 0, labelReads = 0;
        const checkMetadata = (node, depth) => {
          if (++visited > 384 || depth > 12) throw "unsupported_structure";
          if (node.nodeType === Node.TEXT_NODE) {
            if (!Number.isInteger(node.length) || node.length < 0 || node.length > 160
                || ++textNodes > 96 || (textSize += node.length) > 8192) throw "unsupported_structure";
            return;
          }
          if (node.nodeType !== Node.ELEMENT_NODE) return;
          if (node.matches(inputs) || node.isContentEditable) throw "unsafe_content";
          if (node.matches(excluded)) return;
          if (node.childNodes.length > 32) throw "unsupported_structure";
          for (const child of node.childNodes) checkMetadata(child, depth + 1);
        };
        const records = [];
        for (const meter of meters) {
          if (!visible(meter) || meter.closest(excluded + ',' + inputs)) continue;
          if (meter.localName !== 'div') throw "unsupported_structure";
          const panel = meter.closest(panelSelector);
          if (!panel || !visible(panel)) continue;
          // This single ARIA reference is local lookup metadata, never returned.
          const labelID = meter.getAttribute('aria-labelledby');
          if (typeof labelID !== 'string' || labelID.length < 1 || labelID.length > 128
              || !/^[A-Za-z0-9_:.-]+$/.test(labelID)) throw "unsupported_structure";
          const label = document.getElementById(labelID);
          if (!label || !panel.contains(label) || !visible(label) || label.localName !== 'span'
              || label.closest(excluded + ',' + inputs) || label.childNodes.length !== 1
              || label.children.length !== 0 || label.childNodes[0].nodeType !== Node.TEXT_NODE) continue;
          const labelNode = label.childNodes[0];
          if (!Number.isInteger(labelNode.length) || labelNode.length < 1 || labelNode.length > 24) continue;
          checkMetadata(label, 0);
          if (++labelReads > 12) throw "unsupported_structure";
          const name = labelNode.substringData(0, labelNode.length).trim().replace(/\s+/g, ' ').toLowerCase();
          let metric = null;
          if (['현재 세션', '현재세션', 'current session'].includes(name)) metric = 'session';
          if (['이번 주', '이번주', 'weekly limits'].includes(name)) metric = 'weekly';
          if (['모든 모델', 'all models'].includes(name)) metric = 'allModels';
          // Unknown product limits are skipped before their card or value fields.
          if (!metric) continue;
          const wrapper = label.parentElement;
          // Validate the complete supported caption only after excluding unrelated
          // product meters, including short labels such as the Korean Other label.
          if (!wrapper || wrapper.localName !== 'span' || wrapper.children.length !== 1
              || wrapper.children[0] !== label || wrapper.childNodes.length !== 1 || !visible(wrapper)) throw "unsupported_structure";
          const heading = label.closest('h1,h2,h3,h4,h5,h6,[role="heading"]');
          if (heading && (heading.childNodes.length !== 1 || heading.children.length !== 1
              || heading.children[0] !== wrapper)) throw "unsupported_structure";
          let card = meter.parentElement;
          for (let depth = 0; card && card !== panel && depth < 5 && !card.contains(label); depth++) card = card.parentElement;
          if (!card || card === panel || !card.contains(label) || card.localName !== 'div' || !visible(card)
              || card.closest(excluded + ',' + inputs)) throw "unsupported_structure";
          const cardMeters = card.querySelectorAll('[role="meter"]');
          if (cardMeters.length !== 1 || cardMeters[0] !== meter) throw "ambiguous_limit";
          if (card.childNodes.length !== 2 || card.children.length !== 2) throw "unsupported_structure";
          const labelBranch = Array.from(card.children).find(node => node === label || node.contains(label));
          const meterBranch = Array.from(card.children).find(node => node === meter || node.contains(meter));
          if (!labelBranch || !meterBranch || labelBranch === meterBranch) throw "unsupported_structure";
          // Counts and text lengths are checked only in this smallest quota card;
          // settings search and unrelated account controls outside it are ignored.
          checkMetadata(card, 0);
          records.push({ meter, panel, card, label, metric });
        }
        const sessions = records.filter(record => record.metric === 'session');
        const weeks = records.filter(record => record.metric === 'weekly');
        const allModels = records.filter(record => record.metric === 'allModels');
        if (sessions.length > 1 || weeks.length > 1 || allModels.length > 1) throw "ambiguous_limit";
        if (sessions.length !== 1) throw "missing_usage";
        let week = weeks[0];
        if (allModels.length) {
          // All-models by itself says nothing about period. Require a bounded
          // exact weekly heading in its own group, never the whole dialog.
          if (week) throw "ambiguous_limit";
          week = allModels[0];
          let group = week.card.parentElement, confirmed = false;
          for (let depth = 0; group && group !== week.panel && depth < 3; depth++, group = group.parentElement) {
            if (group.contains(sessions[0].meter)) break;
            const headings = group.querySelectorAll('h1,h2,h3,h4,h5,h6,[role="heading"]');
            if (headings.length > 8) throw "unsupported_structure";
            let matches = 0;
            for (const heading of headings) {
              if (!visible(heading) || heading.closest(excluded + ',' + inputs) || heading.childNodes.length !== 1) continue;
              let leaf = heading.childNodes[0];
              if (leaf.nodeType === Node.ELEMENT_NODE && leaf.localName === 'span' && leaf.childNodes.length === 1) leaf = leaf.childNodes[0];
              if (leaf.nodeType !== Node.TEXT_NODE || ![3, 4, 13].includes(leaf.length)) continue;
              checkMetadata(heading, 0);
              if (++labelReads > 20) throw "unsupported_structure";
              const name = leaf.substringData(0, leaf.length).trim().toLowerCase();
              if (['이번주', '이번 주', 'weekly limits'].includes(name)) matches++;
            }
            if (matches > 1) throw "ambiguous_limit";
            if (matches === 1) { confirmed = true; break; }
          }
          if (!confirmed) throw "missing_usage";
        }
        if (!week || week.panel !== sessions[0].panel || week.card === sessions[0].card
            || week.card.contains(sessions[0].card) || sessions[0].card.contains(week.card)) throw "missing_usage";
        const readValue = record => {
          const minimum = record.meter.getAttribute('aria-valuemin');
          const maximum = record.meter.getAttribute('aria-valuemax');
          const raw = record.meter.getAttribute('aria-valuenow');
          const description = record.meter.getAttribute('aria-valuetext');
          // Attribute getters have no pre-read length API. Only these four
          // specific meter fields are obtained and bounded within JavaScript.
          if (minimum !== '0' || maximum !== '100' || typeof raw !== 'string' || raw.length > 7
              || !/^(?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?$/.test(raw)
              || typeof description !== 'string' || description.length < 4 || description.length > 24) throw "invalid_percent";
          const match = /^((?:100|[1-9]?[0-9])(?:\.[0-9]{1,2})?)\s?%\s*(used|사용됨|사용함)$/i.exec(description.trim());
          if (!match) {
            if (/remaining|남음|잔여/i.test(description)) throw "meaning_mismatch";
            throw "invalid_percent";
          }
          const value = Number(raw), displayed = Number(match[1]);
          if (!Number.isFinite(value) || value < 0 || value > 100 || value !== displayed) throw "invalid_percent";
          return value;
        };
        return { status: "ok", sessionUsed: readValue(sessions[0]), weeklyUsed: readValue(week) };
      } catch (reason) { return unsupported(reasons.has(reason) ? reason : "script_exception"); }
    })()
    """#
}
