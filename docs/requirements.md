# 요구조건과 검증 상태

[README로 돌아가기](../README.md)

## 현재 범위

Terraform으로 AWS와 SSM 서버 설정을 관리한다.
DuckDNS는 EC2 공인 IP를 자동 반영한다. Cloudflare는 수동 설정한다.
필요할 때 생성하고 사용 후 AWS 리소스와 저장 데이터를 모두 삭제한다.

| ID | 구성 | 상태 |
| --- | --- | --- |
| INF-NET-01 | `openstudy.duckdns.org`에 EC2 공인 IP 자동 반영 | 삭제 전 DNS와 EC2 공인 IP 일치 확인 |
| INF-NET-02 | 정적 웹 HTTPS·Backend API 원본 TLS | DuckDNS·EC2 HTTPS 게시·접속 확인 완료, Backend API 연결 후속 |
| INF-NET-03 | cloudflared 설치와 수동 Tunnel 연결 | 서버 코드 준비·연결 전 |
| INF-NET-04 | Cloudflare WAF·요청 제한 | 연결 조건 확인 필요 |
| INF-NET-05 | 기본 인바운드 차단·선택한 80·443 허용·Session Manager | 코드·모의 테스트 완료 |
| INF-SRV-01 | `t4g.small`·gp3 8GiB | 생성·전체 삭제 검증 완료·계정 혜택 별도 확인 |
| INF-SRV-02 | Docker·스왑 1GiB | 삭제 전 SSM 설정 성공·컨테이너 배포 전 |
| INF-SRV-03 | 보안 업데이트·Asia/Seoul·시간 동기화 | SSM 설정 성공·재부팅 검증 남음 |

