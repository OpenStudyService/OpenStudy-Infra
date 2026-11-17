# 2026-11-17 Playwright E2E 구성

## 배경과 범위

사용자가 Playwright와 E2E 구성을 요청했습니다.
현재 GitOps 저장소에 배포 검증용 테스트를 추가했습니다.
작업 브랜치는 `test/2-playwright-e2e`입니다. 기준은 `origin/main`의 `05a5ed9`입니다.
기존 AI 배포 준비 PR #10과 별도 작업입니다.
프론트엔드 저장소에는 Playwright가 이미 있어 해당 코드는 수정하지 않았습니다.

## 결정

로컬 배포 경로와 실제 배포 서비스의 실행 설정을 나눴습니다.
로컬 검사는 저장소의 실제 Nginx 템플릿과 이미지를 사용합니다.
정적 fixture와 echo upstream은 전용 테스트 데이터입니다.
이 검사로 실제 업무 API가 동작한다고 판단하지 않습니다.
실제 서비스 검사는 배포 주소를 명시한 경우에만 실행합니다.

## 구현

- Playwright `1.65.1`, Chromium, npm lockfile을 추가했습니다.
- `npm run test:e2e`가 일회용 Nginx 스택을 시작하고 종료 시 정리합니다.
- 원본 ACME·njs 구성은 구문 검사합니다. 로컬 요청에는 자체 서명 인증서를 사용합니다.
- SPA 경로, 자산 캐시·404, HTTPS 이동, JSON 503, 쿠키·CSRF 전달, CORS, 데모 로그인 등을 검사합니다.
- `npm run test:e2e:live`는 실제 로그인 화면, 인증 API, 세션 유지, 로그아웃을 검사합니다.
- 선택 설정 `E2E_REQUIRE_AI=true`는 AI 카탈로그와 임베딩 모델 준비 상태를 확인합니다. LLM은 호출하지 않습니다.
- 실제 서비스 검사에는 API mock과 TLS 검증 우회를 넣지 않았습니다.
- 인증 실행의 trace·스크린샷·비디오는 끕니다. 이메일·비밀번호를 가린 요약만 CI에 게시하도록 구성했습니다.
- GitHub Actions는 관련 PR·main push에서 로컬 검사를 실행합니다. 실제 서비스 검사는 `e2e` Environment를 쓰는 수동 실행입니다.
- 설정과 실행 방법은 [E2E 안내](../e2e.md)에 기록했습니다.

## 검증 결과

macOS ARM64, Node.js `26.12.1`, Docker `29.9.2`, Terraform `1.16.6`, Chromium에서 확인했습니다.

- 로컬 Playwright E2E: **12개 통과**, 건너뜀 없음.
- 인증 보고서 검사: 원문·이스케이프·URL 인코딩 자격증명 제거와 목록 조회의 결과 오기록 방지 **2개 통과**.
- 기존 Node 배포·라우팅 테스트: **12개 통과**.
- `actionlint 1.7.12`: GitHub Actions 워크플로 검사 통과.
- 배포 서비스 검사 **4개를 발견**했습니다. 배포 주소 누락 시 실행 전 실패하는 조건을 확인했습니다.
- Python 구문, npm lockfile 일치, YAML 구문, Git diff 공백 검사를 통과했습니다.
- 테스트 종료 후 `openstudy-e2e-*` 컨테이너와 네트워크가 남지 않았습니다.

첫 실행에서 fixture의 CORS 출처와 Docker Desktop의 `host.docker.internal` 처리를 수정했습니다.
읽기 전용 upstream의 임시 파일 경로를 `/tmp`로 지정했습니다.
포트 연결만으로 준비 완료를 판단하지 않도록 실제 HTTPS 200 응답을 확인합니다.

## 실행하지 않은 범위

실제 배포 주소·테스트 계정이 설정되지 않아 로그인·세션 서비스 E2E는 실행하지 않았습니다.
위 로컬 검증 시점에는 GitHub Actions를 실행하지 않았습니다. PR의 CI 결과로 별도 확인합니다.
`e2e` Environment·비밀값 등록은 수행하지 않았습니다.
AWS 리소스 변경, 업무 데이터 변경, 실제 Qwen 호출은 수행하지 않았습니다.
구성 완료와 실제 운영 환경 검증 완료를 구분합니다.
