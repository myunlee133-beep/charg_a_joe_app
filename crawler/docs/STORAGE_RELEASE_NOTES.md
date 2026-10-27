# v0.3.2 배포 변경 사항

## 목표

v0.3.1의 단일 CLI는 `--write-db`를 지정하면 CSV/JSON을 내보낸 뒤 DB도 갱신했습니다. 이제 개인 테스트와 앱 운영이 섞이지 않도록 진입점을 분리했습니다.

## 새 실행 경로

- **개인 CSV 테스트**: `python -m chajwo_meals.csv_runner --live --days 1 --output outputs/test_csv`
- **앱 DB 운영**: `python -m chajwo_meals.db_runner --live --days 30` + 영속 `DATABASE_URL` 환경변수
- **CSV 실습 노트북**: `notebooks/01_test_csv.ipynb`
- **DB 실습 노트북**: `notebooks/02_sync_database.ipynb`

DB 진입점은 `pipeline.export`를 호출하지 않고 데이터·상태 리포트를 메모리에서 계산합니다. CSV 진입점은 DB 연결 코드인 `sync_db`를 호출하지 않습니다. 양쪽 모두 같은 원본 HTML 크롤링, 가격 보정, 코너 매핑, 운영시간 수집을 사용합니다.

## 호환성 및 안전성

- `python -m chajwo_meals --live --write-db --database-url ... --output ...`는 종전과 같이 CSV+DB 둘 다 저장해 오래된 사용법을 지원합니다. 신규 운영에는 권장하지 않습니다.
- `--live` 없는 요청은 외부 크롤링을 수행하지 않습니다.
- 예정된 GitHub Actions 작업은 이제 DB 전용 경로를 사용하며 불필요한 CSV 파일을 업로드하지 않습니다.
- `crawl_runs`, `crawl_errors` 테이블에는 DB 모드의 감사 이력이 남습니다.
- 실사이트 HTTP 요청과 운영 PostgreSQL 연결은 이번 오프라인 테스트 범위 밖입니다.

## 검증 항목

- 단위 테스트 60개 통과(오프라인 HTTP fixture 기반)
- CSV 모드 실행 시 `DATABASE_URL`이 설정돼 있어도 DB 파일 미생성
- DB 모드 실행 시 CSV 출력 폴더 미생성
- 두 모드의 `record_id` 집합 일치
- DB 재실행 시 메뉴 행 수 불변 및 가격 수정 반영
- 외부 접속 오류 시 저장된 정상 메뉴 보존
- 2개 분리 노트북 전체 셀 실행 검증
- Python wheel 빌드 성공
