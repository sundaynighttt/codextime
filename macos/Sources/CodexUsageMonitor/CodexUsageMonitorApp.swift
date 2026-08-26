import AppKit
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @StateObject private var store = UsageStore()
    @AppStorage("showResetTimeInMenuBar") private var showResetTimeInMenuBar = true

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(store: store, showResetTimeInMenuBar: $showResetTimeInMenuBar)
        } label: {
            Text(store.menuTitle(showResetTime: showResetTimeInMenuBar))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Codex 남은 사용량 \(store.menuTitle(showResetTime: showResetTimeInMenuBar))")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct StatusMenu: View {
    @ObservedObject var store: UsageStore
    @Binding var showResetTimeInMenuBar: Bool
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Group {
            if let buckets = store.report?.buckets {
                ForEach(buckets) { bucket in
                    Section(bucket.name) {
                        Text(UsageFormatter.detail(for: bucket, now: store.now))
                            .monospacedDigit()
                        if let secondary = bucket.secondary {
                            Text("추가 한도 \(max(0, 100 - secondary.usedPercent))% · \(UsageFormatter.remainingTime(until: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }, now: store.now))")
                                .monospacedDigit()
                        }
                    }
                }
            } else if store.isRefreshing {
                Text("Codex 사용량 확인 중…")
            }

            if let error = store.errorMessage {
                Text(error)
            }

            if let loginItemError {
                Text(loginItemError)
            }

            Divider()

            Button {
                store.refresh()
            } label: {
                Label(store.isRefreshing ? "새로고침 중…" : "지금 새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)

            Toggle("메뉴바에 리셋 시간 표시", isOn: $showResetTimeInMenuBar)

            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try LoginItemManager.setEnabled(newValue)
                        launchAtLogin = LoginItemManager.isEnabled
                        loginItemError = nil
                    } catch {
                        launchAtLogin = LoginItemManager.isEnabled
                        loginItemError = "자동 실행 설정 실패: \(error.localizedDescription)"
                    }
                }
            ))

            Button("Codex 사용량 설정 열기") {
                NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
            }

            if let lastUpdated = store.lastUpdated {
                Text("업데이트 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
            }

            Divider()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
