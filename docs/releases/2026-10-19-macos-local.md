# macOS 0.2.4 로컬 설치 이력

현재 설치 기준은 **2026101905**다. 승인된 Cursor 단일 로그인 항목으로 공유 Grok 사용량을 연결했다. 웹 표시의 정수 정밀도와 reset을 대조한 뒤 10분 갱신을 활성화했으며 Codex·Claude 실제 조회도 유지한다.

2026-10-19 정본 `~/venture/codextime`의 로컬 확장이다. 공개 release·push·PR·새 예약은 만들지 않았다. 로그인 시 자동 실행과 기존 표시 설정은 유지했다.

## 2026101901 — 세 공급자 표시·상태

- 하나의 네이티브 메뉴 막대 항목에 Codex / Grok / Claude 실제 로고와 잔여율 또는 `—`를 고정 순서로 표시한다. 공급자별 독립 조회·시간 제한·중복 방지·개별 새로고침·마지막 성공 유지·stale 표시를 추가했다.
- 이 빌드는 Codex만 실제 연결했고 Grok Bot·Claude는 미연결이었다. 42개 테스트 6.792초, Codex 실조회 테스트 0.746초, release 빌드·서명 검증을 통과했다.
- 설치 실행파일 SHA256: `e3672ed63edbb6ea90fe9949e75384a2d4e8a0adf00de682fdbc5feef2d24f05`.
- 기존 설치본 0.2.3(1)은 Oct 13 빌드로 read hang 수정의 JSONLineReader/OwnedAppServer 심볼이 있었다. 과거 dist는 Aug 26 빌드와 달랐으므로 완전한 source 동일성을 단정하지 않고 전체를 `~/Applications/Codex Usage Monitor.backup-20261019-014012.app`에 보존했다.

## 2026101902 — 승인된 실제 사용량 연결

사용자가 현재 Grok Bot 계정 인증정보와 Claude Code Keychain 인증정보로 지정된 사용량·reset만 최초 확인하고 10분마다 조회하는 지속 접근을 승인했다. 인증정보 추출·출력·별도 저장, 대화·세션·쿠키 읽기, 인증 갱신·마이그레이션·쓰기, 모델 호출은 제외했다. 공식 `claude auth login --claudeai`는 성공 응답을 확인했다.

- Grok Bot은 설치 제품의 고정 DashboardService usage RPC, Claude는 고정 OAuth usage GET으로 연결한다. background Keychain UI를 금지하고 명시 연결에서만 OS 권한을 요청한다. 거절을 기억해 자동 재요청하지 않는다.
- 기본 표시는 공통 한도 중 최소 잔여율이다. Claude 모델별 한도는 상세에 남기고 요약에서 제외한다. 결측·범위 밖 값은 0/100으로 만들지 않는다.
- **75개 합성·회귀 테스트 통과, 7.326초.** 첫 실행에서 CBC의 잘못된 키가 항상 padding 오류를 낸다는 가짜 테스트 기대값 1개가 실패했다. 프로덕션 암호 코드는 그대로 두고 원문과 다른 결과를 검증하도록 수정한 뒤 전체 재실행했다. Codex의 기존 EOF/read hang·deadline·취소·자식 정리 회귀도 포함한다.
- release 빌드 3.98초, `codesign --verify --deep --strict` 통과. Keychain UI 상수의 macOS deprecation 경고가 있으나 빌드 오류는 없다.
- 설치 경로 `~/Applications/Codex Usage Monitor.app`, bundle ID `com.sundaynighttt.codex-usage-monitor`, version `0.2.4 (2026101902)`. 설치본과 dist SHA256 일치: `435faf27fca5dbbc89c0978cef1e2590be672b79fc90bbc1509b0cf9e2973df3`.
- 직전 2026101901 전체 백업: `~/Applications/Codex Usage Monitor.backup-20261019-021337.app`. 정상 종료 후 교체하고 정상 메뉴 막대 모드로 다시 실행했다.
- 설치 앱 자체의 quota 전용 진단에서 **Codex와 Claude 실제 사용량 응답 성공**을 확인했다. Grok은 인증 필요 오류로 끝나 실제 quota 응답은 아직 미확인이다. 인증값·계정 식별자·HTTP 본문은 진단에 포함하지 않았다.

## 2026101903 — Grok 실패 단계 확인

