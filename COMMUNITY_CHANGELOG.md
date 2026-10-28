# 사랑방 MVP 변경사항

## 이번에 추가한 기능

- **탭:** 기존 지도/식당/분실물 기능을 유지하고 `사랑방`을 다섯 번째 탭으로 추가.
- **회원:** Supabase 이메일·비밀번호 인증, 닉네임, 키체인 세션, 계정 삭제.
- **게시판:** 자유 이야기/질문·답변/선의, 태그 검색, 30개 단위 페이지 읽기.
- **글/댓글:** 작성할 때마다 `익명` 또는 `닉네임` 선택, 삭제.
- **참여:** 추천, 스크랩, 게시물·댓글 신고, 작성자 차단 및 해제.
- **선의:** 정보 종류·출처·유효기간, 운영진 검증/반려, 인정된 기여 이력 기록.
- **운영진:** 승인 대기·신고 처리 화면, RBAC는 서버에서 검사.

## GitHub에 필요한 변경사항

수정: `ios/Chajajwo/ChajajwoApp.swift`, `Store.swift`, `Info.plist`, `ios/project.yml`, `ios/Chajajwo.xcodeproj/project.pbxproj`.

추가: `ios/Chajajwo/CommunityAPI.swift`, `CommunityView.swift`, `CommunityRules.swift`, `backend/community/001_community_mvp.sql`, `backend/community/README.md`.

## 필수 연결 작업

1. Supabase 프로젝트 생성 및 `backend/community/001_community_mvp.sql` 실행
2. Xcode에 Supabase URL과 공개키 설정. `service_role` 키는 앱에 넣지 않음.
3. 이메일/비밀번호 회원가입 및 로그인, 운영진 지정 후 실제 iPhone에서 UI·권한·공유 테스트

**미구현:** 대학/학교 인증, PDF 업로드, 보상 지급, 전국 범위 분류, 실시간 채팅, 콘텐츠 자동 심사.

## 테스트 범위

Swift 구문과 계산 유닛 테스트, 프로젝트 파일·Plist 검증, 변경 파일/ZIP 무결성 등 오프라인 검사까지 수행. Xcode 및 Supabase 실서버가 없는 Linux 환경에서는 iOS 빌드와 실제 다중 계정 연동 테스트를 수행하지 못함.