DNS는 사용자 요청에 따라 DuckDNS로 구성한다. 관리 접속은 SSH 대신 Session Manager를 사용한다.
INF-NET-04와 INF-SRV-03은 [원문 명세](https://docs.google.com/document/d/1RMxQHpqLZzPtN-OPuPSDGE3THKxtgHXNu4XbcZmbFSA/edit?tab=t.0)의 권장 항목이다.

## 추가 배포 범위

[Frontend](https://github.com/OpenStudyService/OpenStudy-Frontend)의 React·Vite 정적 빌드는 기본으로 DuckDNS·EC2 Caddy로 제공한다. S3·CloudFront는 별도 선택 경로다.
[Backend](https://github.com/OpenStudyService/OpenStudy-Backend)는 GitHub Actions에서 ARM64 OCI 이미지를 빌드해 ECR에 저장하고 EC2에서 실행하도록 설계한다.
Frontend의 S3·CloudFront·OIDC 역할과 Actions 워크플로 코드를 추가했다.
`terraform/frontend apply`는 기본으로 로컬 Frontend 검사·live 빌드·S3 게시·CloudFront 확인까지 실행한다.
Actions로만 게시할 때는 `deploy_frontend = false`를 설정한다.
실제 생성·배포와 Backend 연결은 [Frontend 배포 순서](frontend-deployment.md)를 따른다.
Backend ECR·OCI 배포 워크플로는 아직 구현하지 않았다.
구현 순서는 [배포 설계](deployment.md)를 따른다.

## 로컬 검증

Terraform 버전은 1.16.6으로 고정한다.
2026-10-19에 AWS 모의 테스트 8개, 이전 Cloudflare 예제 테스트 5개와 Python 테스트 9개를 통과했다.
Frontend Terraform 모의 테스트 5개와 SPA 경로 테스트 3개도 통과했다.
Frontend 저장소의 검사·live 빌드와 배포 절차 테스트 3개를 통과했다. 당시 실제 AWS 정적 웹 배포는 실행 전이었다.
ARM·x86 초기 설정의 Bash·Python 구문과 user data 크기 검사도 통과했다.
SSM 설정 전달과 설치 버전 변경 시 기존 EC2 보존도 검사했다.
모의 테스트 통과는 실제 배포 성공을 뜻하지 않는다.

2026-10-19에 Terraform 적용으로 SSM 문서·실행 연결·IAM 정책을 추가했다.
기존 EC2를 유지했고, SSM 실행의 `Success` 상태와 종료 코드 0을 확인했다.
DuckDNS의 A 레코드와 EC2 공인 IPv4가 일치하는 것도 확인했다.

같은 날 사용 종료 후 Terraform 관리 리소스 15개를 삭제했다.
`terraform/aws` state에는 관리 리소스가 없다.
EC2 루트 EBS와 별도 등록한 DuckDNS 토큰도 삭제했다.
사용 가능한 AWS 리전 17개를 확인했다.
당시 S3 버킷, RDS·Aurora, DynamoDB, EBS와 관련 스냅샷·백업은 남아 있지 않았다.

이후 `terraform/frontend`로 S3·CloudFront·OIDC 배포 역할 등 12개 리소스를 생성했다.
Terraform 1.10.0으로 실제 AWS를 다시 조회했고 `No changes`를 확인했다.
CloudFront의 `Deployed` 상태와 S3 객체 0개를 확인했다.
이후 사용자 요청으로 Frontend 리소스 12개를 모두 삭제했다.
AWS API에서도 S3·CloudFront 구성·IAM 배포 역할·OIDC Provider 삭제를 확인했다.
당시 `terraform/aws`와 `terraform/frontend` state의 관리 리소스는 모두 0개였다.
로컬 Frontend 배포는 Node.js 24·npm·AWS CLI와 로컬 소스를 준비한 뒤 인프라를 적용한다.
Actions 배포를 선택할 때만 PR #2 병합과 새 Actions 변수 등록이 필요하다.

2026-10-20에 로컬 Frontend 게시를 Terraform 적용에 연결했다.
Frontend Terraform 모의 테스트 8개와 로컬 게시 테스트 9개를 통과했다.
Node.js 24에서 Frontend 타입 검사·린트·테스트 29개·live 빌드를 통과했다.
기존 게시 스크립트의 모의 테스트 3개도 통과했다.

같은 날 Terraform 1.10.0과 Node.js 24.19.0으로 실제 AWS 배포를 완료했다.
AWS 리소스 12개와 로컬 게시 항목 1개를 생성했다. S3에는 정적 파일 11개를 게시했다.
CloudFront 배포 `EHC94BW0NZ1HF`의 `Deployed` 상태와 캐시 갱신 완료를 확인했다.
`/`, `/login`, `/invitations/accept`의 HTML과 진입 JavaScript·CSS가 로컬 빌드와 일치한다.
배포 당시 `d14goo9a4tr1w0.cloudfront.net`에서 로그인 화면도 확인했다.
적용 후 Terraform 재검사 결과는 `No changes`다. `terraform/aws`의 관리 리소스는 계속 0개다.
Backend는 연결하지 않았다. 당시 `/api/me`는 JSON 503을 반환했다.

이후 같은 날 사용자 요청으로 Terraform 삭제 계획을 적용했다.
AWS 리소스 12개와 로컬 게시 항목 1개를 모두 삭제했다. S3 정적 파일 11개도 함께 삭제했다.
AWS API에서 버킷·CloudFront 배포·OAC·SPA 함수·캐시 정책·IAM 역할·OIDC Provider 삭제를 확인했다.
삭제 직후 `terraform/frontend`와 `terraform/aws`의 관리 리소스는 모두 0개였다.
두 경로의 삭제 계획은 모두 `No changes`를 반환했다. 서비스 주소는 종료했다.
코드와 로컬 state·변수 파일은 보관한다.

2026-10-21에 DuckDNS 접속 주소로 정적 웹을 다시 배포했다.
`terraform/aws`에서 EC2·Caddy HTTPS·비공개 S3 배포 파일과 게시 단계를 포함한 21개 항목을 관리했다.
`terraform/frontend`의 S3·CloudFront 경로는 계속 삭제 상태다.
당시 DuckDNS A 레코드와 EC2 공인 IP `43.203.123.190`이 일치하는 것을 확인했다.
`/`, `/login`, `/invitations/accept`와 진입 JavaScript·CSS가 실제 빌드와 일치하는 것을 확인했다.
HTTP의 HTTPS 이동, 없는 정적 파일의 404와 미연결 API의 JSON 503도 확인했다.
최초 SSM 실행 완료 전에 게시가 시작되는 문제는 해당 EC2의 실제 설정 실행 성공을 기다리도록 수정했다.
토큰은 Parameter Store SecureString에 저장했다. Terraform state에는 토큰 값을 넣지 않는다.

이후 같은 날 사용자 요청으로 Terraform 관리 항목 21개를 모두 삭제했다.
AWS API에서 EC2 종료와 루트 EBS·S3 버킷·네트워크·IAM·SSM 구성 삭제를 확인했다.
해당 루트 EBS의 스냅샷도 남아 있지 않다.
DuckDNS A·AAAA 기록을 비웠고 AWS에 저장한 프로젝트 토큰도 삭제했다.
`terraform/aws`와 `terraform/frontend`의 관리 리소스는 모두 0개다.
두 경로의 삭제 계획은 모두 `No changes`를 반환했다. 현재 웹 서비스는 중지 상태다.

2026-10-21에 배포 변경을 정리하면서 로컬 검증을 다시 실행했다.
Terraform 모의 테스트 25개, Node.js 테스트 12개와 Python 테스트 20개를 통과했다.
ARM·x86 서버 설정은 정적 웹 활성화·비활성화 조합 4개에서 구문과 크기 검사를 통과했다.
이 검증에서는 실제 AWS 리소스를 생성하거나 변경하지 않았다.

같은 날 실행 버전과 현재 문서를 최신화했다.
Terraform CLI를 1.16.6, Cloudflare 공급자를 5.28.1, cloudflared를 2026.10.2로 갱신했다.
AWS 공급자 6.69.1과 Caddy 2.11.7-alpine은 유지했다.
cloudflared 2026.10.1에서 2026.10.2로 설정을 바꿀 때 기존 EC2를 유지하는 모의 테스트도 통과했다.
새 버전에서 Terraform 모의 테스트 25개, Node.js 테스트 12개, Python 테스트 20개와 서버 설정 조합 4개의 구문·크기 검사를 통과했다.
실제 AWS 조회 계획은 `terraform/aws` 생성 21개와 `terraform/frontend` 생성 13개다. 두 계획 모두 수정·삭제는 0개다.
게시 작업을 포함한 리소스 주소와 작업 종류는 갱신 전 계획과 같다.
계획은 각 Terraform 버전으로 읽어 비교했다. 이전 버전의 계획 파일은 적용하지 않는다.
기본 DuckDNS·EC2 아키텍처의 HTML·SVG·PNG·draw.io 파일을 추가했다. 기존 CloudFront 그림은 선택 경로로 보존했다.
그림의 글자 잘림·모바일 스크롤·문서 링크를 확인했다. 이 검증에서는 AWS 적용을 실행하지 않았다.

```sh
./scripts/validate.sh
```

## 다음 순서

1. Frontend를 수정할 때 [DuckDNS 배포 순서](duckdns-frontend.md)에 따라 `terraform/aws`의 새 계획을 만들고 다시 게시한다.
2. Backend를 배포할 때 [구축 절차](setup.md)로 EC2·DuckDNS를 재생성한다. OCI·ECR 배포는 후속 구현한다.
3. `/api/*` 원본 HTTPS·세션·CSRF·SSE와 외부 포트 차단을 확인한다.
4. [Cloudflare 연결 조건](cloudflare-manual.md)을 확인하고 수동 설정한다.
5. [GitOps 자동 배포](gitops.md)를 구현한다.
6. 사용을 마치면 [AWS 전체 정리](teardown.md)로 리소스와 저장 데이터를 삭제한다.
