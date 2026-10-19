# CodexTime for iPhone

작은 사각 카드와 홈 화면 소형 위젯에 Codex·Grok·Claude를 가로 3열로 표시하는 iPhone 앱입니다. Codex는 iPhone에서 본인 계정으로 직접 조회합니다. 새 1.0(12) 후보는 사용자가 선택한 본인 iCloud 동기화로 Mac의 Grok 결과를 읽으며, Claude 자동 연결은 공급자 제한으로 차단합니다.

## 현재 후보와 배포 상태

1.0(12)는 공유 20개·Mac 102개·iPhone 24개 테스트와 시뮬레이터 검증을 통과한 코드 후보입니다. Release archive는 기존 앱·위젯 프로필의 CloudKit 컨테이너 권한 불일치로 중단됐으며, 실제 iCloud 전달·설치·TestFlight 업로드는 완료하지 않았습니다. [후보 검증과 차단점](../docs/releases/2026-10-19-private-icloud-sync.md)과 [루트 README](../README.md)를 확인하세요.

이전 1.0(11)은 3열 UI와 Codex 직접 조회만 지원하고 Grok·Claude는 `— / 미지원`으로 표시했습니다. 2026-10-19 13:37:25 KST 업로드 후 13:38:53 KST Apple의 테스트 가능 알림을 확인했습니다. 이는 새 iCloud 기능을 검증한 빌드가 아닙니다. [빌드 11 근거](../docs/releases/2026-10-19-ios-three-provider-card.md)를 참고하세요.

## 지원 범위

- iOS 17 이상
- 앱의 작은 사각 카드와 소형 위젯(`systemSmall`): `Codex / Grok / Claude` 순서의 3열, 각 로고·이름·잔여 비율·상태
- Codex: OpenAI 공식 기기 로그인 화면을 통한 본인 ChatGPT 연결과 직접 조회, 상세 리셋·누적 토큰 유지
- Grok: 연결·웹 대조를 마친 본인 Mac의 최소 결과를 같은 본인 Apple 계정의 비공개 CloudKit 저장소로 전달
- Claude: 현재 구독 인증정보의 타사 앱 이용 제한으로 `—`와 차단 상태 표시, 공식 사용량 페이지 안내
- iCloud 동기화는 Mac과 iPhone에서 각각 명시적으로 켜야 하며 기본 꺼짐
- 30분 간격의 위젯 타임라인 갱신 요청; 실제 실행 시점은 WidgetKit이 결정
- 광고·분석 SDK·개발자 중계 서버 없음
- 로그인 없는 오프라인 예시 보기: 앱에 예시 배너, 위젯 제목에 `예시` 표시

Codex 직접 조회에는 API 키·Codex CLI·켜져 있는 Mac이 필요하지 않습니다. **Grok의 최신 결과에는 깨어 있는 Mac과 실행 중인 앱이 필요합니다.** Mac의 기존 10분 조회와 iCloud 전달·위젯 실행은 별개이며 실시간 갱신을 보장하지 않습니다. 20분 지난 조회 또는 동기화 실패는 마지막 조회 시각과 오래된 정보·오류 상태로 구분합니다. 값이 없으면 `—`이고 실제 잔여량 0%와 구분합니다.

예시 모드는 Codex의 별도 캐시를 사용하며 실제 계정·iCloud 데이터와 섞지 않습니다. Grok·Claude 수치를 만들거나 Codex 수치를 재사용하지 않습니다. 예시 새로고침은 갱신 시각만 바꾸고 네트워크에 접근하지 않으며 예시 값을 iCloud에 올리지 않습니다.

