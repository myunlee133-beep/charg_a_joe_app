# 통합 습득물 서버

## 적용 순서

선택적 화면 확인용 자료는 [demo/README.md](demo/README.md)를 따릅니다. 기존 테스트 계정에 가상 물품 16건을 추가하는 관리용 SQL이며 일반 마이그레이션에 포함하지 않습니다. 모든 제목에 `[테스트]`를 붙이고 실제 MySNU 출처로 등록하지 않습니다.

1. 기존 `backend/community/001_community_mvp.sql`과 `001_lost_found_mvp.sql`이 적용된 Supabase 프로젝트를 백업합니다.
2. SQL Editor에서 `002_unified_found_items.sql`을 실행하고 통합 목록을 사용하는 iOS 클라이언트를 함께 배포합니다. 마이그레이션은 한 트랜잭션이며 다시 실행할 수 있습니다.
3. 담당자 권한은 운영자가 `community_profiles.role = 'moderator'`로 지정합니다. 클라이언트는 이 권한을 직접 설정하지 못합니다.
4. `003_shuttle_storage_center.sql`로 331동 셔틀버스 보관처를 추가합니다. 보관처 데이터만 추가하며 권한·RLS를 변경하지 않습니다. 2014년 공식 안내에 근거하므로 현재 운영·이관 일정은 방문 전 확인하도록 표시합니다.

앱의 목록 필터는 등록자가 아닌 현재 보관 장소 5개(101동, 67동, 셔틀버스 보관소, 기타, 관악경찰서)를 사용합니다. MySNU와 staff의 표시 이름은 모두 `운영진`이며 원본 `source`·`source_id`는 동기화 중복 방지·이력 보존을 위해 그대로 유지합니다. 경찰 이관은 실제 수령 완료가 아니며, 경찰서 수령 기록과 연동하지 않으므로 이관 후 실제 수령 여부를 알 수 없다고 안내합니다.

마이그레이션 파일은 앱 실행 시 자동 적용되지 않습니다. 현재 앱 프로젝트에는 통합 마이그레이션과 331동 보관처 데이터가 적용되어 있고, 사용자 요청으로 MySNU 실제 물품 58건(8월 24·9월 16·10월 18)을 반영한 뒤 테스트 자료의 숨김 상태를 유지했습니다. 전체 게시판이 아닌 부분 범위이므로 `p_complete=false`를 사용했습니다. 기존 접근 보호·운영 권한은 변경하지 않았습니다.

기존 `lf_found_items`, `lf_lost_requests`, `lf_claims`, `lf_leads`는 삭제하지 않습니다. 기존 습득물과 수령 의사는 같은 UUID로 새 `lf_items`, `lf_item_claims`에 복사합니다. 이전 `returned`와 `closed`는 수령 완료로 옮깁니다. `handed_over`만으로 경찰서 이관을 추정하지 않으며 기존 위치를 유지해 보관 중으로 옮깁니다. 예전 분실 의뢰·연결·상태변경 RPC 권한은 회수합니다. 따라서 예전 앱에서 해당 RPC를 계속 호출하면 권한 오류가 발생합니다.

## 회원 RPC

모든 통합 RPC는 로그인한 회원만 호출합니다. 테이블 직접 읽기/쓰기는 허용하지 않습니다. 보관처 정보 `lf_centers_list()`만 기존대로 비로그인 조회를 허용합니다.

| RPC | 결과 |
| --- | --- |
| `lf_items_list()` | 보관 중·경찰 이관 물건 배열. 목록용 사진 본문은 항상 null |
| `lf_item_detail(p_item_id uuid)` | 상세 객체 또는 null. 허용된 상세 조회에서 JPEG base64 제공 |
| `lf_item_create(p_category, p_title, p_description, p_location_name, p_latitude, p_longitude, p_photo_base64 = null)` | UUID. 담당자는 staff, 일반 회원은 user로 자동 분류 |
| `lf_claim_interest(p_item_id uuid, p_proof text)` | 수령 의사 UUID. 같은 회원·물건 요청은 같은 UUID 반환 |
| `lf_claims_list()` | 자신의 수령 의사와 자신이 확인할 수 있는 요청 배열 |
| `lf_claim_verify(p_claim_id uuid, p_is_owner boolean)` | 작성자 또는 담당자의 본인 확인. 요청자 자신은 승인 불가 |
| `lf_claim_complete(p_claim_id uuid, p_outcome text)` | 요청자만 결과 등록. received는 본인 확인 accepted 이후에만 가능 |
| `lf_item_transfer(p_item_id uuid, p_location_name, p_latitude, p_longitude)` | 작성자 또는 담당자가 실제 경찰서 보관 위치를 필수 입력해 이관 |

