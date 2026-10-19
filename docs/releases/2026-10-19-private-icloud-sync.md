# 비공개 iCloud 동기화 후보 — 중단·미배포 이력

대상은 macOS **0.3.1(2026101907)**과 iPhone **1.0(12)**다. 이 후보는 코드·로컬 검증 이후 중단했으며 Mac 정식 배포·설치, iPhone TestFlight 업로드, 실제 CloudKit 송수신을 완료하지 않았다. 현재 iPhone 웹 사용량 후보 **1.0(13)**에 이 코드를 혼합하지 않는다. 기존 공개 Mac은 v0.3.0이다.

보존 소스는 `git:f98bb6d`(iCloud 후보)와 `git:bdef8de`(같은 후보 위의 제한된 Grok 웹 시험)다. 개인정보 방침 변경 커밋 `1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6`도 당시 계약 이력이며 현재 웹 후보의 정책 링크로 재사용하지 않는다.

## 당시 구현과 로컬 검증

- 검증한 Mac Grok 잔여율·리셋·공급자 조회 시각·고정 상태만 같은 본인 Apple 계정의 비공개 CloudKit으로 전달하도록 구현했다. 양쪽 모두 기본 꺼짐이며 인증정보·계정 식별자를 전송하지 않았다. 컨테이너는 `iCloud.com.sundaynighttt.codextime`, 레코드 형식은 `UsageSnapshotV1`이었다.
- 당시 후보의 Claude Keychain·OAuth 조회와 수치 직렬화는 공식 인증정보 이용 제한을 이유로 차단했다. 이는 공개 Mac 0.3.0의 과거 연결 이력 및 현재 별도 iPhone 웹 후보와 구분한다.
- 공유 모듈 **20개**, Mac **102개**, iPhone **24개** 테스트를 통과했다. 가짜 전송의 계정 전환·로그아웃·실패·삭제 대기·늦은 응답·앱/위젯 설정 경합·예시 격리 검증이며 실제 iCloud 계정 전환/송수신 성공을 뜻하지 않는다.
- iPhone 17 Pro Max / iOS 26.5 시뮬레이터에서 3열 카드·설정·일반/접근성 최대 글꼴을 확인했다. Mac arm64 ad-hoc 패키징과 strict 서명 검사를 통과했으나 iCloud 준비 플래그는 false였고 설치·실행하지 않았다.

## 배포 실패와 중단

Mac 개발용 archive/profile 생성 이후 Developer ID export의 프로비저닝 단계가 5분 이상 진행되지 않아 해당 프로세스만 종료했다(exit 143). exported app은 없으며 포털 인증서 생성 여부는 확인되지 않았다. 개발용 프로필을 배포용으로 오인하거나 검사를 약화하지 않았다.

iPhone 앱·위젯의 기존 프로비저닝 프로필이 새 `com.apple.developer.icloud-container-identifiers` entitlement와 일치하지 않아 Release archive가 실패했다. `com.apple.iCloud` capability를 명시한 재시도도 같은 이유로 실패했다. **빌드 12를 TestFlight에 업로드하지 않았고 Apple 처리 빌드도 아니다.**

원래 후속 항목이었던 Apple Developer 컨테이너/앱 ID 연결·Production 프로필·운영 스키마·실제 Mac→iPhone 송수신은 완료하지 않고 보류했다. 새 웹 후보를 위해 이 권한이나 서버를 추가하지 않는다.

## 로컬 증거 위치

다음 파일은 해당 Mac의 임시 검증 자료이며 배포물·비밀정보·실제 계정 수치를 저장소에 복제하지 않는다. 임시 경로는 정리될 수 있으므로 원장의 영구 근거는 위 보존 커밋과 이 문서다.

- `/tmp/codextime-cloud-macos-final-tests.log`
- `/tmp/codextime-shared-sync-final-tests.log`
- `/tmp/codextime-cloud-macos-adhoc-build.log`
- `/tmp/codextime-cloudkit-mac-provisioning.log`
- `/tmp/codextime-cloudkit-mac-export.log`
- `/tmp/codextime-ios-archive-12-20261019.log`
- `/tmp/codextime-ios-archive-12-capabilities-20261019.log`

별도 제한 Grok 웹 시험 소스는 `git:bdef8de`에 보존한다. 그 시험 자체에는 새 TestFlight 배포 이력이 없다.
