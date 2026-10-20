# Codex usage protocols

## macOS and Windows

CodexTime does not open Codex authentication files. It starts `codex app-server` as a child process and communicates over JSONL using standard input and output.

## Request sequence

1. `initialize`
2. `initialized`
3. `account/rateLimits/read`

## Consumed response fields

- `rateLimitsByLimitId.codex.primary.usedPercent`
- `rateLimitsByLimitId.codex.primary.resetsAt`
- `rateLimitsByLimitId.*.limitName`
- `rateLimitsByLimitId.*.secondary`
- the backward-compatible `rateLimits` snapshot when the keyed map is absent

`resetsAt` is interpreted as Unix epoch seconds. `usedPercent` is clamped into a remaining percentage using `100 - usedPercent`.

The monitor launches a fresh child process for each network refresh and terminates it after receiving a response. It does not attach to the Codex Desktop app's existing app-server session.

## iPhone

The iPhone app cannot run the local Codex CLI. It uses OpenAI's device-login flow and then requests the authenticated account's Codex usage metadata directly.

1. Request a device code from `auth.openai.com`.
2. Ask the user to approve that code on OpenAI's official device page.
3. Exchange and refresh the OAuth tokens with `auth.openai.com`.
4. Read the primary window's `used_percent` and `reset_at` fields from the ChatGPT usage response.
5. Read only `stats.lifetime_tokens` from the authenticated ChatGPT profile response.

The profile response can contain a display name, username, and profile image URL, but CodexTime does not decode or store them. Tokens stay in the shared iOS Keychain access group. The widget requests a new timeline after 30 minutes, but WidgetKit controls the actual execution time and may use the last cached snapshot.

### 1.0(9) 예시 모드와 개인정보 경계

공개 예시 모드는 `demoUsageSnapshot`을 사용하고 실제 캐시 `usageSnapshot`과 분리됩니다. 예시가 활성화되면 앱·위젯의 사용량 client는 Keychain이나 네트워크를 사용하기 전에 예시를 반환합니다. 새로고침은 예시의 갱신 시각만 변경합니다. `isDemo`는 선택 필드라 기존 실제 캐시도 해독할 수 있습니다.

프로필 JSON의 이름·사진을 저장하지 않는다는 것은 인증 토큰에 개인정보가 없다는 뜻이 아닙니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 실제 조회의 외부 전송, 로컬 저장, 연결 해제 범위는 [개인정보 처리방침](privacy-policy.md)을 따릅니다. 이 구현 자체가 외부 서비스의 독립 앱 이용 허가를 증명하지는 않습니다.

### 1.0(11) iPhone 3열 표시와 데이터 범위

이 절은 빌드11의 이력이다. 빌드13의 연결·저장 계약과 빌드16 후보의 Claude 확장은 다음 절을 따른다.

앱의 작은 사각 카드와 `systemSmall` 위젯은 `Codex / Grok / Claude` 순서로 각 로고·이름·잔여 비율·상태를 가로 3열에 표시한다. 이 변경은 표시 계층만 확장하며, 실제 사용량은 기존 `CodexAccountClient`의 OpenAI 직접 인증·조회와 단일 `UsageSnapshot` 경로를 유지한다. Codex 스냅샷이 없으면 `— / 연결 필요`, 실제 잔여량이 0이면 `0%`로 구분한다. 앱의 Codex 상세에는 리셋·누적 토큰을 유지하고 소형 위젯 하단에는 리셋·갱신 시각을 표시한다.

Grok·Claude는 iPhone 인증·조회 구현이 없어 `— / 미지원`으로 표시한다. Codex의 실제 값이나 예시 값을 다른 공급자에 복제하지 않으며, 예시 모드에서도 두 칸은 미지원 상태를 유지한다. 로고가 보인다는 사실이 해당 계정 연결을 의미하지 않는다.

`SharedUsageStore`의 App Group은 같은 iPhone의 앱과 위젯 사이 저장소다. macOS의 다중 공급자 상태를 전달하는 서버·Mac 연결·기기 간 동기화 경로는 없다. 이번 UI 변경은 macOS Keychain·Cursor 인증정보를 읽거나 iPhone으로 전송하지 않으며 새 자격증명 접근·네트워크 공급자·지속 권한을 추가하지 않는다. Grok·Claude 실제 조회를 추가하려면 iPhone에서 사용할 인증 경로와 개인정보 처리 범위를 별도로 확정해야 한다.

### 1.0(13) 이력: 공식 웹 로그인과 수동 숫자 확인

