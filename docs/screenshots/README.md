# 문서 화면 이미지

README 이미지는 현재 제품의 화면 코드에 **오프라인 예시 데이터**를 넣어 생성합니다. 실제 계정·로그인·Keychain·네트워크 조회를 사용하지 않습니다.

| 이미지 | 기준 | 내용 |
| --- | --- | --- |
| [macos-menubar-v0.3.1.png](macos-menubar-v0.3.1.png) | macOS 0.3.1 (2026101907) | 실제 `MenuBarPresentation`의 세 로고와 남은 사용량. 리셋 시간 표시를 끈 기본 상태 |
| [macos-setup-v0.3.1.png](macos-setup-v0.3.1.png) | macOS 0.3.1 (2026101907) | 실제 `ConnectionSettingsWindow`의 로그인 전 화면 |
| [macos-connected-v0.3.1.png](macos-connected-v0.3.1.png) | macOS 0.3.1 (2026101907) | 같은 설정 창의 세 서비스 연결 완료 예시 |
| [ios-widget-v1.0-b9.png](ios-widget-v1.0-b9.png) | iPhone 1.0 (9) | 실제 `CodexTimeWidgetView`와 `UsageSnapshot.demo`: 예시·갱신 시각·잔여율·리셋·누적 토큰 |

macOS는 AppKit 화면 내용을 PNG로 내보냅니다. iPhone은 별도의 오프라인 iOS Simulator 호스트에서 원본 위젯 뷰를 `ImageRenderer`로 렌더링합니다. 위젯 영역만 보여 주는 UI 미리보기이며 iPhone 홈 화면 전체를 촬영한 스크린샷은 아닙니다. 문서용 호스트는 사용자 앱의 인증정보·캐시를 사용하지 않습니다.

2026-10-19에 갱신했습니다. macOS 이미지는 M2 MacBook Air에서 생성했고, iPhone 이미지는 [iOS 26.4.1 Simulator 생성 실행](https://github.com/sundaynighttt/codextime/actions/runs/39231272682)에서 가져왔습니다. 제품 UI의 소스 기준은 [v0.3.1](https://github.com/sundaynighttt/codextime/tree/v0.3.1)이며 iPhone UI는 이 태그에 포함된 1.0 (9)입니다. 문서 그림 교체는 제품 버전이나 App Store 심사 상태를 변경하지 않습니다.

## 다시 생성하기

가장 간단한 방법은 GitHub Actions의 **Documentation previews → Run workflow**입니다. 완료되면 `documentation-previews` 아티팩트를 받아 이미지를 확인하고 이 폴더에 반영합니다. [워크플로](../../.github/workflows/docs-previews.yml)

로컬 macOS 이미지는 저장소 루트에서 다음 명령으로 만듭니다. Swift Command Line Tools가 필요합니다.

```sh
python3 docs/screenshots/render-macos.py
```

iPhone 이미지는 Xcode·사용 가능한 iPhone Simulator·XcodeGen이 있는 Mac에서 다음 명령으로 만듭니다. 임시 문서용 앱을 설치하고 이미지 출력 후 제거하며, 스크립트가 부팅한 시뮬레이터는 종료합니다.

```sh
python3 docs/screenshots/render-ios.py
```

화면을 따로 그린 예전 `CodexTimeScreenshotPreview` 대상은 이 이미지 생성에 사용하지 않습니다. UI가 바뀌면 원본 제품 뷰에서 다시 생성하고 파일명·버전·README 설명을 함께 갱신하세요.