- 인증 실패를 토큰·계정·경로·OSStatus·본문 없이 고정 enum 단계로만 구분하는 진단을 추가했다. production에서는 진단 객체를 사용하지 않는다. `--check-usage --grok-only`는 Grok만 확인해 다른 공급자 요청을 반복하지 않는다.
- **78개 합성·회귀 테스트 통과, 6.669초.** release 빌드 3.91초 및 서명 검증 통과. 버전 `0.2.4 (2026101903)`으로 기존 위치에 설치하고 정상 모드로 다시 실행했다.
- 설치본·dist SHA256 일치: `824a60bea23627ae92a59a20ce9a88bdf267b901e80dc99c06515e52fe2ee8cd`. 직전 빌드 전체 백업은 `~/Applications/Codex Usage Monitor.backup-20261019-021830.app`이다.
- 실제 Grok 전용 진단 결과는 **`keychain_item_missing`**이다. 현재 계정 저장 형식 선택 다음, 지정된 `Grok Bot Safe Storage` / `Grok Bot` 항목을 찾는 단계에서 끝났다. HTTP 요청 전이므로 토큰 만료·서버 인증 거절·실제 잔여율은 확인하지 못했다. 다른 Keychain service·account를 자동으로 탐색하지 않았다.
- 정적 재검증에서 설치 0.71.2의 productName과 Electron 초기화는 동일한 Grok Bot service/account를 가리켰다. Cursor/sand 등 다른 항목을 시도할 근거는 찾지 못했다. 다음 단계는 사용자가 공식 Grok Bot의 로그인·Usage & Billing 정상 여부를 확인하는 것이다. 다른 OS 항목 접근이 필요하면 구체 범위를 다시 판단한다.
- Codex·Claude의 실제 응답 성공은 앞선 2026101902에서 확인했다. 현재 Claude는 로그아웃으로 취급하지 않는다.

## 2026101904 — 일반 Grok 구독으로 대상 전환

