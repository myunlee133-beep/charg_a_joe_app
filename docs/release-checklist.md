# 앱스토어 출시 체크리스트

코드에서 처리한 항목과 사람이 직접 해야 하는 항목을 나눕니다.

## 코드에서 처리됨
- [x] 계정·사용자 작성 콘텐츠 기능 제거(커뮤니티, 분실물, 퀘스트) — 가이드라인 1.2, 5.1.1(v) 해당 없음
- [x] 시연용 퀘스트·보관 거점 예시 데이터 제거 — 2.1 완성도
- [x] Supabase URL·키 제거
- [x] `PrivacyInfo.xcprivacy` 추가(UserDefaults `CA92.1`, 부팅 시간 `35F9.1`, 추적 없음, 수집 데이터 없음)
- [x] `ITSAppUsesNonExemptEncryption = false`(HTTPS 표준 암호화만 사용)
- [x] 위치 권한은 사용 중에만(`NSLocationWhenInUseUsageDescription`)

## 직접 해야 함
1. **Xcode에서 빌드 확인** — 이 브랜치는 Swift 컴파일러가 없는 환경에서 정리했습니다. GitHub Actions의 `iOS and campus core` 결과와 실기기 빌드를 확인하세요.
2. **Apple Developer Program** 가입과 `DEVELOPMENT_TEAM`(현재 `UZ3883JFZS`) 확인, App Store Connect에서 앱 생성(번들 ID `org.chargajoe.chajajwo`).
3. **카카오 개발자 콘솔**에서 iOS 번들 ID 등록. 앱 키 제한과 호출 한도 확인.
4. **Kakao Maps SDK의 privacy manifest** 포함 여부 확인(Archive 후 Privacy Report). 없거나 SDK가 데이터를 수집하면 `NSPrivacyCollectedDataTypes`와 App Privacy 항목을 맞게 고치세요.
5. **개인정보 처리방침 URL** 준비(위치 정보는 기기에서만 쓰고 서버로 보내지 않는다는 내용, 카카오맵 SDK 고지 포함).
6. **App Privacy 항목** 작성. 앱은 위치를 서버로 전송하지 않지만 SDK 동작은 4번 결과를 따릅니다.
7. **스크린샷**(6.7"·6.1" iPhone), 앱 설명, 키워드, 지원 URL, 연령 등급.
8. **심사 메모**(App Review Notes)에 적을 것
   - 교내순환 셔틀은 운행 시간에만 차량 위치가 표시됩니다. 운행 시간 외에는 "제공된 차량 위치가 없어요"가 나오며 정상입니다.
   - 위치는 노선도 좌표를 보정한 추정치라고 앱 안에 표시합니다.
   - 서울대학교 공식 앱이 아닙니다(공식으로 오인될 문구를 쓰지 마세요, 가이드라인 5.2.1).
   - 가능하면 운행 중 화면 녹화를 첨부하세요.
9. **TestFlight**에서 실기기 확인: 위치 권한 허용·거부, 비행기 모드(식단 번들 폴백), 셔틀 운행 시간 안팎.
10. 식단·셔틀 서버(`raw.githubusercontent.com`, `chajajwo-web-mu.vercel.app`)가 내려가도 앱이 정상 동작하는지 확인. 셔틀에는 오프라인 폴백이 없고 안내 문구만 나옵니다.
