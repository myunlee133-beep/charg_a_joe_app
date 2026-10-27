# 찾아줘: 서울대학교 독립 식단·식당 크롤러 (v0.3.2 · CSV/DB 저장 분리판)

> **식샤 소스코드·식샤 API 없이 실행합니다.** 식당·코너 단위 정보, 메뉴/가격, 기본 운영시간, 해당일 식사 시간, 건물 좌표를 직접 수집·관리하도록 독립 개발한 Python 프로젝트입니다.
>
> **주의:** 실제 서비스에서 반복 수집·재게시하기 전에는 각 원천 서비스 이용약관과 이용 허가를 확인해야 합니다. 소스 사이트가 공개했다는 이유만으로 무제한 수집·재배포 권한이 생기지 않습니다.

## 저장 모드 선택 (v0.3.2 · 핵심 변경)

**동일한 독립 크롤러가 서로 다른 두 저장 모드를 제공합니다.** 사용자 데이터 검증은 **CSV 전용**, 실제 앱 서버의 자동 갱신은 **DB 전용**을 사용하세요. 자세한 사용법은 [`docs/CSV_VS_DB.md`](docs/CSV_VS_DB.md)입니다.

| 용도 | 실행 모듈 / 실행 파일 | 결과 |
|---|---|---|
| 개인 테스트용 | `chajwo_meals.csv_runner` / `examples/save_as_csv.py` | CSV/JSON 파일만. **DB 접속 없음** |
| 앱 서버 운영용 | `chajwo_meals.db_runner` / `examples/save_to_database.py` | SQLite/PostgreSQL만. **CSV 내보내기 없음** |

아래 명령은 프로젝트 루트에서 실행합니다.

```bash
python -m pip install -e '.[dev]'

# 1. 실제 웹사이트 하루치 수집 후 CSV로 확인 (DB에 영향 없음)
python -m chajwo_meals.csv_runner --live --days 1 --output outputs/test_csv
# 정상 데이터 확인 뒤 30일로 확장
python -m chajwo_meals.csv_runner --live --days 30 --output outputs/test_csv

# 2. 로컬 SQLite로 DB 갱신 동작만 검증 (CSV 파일 미생성)
python -m chajwo_meals.db_runner --live --days 1 --database-url sqlite:///data/meals_test.sqlite3
```

**운영 PostgreSQL (서버):**

```bash
python -m pip install -e '.[postgres]'
export DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/DBNAME' # 로컬에서만 설정, GitHub 커밋 금지
python -m chajwo_meals.db_runner --live --days 30
```

- **CSV 재현 노트북:** [`notebooks/01_test_csv.ipynb`](notebooks/01_test_csv.ipynb) — 합성 HTML 모드에서 시작, `MODE='live'`로 변경 가능.
- **DB 재현 노트북:** [`notebooks/02_sync_database.ipynb`](notebooks/02_sync_database.ipynb) — 합성 HTML + 격리된 SQLite에서 시작, 실제 운영은 Python 서버 모듈 실행.
- **기존 통합 노트북:** `notebooks/independent_meal_crawler.ipynb`는 이전 버전 사용자를 위해 유지합니다.
- 백엔드 API가 DB를 읽어 앱에 전달해야 합니다. 앱 코드/모바일 앱에 DB 접속 비밀번호를 포함하지 마세요.
- 이전 `python -m chajwo_meals --live --write-db ...` 명령은 **기존 호환용으로 CSV+DB 둘 다 저장**합니다. 권장 방식은 위 두 전용 명령입니다.

## 요청사항 반영

