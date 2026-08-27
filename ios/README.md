# CodexTime for iPhone (alpha)

홈 화면 위젯에서 Codex의 남은 사용량과 리셋까지 남은 시간만 확인하기 위한 최소 iPhone 앱입니다.

## 현재 범위

- iOS 17 이상
- 소형 위젯 한 종류: `Codex / 98% / 3d 17h`
- OpenAI 공식 기기 로그인 화면을 통한 ChatGPT 연결
- 30분 간격의 위젯 타임라인 갱신 요청
- 광고·분석·별도 중계 서버 없음

앱 화면은 최초 연결, 수동 새로고침, 연결 해제만 제공합니다. iOS가 실제 위젯 갱신 시점을 결정하므로 정확히 30분마다 실행된다고 보장되지는 않습니다.

> 이 구현은 OpenAI가 공개한 Codex 기기 로그인과 사용량 응답 형식을 사용하는 실험적 알파입니다. OpenAI의 공식 iPhone 앱이 아니며, 인증 또는 사용량 형식이 바뀌면 업데이트가 필요할 수 있습니다.

## 직접 빌드

1. Xcode 16 이상과 [XcodeGen](https://github.com/yonaskolb/XcodeGen)을 설치합니다.
2. `ios` 폴더에서 프로젝트를 생성합니다.

   ```bash
   xcodegen generate
   ```

3. `CodexTime.xcodeproj`를 열고 앱과 위젯 타깃의 Signing Team을 자신의 Apple Developer 팀으로 지정합니다.
4. App Group `group.com.sundaynighttt.codextime`과 Keychain Sharing 권한을 두 타깃에 동일하게 설정한 뒤 실행합니다.

다른 Apple Developer 팀에서 직접 빌드할 때는 번들 ID, App Group ID, Keychain 그룹을 자신의 고유 값으로 함께 변경해야 합니다.

시뮬레이터 빌드와 단위 테스트는 저장소 루트에서 실행할 수 있습니다.

```bash
./ios/scripts/test-ios.sh
```

## 보안

- 액세스 토큰과 갱신 토큰은 동기화되지 않는 iOS Keychain에 저장합니다.
- 앱과 위젯은 서명된 공유 Keychain 그룹으로만 로그인 정보를 공유합니다.
- 사용량 스냅샷은 App Group 저장소에 보관합니다.
- API 키, Codex CLI, 켜져 있는 Mac은 필요하지 않습니다.
- 토큰과 실제 계정 응답은 로그·스크린샷·이슈에 첨부하지 마세요.
