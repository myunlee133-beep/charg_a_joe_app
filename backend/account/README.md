# 찾아줘 공통 계정과 직접 송금 퀘스트

대상: `iqalavbntvadqawkegfa` / 앱과 기존 커뮤니티·분실물의 같은 Supabase Auth 프로젝트.

## 계정 키와 접근 제어

- 로그인 주체는 언제나 `auth.users.id` (UUID)입니다. 이메일·닉네임으로 사용자 식별자를 만들거나 기존 사용자를 병합하지 않습니다. 이메일이 없는 소셜 회원도 Auth가 관리하는 `auth.identities`의 Google·카카오·Apple 연결로 인증 여부를 확인합니다. 이용자가 편집하는 metadata로 인증을 대체하지 않습니다.
- `account_profiles.user_id`, 기존 `community_profiles.user_id`, 의뢰의 `requester_user_id`, 수행의 `performer_user_id`, 거래의 `payer_user_id`·`payee_user_id`가 같은 Auth UUID를 참조합니다.
- 모든 쓰기 RPC는 `auth.uid()`에서 호출자를 결정합니다. 앱은 user ID, 지급자·수취인 ID 또는 확정 보상액을 전달해 다른 사람으로 기록할 수 없습니다.
- 클라이언트의 테이블 직접 접근은 권한과 RLS 양쪽에서 차단합니다. 공개 목록에는 내부 사용자 UUID·이메일·제출 원문·은행 정보를 반환하지 않습니다. 비공개 결과는 의뢰자·제출자만, 거래·계좌 안내는 해당 당사자만 RPC로 조회합니다.
- `private.account_subjects.id`는 탈퇴 후 법정 보존 기록을 연결하기 위한 별도 가명키입니다. 익명 정보로 취급하지 않습니다. `user_id` FK는 탈퇴 시 null이 되고 프로필은 삭제되며, 거래·증빙에 CASCADE 삭제를 걸지 않습니다.
- `AccountStore.shared`가 기기 Keychain 세션과 토큰 갱신을 하나만 소유합니다. 이메일 인증·재설정과 OAuth는 PKCE로 요청 기기에 연결하고, 임의 deep link의 access token은 받아들이지 않습니다. 커뮤니티·분실물·퀘스트가 같은 계정과 갱신 작업을 공유하고 로그아웃·계정 전환 시 이전 계정 화면 데이터를 비웁니다.

## 적용

기존 `backend/community/001_community_mvp.sql`이 적용된 프로젝트에서 다음 순서로 실행합니다.

1. `001_account_quests.sql`: 테이블·키·권한·RPC·기존 사용자 키 매핑·신규 가입 트리거.
2. `002_policy_seed.sql`: 공개 문서 5종과 문서별 SHA-256·버전. 기존 회원을 자동 동의 처리하지 않습니다.
3. `003_retention_job.sql`: Supabase pg_cron, 매일 한국 시각 03:20에 보유 기간 종료 데이터 정리.
4. `verify.sql`: 계정 매핑 누락 0, 활성 문서 5, 비공개 접근 false, 직접 쓰기 false, 미인증 수락 false, RLS 비활성 0, 정리 작업 active를 확인합니다.
5. `tests.sql`: 임의 생성한 합성 계정 네 명으로 권한·보상·탈퇴 보존 검증 후 전체 ROLLBACK. 실제 이용자의 계정·글을 수정하지 않습니다.

SQL은 재실행할 수 있습니다. 정책 본문을 바꾸려면 `policies.json`에서 문서 버전을 올리고 `python scripts/build_account_policies.py`를 실행합니다. 이미 게시한 같은 버전의 본문을 덮어쓰지 않습니다. 네이티브 번들 문서는 동일 소스에서 생성하며, 동의 버튼은 서버에서 받은 문서와 해시를 확인하기 전에는 활성화하지 않습니다.

앱 복귀 URL은 2026-11-03 사용자가 소유자 계정에서 추가했고 대시보드에서 등록을 확인했습니다. Brevo SMTP 연결과 찾아줘 발신자 인증을 완료했습니다. 실제 가입·복구 메일의 전달 확인은 별도이며, SMTP 값 저장만으로 수신 완료를 판단하지 않습니다.

Auth의 Redirect URL 허용 목록에 `org.chargajoe.chajajwo://auth/callback`을 추가합니다. 기존 웹·다른 앱의 redirect는 유지합니다. 이메일 인증을 유지하고 실제 발송 SMTP와 발송 제한을 점검합니다.

앱 시작과 로그아웃 시 로그인·회원가입 전용 화면이 먼저 표시됩니다. 로그인과 필수 계정 설정을 마쳐야 홈·탭·위치 기능이 생성됩니다. 저장된 세션은 먼저 복원하며, 정상 세션이면 홈으로 이어집니다. Google·Apple·카카오와 이메일 입력을 첫 화면에 표시합니다. 공급자가 서버에서 활성화된 경우에만 OAuth를 시작하며 미설정 방법은 준비 중 안내를 표시합니다. Google·카카오를 Supabase에서 활성화했고 Apple 활성화는 사용자 요청으로 보류합니다. Google은 외부 사용자 대상 production 상태이며 공개 정책 링크를 등록했습니다. Google은 `openid email`, 카카오는 `profile_nickname`만 요청하고 실제 authorize 리다이렉트에서 범위를 확인했습니다.

