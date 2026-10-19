# CodexTime for iPhone

작은 사각 카드와 홈 화면 소형 위젯에 Codex·Grok·Claude를 가로 3열로 표시하는 iPhone 앱입니다. 현재 실제 계정 연결과 잔여량 조회는 Codex만 지원하며, Grok·Claude는 `— / 미지원`으로 표시합니다.

## 현재 범위

- iOS 17 이상
- 앱의 작은 사각 카드와 소형 위젯(`systemSmall`): `Codex / Grok / Claude` 순서의 3열, 각 로고·이름·잔여 비율·연결 상태
- Codex 상세에서 리셋까지 남은 시간과 누적 토큰 확인; 소형 위젯 하단에는 Codex 리셋·갱신 시각 표시
- Grok·Claude는 iPhone 연결 미지원: Codex 수치를 재사용하거나 예시 수치를 만들지 않음
- Mac 사용량 전달·기기 간 동기화 없음
- OpenAI 공식 기기 로그인 화면을 통한 ChatGPT 연결
- 30분 간격의 위젯 타임라인 갱신 요청
- 광고·분석·별도 중계 서버 없음
- 로그인 없는 오프라인 예시 보기: 앱에 예시 배너, 위젯 제목에 `예시` 표시
- 앱 내 이용 안내·개인정보·지원 링크

앱은 연결·수동 새로고침·연결 해제와 예시 보기·이용 안내를 제공합니다. iOS가 실제 위젯 갱신 시점을 결정하므로 정확히 30분마다 실행된다고 보장되지는 않습니다. 예시 모드는 Codex의 별도 캐시를 사용하며 실제 계정 데이터와 섞지 않습니다. 예시에서도 Grok·Claude는 `— / 미지원`으로 남습니다. 예시 새로고침은 갱신 시각만 바꾸고 네트워크에 접근하지 않습니다.

> OpenAI의 공식 iPhone 앱이 아닙니다. 인증 또는 사용량 인터페이스가 바뀌면 업데이트가 필요할 수 있으며, 동작 확인과 타사 서비스 이용 권한 확인은 별개입니다. 1.0(11)은 새 3열 화면의 시뮬레이터 빌드·단위 테스트 17개·서명 아카이브 검증을 통과하고 2026-10-19 13:37:25 KST TestFlight 업로드에 성공했습니다. 빌드 11의 Apple 처리 완료는 아직 확인하지 않았습니다. 이전 1.0(10)은 2026-10-19 13:02:56 KST 업로드 후 13:04:42 KST Apple의 테스트 가능 알림을 확인했습니다. 테스트 그룹 배포·실기기 설치는 별도 확인 대상입니다. [빌드 11 업로드 근거](../docs/releases/2026-10-19-ios-three-provider-card.md)와 [제출 현황](../docs/app-store/submission.md)을 참고하세요.

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