> OpenAI·xAI·Anthropic·Apple의 공식 앱이 아닙니다. 인증·사용량 인터페이스 변경으로 업데이트가 필요할 수 있습니다. Claude의 현재 자동 조회를 중지하며, iPhone 웹 로그인·세션 수집·토큰 수동 입력을 대체 경로로 추가하지 않습니다. [공식 인증 규정](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)과 [Claude 사용량 페이지](https://claude.ai/settings/usage)를 참고하세요.

## 본인 iCloud 연결과 해제

1. 지원되는 새 Mac/iPhone 빌드를 설치하고 같은 본인 Apple 계정으로 각 기기의 iCloud에 로그인합니다.
2. Mac에서 기존 Grok 연결과 같은 계정·구독 기간의 웹 값 대조를 마칩니다. [Mac 설정](../docs/macos-setup.md)을 따르세요.
3. Mac과 iPhone의 iCloud 동기화를 각각 켭니다. 연결 상태와 공급자 조회 시각을 확인합니다. 로그인이나 CloudKit 권한·서명 설정이 충족되지 않으면 해당 오류를 표시합니다.

전송 필드는 **서비스 구분·잔여율·리셋·공급자 조회 시각·고정 상태**뿐입니다. 비밀번호·인증 토큰·쿠키·계정 ID/이메일·기기 이름·구독 이름·누적 토큰·원시 응답은 전송하지 않습니다. `iCloud.com.sundaynighttt.codextime`의 본인 비공개 데이터베이스를 사용하며 Apple이 저장·전달합니다.

iPhone의 **이 iPhone에서 동기화 해제**는 이 기기의 수신·로컬 캐시만 정리합니다. **iCloud 동기화 데이터 삭제**는 별도로 원격 삭제를 요청합니다. Mac에서 동기화 체크를 끄거나 **끄고 iCloud 값 삭제**를 선택하면 Mac의 전송·로컬 캐시를 중지하고 원격 삭제도 요청합니다. 어느 기기든 Apple의 성공 응답 전에는 삭제 대기로 표시합니다. 오프라인이면 네트워크 복구 후 다시 시도하세요. 다른 Mac이 동기화 중이면 새 값이 다시 올라갈 수 있으므로 전체 중단에는 각 발신 Mac에서도 꺼야 합니다.

iCloud 로그아웃·계정 변경 시 해당 로컬 캐시·동기화 선택을 지우고 새 계정에서는 재동의를 요구합니다. 이 동작이 이전 계정의 CloudKit 레코드를 지우지는 않습니다. 필요하면 로그아웃 전에 삭제를 완료하세요. Codex 연결 해제는 iPhone의 Codex 토큰·캐시 삭제이며 iCloud 설정·삭제와 별개입니다.

## 직접 빌드

1. Xcode 16 이상과 [XcodeGen](https://github.com/yonaskolb/XcodeGen)을 설치합니다.
2. `ios` 폴더에서 프로젝트를 생성합니다.

   ```bash
   xcodegen generate
   ```

3. `CodexTime.xcodeproj`를 열고 앱과 위젯 타깃의 Signing Team을 자신의 Apple Developer 팀으로 지정합니다.
4. App Group `group.com.sundaynighttt.codextime`과 Keychain Sharing 권한을 두 타깃에 동일하게 설정합니다.
5. iCloud 기능을 빌드하려면 Apple Developer에서 본인 팀의 CloudKit 컨테이너와 앱 ID를 연결하고 앱·위젯에 동일 컨테이너의 iCloud entitlement·프로비저닝을 적용합니다. 저장소의 기본 컨테이너는 `iCloud.com.sundaynighttt.codextime`이며 다른 팀에서는 자신의 고유 값으로 바꿔야 합니다. 공유 모듈의 컨테이너 상수와 Mac의 bundle/entitlement·프로필 검사 상수도 자신의 팀에 맞게 함께 변경해야 합니다. Mac 발신 앱은 같은 컨테이너·환경을 사용해야 합니다.
6. 개발용 스키마와 TestFlight의 production 스키마를 구분해 설정하고 실제 본인 iCloud 계정에서 별도로 검증합니다. 설정이 없는 빌드의 컴파일 성공은 동기화 성공이 아닙니다.

다른 Apple Developer 팀에서 직접 빌드할 때는 번들 ID, App Group ID, Keychain 그룹, CloudKit 컨테이너를 자신의 고유 값으로 함께 변경해야 합니다. Codex 직접 조회와 iCloud 동기화는 독립 기능입니다.

시뮬레이터 빌드와 단위 테스트는 저장소 루트에서 실행할 수 있습니다.

```bash
./ios/scripts/test-ios.sh
```

## 보안

- Codex 액세스·갱신 토큰은 동기화되지 않는 iOS Keychain에 저장하고 같은 서명 그룹의 앱·위젯만 공유합니다.
- Codex 사용량·누적 토큰과 계정 범위가 확인된 iCloud 사용량 캐시는 App Group에 보관합니다. 캐시·예시·자격증명 저장소를 구분합니다.
- 프로필에서 누적 토큰만 읽으며 이름·사진·사용자명을 별도로 저장하지 않습니다. 인증 ID 토큰에는 계정 정보가 포함될 수 있습니다.
- Codex 실제 조회는 OpenAI에 계정 식별자·인증·사용량 요청 및 네트워크 정보를 보냅니다. 선택한 iCloud 동기화는 허용 필드를 Apple에 저장·전달합니다.
- 인증정보는 Mac에서 iPhone으로 옮기지 않습니다. Claude의 실제 수치·인증정보도 동기화하지 않습니다.
- 실제 계정 연결 해제는 외부 서비스 계정이나 구독 삭제가 아닙니다. [개인정보 처리방침](../docs/privacy-policy.md)과 [통신 규약](../docs/protocol.md)을 확인하세요.
- 토큰과 실제 계정 응답은 로그·스크린샷·이슈에 첨부하지 마세요.
