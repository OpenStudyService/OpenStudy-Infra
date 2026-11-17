# Playwright E2E

GitOps 저장소에서 배포 경로와 배포된 서비스의 브라우저 동작을 검사합니다.
프론트엔드 저장소의 기존 화면 테스트와 별도로 실행합니다.

## 실행 환경

Node.js 24 또는 26, Python 3.9 이상을 사용합니다.
Playwright는 `1.65.1`로 고정하고 `package-lock.json`으로 설치합니다.
로컬 배포 경로 검사에는 Docker, Terraform `.terraform-version` 버전, OpenSSL, `htpasswd`도 필요합니다.
Ubuntu에서는 `apache2-utils` 패키지가 `htpasswd`를 제공합니다.

```sh
npm ci --ignore-scripts
npm run test:e2e:install
npm run test:e2e
```

브라우저 창을 보려면 `npm run test:e2e:headed`를 사용합니다.
결과는 `npm run test:e2e:report`로 엽니다.

## 로컬 배포 경로 검사

Playwright가 일회용 Docker 네트워크와 Nginx 컨테이너를 시작합니다.
기본 포트는 `127.0.0.1:18700`부터 `18706`까지입니다.
사용 중인 포트가 있으면 기존 서버를 재사용하지 않고 실패합니다.
필요하면 `E2E_STACK_PORT=18800 npm run test:e2e`처럼 바꿉니다.
테스트 종료와 일반적인 중단 시 생성한 컨테이너와 네트워크를 정리합니다.

실제 `nginx.conf.tftpl`을 빈 임시 Terraform 디렉터리에서 렌더링합니다.
AWS 인증, 운영 state, 업무 계정, 프론트엔드 체크아웃은 필요하지 않습니다.
Nginx의 ACME·njs 구성은 원본 상태로 구문 검사합니다.
로컬 실행에서는 ACME 인증서 발급 대신 일회용 자체 서명 인증서를 사용합니다.
이 로컬 Playwright 설정에서만 인증서 신뢰 검사를 건너뜁니다.
별도 테스트는 신뢰 설정이 없을 때 해당 인증서가 거부되는지도 확인합니다.

검사 범위는 다음과 같습니다.

- Backend 미연결, 데모 로그인, 프록시 연결의 3개 구성.
- 브라우저의 SPA 직접 접속과 실제 JavaScript 자산 로딩.
- HTTP의 HTTPS 이동, 경로·쿼리 보존, 자산 캐시와 404.
- Backend 미연결 시 JSON 503.
- 브라우저의 Secure·HttpOnly 쿠키와 CSRF 헤더 전달.
- 실제 브라우저 CORS 사전 요청의 허용·차단.
- 오류 응답의 CORS 정책과 중복 헤더 차단.
- njs·bcrypt 기반 데모 로그인 성공·실패.

정적 페이지와 API echo 서버는 배포 경로 검사용 fixture입니다.
이 검사의 통과를 실제 OpenStudy 업무 API나 AI 서비스의 완료로 간주하지 않습니다.
실제 프론트엔드·백엔드 연결은 다음 배포 주소 검사로 확인합니다.

## 실제 배포 주소 검사

`.env.e2e.example`을 Git에서 제외하는 `.env.e2e.local`로 복사합니다.
대상 주소와 전용 테스트 계정을 입력합니다.
실행 명령이 이 파일을 읽으므로 비밀번호를 명령 인자로 적을 필요가 없습니다.

```sh
cp .env.e2e.example .env.e2e.local
# .env.e2e.local의 주소와 테스트 계정을 설정합니다.
npm run test:e2e:live
```

`E2E_BASE_URL`은 명시해야 합니다. 주소를 생략하면 실행하지 않습니다.
HTTPS 인증서를 정상 검증합니다. 로컬 개발 주소만 HTTP를 허용합니다.
전체 검사는 `E2E_EMAIL`, `E2E_PASSWORD`도 필요합니다.
계정이 없으면 인증 검사를 건너뛰지 않고 실패합니다.
배포 전 API의 503 응답도 성공으로 처리하지 않습니다.

계정 없이 공개 화면과 비로그인 API만 검사하려면 실행 대상을 지정합니다.

```sh
npm run test:e2e:live -- --project=smoke
```

`smoke`는 로그인 화면, 데모·MSW 미활성, 보호 화면의 로그인 이동, CSRF 발급과 비로그인 접근 거부를 검사합니다.
`authenticated`는 화면 로그인, 세션 ID 갱신, 쿠키 속성, 새로고침 후 세션 유지, CSRF 누락 거부, 로그아웃을 검사합니다.
활성 상태이며 홈에 접근할 수 있는 전용 테스트 계정을 사용합니다.
업무 데이터의 생성·수정은 수행하지 않습니다. 테스트가 만든 세션은 종료 시 로그아웃합니다.

`E2E_REQUIRE_AI=true`이면 로그인 후 AI 카탈로그 준비 상태와 임베딩 경고 없음도 검사합니다.
이는 실제 LLM 호출 검사가 아닙니다. AI 질문이나 유료 모델 호출은 하지 않습니다.

인증 실행은 trace·스크린샷·비디오를 저장하지 않습니다.
터미널과 `test-results/live/summary.json`에는 이메일·비밀번호를 가린 결과만 기록합니다.
Playwright가 만든 로컬 실패 문맥 파일에는 화면 정보가 있을 수 있으므로 Git에서 제외합니다.
CI에는 인증 실행의 요약 JSON만 업로드합니다.

## CI

`.github/workflows/e2e.yml`은 관련 변경의 PR과 `main` push에서 로컬 Nginx 검사를 실행합니다.
이 검사는 AWS 리소스를 변경하지 않습니다.
로컬 검사 보고서와 실패 trace의 보존 기간은 7일입니다.

실제 배포 검사는 수동 `workflow_dispatch`의 `suite=live`에서만 실행합니다.
GitHub의 `e2e` Environment에 다음 값을 설정합니다.

| 종류 | 이름 | 내용 |
| --- | --- | --- |
| Variable | E2E_BASE_URL | 검증할 기존 배포 주소 |
| Variable | E2E_REQUIRE_AI | 선택 사항. `true`이면 모델 준비 상태도 검사 |
| Secret | E2E_EMAIL | 전용 테스트 계정 |
| Secret | E2E_PASSWORD | 테스트 계정 비밀번호 |

워크플로 파일을 추가하는 것과 GitHub 환경 설정·실제 배포 검증은 별도입니다.
기존 `scripts/validate.sh`는 빠른 인프라 검증을 유지합니다.
브라우저 검사는 `npm run test:e2e`로 실행합니다.

## 근거

- [Playwright webServer 설정](https://playwright.dev/docs/test-webserver)
- [Playwright 테스트 작성 원칙](https://playwright.dev/docs/best-practices)
- [Playwright GitHub Actions 구성](https://playwright.dev/docs/ci-intro)