Codex의 기존 `CodexAccountClient`·`UsageSnapshot`·기기 전용 Keychain 경로는 유지한다. Grok·Claude는 iPhone에서 각 공식 웹을 `WKWebsiteDataStore.nonPersistent()` 기반 독립 웹뷰로 열고 사용자가 직접 로그인한다. 비밀번호·2FA·SSO와 추가 인증은 공식 페이지에서 처리하며 앱이 입력하거나 우회하지 않는다. Safari·다른 앱·Mac의 인증정보를 가져오지 않고 로그인 후 내부 quota API를 호출하지 않는다. Mac·Cursor·CloudKit·개발자 서버는 필요하지 않다.

사용자는 공식 사용량 페이지와 숫자가 보임을 확인하고 `사용함 / 남음`, 읽을 한도(Grok 주간, Claude 현재 세션/주간)를 선택한다. `숫자 위치 지정해서 읽기`를 누르면 의미·한도를 고정한 한 번의 직접 탭만 읽기에 사용하며 15초 후 취소한다. 주소·가시성·화면 구조·범위·숫자 형식 검증을 통과하지 못하면 고정 실패 상태로 끝낸다. 탐색·의미/한도 변경·완료/숨김은 진행 중 읽기를 취소한다. Swift로 반환하는 값은 성공 상태와 퍼센트 숫자 또는 고정 실패 enum뿐이다. 페이지 전체 원문·원시 선택 텍스트·계정 정보·쿠키·토큰·로그인 입력·원시 HTTP 응답은 반환·로그·저장하지 않는다. 화면 문구로 한도나 숫자 의미를 자동 선택하지 않는다. 제한된 표시 요소에 사용함/남음 단위가 명시돼 있으면 사용자가 고른 의미와 일치해야 하며 충돌 시 중단한다. 원문·단위 라벨은 네이티브로 반환하지 않는다. 실패·취소가 이전 정상 숫자를 지우지는 않는다.

웹 세션은 앱 실행 중 WebKit 메모리에서 유지한다. 창을 닫아도 같은 실행 중에는 유지될 수 있으나 명시적 연결 해제·앱 종료 후에는 재로그인이 필요하다. 로그인 세션을 Keychain이나 파일로 내보내지 않는다. 별도 자동 웹 조회·백그라운드 웹 새로고침은 없다.

`WebUsageReading`의 저장 허용 필드는 `provider`, `percent`, `valueKind`, `metric`, `updatedAt`뿐이다. `WebUsageStore`는 같은 기기의 App Group에 서비스별 캐시를 저장하며 숫자는 앱 종료 뒤에도 남는다. 사용함 값은 잔여율로 변환하고 서로 다른 서비스·한도의 수치를 복제·합산하지 않는다. 비정상 비율·미래 시각·공급자/한도 불일치는 거부한다. 카드·위젯은 수동 확인·한도·시각을 표시하며 1시간 뒤 지난 확인으로 구분하고 만료만으로 숫자를 지우지는 않는다. 위젯은 캐시만 읽으며 Codex 새로고침도 웹 확인 시각을 바꾸지 않는다. `연결 해제·기록 삭제`는 해당 메모리 웹 세션과 캐시를 지운다. 예시에는 실제 웹 수치를 섞지 않고 예시 중 웹 연결도 시작하지 않는다.

이 절은 빌드13의 동작 계약 이력이다. 당시 실제 계정·서명·배포 근거는 [빌드13 기록](releases/2026-10-19-ios-web-usage.md)을 따른다. Claude의 한 번 읽기·한도별 보관을 추가하는 빌드16 후보 계약은 다음 절로 구분한다. 중단된 iCloud 후보 1.0(12)·Mac 0.3.1의 코드·권한은 포함하지 않으며 [미배포 이력](releases/2026-10-19-private-icloud-sync.md)만 보존한다. 기술적인 로그인 성공과 외부 서비스 이용 허용·App Store 승인은 구분한다.

### 1.0(16) 후보: Claude 세션·주간 한 번 읽기

Codex의 직접 인증·조회와 Grok의 사용함/남음·주간 선택·위치 탭 읽기는 유지한다. Claude는 사용자가 **사용량 읽기**를 한 번 누르면 HTTPS 공식 Claude 호스트의 보이는 사용량 패널에서 정해진 한국어·영어 라벨과 가까운 퍼센트를 제한된 DOM 탐색으로 해석한다. 로그인 후 URL 경로만으로 사용량 패널이 없다고 단정하지 않는다. 현재 세션과 전체 모델 주간을 구분하며 모델별 한도는 제외하고 첫 퍼센트 선택·한도 간 복제·합산을 하지 않는다.

