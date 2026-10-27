# CSV 테스트와 DB 운영의 완전 분리 (v0.3.2)

두 경로는 동일한 `pipeline.collect()`(식단 HTML), `pipeline.collect_metadata()`(식당/위치/운영시간) 및 파서와 가격 보정 코드를 사용합니다. **식샤 API·식샤 크롤러를 호출하지 않습니다.**

| | 테스트/검증: CSV | 실제 앱 운영: DB |
|---|---|---|
| 모듈 | `chajwo_meals.csv_runner` | `chajwo_meals.db_runner` |
| 바로 실행하는 파이썬 파일 | `examples/save_as_csv.py` | `examples/save_to_database.py` |
| 재현 노트북 | `notebooks/01_test_csv.ipynb` | `notebooks/02_sync_database.ipynb` |
| 저장 | `outputs/test_csv/*.csv`, `*.json` | 외부 PostgreSQL 또는 로컬 SQLite |
| DB 열기 | **하지 않음** | **반드시 연결** |
| CSV 내보내기 | 사용 | **하지 않음** |
| 잘못된 가격 | 두 경로 공통 검증·보정·원문 보존 | 동일 |
| 식당 정보 | `restaurant_directory.csv` | `restaurants` |
| 날짜별 운영 메모 | `meal_service_hours.csv` | `meal_service_hours` |
| 수집 오류 | `errors.json` | `crawl_errors` |
| 수집 실행이력 | `manifest.json`(마지막 실행) | `crawl_runs`(누적) |

## 1. 사용자 노트북/CSV 테스트

```bash
python -m pip install -e '.[dev]'
python -m chajwo_meals.csv_runner --live --days 1 --output outputs/test_csv
# 식단/CSV 확인 후
python -m chajwo_meals.csv_runner --live --days 30 --output outputs/test_csv
```

`python examples/save_as_csv.py --live --days 1 --output outputs/test_csv`도 동일합니다. 기본적으로 `--start`를 생략하면 KST 오늘 날짜를 사용합니다. CSV 파일은 UTF-8 BOM(Excel 호환)을 포함하고, 스프레드시트 수식 삽입을 방어하기 위해 일부 원문 값 앞에 작은따옴표가 붙을 수 있습니다. CSV 저장은 앱 DB를 변경하지 않습니다.

## 2. 개발 PC에서 DB 동작만 검사 (SQLite)

```bash
python -m chajwo_meals.db_runner --live --days 1 \
  --database-url sqlite:///data/meals_test.sqlite3
```

DB-only 실행은 `outputs/test_csv`를 만들지 않습니다. 수집 상태는 터미널 JSON 출력 및 `crawl_runs`, `crawl_errors` 테이블에서 확인합니다. `--output`을 주더라도 CSV 파일은 만들지 않습니다.

## 3. 앱 운영 DB (PostgreSQL)

```bash
python -m pip install -e '.[postgres]'
export DATABASE_URL='postgresql://<user>:<password>@<host>:5432/<db>'
python -m chajwo_meals.db_runner --live --days 30
```

서버 비밀번호는 GitHub 저장소, 앱 바이너리, 노트북 코드에 넣지 마세요. 사용자의 앱은 PostgreSQL에 직접 접근하지 않고 **서버 측 API를 통해 식단을 조회**해야 합니다.

GitHub Actions `.github/workflows/full-month.yml`, `same-day-refresh.yml` 모두 **DB 전용 실행기**를 사용합니다. `CHAJWO_DATABASE_URL` Secret은 영속 PostgreSQL URL이어야 하며, SQLite를 GitHub Actions 임시 파일시스템에 기록하면 이후 실행에 유지되지 않습니다.

## 4. DB 테이블

- `restaurants`: 식당·세부 코너별 위치/운영시간 및 출처
- `menu_entries`: 메뉴 단위. `source_date`, `restaurant_unit`, `meal_type`, `price_won`, `data_origin` 포함. `fixed_catalog`는 `source_date IS NULL`입니다.
- `meal_service_hours`: 날짜별 운영 공지(있을 경우)
- `crawl_runs`: 수집 이력; 매 실행마다 신규 기록
- `crawl_errors`: 수집 오류 이력; 오류가 있으면 누적

**갱신 범위:** 성공적으로 파싱한 **출처 + 날짜**의 기존 메뉴를 하나의 트랜잭션 안에서 대체합니다. 동일 메뉴는 재실행해도 계속 쌓이지 않습니다. 미게시 식단과 실패한 요청은 기존 데이터를 보존합니다. 단, 원천 사이트가 실제로 모든 메뉴를 의도적으로 삭제한 것인지, 아직 게시하지 않은 것인지 빈 응답만으로는 구분하기 어려워 **빈 응답은 삭제를 수행하지 않습니다**.

### 앱 백엔드용 조회 SQL 예시

```sql
SELECT m.restaurant_unit, m.menu_name, m.price_won, m.meal_type,
       m.source_date, m.data_origin, r.building_number, r.floor,
       r.latitude, r.longitude, r.weekday_hours
FROM menu_entries AS m
LEFT JOIN restaurants AS r ON r.name = m.restaurant_unit
WHERE m.source_date = :date OR m.data_origin = 'fixed_catalog'
ORDER BY r.building_number, m.restaurant_unit, m.meal_type;
```

`:date`는 **파라미터 바인딩**을 의미하는 예시입니다(라이브러리에 따라 `%s`, `$1`, `?` 등 사용). 날짜별 휴일/주말 운영시간과 `meal_service_hours`도 적용해야 실제 영업시간을 판단할 수 있습니다.

## 5. 예외·운영 정책

- `--live` 없이 네트워크 요청하지 않습니다.
- 개인 테스트는 1일치부터 확인하고, 정상 수집을 확인한 뒤 30일로 확대하세요.
- 실패하면 실행기는 종료 코드 `2`를 반환합니다. CSV 출력 파일의 존재만으로 성공으로 판단하지 마세요.
- GitHub Actions의 예약 실행은 지연될 수 있습니다. 당일 갱신을 엄격히 보장하려면 상시 서버의 cron/작업 큐 및 지연 알림이 필요합니다.
- 외부 페이지/데이터의 이용 조건과 재게시 허가를 먼저 확인하세요.
- 온라인 실사이트 접속·PostgreSQL 운영 연결은 이 코드 번들의 오프라인 테스트로 검증된 것이 아닙니다.