| 요청 | 구현 |
|---|---|
| `호구세트 8,3000원` 오류 | **8,300원**으로 보정, 원문/보정 사유도 기록 |
| 이상한 가격의 맨 끝 `0` 삭제 | 천 단위 쉼표의 **마지막 그룹 길이가 4~5자리이고 초과 부분이 0**일 때만 보정. 정상 `10,000원` 등은 그대로 유지 |
| 향후 한 달 식단 | **오늘 포함 30일** 조회 지원 (`--days 30`, 최대 31일) |
| 당일 갱신 | GitHub Actions **05:20 KST 전 범위**, **12:20/18:20/23:20 KST 당일+2일** 재조회 예제 |
| DB 저장 | **SQLite(로컬), PostgreSQL(공용/서버)** 실시간 upsert. 오류·빈 미래 날짜는 정상 DB 보존 |
| 식당 위치 | SNUCO [식당안내](https://snuco.snu.ac.kr/식당안내/)의 건물·층 정보 + SNU 캠퍼스맵의 건물 위치 점 (옵션) |
| 운영시간 | SNUCO 식당안내의 **평일/토요일/휴일** 시간 + 메뉴페이지의 날짜별 운영/브레이크타임 공지 |
| 식샤 식당 비교 | 식샤 V2 공개 **초기 DB seed 31개 코너** + SNUCO 공식 안내의 **버거운버거·프레퍼스 추가**, 총 **33개** |
| 푸드코트 세분화 | 3식당/301동/220동/75-1동 푸드코트/예술계식당/두레미담의 섹션명에 따라 하위 코너 분류 |

**실제 식샤 앱 또는 운영 DB의 현재 식당 수는 검증되지 않았습니다.** 31개는 공개 SQL 마이그레이션의 **초기 등록 수**이며, `siksha_seed_comparison.csv`는 이 파일을 기준으로 한 비교입니다. 위치와 영업시간도 사이트의 갱신 주기에 따라 달라질 수 있습니다.

## 라이브 모드 점검 사항 (v0.3.1에서 확인; v0.3.2에서도 적용)

- 노트북에서 `MODE='live'`로 바꾸면 시작일이 **실행 시점의 한국 날짜**로 설정되며, 데모와 **출력 폴더 및 SQLite DB를 공유하지 않습니다**.
- 명령행에서는 기본적으로 `--live`가 필수입니다. `--start`를 생략하면 실행일(KST)을 사용합니다.
- 캠퍼스맵의 `EUC-KR` 응답은 UTF-8 우선·EUC-KR 대체 디코딩으로 처리합니다.
- 웹사이트 전체를 요청하는 실제 통합 검증은 네트워크 접근이 가능한 환경에서 재확인해야 합니다. DNS 연결이 실패하거나 차단 페이지가 오면 해당 항목이 `errors.json`에 기록되고, CLI는 종료 코드 2를 반환합니다.
- 네트워크 차단을 재현한 `--live` 경로 테스트와 30일 전체 요청·DB 갱신·재실행 테스트는 `tests/test_live_path.py`를 참고하세요.

## 빠른 시작

```bash
python -m pip install -e '.[dev]'
python -m pytest -q
```

재현용 노트북은 **CSV 전용** `notebooks/01_test_csv.ipynb`, **DB 전용** `notebooks/02_sync_database.ipynb`로 분리되었습니다. 모두 기본값은 자체 합성 HTML 데모로 인터넷에 접속하지 않습니다.

### CSV로 30일 식단 검증

```bash
python -m chajwo_meals.csv_runner --live --days 30 --output outputs/live_csv
```

### 로컬 SQLite로 DB 연동 테스트

```bash
python -m chajwo_meals.db_runner --live --days 1 --database-url sqlite:///data/meals_test.sqlite3
```

### 서버에서 PostgreSQL 운영

```bash
python -m pip install -e '.[postgres]'
export DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/chajwo'
python -m chajwo_meals.db_runner --live --days 30
```

운영 예약 수집은 두 GitHub Actions 워크플로가 **DB 전용 모듈**로 실행하도록 수정했습니다. 저장소 `Settings → Secrets and variables → Actions`에 영속 DB 주소를 **`CHAJWO_DATABASE_URL`** Secret으로 등록해야 합니다. 현재 GitHub Actions 예약 시각은 05:20(KST) 30일 및 12:20/18:20/23:20 당일+2일입니다. 스케줄이 지연될 수 있으므로 실제 반영 시각은 `crawl_runs`로 확인해야 합니다.

**주의:** `--days 30`은 최대 30개 날짜의 식단 URL을 확인한다는 뜻입니다. 원천 사이트에 미래 30일 전체 메뉴가 미게시되어 있으면 해당 날짜는 비어 있고, 데이터는 이후 수집 시 추가됩니다.

## CSV 모드 출력 데이터

| 파일 | 설명 |
|---|---|
| `restaurant_directory.csv` | 33개 장소/세부 코너, 건물·층, 평일·토요일·휴일 운영시간, 좌표 출처 및 신뢰수준 |
| `siksha_seed_comparison.csv` | 식샤 **초기 V2 seed** 대비 31개/신규 2개 비교 |
| `meal_service_hours.csv` | **각 날짜·끼니** 원문에 실제로 게시된 운영시간·브레이크타임 안내 |
| `menu_lines.csv` | HTML의 메뉴 원문 줄 + 변경 전 가격 + 파싱/보정상태 |
| `menu_entries.csv` | 유료·무료가격미표시·고정 메뉴를 포함하는 검토 가능한 행 |
| `menu_items.csv` | 가격이 확인/정규화된 판매 메뉴와 고정 카탈로그의 가격 옵션 |
| `locations.csv` | 이전 버전과 호환되는 식당/코너·위치 목록 |
| `fixed_menu_catalog.csv` | 버거운버거, 공대간이식당의 136개 가격 옵션 고정 스냅샷 |
| `fixed_menu_observed.csv` | 크롤링 페이지에서 발견한 고정식당 원문; 가격 변경 감시용 |
| `raw_records.json`, `errors.json`, `manifest.json` | 원문 관측기록, 실패 및 실행 요약 |

`restaurant_unit`은 `restaurant`(원본 식당 이름)보다 더 세분화된 이름입니다. 예: `220동식당` → `220동식당 포포420`. 메뉴 원문에 하위 브랜드 표기가 없다면 잘못 추정하지 않고 상위 식당 이름이 남을 수 있습니다.

**위도·경도는 개별 음식점 문 앞 좌표가 아니라 캠퍼스맵의 건물 대표 좌표**입니다. 확보할 수 없으면 NULL로 남깁니다. 영업시간은 일반 안내와 해당 날짜 공지를 분리해 제공합니다. `프레퍼스`는 공식 식당안내에 있으나 이번 3개 식단 출처에서 확인한 개별 메뉴는 없습니다. 없는 메뉴를 생성하지 않습니다.

## 데이터 안전성

- **30일 조회**: SNUCO 30건 + SNUDORM 30건 + VET 주간 페이지 1건. 부가적으로 식당안내와 캠퍼스맵 각 1건 조회. 1일 전체 실행 시 최대 63개 논리 요청이며 네트워크 재시도는 추가될 수 있습니다.
- **당일 재수집**: 별도 워크플로가 3일(최대 6+1+2 요청) 범위를 반복 조회합니다. GitHub Actions는 시작 시각이 지연될 수 있으므로 **정시 또는 같은 날 반영을 법적·기술적으로 보장하지 않습니다**. 엄격한 SLA가 필요하면 상시 실행 서버의 cron/작업큐를 권장합니다.
- **DB 보존**: 사이트 실패 시 이전 날짜 레코드는 삭제하지 않습니다. 200 OK지만 식단이 비어 있는 미래 날짜도 이전 데이터를 덮어쓰지 않습니다. 메뉴 줄이 성공적으로 존재하면 같은 출처·날짜만 트랜잭션으로 갱신합니다.
- **유효성**: 크롤링 요청은 최소 2초 간격, HTTPS 검증 켬, 타임아웃·제한 재시도. 차단 우회 없음.
- **가격**: `8,3000원` → 8,300원은 보정된 사례입니다. 비정상 가격 전부를 끝자리 0 제거해서 해결할 수 있는 것은 아닙니다. 불확실한 값은 `needs_review`로 보관합니다. `5.900원`은 점을 천 단위 구분으로 해석하고 상태를 남깁니다.
- **고정 메뉴**: 일자별 판매 확정 정보가 아닙니다(`meal_type=FIXED`, `source_date` 빈 값). 136행 중 2개 옵션은 여전히 검토 필요 상태입니다.

## 파일 구성

```text
src/chajwo_meals/
  cli.py                   # 공통 실행기와 --storage 모드 관리
  csv_runner.py            # CSV 전용 진입점
  db_runner.py             # DB 전용 진입점
  parser.py, prices.py     # 날짜별 식단/하위 코너/가격 분류
  directory.py             # 공식 식당안내·캠퍼스맵의 위치·영업시간
  hours.py                 # 당일 운영/휴식시간 메모 추출
  database.py              # SQLite/PostgreSQL 트랜잭션 동기화
  pipeline.py              # 직접 수집과 모든 JSON·CSV 내보내기
  fixed.py                 # 고정식당 참조 카탈로그
  data/restaurant_registry.csv   # 33개 매장/하위코너 데이터
  data/fixed_menu_catalog.csv    # 검토 가능한 고정 메뉴 스냅샷
.github/workflows/
  tests.yml
  full-month.yml          # 05:20 KST 30일 조회
  same-day-refresh.yml    # 12:20·18:20·23:20 KST 당일+2일 재조회
notebooks/01_test_csv.ipynb
notebooks/02_sync_database.ipynb
notebooks/independent_meal_crawler.ipynb (기존 호환)
examples/save_as_csv.py, save_to_database.py
```

추가 문서: [CSV/DB 저장 모드](docs/CSV_VS_DB.md), [식샤 seed 비교](docs/SIKSHA_COMPARISON.md), [DB·스케줄 운영](docs/OPERATIONS.md), [가격 보정 규칙](docs/PRICES.md).

## 라이선스와 출처

독립 구현 소스는 `LICENSE`(MIT) 조건을 따릅니다. 수집한 제3자 식단 데이터나 공식 사이트 내용의 재사용 허가를 의미하지 않습니다.

- [서울대 생활협동조합 식단](https://snuco.snu.ac.kr/foodmenu/)
- [서울대 생협 식당안내](https://snuco.snu.ac.kr/식당안내/)
- [관악학생생활관 식단](https://snudorm.snu.ac.kr/foodmenu/)
- [수의대 식단](https://vet.snu.ac.kr/cafe_menu/)
- [서울대 캠퍼스맵](https://map.snu.ac.kr/)
- [식샤 V2 seed SQL (비교 참고만)](https://github.com/wafflestudio/siksha-spring/blob/main/core/src/main/resources/db/migration/V8__split_v2_building_restaurant_custom.sql)
