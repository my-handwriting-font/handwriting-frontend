# 손글씨 폰트 생성 서비스 — 프론트엔드 (Flutter 웹)

> 졸업작품 「자모 단위 필기 획 합성 기반 개인 맞춤형 한글 폰트 생성 응용 프로그램 구현」의 웹 클라이언트

iPad Safari에서 스타일러스 펜으로 자음 14자·모음 12자를 쓰면, 서버가 검증한 뒤 현대 한글 11,172자를 담은 나만의 TTF 폰트를 만들어 줍니다.

## 관련 저장소

| 구성 | 역할 |
| --- | --- |
| **프론트엔드 (Flutter 웹)** | 손글씨 캔버스, 회원 화면, 폰트 만들기·다운로드 화면 (이 저장소) |
| 백엔드 (Spring Boot) | 회원·자모·폰트 관리 REST API |
| AI·폰트 서버 (FastAPI) | CNN 자모 검증, 11,172자 음절 배치, TTF 생성 |

## 기술 스택

- Flutter (Dart), 웹 빌드
- 대상 기기: iPad Air 13형 + Safari + 스타일러스 펜

## 주요 기능

- **회원가입·로그인·탈퇴**: 이메일 인증번호 타이머, 인증 완료 후 가입 버튼 활성화
- **손글씨 캔버스**: 펜이 닿은 순간부터 떨어질 때까지를 한 획으로 모으고, 점마다 x·y 좌표와 필압을 기록합니다. 화면에는 2차 베지에 곡선으로 부드럽게 그립니다.
- **자모 검증**: '검증하고 추가'를 누르면 서버에서 CNN 분류와 코사인 유사도로 검증합니다. 실패하면 인식된 자모와 유사도를 보여 줍니다.
- **자모 저장**: 26자가 모두 통과해야 저장 버튼이 활성화되고, 저장하지 않고 나가려 하면 확인 창을 띄웁니다.
- **폰트 만들기**: 폰트 이름과 획 두께를 정해 TTF를 생성합니다.
- **내 폰트**: 홈 화면에서 만든 폰트 목록을 보고 TTF 파일을 내려받습니다.

## 화면

| 화면 | 파일 |
| --- | --- |
| 홈 (폰트 만들기 시작, 내 폰트 목록) | `screens/home_screen.dart` |
| 로그인 / 회원가입 | `screens/login_screen.dart`, `screens/signup_screen.dart` |
| 폰트 만들기 (자모 입력·검증·생성) | `screens/font_maker_screen.dart` |

`screens/` 안의 `*_test_screen.dart`는 음절 배치 규칙을 정할 때 쓴 실험용 화면입니다.

## 폴더 구조

```
lib/
├── core/       # 서버 주소(api_config.dart), 로그인 세션
├── http/       # Spring Boot·FastAPI 호출
├── models/     # 획·점 데이터 모델
├── screens/    # 화면
├── services/   # 좌표 정규화, 음절 배치 실험용 로직
├── utils/      # 웹 파일 다운로드
└── widgets/    # 손글씨 캔버스
```

## 실행 방법

### 1. 서버 주소 설정

`lib/core/api_config.dart`에서 서버가 실행되는 PC의 IP를 바꿉니다.

```dart
static const String host = '{서버 PC의 IP}';
```

Spring Boot 서버는 `8080`, FastAPI 서버는 `8000`번 포트를 사용합니다.

### 2. 실행

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000
```

같은 와이파이에 연결된 iPad의 Safari에서 `http://{서버 PC의 IP}:3000`으로 접속합니다.
