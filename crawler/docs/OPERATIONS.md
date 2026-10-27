# DB 및 주기적 수집 운영

## 1. 가져오는 정보

| 원천 | 무엇을 가져오나 | 빈 데이터 취급 |
|---|---|---|
| SNUCO 식단표 | `?date=YYYY-MM-DD` 날짜별 메뉴·가격·시간공지 | 페이지가 비어 있어도 미래 메뉴를 채워 넣지 않음 |
| SNUDORM 식단표 | `?date=YYYY-MM-DD` 날짜별 메뉴·가격 | 동일 |
| VET 주간 표 | 주 단위로 게시한 날짜들만 | 게시되지 않은 날짜는 결측 |
| SNUCO 식당안내 | 건물·층·평일/주말/휴일 운영시간 | 요청 실패 시 이전 DB 시간 보존 |
| SNU 캠퍼스맵 | 건물명/번호/대표 좌표 (가능할 때만) | 요청 실패 시 이전 DB 좌표 보존 |

## 2. 영속적 DB

권장 운영 환경: PostgreSQL(자체 서버 또는 관리형 서비스). 빠른 로컬 실험: SQLite.

```bash
python -m pip install -e '.[postgres]'
export DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/DBNAME'
python -m chajwo_meals --live --days 30 --write-db
```

중요: `DATABASE_URL`에는 실제 접속 정보를 넣되 **절대 GitHub에 커밋하지 않습니다**. GitHub Actions Repository secrets에는 `CHAJWO_DATABASE_URL` 이름으로 등록합니다. GitHub Actions는 코드 push와 secret 등록만으로 데이터베이스를 자동 생성해 주지 않습니다. 공용 PostgreSQL 서비스는 사용자가 준비해야 합니다.

`database.py`는 다음 테이블을 자동 생성합니다:

```mermaid
erDiagram
  restaurants ||--o{ menu_entries : "restaurant_unit (logical)"
  restaurants ||--o{ meal_service_hours : "restaurant_unit (logical)"
  crawl_runs ||--o{ crawl_errors : "audit (run-time logical)"
  restaurants {
    text name PK
    text building_number
    text floor
    text weekday_hours
    text saturday_hours
    text holiday_hours
    double latitude
    double longitude
  }
  menu_entries {
    text record_id PK
    text source_date
    text restaurant_unit
    text meal_type
    text menu_name
    int price_won
    text data_origin
  }
  meal_service_hours {
    text source_date PK
    text restaurant_unit PK
    text meal_type PK
    text raw_notice PK
  }
  crawl_runs {
    int id PK
    text executed_at
    text status
  }
  crawl_errors {
    int id PK
    text source
    text target_date
  }
```

위 ERD 관계는 **조인 가능한 논리 관계**를 표시하며 현재 초기 간편 DB 스키마에서 FK 제약을 물리적으로 강제하지는 않습니다. `fixed_catalog`는 날짜가 NULL이며, 동적 식단은 날짜별로 저장합니다.

## 3. 재수집과 데이터 보존

- **매일 05:20 KST** 전 범위 30일을 조회합니다. URL이 30일치를 받아도 원천에 게시된 것만 적재합니다.
- **12:20, 18:20, 23:20 KST** 당일+다음 이틀을 재조회하여 변경을 반영합니다.
- 하루 동안 미래 식단이 추가되면 다음 성공 수집 직후 DB에 반영됩니다. GitHub cron은 best effort이며 정시 실행 보장은 없습니다.
- 파싱 성공했지만 데이터가 전혀 없는 날짜는 **기존 데이터 유지** 정책입니다. 이 정책은 미래 미게시로 인해 정상 데이터를 지우지 않지만, 식당이 실제로 폐업·휴무로 비워졌을 때 기존 메뉴가 남는 오탐이 생길 수 있습니다. **휴무/삭제를 확실히 식별하는 규칙은 별도 구현해야 합니다**.
- 성공적으로 메뉴가 존재하는 날짜·출처만 묶어서 갱신합니다. 다른 날짜·다른 출처를 삭제하지 않습니다.
- 수집 오류는 `errors.json`, `crawl_errors` 테이블에 기록합니다. `crawl_runs`로 배치 상태를 확인합니다.

## 4. 외부 출처 접속 문제

- HTTPS 인증서를 검증합니다. 외부가 잘못된 인증서를 제공하면 기록 후 중단합니다.
- 방화벽/차단 페이지가 정상 HTTP 200을 반환할 수 있으므로 HTML 식단 구조와 날짜 입력 값을 확인합니다.
- 메타데이터 제공 페이지 구조가 변경되면 운영시간이 누락될 수 있으므로 `guide_matched_units` 지표를 모니터링합니다.
- 매일 총 요청량과 사이트 이용 약관, 로봇 정책을 확인해야 합니다. 수집 제한을 우회하지 않습니다.
- 시스템 시각대는 KST로 고정합니다. 사람이 호출하는 `--start`는 YYYY-MM-DD.

## 5. 아직 구현되지 않은 운영 기능

- 날짜별 확정 휴무/폐점 추론을 통한 이전 데이터 삭제
- 서로 다른 날의 가격 변동 자동 승인 / 식당별 이상치 검토 화면
- 크롤링 실패에 대한 이메일/Slack 경고 및 수집 지연 SLA 알림
- 메뉴 없는 카페/신규 입점업체를 탐색하는 별도 전체 캠퍼스 사업자 데이터 파이프라인

이 기능들은 데이터를 임의 생성하거나 허가 없는 사이트를 추가로 수집하지 않기 위해 별도 범위로 남겼습니다.

## v0.3.1 라이브 전환 점검

1. `python -m pip install -e '.[dev,postgres]'` (로컬 SQLite만 사용할 때는 postgres 불필요)
2. `python -m pytest -q`로 오프라인 테스트 확인
3. 네트워크 접근 권한을 확보한 환경에서 `python -m chajwo_meals --live --days 1 --write-db --database-url sqlite:///data/live_check.sqlite3 --output outputs/live_check`
4. `outputs/live_check/errors.json`과 `manifest.json`의 `observation_count`, `database_sync.updated_source_date_scopes`를 확인. 종료 코드 0만으로 실제 메뉴가 게시됐다고 단정하지 말 것.
5. 하루 테스트가 정상인 경우 `--days 30`으로 확대. 서비스 운영 전 해당 출처 이용 허가 및 자동 수집 정책 검토.

노트북은 `MODE='live'` 설정 하나만 변경해도 KST 당일을 선택하며,
데모와 분리된 `outputs/notebook_live_v031/live_only.sqlite3`를 이용한다.
