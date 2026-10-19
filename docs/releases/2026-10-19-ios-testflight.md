# iPhone 1.0(10) TestFlight 업로드 — 2026-10-19

## 확인한 결과

2026-10-19 **13:02:56 KST**, Xcode가 `Upload succeeded`, `Uploaded CodexTime`, `EXPORT SUCCEEDED`를 반환했다. 직전 응답은 `Uploaded package is processing`이었다. 앱·위젯은 모두 버전 `1.0`, 빌드 `10`, iOS 17 이상이다.

이후 **13:04:42 KST Apple의 테스트 가능 알림으로 빌드 10의 처리 완료를 확인했다.** TestFlight 그룹 배포·실기기 설치·App Store 심사·정식 출시는 별도로 확인하지 않았다. 빌드 10에는 Codex 전용 화면이 들어 있으며, 후속 [3열 UI 후보 1.0(11)](2026-10-19-ios-three-provider-card.md)과 구분한다. [TestFlight](https://appstoreconnect.apple.com/teams/8874948e-3fee-4bea-a414-67a4c0f0e7d8/apps/6805935440/testflight).

## 범위

기존 iPhone Codex 앱·소형 위젯을 재빌드했다. Codex 잔여율·리셋·누적 토큰·본인 계정 기기 로그인·오프라인 예시 기능을 유지한다. macOS의 Claude·Grok 연결은 포함하지 않는다. Windows 역시 이번 macOS 확장과 별개인 Codex 전용 구현이다.

기능 소스는 `b3848b0`의 iOS 코드와 같으며, 아카이브 명령에서 `CURRENT_PROJECT_VERSION=10`을 명시했다. 재현용 `ios/project.yml`과 체크인된 Xcode 프로젝트의 빌드 번호도 10으로 맞췄다.

## 검증

- iPhone 17 Pro Max / iOS 26.5 시뮬레이터 빌드·설치·실행 성공, 예시 모드의 명시적 배너와 Codex 화면 확인.
- iOS 단위 테스트 **14개 통과**, 실패·건너뜀 0개.
- Release archive 성공. 앱과 위젯의 번들 ID·버전·빌드·최소 iOS 확인.
- 앱·내장 위젯의 `codesign --verify --deep --strict` 성공.
- 기존 App Store export 설정으로 업로드 성공. 정식 App Store 출시 동작은 수행하지 않았다.
- 실기기 본인 계정 로그인과 위젯의 실제 갱신은 이번 검증에 포함하지 않았다. 시뮬레이터 예시는 실제 계정 조회 증거가 아니다.

## 재현과 상태 경계

```sh
xcodebuild -project ios/CodexTime.xcodeproj -scheme CodexTime \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath <archive-path> -allowProvisioningUpdates \
  archive DEVELOPMENT_TEAM=<your-team> CURRENT_PROJECT_VERSION=10

# destination=upload 설정이므로 다음 명령은 실제 Apple 업로드다.
xcodebuild -exportArchive -archivePath <archive-path> \
  -exportPath <export-path> \
  -exportOptionsPlist ios/Config/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

이전 [1.0(9) 제출 기록](../app-store/submission.md)은 2026-09-04 당시 이력이다. 2026-10-19 ASC 앱 목록은 1.0을 ‘제출 준비 중’으로 표시했으므로 과거 ‘심사 대기 중’을 현재 상태로 사용하지 않는다. 새 빌드의 업로드·Apple 처리·테스터 배포·App Store 심사·출시는 각각 별도로 확인한다.