Google Cloud의 웹 OAuth 클라이언트와 Kakao Developers의 REST API 키에는 `https://iqalavbntvadqawkegfa.supabase.co/auth/v1/callback`을 redirect URI로 등록합니다. 앱 복귀 URL과 공급자 서버 callback URL은 서로 다른 단계입니다. 클라이언트 secret·SMTP key는 Supabase 대시보드에만 저장하고 앱·Git 저장소에는 넣지 않습니다. Brevo의 처리 국가·연락처·발송 로그 1개월·미리보기 미보관과 소셜 인증에 맞춰 정책 버전을 2026-11-03.2로 갱신했습니다.

네이티브 화면 캡처용 `-preview-content`는 DEBUG 빌드에서만 공개 홈을 렌더링합니다. 인증 세션을 만들거나 서버 권한을 부여하지 않으며 Release 빌드의 로그인 흐름에는 적용되지 않습니다.

## 퀘스트와 보상

선착순은 퀘스트 행 잠금과 상태 전환으로 한 명에게만 수락을 허용합니다. 결과 보상은 여러 결과를 접수하고 한 결과만 승인합니다. 승인과 거래 생성은 같은 DB 트랜잭션이며 금액은 서버의 의뢰 금액을 복사합니다. 중복 승인·중복 보상은 unique 제약으로도 차단합니다.

`결과 승인 → awaiting_transfer → 의뢰자 송금 신고 → transfer_reported → 수행자 실제 입금 확인 → received` 순서입니다. 은행 API·PG·잔액·에스크로는 연결하지 않습니다. 앱 상태는 은행 이체 성공을 증명하지 않습니다. 운영자가 다른 사람 대신 송금 또는 입금 확인을 누르는 기능은 제공하지 않습니다.

계좌 안내는 승인된 거래의 수취인이 거래별 동의를 한 후 은행·예금주·계좌번호를 입력할 때만 저장합니다. 해당 지급자만 확인할 수 있으며 철회 시 원문을 즉시 삭제합니다. 입금 확인 후 30일이 지나면 계좌 안내와 제출 결과 원문을 정리합니다. 법정 보존 대상 최소 계약·보상 기록은 완료 후 5년 보존하고 이후 삭제합니다. 분쟁은 완료로 자동 처리하지 않으며 운영자가 당사자 증빙과 적용 보존 근거를 확인해 해결해야 합니다.

미확인 송금·진행 의뢰·분쟁이 있으면 자동 계정 삭제를 막고 운영자 삭제 지원 연락처를 표시합니다. 운영자는 미해결 의무를 영구 방치하지 말고 당사자 확인, 목적별 처리 제한, 법정 보존 사유와 기간 안내, 계좌 정보 파기를 포함하여 권리 행사 요청을 처리해야 합니다.

## 운영과 검증

- 운영자·개인정보 보호책임자: 기존 서비스에 게시된 이경록 / `info@chargajoe.org`를 사용자 확인에 따라 유지했습니다. 존재하지 않는 사업자 번호·주소·결제대행사를 만들어 넣지 않았습니다.
- 프로젝트 대시보드의 기본 저장 지역은 India / Mumbai / `ap-south-1`입니다. Supabase의 계약상 처리자 명칭은 현재 DPA의 Supabase Pte. Ltd.를 사용합니다. 국외 처리 문서에 저장 국가, 항목, 목적, 방법·시점, 보유 기간, 연락처와 거부 시 영향을 기재했습니다.
- `.github/workflows/account-backend.yml`은 독립 PostgreSQL 17에 마이그레이션을 두 번 실행하고 실제 DB 권한·상태 전환 테스트를 수행합니다. `.github/workflows/ios.yml`은 실제 iOS 시뮬레이터 빌드, 로그인 입력 검증, 인증 전 정책 화면 접근 및 스크린샷을 검증합니다. UI 검증에서 실제 가입·정책 동의·금전 지급을 실행하지 않습니다.
- 법적 적용 범위와 처리 실태가 바뀌면 문서·보유 기간·제공 동의를 함께 갱신해야 합니다. 사업자 등록, 통신판매 중개 관련 표시 의무 등 운영 주체의 실제 법적 지위는 이 코드가 대신 확정하지 않습니다.

검토 근거: [개인정보 보호법 제30조](https://www.law.go.kr/LSW/lsLinkCommonInfo.do?lsJoLnkSeq=1029334833), [전자상거래법 시행령의 거래기록 보존](https://law.go.kr/LSW/lsLawLinkInfo.do?chrClsCd=010202&lsJoLnkSeq=900619372), [Supabase 사용자 키 관리](https://supabase.com/docs/guides/auth/managing-user-data), [Supabase DPA](https://supabase.com/legal/customer-resources/data-processing-addendum), [재수탁자 목록](https://supabase.com/legal/customer-resources/subprocessor-list).

소셜 로그인 아이콘 출처: [Google 공식 버튼 리소스](https://developers.google.com/identity/branding-guidelines), [카카오 공식 로그인 리소스](https://developers.kakao.com/tool/resource/login). 카카오 심볼의 원본 경로를 유지하며 Google 아이콘도 공식 PNG를 사용합니다.