웹뷰 안에서 필요한 짧은 허용 라벨과 숫자만 검사한다. 앱으로 반환하는 정보는 검증된 세션·주간 퍼센트와 고정 결과 상태뿐이며 원시 표시 라벨·전체 페이지 텍스트·계정 정보·인증 URL을 반환하지 않는다. 로그인 입력·쿠키·토큰·웹 저장소·스크립트 소스·네트워크 응답을 읽지 않고 내부 API를 호출하지 않는다. 가시성·라벨·구조·수치 검증을 통과하지 못하면 고정 실패로 중단하며 이전 정상 캐시를 지우지 않는다.

저장 필드 `provider`, `percent`, `valueKind`, `metric`, `updatedAt`의 허용 범위는 유지하고 `webUsageReading.v2.<provider>.<metric>` 키에 한도별로 보관한다. Claude 주간이 대표이며 현재 세션은 앱·위젯에 별도로 표시한다. 읽기는 v2 또는 같은 한도의 유효한 v1을 반환할 뿐 저장소를 변경하지 않는다. 이전 v1의 유효한 숫자는 앱의 명시적 저장 때만 원래 한도로 옮기며 기존 v2가 있으면 덮어쓰지 않는다. 저장·이전·연결 해제는 순서를 보장해 삭제 후 이전 값이 다시 생기지 않도록 한다. Claude 버튼의 읽기는 세션·주간 두 숫자를 모두 검증한 경우에만 두 한도를 갱신한다. 부분 반환·한쪽 실패·모호한 값은 전체 읽기 실패이며 두 캐시의 이전 값·확인 시각을 그대로 유지한다. 저장소의 한도별 독립 저장 기능을 Claude의 부분 읽기 허용으로 해석하지 않는다. 세션 값을 주간으로 바꾸거나 이전 시각을 새로 확인한 것처럼 바꾸지 않는다.

계정 이메일·원시 라벨·사용자 사진·인증정보는 저장하지 않는다. 각 값에 수동 확인·한도·시각을 표시하고 1시간 뒤 지난 확인으로 구분한다. 위젯은 마지막 숫자 캐시만 읽으며 웹 자동 갱신·Codex 새로고침을 통한 웹 확인 시각 갱신은 없다. 연결 해제는 해당 서비스의 메모리 웹 세션과 모든 한도·이전 형식 캐시를 지운다. 예시에는 실제 값을 섞지 않는다.

빌드15의 Google/새창 제한 안내·부모 페이지 보존·뒤로/새로고침/공식 사용량 복귀는 유지한다. 이 확장은 Google OAuth 지원이나 외부 브라우저 세션 이전을 추가하지 않는다. 세션은 앱 실행 중 메모리에만 유지하고 앱 종료·연결 해제 뒤 재로그인이 필요하다. 빌드16의 검증·배포 상태와 실제 계정 확인 범위는 [릴리스 원장](releases/release-ledger.json)을 따른다. 이 동작 계약 자체를 파서·캐시·위젯 실계정 검증 완료로 해석하지 않는다.

### 1.0(17) 내부 TestFlight: 아이폰 단독 직접 연결과 자동 조회

이 절은 기존 웹 수동 확인을 대체할 수 있는 **1.0(17) 내부 TestFlight 기술 후보**의 계약이다. 2026-10-20 13:21:13 KST 업로드와 13:25 KST 기준 App Store Connect의 처리 완료·CodexTime Internal 그룹·초대1명·설치 집계 `–`를 확인했다. Apple 처리 확인 최신은1.0(17)이며 실제 계정 로그인·권한·토큰 갱신·위젯 대조·사용자 설치는 미확인이다. [검증·배포 근거](releases/2026-10-20-ios-direct-refresh.md)와 [제출 현황](app-store/submission.md)을 구분한다. 이 구현은 Mac·PC·Cursor·iCloud·개발자 서버를 경유하지 않는다. 이전 빌드13/16의 수동 웹 확인은 별도 대체 경로로 유지하며 과거 계약과 배포 이력은 보존한다.

