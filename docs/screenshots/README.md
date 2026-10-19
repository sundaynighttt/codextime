# 문서 화면 이미지

README 이미지는 현재 제품의 화면 코드에 **오프라인 예시 데이터**를 넣어 생성합니다. 실제 계정·로그인·Keychain·네트워크 조회를 사용하지 않습니다.

| 이미지 | 기준 | 내용 |
| --- | --- | --- |
| [macos-menubar-v0.3.1.png](macos-menubar-v0.3.1.png) | macOS 0.3.1 (2026101907) | 실제 `MenuBarPresentation`의 세 로고와 남은 사용량. 리셋 시간 표시를 끈 기본 상태 |
| [macos-setup-v0.3.1.png](macos-setup-v0.3.1.png) | macOS 0.3.1 (2026101907) | 실제 `ConnectionSettingsWindow`의 로그인 전 화면 |
| [macos-connected-v0.3.1.png](macos-connected-v0.3.1.png) | macOS 0.3.1 (2026101907) | 같은 설정 창의 세 서비스 연결 완료 예시 |
| [ios-widget-v1.0-b16.png](ios-widget-v1.0-b16.png) | iPhone 1.0 (16), TestFlight | 실제 `CodexTimeWidgetView`와 `UsageSnapshot.demo`: 세 로고·Codex 예시 73%·Grok 예시 없음·Claude 주간/세션 예시 없음·리셋·갱신 시각 |
| [ios-widget-v1.0-b9.png](ios-widget-v1.0-b9.png) | iPhone 1.0 (9), 이전 이미지 | 기존 Codex 전용 위젯 예시 보존 |

macOS는 AppKit 화면 내용을 PNG로 내보냅니다. iPhone은 별도의 오프라인 iOS Simulator 호스트에서 원본 위젯 뷰를 `ImageRenderer`로 렌더링합니다. 위젯 영역만 보여 주는 UI 미리보기이며 iPhone 홈 화면 전체를 촬영한 스크린샷은 아닙니다. 문서용 호스트는 사용자 앱의 인증정보·캐시를 사용하지 않습니다.

macOS 이미지는 2026-10-19에 M2 MacBook Air에서 생성했으며 소스 기준은 [v0.3.1](https://github.com/sundaynighttt/codextime/tree/v0.3.1)입니다. iPhone 이미지는 2026-10-20에 iOS 26.5 Simulator에서 [빌드 16 소스 커밋](https://github.com/sundaynighttt/codextime/tree/0effad7c2f703638a0a97d6b066dc6ea93d89114)을 고정해 새로 생성했습니다. 원본 `UsageEntry`, `CodexTimeWidgetView`, 공유 표시 뷰를 그대로 사용하며 네트워크 타임라인 공급자는 문서 호스트에서 제외합니다. 예시 모드는 Grok·Claude 숫자를 만들지 않습니다. 빌드 16은 별도 브랜치의 TestFlight 배포본이며, 문서 그림 교체는 main의 앱 코드·제품 버전·App Store 심사 상태를 변경하지 않습니다.

## 다시 생성하기

가장 간단한 방법은 GitHub Actions의 **Documentation previews → Run workflow**입니다. 완료되면 `documentation-previews` 아티팩트를 받아 이미지를 확인하고 이 폴더에 반영합니다. [워크플로](../../.github/workflows/docs-previews.yml)

로컬 macOS 이미지는 저장소 루트에서 다음 명령으로 만듭니다. Swift Command Line Tools가 필요합니다.

```sh
python3 docs/screenshots/render-macos.py
```

iPhone 이미지는 Xcode·사용 가능한 iPhone Simulator·XcodeGen이 있는 Mac에서 다음 명령으로 만듭니다. 임시 문서용 앱을 설치하고 이미지 출력 후 제거하며, 스크립트가 부팅한 시뮬레이터는 종료합니다. 먼저 공개 저장소에서 고정 소스 커밋을 가져옵니다. 렌더 실행 중 서비스 로그인·사용량 네트워크 조회는 없습니다.

```sh
git fetch origin 0effad7c2f703638a0a97d6b066dc6ea93d89114
python3 docs/screenshots/render-ios.py
```

화면을 따로 그린 예전 `CodexTimeScreenshotPreview` 대상은 이 이미지 생성에 사용하지 않습니다. UI가 바뀌면 원본 제품 뷰에서 다시 생성하고 파일명·버전·README 설명을 함께 갱신하세요.
