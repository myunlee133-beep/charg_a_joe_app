# iOS 캠퍼스 건물 상세정보

2026-11-15 확인 자료를 기준으로 기존 지도 장소 251개에 상세정보를 추가했습니다. Android 소스와 자산은 이번 작업에서 수정하지 않았습니다.

## 사용 방법

홈 지도에서 건물 이름·동 번호·등록된 편의시설을 검색해 결과를 선택합니다. 전체 지도에서는 확대 수준 16 이상에서 건물 위치를 눌러 선택할 수 있습니다. 기존 퀘스트·분실물·식당 마커가 겹치는 지점은 해당 마커 선택을 우선합니다. 지도 배경 탭은 최대 40m 이내의 가장 가까운 등록 건물점만 고릅니다. 건물 외곽선이 아닌 공식 위치 좌표를 사용하므로 정확한 건물 선택은 검색도 이용할 수 있습니다.

기존 3단계 스와이프 시트에 건물 소개, 층별 시설, 이용 안내, 연락처, 접근성 등록 정보, 공식 출처와 확인일을 표시합니다. 시트 내용은 스크롤할 수 있으며 길찾기·전화 문의·운영기관 홈페이지를 열 수 있습니다.

## 데이터와 근거

- 기본 목록·위치 ID·좌표·좌표 출처를 유지했습니다. 901동은 현재 공식 분류가 학부생활관이므로 표시명을 ‘관악학생생활관 901동’으로 정정했습니다.
- [서울대학교 공식 건물 목록 API](https://map.snu.ac.kr/api/building.action?page=1&rows=1000)와 건물별 상세 API를 조회했습니다. 상세 경로는 `/api/building/{inst_seq}.action?convinType=Y`이며 응답은 EUC-KR입니다.
- 기존 SNU ID 249개를 각각 확인해 층별 시설 646건을 수록했습니다. 174개 장소에 시설 목록, 132개 장소에 공시 연락처가 있습니다. 공식 자료에 없는 전화·시설·시간은 만들어 넣지 않았습니다.
- 71-1동·901동은 기존 OpenStreetMap 좌표와 저작자 표시를 유지하고 공식 캠퍼스 안내도·생활관 안내를 근거로 소개를 보완했습니다.
- 건물별 원문 페이지와 추가 조사 출처는 `details.sources`에 저장했습니다. 도서관·박물관·미술관·규장각·학생회관·스포츠센터·국제처 등의 안내는 운영기관 자료로 보강했습니다.
- 공식 지도에서 공사·정전 공지가 시설로 등록된 항목은 시설 목록에서 제외했습니다. 시설의 미등록은 시설 부재를 의미하지 않습니다.
- 박물관의 2026-11-21 재개관 예정, 문화관 리모델링·증개축 안내를 확인일과 공식 공지 링크로 수록했습니다. 개관·운영시간과 연락처는 이후 변경될 수 있어 방문 전 운영기관 공지를 확인해야 합니다.
- 데이터는 앱 번들에 포함되어 상세정보 열람에 네트워크가 필요하지 않습니다. 출처·길찾기·홈페이지 링크는 사용자 선택 시 외부로 열립니다.

## 검증과 실행

Windows에서는 iOS SDK와 Xcode 시뮬레이터를 실행할 수 없습니다. 저장소의 기존 macOS GitHub Actions에서 Swift 모델 검사·iOS 시뮬레이터 빌드·네이티브 실행을 검증하고 생성된 시뮬레이터 ZIP을 Appetize에 업로드하는 경로를 사용합니다.

모델·데이터 검증:

```sh
swiftc ios/Chajajwo/CampusBuildings.swift ios/Tests/BuildingCatalogChecks/main.swift -o /tmp/building-catalog-checks
/tmp/building-catalog-checks ios/Chajajwo/Resources/campus_buildings.json
swift test
```

Debug 빌드는 `-preview-building 63 -preview-building-expanded` 실행 인자로 학생회관 상세 시트를 열어 확인할 수 있습니다. `.github/workflows/ios.yml`은 학생회관·박물관 상세 화면을 네이티브 시뮬레이터에서 실행하고 스크린샷을 보관합니다.

[Appetize iOS 업로드 안내](https://docs.appetize.io/platform/app-management/uploading-apps/ios)에 따라 iOS Simulator용 `.app` ZIP을 사용합니다. 기기용 IPA는 이 실행 경로에 해당하지 않습니다.