사용자가 Grok Bot Usage 화면은 보인다고 확인한 뒤 일반 Grok 앱·웹을 대상으로 바꾸도록 요청했다. Bot 키체인 추적은 중단했다. `/Applications`와 `~/Applications`의 Grok 이름·Info.plist 조사에서는 Bot만 발견됐고 일반 Grok 앱은 없었다. 공식 [Grok 안내](https://x.ai/grok)는 일반 제품을 웹·iOS·Android로 안내한다.

- 공식 [Grok FAQ](https://docs.x.ai/grok/faq)의 Settings → Usage는 구독 사용한 %·제품별 비중·주간 reset을 제공한다. 실제 계정의 공통 사용률에서 잔여율을 계산할 수 있으나 Bot·API 과금과 같다고 가정하지 않는다. 소비자 공개·안정적 quota API 계약은 미확인이다.
- production·수동 factory·진단에서 Bot client를 제거하고 일반 Grok 미연결 placeholder로 교체했다. 새 Grok 쿠키·토큰·Keychain·세션에는 접근하지 않는다. 메뉴의 Grok 동작은 공식 로그인 링크만 연다. 기존 Bot/Build 구현과 회귀 fixture는 보존한다.
- **79개 테스트 통과, 6.950초**, release 빌드 3.34초, 서명 검증 통과. version `0.2.4 (2026101904)`으로 기존 위치에 설치했다. 설치본·dist SHA256 일치: `d5195fcb2e5656eded07687cd27f98018d3198e099e16ea2c1bbab6193699687`.
- 직전 전체 백업: `~/Applications/Codex Usage Monitor.backup-20261019-022801.app`. 정상 메뉴 막대 모드로 다시 실행했다. 설치 앱의 background 진단에서 Codex·Claude 실제 조회 성공을 다시 확인했고 Grok은 `.notConnected`로 종료했다.
- 새 Grok 인증 연결은 미실행이다. 최소 다음 범위는 사용자가 공식 웹 구독 계정으로 직접 로그인해 연 Settings → Usage 화면에서 플랜·사용률·reset만 1회 읽는 것이다. 기존 Bot 승인으로 다른 앱·웹의 쿠키·토큰·키체인 지속 접근을 허용하지 않는다. 해당 1회 확인 후에 자동 갱신 방식과 정확한 지속 접근 범위를 판단한다. 자격증명 값이나 대화 내용은 필요하지 않다.

## 후속 웹 경로·공개 구현 비교

허용된 브라우저에서 일반 웹의 실제 Usage UI와 표시 필드를 확인했다. 계정 수치·날짜·제품별 사용 내역은 문서와 원장에 기록하지 않는다. 쿠키·토큰·WKE 키·대화 원문은 읽지 않았다.

사용자가 Bot도 공유 조회 후보로 포함해도 된다고 정정해 기존 세 공개 구현을 비교했다. LoopLabsBar는 Cursor IDE의 지정 access-token 항목으로 동일 GetSandUsageStatus RPC를 호출한다. CodexBar·codex-limits는 공식 Grok CLI의 다른 인증 경로다. Bot Keychain 항목명 오타를 입증한 사례는 없다. 새 인증 source는 별도 승인 전이므로 새 연결·추가 설치·소스 복사는 하지 않았다. 원본 링크와 범위는 [통신 규약](../protocol.md#macos-공급자별-상태)에 기록했다. 설치판은 2026101904 그대로다.

## 2026101905 — 승인된 Cursor 단일 항목 연결

사용자가 Cursor 저장소의 access-token 한 항목을 앱 메모리에서만 읽어 기존 usage RPC에 사용하는 지속 접근을 승인했다. 새 source는 지정 경로의 ItemTable에서 cursorAuth/accessToken 하나만 SELECT하며 다른 키·대화·쿠키·refresh token·Keychain을 조회하지 않는다. 별도 토큰 저장·인증 갱신·로그인·모델 호출은 수행하지 않는다.

- SQLite는 Unix VFS의 mode=ro와 readonly_shm=1, READONLY·NOFOLLOW·PRIVATECACHE로 연다. DB·sidecar의 파일 형식·소유자·크기·경로를 검사하고 부분 WAL 쌍은 실패 처리한다. 단일 SELECT authorizer와 2초 busy/progress 제한을 적용했다.
- **90개 합성·회귀 테스트 통과, 6.944초.** 독립 프로세스가 유지한 가짜 WAL의 최신 값을 읽고 DB·WAL·SHM bytes가 모두 동일함을 검증했다. 첫 실행의 임시 폴더 심볼릭 링크 별칭 문제는 fixture realpath만 수정했으며 production 경로 보호는 유지했다.
- release 빌드 4.23초, 설치본 strict 서명 검증과 dist SHA256 일치 확인. version **0.2.4 (2026101905)**, 실행파일 SHA256 **4fb7129617d00191accce3ead7443c8cee52af7a0efd0fe6d2f6ae6d4c934c47**.
- 설치 경로는 기존과 같으며 직전 2026101904 전체 백업은 ~/Applications/Codex Usage Monitor.backup-20261019-025837.app 이다.
- 설치 앱의 일회성 Grok 조회에서 공유 주간 quota 응답을 확인하고, 실제 웹 Usage의 사용률 정수 표시 범위와 현지 시각의 reset 분 단위가 일치함을 대조했다. 원본 소수 잔여율은 다른 공급자와 동일하게 내림 표시한다. 실제 계정 수치·reset·제품별 내역은 파일에 기록하지 않았다.
- 대조 후 비밀값 없는 검증 플래그만 저장하여 기본 600초 갱신을 활성화했다. 정상 앱의 실제 검수 창에서 동일 MenuBarPresentation 이미지의 세 로고와 세 공급자의 실제 성공 상태·한도·reset을 읽어 확인했다. 검수 창은 닫고 메뉴 앱은 실행 중으로 남겼다.
- 실제 메뉴 클릭 검수는 여전히 제한적이다. 창을 닫은 메뉴 전용 앱의 Computer Use 접근은 timeout으로 종료됐다. 새 권한 부여나 다른 UI 자동화로 우회하지 않았다. 위 성공 범위는 실제 검수 창과 동일 렌더링·정상 provider 조회다.

## 화면 검증 범위

fixture로 세 로고·미연결 이미지를 렌더링해 형태와 조합을 확인했고 기계 UI 검사와 `git diff --check`를 통과했다. SwiftPM `--show-bin-path`의 새 실행파일과 app Resources의 로고를 패키징한다. 원본 및 MIT 고지는 [third-party-notices](../third-party-notices.md)에 보존했다.

**빌드 01–04의 실제 메뉴 클릭·화면 육안 검수는 미완료였다.** Computer Use가 앱 이름과 정확한 설치 경로에서 `timeoutReached (-10005)`를 반복했고 허용된 추가 1회 재시도도 같은 결과였다. 새 접근성·화면 기록 권한을 부여하거나 다른 UI 자동화로 우회하지 않았다. 설치 smoke는 파일·서명·실행과 실제 provider 조회 범위다.

현재 연결 범위와 고정 조회 경로는 [통신 규약](../protocol.md#macos-공급자별-상태)에 기록했다.