**Grok:** `GrokAccountClient`는 `POST https://auth.x.ai/oauth2/device/code`에서 기기 코드를 요청하고 사용자가 xAI 페이지에서 승인한 뒤 `POST https://auth.x.ai/oauth2/token`으로 토큰을 발급·갱신한다. [OpenClaw 문서](https://docs.openclaw.ai/providers/xai)에 소개된 공유 공개 클라이언트를 사용하므로 승인 화면에 Grok Build가 표시될 수 있다. CodexTime의 독립 앱 등록·공식 승인을 주장하지 않는다. 후보 요청 범위는 `openid offline_access grok-cli:access`다. 익명 기기 코드 요청이 이 범위로 수락됨은 확인했지만 실제 계정 billing 권한과 공식 웹의 같은 구독 한도·리셋 일치는 아직 확인하지 않았다.

사용량은 고정 `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`에서 읽는다. 수치가 없거나 범위·기간 형식이 유효하지 않으면 값을 만들지 않는다. 주간·월간·미상 기간을 구분하고 `currentPeriod`가 존재하면 잘못된 현재 기간을 과거 billing 날짜로 대체하지 않는다. 실제 관측한 사용률·기간·선택적 리셋·시각만 `GrokUsageSnapshot`에 보관한다. 금액·모델별 비중·API 결제 잔액을 구독 잔여율로 변환하지 않는다.

**Claude:** `ClaudeNativeAccountClient`는 **비공식 호환 기술 후보**다. 공개 네이티브 구현의 Claude Code 공개 클라이언트 ID를 참고한 독립 PKCE 구현이며, Anthropic이 CodexTime에 별도 타사 로그인을 허용했다고 확인한 경로가 아니다. [공식 지침](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)은 자체 앱의 Claude.ai 로그인과 구독 인증정보의 수집·보관·중개를 제한하고, [공식 안내](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)는 타사 개발자에게 API 키를 안내한다. 특정 타사 도구의 허용 재량 조항은 있으나 사용량 전용·개인 오픈소스·내부 TestFlight에 대한 명시 예외나 이 후보의 허용은 확인하지 못했다. 실제 계정 인증·공급자 허용의 근거로 공개 구현 사례·합성 검증·Apple 처리·내부 그룹 배정을 사용하지 않는다.

후보는 `https://claude.ai/oauth/authorize`에 PKCE S256·무작위 state·`user:profile`을 요청한다. 정확한 HTTPS `https://platform.claude.com/oauth/code/callback` 또는 사용자가 입력한 일회성 `code#state`만 같은 진행 중 세션과 대조한다. 검증자·state는 actor 메모리에만 보관하며 만료·중복·다른 세션 결과를 거부한다. 고정 `POST https://platform.claude.com/v1/oauth/token`과 `GET https://api.anthropic.com/api/oauth/usage`만 사용할 수 있다. `user:profile`의 실제 계정 승인·usage 접근 가능은 미검증이다. 공통 `five_hour`·`seven_day`의 두 사용률·리셋과 실제 조회 시각을 함께 검증해 원자적으로 교체하며 부분 응답으로 한쪽을 새 값처럼 저장하지 않는다. 모델별 한도·계정·프로필·결제 정보는 보관하지 않는다.

**인증·저장·취소 경계:** 각 후보는 이 앱이 새로 발급받은 토큰만 별도의 `ThisDeviceOnly`·동기화 꺼짐 Keychain 항목에 보관하도록 설계한다. 같은 서명 그룹의 앱·위젯만 공유하며 다른 앱·CLI·브라우저 저장소를 읽지 않는다. App Group의 작은 원자적 JSON에는 사용량·기간·리셋·실제 조회 시각과 불투명한 연결 세대만 둔다. 프로세스 간 잠금과 연결 세대 검증으로 앱·위젯의 토큰 회전과 삭제를 직렬화한다. 갱신 요청 전에 불확실 상태를 영속화하고 성공을 확정하지 못하면 이전 refresh token을 자동 재사용하지 않는다. 연결 해제는 새 세대와 빈 캐시를 기록하고 앱 전용 토큰을 지워 이전 작업이 값을 복원하지 못하게 한다. 응답 완료가 확인된 회전 토큰은 같은 연결에 한해 보관하되 취소·예시 전환 후 사용량을 게시하지 않는다.

**갱신·표시:** 앱은 연결된 공급자를 독립적으로 조회하고 앱 활성화·복귀·공통 새로고침과 활성 중 600초 갱신을 사용한다. 하나의 공급자 미연결·실패가 다른 공급자의 갱신을 막지 않는다. 위젯 타임라인도 직접 조회를 시도하고 30분 후 다시 실행을 요청하되 실제 실행 시점은 iOS가 결정한다. 위젯 버튼의 App Intent 반환 후 WidgetKit이 타임라인을 다시 요청하며 같은 버튼에서 중복 네트워크 조회를 시작하지 않는다. 서버 조회는 소유 작업의 취소·정리를 포함한 전체 25초 제한을 적용한다. 같은 연결의 실패는 마지막 성공 값과 실제 시각을 보존하고, 20분 경과·리셋 경과·재연결 필요를 구분한다. 새로운 계정 인증에서 이전 계정 값을 최신 자동 값으로 재사용하지 않는다. 수동 웹 값은 직접 조회 값과 출처·시각을 구분하며 실패한 직접 경로가 수동 확인 시각을 갱신하지 않는다. 예시 중에는 실제 인증·조회·수치 혼합을 차단한다.

두 직접 transport는 고정 URL·method, 임시 URLSession, 쿠키·자격증명·디스크 캐시 없음, redirect 차단과 응답 크기 제한을 적용한다. 모델 호출·대화 조회·과거 세션 원문·원시 오류·원시 계정 응답 로그는 없다. 인증·구독 인터페이스 변경은 고정 연결 오류로 끝내며 쿠키·다른 저장소·더 넓은 scope를 자동 탐색하지 않는다. 이 계약은 실제 공급자 허용이나 실계정 E2E 성공의 증거가 아니다.

## Compatibility boundary

`app-server`, `account/rateLimits/read`, and the iPhone usage and profile paths are compatibility-sensitive interfaces. CodexTime's desktop parser ignores unrelated JSON-RPC notifications and initialization responses, but a renamed method, authentication change, or materially changed response shape will require a compatibility update.


## macOS 공급자별 상태

macOS v0.3.0은 `Codex / Grok / Claude`를 기본 모두 표시하며 하나의 네이티브 메뉴 막대 항목에서 순서를 유지한다. 사용자는 `계정 연결 및 표시` 창이나 메뉴에서 서비스별 표시를 선택한다. 기본 수치는 요약 대상으로 지정된 공통 한도 창 중 가장 적게 남은 잔여율을 내림해 표시한다. Claude의 Sonnet·Opus 등 모델별 특수 한도는 상세 메뉴에 남기고 공통 잔여율 계산에서는 제외한다. 응답에 없는 값이나 유효 범위 밖 값은 `—`이며 API 금액·추가 사용량·토큰 합계를 구독 잔여율로 바꾸지 않는다.

- 켜진 서비스만 시작 시·600초마다 독립 조회하며 개별 새로고침을 지원한다. 숨긴 서비스는 자동·수동·잠자기 복귀 조회를 차단하고 진행 중 소유 작업을 취소·정리한다. 숨김은 성공 스냅샷을 메모리에 유지하며, 다시 켜면 연결 허용 범위에서 조회를 재개한다.
- 모두 숨겨도 `사용량` 메뉴 막대 항목과 접근성 설명을 남겨 재설정할 수 있다. 표시 선택은 비민감 사용자 설정으로 저장하며 기본값은 세 서비스 모두 켜짐이다.
- 공급자별 중복 방지와 자동 조회의 15초 store deadline을 유지한다. Claude는 사용자별 앱 연결 동의 전 Keychain·HTTP 접근을 차단하고, Grok은 최초 연결 동의·웹 대조 완료 전 자동 자격증명·네트워크 접근을 차단한다.
- 사용자가 설정에서 시작한 `Claude 연결…`·`Cursor로 연결…`은 같은 공급자의 조회 슬롯을 사용한다. OS 권한 확인을 기다리는 시간에는 store의 15초 deadline을 적용하지 않는다. 실제 HTTP 요청은 공급자 transport의 별도 시간 제한을 유지하며, 권한 대기 중 자동·수동 중복 조회를 시작하지 않는다.
- 성공 응답과 마지막 성공 시각은 메모리에만 유지한다. 실패해도 이전 성공 값을 보존하고 즉시 stale로 표시한다. 마지막 성공 후 20분 경과도 stale이며 메뉴 막대 `*`와 메뉴의 이전 값 상태로 구분한다. 재시작 후 조회 전에는 `—`다.
- 메뉴에는 실제 제공되는 단기·주간·기타 한도, 각 reset, 마지막 성공, 권한 대기와 고정된 오류 문구를 구분한다. 원시 OS·CLI·HTTP 오류, 응답 본문, 계정 식별자와 인증정보는 표시·진단 로그·보고서에 남기지 않는다.
- 종료 시 timer를 중지하고 진행 중 조회 취소·정리를 기다린다. 아직 시작하지 않은 권한 요청은 취소한다. 이미 열린 OS 권한 대화상자는 사용자가 응답해야 반환할 수 있으므로 임의로 우회하거나 같은 요청을 다시 시작하지 않는다.

### 승인된 인증 접근과 권한 동작

공개 앱은 각 사용자의 공식 앱·CLI 로그인과 앱 내 연결 동의를 사용하며 개발자의 인증정보·계정 캐시를 배포하지 않는다. 추가 인증 입력은 Claude Code의 기본 macOS Keychain 항목과 Cursor 저장소의 `cursorAuth/accessToken` 한 항목이다. 두 토큰은 앱 프로세스 메모리에서 지정된 사용량·reset 조회에만 사용한다. 원본 인증정보 자체가 사용량 전용 권한인 것은 아니며 앱의 고정 호스트·경로·HTTP method·응답 필드로 목적을 제한한다. 일반 Grok의 별도 웹 쿠키나 기존 Grok Bot Safe Storage로 인증 범위를 넓히지 않는다.

Claude의 백그라운드 Keychain 조회는 `kSecUseAuthenticationUIFail`을 사용한다. OS 접근 승인이 필요하면 권한 필요 상태로 끝나며 자동으로 확인창을 열지 않는다. 사용자가 `Claude 연결…`에서 사용량 조회에 동의한 경우에만 `kSecUseAuthenticationUIAllow`를 허용한다. OS 암호 입력이나 로그인 제출은 사용자와 공식 앱·CLI가 처리한다.

Claude의 OS 권한 요청을 취소하거나 거부하면 비민감 거부 플래그를 앱 `UserDefaults`에 기억해 자동 재요청을 막으며 명시적인 연결 재시도에서만 해제한다. Claude는 앱 연결 허용 여부를, Grok은 최초 대조 뒤 검증 완료 여부를 기억한다. 연결·검증·거부·표시 플래그에는 인증정보·계정·실제 사용량 값이 없다. 앱은 인증정보를 갱신·마이그레이션·새로 저장하지 않고 refresh token을 사용하지 않는다. 브라우저 쿠키·대화 원문·세션 기록을 읽지 않으며 별도 인증 파일이나 비밀값 로그를 만들지 않는다. 허용 범위를 늘려야 하는 경우에는 자동 대체 경로를 시도하지 않는다.

Claude·Grok의 `연결 해제`는 새 요청을 막고 진행 중 소유 작업 정리가 끝난 뒤 해당 연결 플래그·성공 스냅샷·시각·오류를 지운다. 원본 Keychain·Cursor 인증정보를 삭제하지 않는다. 계정 변경 시 연결 해제와 공식 앱·CLI 로그인, 앱 재연결을 순서대로 수행하며 Grok은 웹 대조도 다시 요구한다. Codex 계정 변경은 공식 CLI에서 처리한 뒤 새로고침한다.

### 공급자별 조회 경로

**Codex:** 사용자가 공식 CLI의 `codex login`을 본인 계정으로 완료한 뒤 사용한다. 기존 `codex app-server`의 `initialize → initialized → account/rateLimits/read`를 유지한다. 인증 파일·브라우저 쿠키를 앱이 직접 읽지 않는다. 기존 nonblocking read·poll·12초 제한·소유 자식 프로세스 정리 안전장치도 유지한다.

**Grok (Cursor 기반 승인 경로):** `GrokSubscriptionUsageProviderClient`는 `CursorGrokCredentialSource`를 명시적으로 주입한 기존 사용량 HTTP client만 사용한다. 자격증명 입력은 Cursor의 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`에서 아래 한 항목을 읽는 것으로 제한한다.

```sql
SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1
```

저장소는 read-only로 열고 최신 WAL 상태를 보존하는 읽기 경로를 사용한다. 다른 키·계정·선택 team·refresh token을 조회하지 않으며 DB·자격증명을 복사·갱신·마이그레이션하지 않는다. 항목 부재·잠금·지원하지 않는 형식·만료는 고정 오류로 끝낸다. 기존 Grok Bot Safe Storage·Keychain과 Grok Build CLI 구현은 소스에 보존하지만 이 wrapper의 기본·수동·진단 자격증명 공급원으로 선택하지 않는다.

네트워크 요청은 고정 `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`에 ConnectRPC JSON으로 보낸다. 승인된 access token을 메모리에서 요청 인증에 사용하며 team header를 추가하지 않는다. 응답의 `usagePercent`·`nextResetTimestampUtc`와 공유·enterprise 구분 필드만 해석한다. 비율 부재·범위 오류·지원하지 않는 pooled enterprise 한도는 수치를 만들지 않는다. API 금액·Extra Usage Credits·제품별 사용 비중을 구독 공통 잔여율로 바꾸지 않는다.

자동 wrapper는 `requiresVerification=true`이며 `grokCursorUsageVerified`가 없으면 자격증명 읽기·네트워크 요청 전에 `.notConnected`로 끝난다. 최초 웹 대조를 위해 사용자가 `Cursor로 연결…`에서 사용량 조회에 동의한 경로만 이 gate를 통과한다. 실제 사용률·리셋을 [Grok 사용량 화면](https://grok.com/?_s=usage)과 대조한 뒤 `웹 값과 일치함 · 자동 갱신`과 확인창의 `일치함 · 10분 갱신 시작`을 선택해야 검증 플래그를 활성화한다. 이후 켜진 서비스만 600초마다 독립 갱신한다. 불일치하거나 계정·기간이 확인되지 않으면 연결 완료로 처리하지 않는다. 실제 계정 수치·날짜·제품별 사용 내역은 문서·원장·보고서에 저장하지 않는다.

공식 [Grok FAQ](https://docs.x.ai/grok/faq)의 Usage 표시를 대조 기준으로 사용한다. Cursor 인증으로 RPC가 응답했다는 사실만으로 일반 Grok의 같은 계정·구독 기간·공통 한도라고 단정하지 않는다. 제품별 비중은 사용 내역이며 별도 한도로 합산하지 않는다. 공개 비교자료는 [LoopLabsBar](https://github.com/RichStone/LoopLabsBar/blob/main/looplabsbar.1m.py), [CodexBar](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/docs/grok.md), [codex-limits](https://github.com/thrr87/codex-limits/blob/c1508063a493b8fc433dcdf3cee013f717035805/Sources/CodexLimits/GrokBillingClient.swift)이며 실제 계정 대조를 대신하지 않는다.

**Claude:** 앱 연결 허용 플래그의 기본값은 꺼짐이며, 사용자가 `Claude 연결…`에서 동의하기 전에는 기본 Keychain이나 사용량 HTTP를 조회하지 않는다. 연결 시 현재 로컬 사용자의 기본 Keychain service `Claude Code-credentials` 항목에서 유효한 Claude Code OAuth access token만 앱 메모리에서 사용한다. 다른 프로필·인증 파일·Claude Desktop 저장소를 탐색하지 않는다. 고정 `GET https://api.anthropic.com/api/oauth/usage` 응답의 공통 `five_hour`·`seven_day`와 제공되는 `seven_day_sonnet`·`seven_day_opus`의 `utilization`·`resets_at`만 상태로 옮긴다. 모델별 창은 상세 정보이며 기본 공통 잔여율에서 제외한다. 금액·추가 사용량·계정 정보는 소비하지 않는다.

구독 계정 로그인은 공식 `claude auth login --claudeai` 경로에서 사용자가 완료하며, 앱은 토큰 갱신이나 Keychain 쓰기를 하지 않는다. 항목 부재·만료·401·403은 로그인 필요로 끝낸다. 자동 `/usage`·PTY·모델 요청을 실행하지 않으므로 해당 CLI 명령이 기존 transcript를 순회할 가능성에도 의존하지 않는다.

두 HTTP transport는 임시 세션을 사용하고 쿠키·인증 캐시·URL 캐시를 사용하지 않으며 redirect로 인증정보를 다른 경로에 전달하지 않는다. Claude OAuth usage와 Cursor 기반 `GetSandUsageStatus`는 외부 앱용 공개 안정 API 계약이 확인된 것은 아니다. 응답·인증 방식이 바뀌면 연결 오류로 끝내고 별도 호스트·DB 키·쿠키·refresh 경로를 자동 탐색하지 않는다.

### 조사 이력과 실제 검증의 구분

초기 읽기 전용 조사에서는 Grok Bot 공개 자동 조회 경로를 확인하지 못했고 Claude Code는 로그아웃 상태였다. 그때의 `auth status` 전용·미연결 설명은 과거 조사 결과다. 이후 설치 앱·CLI의 정적 코드로 위 경로를 확인하고 사용자의 지속 접근 승인을 받아 연결 코드를 추가했다.

2026-10-19 공식 Claude Code OAuth 로그인 후 설치 앱 0.2.4(2026101902)의 실제 Codex·Claude 사용량 응답 성공을 확인했다. 과거 Grok Bot 진단 2026101903은 지정 Keychain 항목 미발견으로 끝났다. 이후 사용자가 Bot 사용량 화면은 보인다고 확인하고 일반 Grok로 대상을 바꾸어 해당 추적을 중단했다. 2026101904는 새 대상의 미연결 경계를 보호하는 테스트를 포함해 79개 합성·회귀 테스트를 통과했으며, 일반 Grok 실조회 성공을 뜻하지 않는다. 동일 설치판의 background 진단에서 기존 Codex·Claude 실제 응답 성공을 다시 확인했고, Grok은 인증·네트워크 없는 미연결로 종료했다.

프로토콜 비교 참고: [CodexBar Grok](https://github.com/steipete/CodexBar/blob/main/docs/grok.md), [QuotaBar](https://github.com/hibik1725/ai-usage-monitor). 로고 라이선스는 [third-party-notices.md](third-party-notices.md)에 보존한다.


## Windows 0.4.0 미리보기: 세 공급자와 계정 연결

이 절은 Windows 0.4.0 공개 미리보기의 동작 계약이다. 공개 ZIP의 고정 소스는 `5e026a0027e5fa6c52b602f6986d294245564625`이며 이전 Windows v0.3.1은 Codex 전용이다. [배포 기록](releases/2026-10-20-windows-v0.4.0.md)은 CI·합성 저장소/HTTP·UI·배포 실행 파일 검사와 아직 미확인인 실물 Windows 실계정·절전 복귀·Explorer 재시작을 구분한다. macOS 0.3.1과 iPhone TestFlight 1.0(16)의 런타임은 변경하지 않는다.

기본 순서는 `Codex / Grok / Claude`이고 세 로고·잔여율을 모두 표시한다. 대표 값은 공통 한도 중 가장 적게 남은 비율을 내림한 값이다. Claude 모델별 한도는 상세에만 두며 공통 한도와 합산하지 않는다. 수치가 없으면 `—`, 실제 영이면 `0%`다. 리셋 시간의 기본 표시는 꺼짐이며 사용자가 선택해 켠다.

서비스별 동의·표시·상태·취소·이전 성공 값을 독립 관리한다. 켜진 연결은 기본 600초 간격으로 조회하고 리셋 카운트다운은 60초 간격으로 표시만 갱신한다. 조회 실패는 이전 성공 값을 유지하며 즉시 이전 값으로 구분하고, 성공 후 20분 경과도 이전 값이다. 숨김은 새 조회를 차단하고 진행 중 작업을 취소한다. 모두 숨겨도 `사용량` 진입점이 남는다. 앱 종료·연결 해제로 메모리 캐시를 정리하고 비민감 설정만 보관한다.

Codex는 기존 공식 `codex app-server` JSONL 조회를 유지한다. 설정에서 사용자가 시작한 Codex·Claude 로그인은 공식 CLI를 사용하며 인증 출력·대화·프롬프트를 수집하지 않는다. Claude는 서비스별 앱 동의 뒤 기본 `~/.claude/.credentials.json`의 `claudeAiOauth.accessToken`·만료·필요 scope만 사용한다. 고정 `GET https://api.anthropic.com/api/oauth/usage`의 공통 `five_hour`·`seven_day`와 제공되는 모델별 `utilization`·`resets_at`만 해석한다. refresh token이나 다른 저장소로 대체하지 않는다.

Grok의 저장소는 `%APPDATA%\Cursor\User\globalStorage\state.vscdb`이고 SQL은 아래 하나다.

```sql
SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1
```

고정 SQLite 3.53.4와 `mode=ro&readonly_shm=1`을 사용하고 읽기 전용 상태를 확인한다. 기본 DB와 기존 WAL·SHM의 로컬 경로·파일·핸들을 검증하며, 두 sidecar가 없거나 지원 조건이 다르면 연결을 중단한다. reparse point·네트워크 경로·DB 복사·immutable/nolock 우회·다른 키·프로필 탐색은 없다. SQL 크기·결과 크기·실행 시간·취소를 제한하며 원본 DB·WAL·SHM·인증정보를 쓰거나 새로 만들지 않는다.

Grok 네트워크는 고정 `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`, JSON `{}`와 ConnectRPC 헤더를 사용한다. 응답의 사용률·리셋·공유/enterprise 구분을 해석하고 pooled enterprise·유효하지 않은 비율은 미지원으로 끝낸다. 최초 동의 조회 후 사용자가 본인 [Grok 웹 사용량](https://grok.com/?_s=usage)의 계정·기간·사용률·리셋을 대조해야 자동 조회를 허용한다. 불일치·미확인은 연결 완료로 처리하지 않는다.

추가 토큰·사용량 스냅샷은 메모리에만 둔다. 두 HTTP 경로는 redirect·쿠키를 사용하지 않으며 원시 오류·응답·인증정보를 표시나 로그에 남기지 않는다. 앱 연결 해제는 해당 동의·검증·메모리 상태를 지우고 공식 인증정보는 유지한다. 계정을 바꾸면 연결 해제·공식 로그인·재연결과 Grok 재대조를 순서대로 수행한다.
