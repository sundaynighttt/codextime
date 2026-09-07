# CodexTime for iPhone

홈 화면 위젯에서 Codex의 남은 사용량, 리셋까지 남은 시간과 누적 토큰을 확인하기 위한 최소 iPhone 앱입니다.

## 현재 범위

- iOS 17 이상
- 소형 위젯 한 종류: `Codex (갱신 시각) / 남은 비율 / 리셋까지 시간 / 누적 토큰`
- OpenAI 공식 기기 로그인 화면을 통한 ChatGPT 연결
- 30분 간격의 위젯 타임라인 갱신 요청
- 광고·분석·별도 중계 서버 없음
- 로그인 없는 오프라인 예시 보기: 앱에 예시 배너, 위젯 제목에 `예시` 표시
- 앱 내 이용 안내·개인정보·지원 링크

앱은 연결·수동 새로고침·연결 해제와 예시 보기·이용 안내를 제공합니다. iOS가 실제 위젯 갱신 시점을 결정하므로 정확히 30분마다 실행된다고 보장되지는 않습니다. 예시 모드는 별도 캐시를 사용하며 실제 계정 데이터와 섞지 않습니다. 예시 새로고침은 갱신 시각만 바꾸고 네트워크에 접근하지 않습니다.

> OpenAI의 공식 iPhone 앱이 아닙니다. 인증 또는 사용량 인터페이스가 바뀌면 업데이트가 필요할 수 있으며, 동작 확인과 타사 서비스 이용 권한 확인은 별개입니다. 1.0(9)의 [App Store 제출 현황](../docs/app-store/submission.md)을 참고하세요.

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
- 사용량과 누적 토큰 스냅샷은 App Group 저장소에 보관합니다.
- 프로필 응답에서는 누적 토큰 숫자만 읽으며 이름·사진·사용자명을 별도로 저장하지 않습니다. 인증 ID 토큰에는 계정 정보가 포함될 수 있습니다.
- 실제 조회 시 OpenAI에 계정 식별자·인증·사용량 요청 및 네트워크 정보가 전달됩니다. [개인정보 처리방침](../docs/privacy-policy.md)을 참고하세요.
- 실제 계정 연결 해제는 로컬 토큰·사용량 캐시 삭제이며 ChatGPT 계정이나 구독 삭제가 아닙니다.
- API 키, Codex CLI, 켜져 있는 Mac은 필요하지 않습니다.
- 토큰과 실제 계정 응답은 로그·스크린샷·이슈에 첨부하지 마세요.
