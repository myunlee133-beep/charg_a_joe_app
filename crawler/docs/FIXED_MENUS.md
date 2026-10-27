# 고정 메뉴 카탈로그: 버거운버거 / 공대간이식당

## 분리하는 이유

SNUCO 공식 페이지는 두 식당을 `* 버거운버거`, `* 공대간이식당`으로 표시합니다. 같은 목록이 아침/점심/저녁에 반복되므로
일반 날짜별 크롤링 값만 쓰면 중복되고 복수 가격이 불확실하게 파싱됩니다. 식당명 `*`는 표기만 제거하고,
원본 관측은 `menu_lines.csv`, `fixed_menu_observed.csv`에 보존합니다.

## 고정 원본

`src/chajwo_meals/data/fixed_menu_catalog.csv` : UTF-8 BOM CSV. 2026-10-22 SNUCO 식단표 공개 표시 기준 수동 점검한 스냅샷.
운영 중 메뉴 변동이 가능하므로 상시 판매·현재 가격의 보증이 아닙니다.

- 버거운버거 101동 아시아연구소 1층 113호: 116 **가격 옵션 행**.
- 공대간이식당(공간) 30-2동: 20 **가격 옵션 행**.
- 버거운버거의 두 가격은 원문에 옵션명이 없어 `첫 번째 표기`/`두 번째 표기`로 표시합니다. 단품/세트로 확정하지 않습니다.
- 공대간이식당 호구세트 원문 `8,3000원`은 사용자 확인 가격 `8,300원`으로 보정하고 `trailing_zero_corrected` 상태로 관리합니다.
- 버거운버거 `쉬림프치즈베이크`와 `화이트어니언치킨버거`의 일부 금액은 원문 표기 오탈자 가능성이 있어 `needs_review`로 표시했습니다.

## CSV 필드

`restaurant`, `building_number`, `building_name`, `floor`, `category`, `menu_name`,
`price_variant`, `price_won`, `price_raw`, `price_status`, `source_url`, `observed_on`, `note`.

가격 옵션이 있는 메뉴는 행을 분리합니다. `price_won`을 수정하는 경우 `price_raw`와 `note`도 갱신하고
`observed_on`을 확인일로 바꾸세요. 확인되지 않은 가격은 숫자를 넣지 않습니다.

## 크롤링 결과와 병합

`--sources`에 `snuco`가 있으면 일반 수집 결과의 두 식당은 통합 메뉴 목록에서 카탈로그로 대체됩니다.
즉 `menu_items.csv`는 `meal_type=FIXED`, `source_date` 공란, `data_origin=fixed_catalog`로 내보냅니다.
나머지 식당은 `data_origin=observed_page`입니다.

`fixed_menu_catalog.csv`는 미확정 가격도 포함(136행)하며,
`menu_items.csv`에는 `published_price` 또는 `trailing_zero_corrected`이고 숫자 가격이 있는 카탈로그 행 **134개**가 들어갑니다.
`menu_entries.csv`는 미확정 가격도 포함합니다.

실제 사이트 조회가 실패해도 카탈로그는 유지됩니다. 단 `manifest.json`의 `status=partial_failure`를
반드시 확인하여 최신 데이터로 오인하지 않도록 해야 합니다.

## 업데이트 절차

1. 원본 [SNUCO 식단 페이지](https://snuco.snu.ac.kr/foodmenu/)의 해당 식당을 사람이 확인합니다.
2. 카탈로그 CSV에서 추가·삭제·가격 변경, 영업 여부 및 위치를 수정합니다.
3. 변경 검토 이유와 `observed_on`을 기록합니다. 중복 `(restaurant, menu_name, price_variant)`는 허용하지 않습니다.
4. `python -m pytest -q` 실행 후 Jupyter Notebook을 재실행합니다.
5. 외부 공개 전에 SNUCO의 데이터 이용 조건·사전 승낙을 확인합니다.

자동 크롤링 결과가 수동 확정 카탈로그를 **묵시적으로 덮어쓰지 않는 것이 핵심 규칙**입니다.


## 2026-10-22 추가 보정

호구세트의 원문 `8,3000원`은 사용자 확인 가격 **8,300원**으로 수정했습니다. `price_status=trailing_zero_corrected`, `price_raw=8,3000원`으로 보정 내역이 추적됩니다. 가격 표기 검토가 필요한 나머지 두 옵션은 그대로 `needs_review`입니다.
