# 기능별 브랜치

원본 저장소 `myunlee133-beep/charg_a_joe_app`의 collaborator 권한으로 아래 브랜치에 직접 작업한다.

| 기능 | 브랜치 | 변경 범위 |
| --- | --- | --- |
| 퀘스트 | [`codex/quest`](https://github.com/myunlee133-beep/charg_a_joe_app/tree/codex/quest) | 전용 탭, 배율별 지도 표시, 군집·선택, 식당 마커와의 겹침 방지 |
| 셔틀 | [`codex/shuttle`](https://github.com/myunlee133-beep/charg_a_joe_app/tree/codex/shuttle) | 위치 보간, 연속 프레임 갱신, 조회 간격, 셔틀 회귀 테스트 |

두 기능은 `main`을 기준으로 독립적으로 검토·병합한다. 이후 변경은 해당 기능 브랜치의 PR에 커밋하고, 다른 기능의 변경을 함께 넣지 않는다. 공통 파일을 수정하는 경우에도 해당 기능에 필요한 변경만 포함한다.

`codex/quest-tab-smooth-shuttle`와 PR #9는 두 기능을 함께 검증한 이전 기록이다. 새 검토와 후속 작업은 위 기능별 브랜치를 사용한다. 기존 Appetize 통합 시연 빌드의 출처를 추적할 수 있도록 이전 브랜치를 보존한다.