물건 객체 필드는 `id`, `source`, `source_id`, `category`, `title`, `description`, `location_name`, `latitude`, `longitude`, `registered_at`, `status`, `photo_url`, `photo_base64`, `mine`입니다. 수령 의사 객체는 `id`, `item_id`, `title`, `proof`, `status`, `mine`, `can_verify`, `created_at`입니다. 개인정보인 증명 내용은 요청자·물건 작성자·담당자만 조회합니다.

위치는 필수이며 위도 33~39, 경도 124~132 범위입니다. 사진은 선택 사항이고 base64로 인코딩한 JPEG만 받습니다. 디코딩 후 512KiB 이하와 JPEG 시작·종료 서명을 검사합니다. 이미지 전체 디코딩 검사는 클라이언트의 이미지 처리 단계에서도 수행해야 합니다.

수령 의사 상태는 `pending`, `accepted`, `rejected`, `received`, `not_mine`, `not_received`입니다. `not_mine`과 `not_received`는 물건 목록·지도를 숨기지 않습니다. `received`만 목록·지도에서 숨깁니다. 물건 행을 먼저 잠가 여러 요청자가 동시에 수령 완료하더라도 한 건만 완료됩니다. 다른 미완료 요청은 거절 상태로 바뀝니다. 완료 후 상세는 요청 이력이 있는 회원·작성자·담당자만 볼 수 있습니다. 완료 상태는 자동으로 되돌리지 않습니다.

## MySNU 동기화

`lf_sync_mysnu(p_items jsonb, p_complete boolean, p_run_id uuid)`는 **service_role 전용**입니다. 이 키는 iOS 앱에 넣지 않습니다. `p_items`는 다음 필드가 모두 있는 객체 배열입니다.

```json
{
  "source_id": "원문에서 변하지 않는 항목 ID",
  "category": "지갑",
  "title": "검정 지갑",
  "description": "원문 설명",
  "location_name": "101동 분실물센터",
  "latitude": 37.46328,
  "longitude": 126.95015,
  "registered_at": "2026-10-30T09:00:00+09:00",
  "status": "stored",
  "photo_url": "https://example.com/photo.jpg"
}
```

`photo_url`은 선택 사항입니다. 상태는 `stored` 또는 `police`이며 날짜에는 시간대가 포함되어야 합니다. 응답은 `ok: true`, `run_id`, `complete`, `seen`, `inserted`, `updated`, `removed`입니다. 배열은 1~5,000건, JSON 전체는 10MiB 이하입니다. 중복 ID·누락 필드·잘못된 위치·미래 등록일·안전하지 않은 사진 URL은 전체 트랜잭션을 실패시킵니다.

- 모든 페이지와 필수 내용을 성공적으로 가져온 경우에만 `p_complete=true`를 보냅니다. 실패·부분 수집은 false로 보내거나 아예 호출하지 않습니다.
- complete=true에서 사라진 MySNU 물건만 `received`, 사유 `source_removed`로 보관 이력에 남깁니다. 원문에서 빠졌다는 뜻이며 실제 주인이 수령했다고 확인한 것은 아닙니다.
- 빈 전체 스냅샷은 거부합니다. 수집 장애로 전체 물건을 숨기는 일을 막기 위한 제한입니다. 실제로 원문이 비었더라도 운영자 확인이 필요합니다.
- 같은 run UUID와 같은 내용은 저장된 응답을 반환합니다. 같은 UUID에 다른 내용은 거부합니다. 재시도 시 같은 순서의 배열과 같은 완료 플래그를 사용합니다.
- 동기화는 advisory transaction lock으로 직렬화합니다. 이미 received인 항목은 재등장해도 자동 복구하지 않습니다. 원문이 stored로 돌아가더라도 앱에서 기록한 police 이관 위치는 유지합니다.
- `lf_item_events`와 `lf_sync_runs`는 운영자용 감사 기록입니다. 서비스 키로도 테이블에 직접 접근하는 대신 허용된 RPC를 호출합니다.

## 검증

`tests/`에서 `pnpm install --ignore-scripts` 후 `pnpm test`를 실행합니다. 테스트는 PGlite의 실제 PostgreSQL 엔진과 pgcrypto를 쓰는 메모리 데이터베이스에서 기존 두 마이그레이션 → 이전 데이터 fixture → 통합 마이그레이션 → 회귀 검사를 수행합니다. 운영 URL이나 키를 읽지 않습니다.

검사 범위: 기존 데이터 보존·이관, RPC/테이블 권한, 필수 위치·JPEG 검증, 목록 사진 제외, 수령 의사 중복 요청·본인 확인·수령 완료·비수령, 담당자 출처, 완전/부분/실패 스냅샷, run UUID 재시도, 삭제 추정·재등장 tombstone, 마이그레이션 재실행입니다. PGlite는 한 연결로 실행하므로 실제 여러 연결의 잠금 경쟁과 Supabase Auth/PostgREST 설정은 별도의 스테이징 검사 대상입니다.
