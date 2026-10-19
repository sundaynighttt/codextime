# 비공개 iCloud 동기화 후보 — 2026-10-19

대상은 macOS **0.3.1(2026101907)**과 iPhone **1.0(12)**다. 현재는 코드·로컬 검증 후보이며 새 Mac 설치·정식 서명 배포·TestFlight 업로드·실제 iCloud 전달 완료를 뜻하지 않는다. 기존 macOS 공개본은 v0.3.0이며 Apple 처리 확인 최신 iPhone 빌드는 1.0(11)이다.

## 동작

Mac에서 본인 계정으로 연결하고 웹 결과와 대조한 Grok 잔여율·리셋·공급자 조회 시각·상태만 본인 비공개 CloudKit에 저장한다. 같은 Apple 계정의 iPhone 앱·위젯은 별도로 동기화를 켠 뒤 계정 범위를 검증하고 읽는다. 기본은 양쪽 모두 꺼짐이다. 비밀번호·토큰·쿠키·계정 ID/이메일·기기 이름·누적 토큰·원시 응답은 전송하지 않는다. 개발자 서버는 없다.

컨테이너는 `iCloud.com.sundaynighttt.codextime`, 레코드 형식은 `UsageSnapshotV1`, 필드는 암호화된 `payload` 한 개다. 고정 Grok·Claude 레코드 외의 조회나 다른 사용자의 공개/공유 DB는 사용하지 않는다. Claude는 [공식 인증 제한](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)에 따라 Mac Keychain·HTTP 조회 전에 차단하고, 직렬화 시에도 수치가 제거된다. 공식 사용량 페이지를 안내한다.

새 값을 받으려면 Mac이 깨어 있고 앱·Grok 연결·네트워크가 동작해야 한다. 20분 지난 값과 통신 실패는 이전 결과임을 구분한다. 계정 변경·로그아웃은 동의와 로컬 캐시를 초기화하며 새 계정에서는 다시 켜야 한다. iPhone 수신 해제는 기기 캐시만 지우고, 별도 iCloud 삭제는 원격 삭제도 요청한다. Mac 끄기는 원격 삭제 요청까지 포함한다. Apple 성공 응답 전에는 삭제 대기다. 이미 렌더링된 위젯 교체 시점은 iOS 일정의 영향을 받는다.

## 로컬 검증

- 공유 모듈 **20개**, Mac **102개**, iPhone **24개** 테스트 통과. 가짜 전송으로 계정 전환·로그아웃·네트워크 오류·삭제 실패·늦은 응답·앱/위젯 간 해제 경합·예시 모드의 외부 요청 차단을 검증했다. 실제 계정 전환이나 CloudKit 송수신 검증과 구분한다.
- iPhone 17 Pro Max / iOS 26.5 시뮬레이터 빌드·실행, 3열 카드·설정 펼침·무권한 빌드의 연결 차단, 일반/접근성 최대 글꼴 확인. 예시 화면은 실제 Grok 값을 섞지 않는다. [설정 화면](../screenshots/ios-icloud-settings-preview.jpg).
- Mac arm64 로컬 ad-hoc 패키징과 strict 서명 검사 통과. 이 빌드의 iCloud 준비 플래그는 false이며 설치·실행하지 않았다. Production 프로필 없이 권한을 붙이지 않는다.
- 읽기 전용 보안 검토에서 발견한 설정 자료형, 해제 경합, 예시 혼합, 공유 모듈 CI 누락을 수정했다. 새 코드의 원격 CI 실행은 아직 확인하지 않았다.
- [새 개인정보 정책 고정 링크](https://github.com/sundaynighttt/codextime/blob/1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6/docs/privacy-policy.md)를 비로그인으로 열 수 있음을 확인하고 빌드 12 소스의 안내 링크에 연결했다. ASC 메타데이터 반영·최종 서명 번들 검증은 남아 있다.

## 배포 차단점

공식 Xcode 자동 서명으로 exact Mac App ID·컨테이너가 들어간 개발용 archive/profile은 생성했다. Developer ID export는 프로비저닝 단계에서 5분 이상 진전이 없어 해당 프로세스만 종료했다(exit 143). exported app은 없고 포털 인증서 생성 여부는 미확인이다. 개발용 프로필은 릴리스 검사에서 거부한다.

iPhone Release archive는 앱·위젯의 기존 프로필이 새 CloudKit 컨테이너 entitlement와 일치하지 않아 실패했다. `com.apple.iCloud` capability를 명시해 재시도했으나 동일한 프로필 불일치가 남았다. 권한을 제거하거나 검사를 약화해 업로드하지 않았다.

계속하려면 Apple Developer 포털에서 기존 iPhone·위젯 App ID의 컨테이너 연결과 프로필 갱신, Mac Production Developer ID 프로필, 운영 `UsageSnapshotV1` 암호화 필드 스키마를 준비해야 한다. 해당 포털 설정과 운영 스키마 반영은 아직 확인 전이다. 실제 Grok 저장→iPhone 수신·실기기 위젯 검증 후 새 Mac 설치와 TestFlight 업로드·처리를 구분해 기록한다.
