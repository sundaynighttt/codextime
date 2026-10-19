# iPhone 1.0(11) — 작은 3열 카드

## 변경

iPhone 앱과 홈 화면 소형 위젯에 Codex·Grok·Claude 로고와 잔여율을 가로 3열로 표시한다. 앱의 기본 카드는 최대 280pt 정사각형이며, 접근성 글꼴에서는 높이를 늘려 표시한다. 서비스 열은 좁은 폭에서도 이름과 퍼센트가 잘리지 않도록 제한된 범위로 확대하며 VoiceOver에는 전체 이름·잔여율·상태를 제공한다. Codex 리셋 시간과 누적 토큰은 앱의 ‘Codex 상세’에서 확인한다.

실제 데이터 연결은 기존 Codex뿐이다. Grok·Claude는 `— / 미지원`, 연결 전 Codex는 `— / 연결 필요`로 표시한다. 실제 0%와 데이터 없음은 다르다. 예시 모드에는 ‘예시 데이터’를 명시하며 Codex 예시 값을 다른 두 서비스에 재사용하지 않는다.

`CodexAccountClient`·기기 로그인·토큰 저장·단일 사용량 캐시·위젯 갱신 경로는 유지한다. 새 서버, Mac→iPhone 전송, 추가 계정 접근 권한이나 공급자 조회는 없다. Grok·Claude 실데이터 연결은 별도 iPhone 인증 경로를 먼저 확정해야 한다.

## 검증

- iPhone 17 Pro Max / iOS 26.5 시뮬레이터 빌드·설치·실행 성공. 일반 크기와 접근성 최대 글꼴의 3열·이름·퍼센트를 화면으로 확인했다.
- 단위 테스트 17개 통과, 실패·건너뜀 0개. 미연결과 실제 0%, Codex 실제/예시, 미지원 서비스 값 분리를 포함한다.
- 작은 위젯 타깃 컴파일 성공. 실제 홈 화면 배치·실기기 동작은 별도 확인 대상이다.
- Release archive와 앱·내장 위젯의 strict 코드 서명 검증 성공. 양쪽 모두 버전 1.0, 빌드 11, iOS 17 이상이며 로고와 MIT 고지가 번들에 포함된다.
- 새로운 실제 계정 로그인·Grok/Claude 조회·모델 호출은 실행하지 않았다.

## 배포 상태

2026-10-19 **13:37:25 KST**, Xcode가 `Upload succeeded`, `Uploaded CodexTime`, `EXPORT SUCCEEDED`를 반환했다. 직전 응답은 `Uploaded package is processing`이었다. **빌드 11의 업로드 성공까지 확인했으며 Apple 처리 완료·테스트 그룹 배포·실기기 설치는 확인 전이다.** 정식 App Store 출시 동작은 수행하지 않았다. 이전 1.0(10)은 Codex 전용 화면이며, 2026-10-19 13:04:42 KST Apple의 테스트 가능 알림이 확인된 이력이다.

## 기존 macOS CI

main `aa6ecf9`의 [run 39194942763](https://github.com/sundaynighttt/codextime/actions/runs/39194942763)은 macOS 테스트 준비 시간 문제로 실패했다. 후속 테스트 fixture 준비 대기를 보정한 `e730f4e`의 [run 39195689279](https://github.com/sundaynighttt/codextime/actions/runs/39195689279)는 macOS·iPhone·Windows 모두 통과했다. 앱의 운영 중 읽기 제한 시간은 변경하지 않았다. 이 결과를 이번 iPhone UI 변경의 CI 통과 증거로 혼동하지 않는다.
