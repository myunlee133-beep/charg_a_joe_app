# 찾아줘 Android

iOS 앱(`ios/`)의 홈 지도와 식당 화면을 Kotlin + Jetpack Compose로 옮긴 앱입니다.

## 포함된 화면

- 홈 지도: 카카오맵, 식당·셔틀 정류장 핀, 교내순환 실시간 추정 위치, 내 위치·나침반, 확대/축소
- 검색: 건물(동 번호·이름)과 편의시설 검색, 건물 카드, 편의시설 둘러보기
- 건물 상세 시트: 홈·시설정보·식당·카페·이용안내 탭, 층별 시설, 연구실, 카페 메뉴, 할 일·방문 알림, 시간표·공강 추천, 일정 동선
- 길찾기: 앱 안의 카카오맵 웹 길찾기(외부 앱 이동 차단), 건물 간 길찾기
- 식당 탭: 날짜·끼니별 식단, 검색, 운영 중·즐겨찾기·가격 필터, 교내 카페 목록

AR 보물찾기·도감은 다음 단계에서 연결합니다(지금은 상단 버튼과 지도 여우를 누르면 안내 문구가 나옵니다).

## 카카오맵 키 설정

안드로이드 전용 카카오 앱 키(`app/build.gradle.kts`의 `KAKAO_APP_KEY`)를 씁니다. 카카오 개발자 콘솔의 그 앱에 Android 플랫폼을 등록해야 지도가 열립니다.

- 패키지명: `org.chargajoe.chajajwo`
- 키 해시: `15Nt2C7JekJYJvK5nXUHUfyqRZw=` (저장소에 포함된 `app/debug.keystore` 기준)

등록하지 않으면 지도 영역이 빈 화면으로 남고, 로그에 `MapAuthException(401)`이 찍힙니다.
`debug.keystore`는 CI 빌드마다 키 해시가 바뀌지 않게 하려고 넣어 둔 공용 디버그 키이며 스토어 배포용이 아닙니다.

## 빌드

```bash
cd android
./gradlew assembleDebug
```

GitHub Actions(`.github/workflows/android.yml`)가 `android-port` 브랜치에 push할 때마다 APK를 빌드해
`Chajajwo-android-apk` 아티팩트로 올리고, 에뮬레이터에서 주요 화면을 캡처합니다.
카카오맵 SDK는 ARM 네이티브 라이브러리만 제공하므로 APK는 `arm64-v8a`, `armeabi-v7a`만 포함합니다.
