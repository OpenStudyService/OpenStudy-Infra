# Terraform IaC 통합 배포 아키텍처

[README로 돌아가기](../README.md)

Terraform의 생성·설정·삭제와 애플리케이션의 빌드·게시·접속을 한 흐름으로 정리한다.
Terraform은 인프라를 관리한다. Frontend의 기본 적용은 로컬 검사·빌드·정적 파일 게시까지 실행한다.
GitHub Actions를 통한 Frontend 게시도 선택할 수 있다. Backend OCI 자동화는 후속 작업이다.
**2026-10-21에 사용자 요청으로 DuckDNS 정적 웹과 관련 인프라를 전체 삭제했다. 현재 웹 서비스는 중지 상태다.**
DuckDNS 배포 경로는 DuckDNS → EC2 Caddy → 정적 파일이다. 배포 압축 파일은 비공개 S3로 전달한다.
실행 절차는 [DuckDNS 정적 웹 배포](duckdns-frontend.md)를 따른다.
기본 DuckDNS 경로와 선택 S3·CloudFront 경로는 별도 그림으로 표시한다.

## 1. 통합 아키텍처

### 기본 경로: DuckDNS·EC2

![DuckDNS·EC2 정적 웹 배포 아키텍처](images/openstudy-duckdns-deployment-numbered.png)

[draw.io 편집 파일](images/openstudy-duckdns-deployment-numbered.drawio) · [SVG 미리보기](images/openstudy-duckdns-deployment-numbered.svg) · [HTML 미리보기](images/openstudy-duckdns-deployment-numbered.html)

Terraform이 EC2·네트워크·IAM·SSM·배포용 S3를 생성한다.
검사·live 빌드 후 압축 파일을 S3에 올리고 SSM으로 EC2에 게시한다.
브라우저는 DuckDNS에서 IP를 조회한 뒤 EC2의 Caddy에 HTTPS로 접속한다.
S3는 압축 파일 전달에만 사용한다. 브라우저는 S3에서 정적 파일을 받지 않는다.

### 선택 경로: S3·CloudFront

![S3·CloudFront 선택 경로와 후속 Backend 배포](images/openstudy-terraform-deployment-numbered.png)

[draw.io 편집 파일](images/openstudy-terraform-deployment-numbered.drawio) · [SVG 미리보기](images/openstudy-terraform-deployment-numbered.svg) · [HTML 미리보기](images/openstudy-terraform-deployment-numbered.html)

draw.io에서 **파일 → 열기 → 기기**를 선택해 `.drawio` 파일을 연다.
아이콘·영역·연결선·번호를 각각 편집할 수 있다. 번호는 20px로 작게 표시한다.

실선은 코드가 있는 경로다. 긴 점선은 후속 연결이다. 짧은 점선은 Terraform·SSM 제어다.
표기는 코드 기준이다. 현재 동작 중인 서비스를 뜻하지 않는다. 기존 구성요소 번호를 유지한다.
선택 경로 그림의 Frontend 게시는 Actions 기준이다. 로컬 게시에서는 Terraform 실행 환경이 같은 S3·CloudFront 작업을 수행한다.

| 번호 | AWS 서비스·구성 요소와 설명 |
| --- | --- |
| 01 | Terraform — 1.16.6으로 plan·apply·destroy를 실행한다. Frontend apply는 기본으로 로컬 정적 파일도 게시한다. |
| 02 | AWS Region — 서울 리전(ap-northeast-2)이다. CloudFront와 IAM은 전역 서비스다. |
| 03·04 | Amazon VPC·Public Subnet — 10.42.0.0/16 VPC 안에 10.42.1.0/24 퍼블릭 서브넷을 구성한다. |
| 05·06 | Amazon EC2·Amazon EBS — t4g.small과 암호화 gp3 8GiB다. 기본 경로의 정적 파일과 Caddy 인증서를 저장한다. Backend 컨테이너 배포는 후속 작업이다. |
| 07·08 | AWS Systems Manager·Parameter Store — SSM이 서버 설정을 적용한다. 토큰 값은 별도 SecureString으로 등록한다. |
| 11 | Amazon S3 — 기본 경로는 비공개 배포 압축 파일 버킷이다. 선택 경로는 Frontend dist/를 저장하고 CloudFront OAC만 읽도록 허용하는 별도 버킷이다. |
| 12 | Amazon CloudFront — HTTPS와 SPA 경로 처리를 제공한다. API 원본은 Backend 준비 후 선택적으로 연결한다. |
| 13 | Amazon ECR — Backend ARM64 OCI 이미지의 SHA 태그와 digest를 저장할 후속 구성이다. |
| 14 | GitHub Actions — Frontend 검사·빌드·게시 코드는 PR #2에 있다. Backend OCI 자동화는 미구현이다. |
| 15 | AWS IAM·AWS STS — Frontend main만 OIDC 배포 역할을 사용한다. STS가 단기 자격 증명을 발급한다. |
| 16 | 사용자 브라우저 — 기본 경로는 DuckDNS HTTPS 주소를 사용한다. 선택 경로는 CloudFront HTTPS 주소를 사용한다. |
| 17 | DuckDNS — EC2가 갱신한 공인 IPv4를 DNS 응답으로 반환한다. |
| 18 | Caddy — EC2 컨테이너에서 HTTPS와 정적 파일을 제공한다. 현재 API는 JSON 503을 반환한다. |

아이콘은 [AWS 공식 아키텍처 아이콘](https://aws.amazon.com/architecture/icons/), [GitHub 공식 로고](https://brand.github.com/foundations/logo), [HashiCorp Terraform 공식 로고](https://www.hashicorp.com/en/brand/hcp-product-logos)를 사용한다.
03·04는 단일 퍼블릭 서브넷을 사용하는 VPC 영역으로 묶었다. 05·06과 07·08은 같은 관리 범위로 묶었다.

## 2. Terraform 관리 범위

| Terraform 경로 | 관리 범위 | 현재 상태 |
| --- | --- | --- |
| terraform/frontend | 11·12·15, OAC·SPA 함수·캐시 정책·배포 역할·프로젝트 OIDC·로컬 정적 파일 게시 | 실제 생성·게시·전체 삭제 검증 완료. 현재 state 0개. |
| terraform/aws | 02~08, Internet Gateway·라우팅·보안 그룹·SSM 실행 연결·DuckDNS HTTPS 정적 웹·비공개 S3 배포 파일 | 실제 게시·접속 후 21개 관리 항목 전체 삭제 검증 완료. 현재 state 0개. |
| Backend ECR·배포 IaC | 13, ECR push 역할·EC2 pull 권한·배포 설정 | 미구현. 후속으로 Terraform에 추가한다. |

토큰 값은 Terraform state에 저장하지 않는다. Parameter Store SecureString에 별도로 등록한다.
Cloudflare는 선택적 수동 연결이다. 현재 Terraform 적용 범위에 포함하지 않는다.
DB 운영 배치와 ECR IaC는 후속 작업이다. 별도 생성한 리소스도 전체 삭제 범위에 포함한다.

## 3. 생성부터 삭제까지

### 기본 DuckDNS 경로

1. Terraform 1.16.6, Node.js 24, npm, Python, AWS CLI와 로컬 Frontend를 준비한다.
2. DuckDNS 토큰을 Parameter Store에 다시 등록한다. `enable_frontend = true`와 공개 80·443 설정을 확인한다.
3. `terraform/aws`의 새 계획을 확인하고 적용한다. EC2·Caddy·비공개 배포용 S3와 SSM 게시를 구성한다.
4. Terraform이 실제 서버 설정 성공을 기다린 뒤 검사·live 빌드와 자동 게시를 실행한다.
5. DuckDNS HTTPS의 HTML과 정적 파일을 확인한다. Backend API 연결은 후속 작업이다.
6. 사용 후 `terraform/aws`를 삭제한다. DuckDNS IP 기록과 별도 저장한 프로젝트 토큰도 정리한다.

명령과 재실행 방법은 [DuckDNS 정적 웹 배포](duckdns-frontend.md)를 따른다.

### 선택 S3·CloudFront 경로

1. Terraform 1.16.6과 AWS 계정을 확인한다. 기존 변수·state 파일을 보관하고 필요한 값만 수정한다.
2. Node.js 24·npm·AWS CLI와 로컬 Frontend를 준비한다. terraform/frontend의 plan을 확인하고 apply한다.
3. Terraform이 S3·CloudFront를 생성한 뒤 로컬 소스를 검사·live 빌드한다. 해시 파일·index.html을 S3에 게시한다.
4. CloudFront 캐시 갱신 완료 후 /와 /login의 HTML을 확인한다. 여기까지가 S3·CloudFront 배포다.
5. Actions를 선택하면 deploy_frontend = false로 설정한다. Frontend PR #2 병합과 Actions 변수 등록 후 main으로 워크플로를 실행한다.
6. Backend는 terraform/aws로 EC2를 준비한다. ECR·OCI 빌드·digest 배포와 EC2 pull은 후속 구현한다.
7. Backend HTTPS 원본을 준비한 뒤 /api와 /api/*를 연결한다. 세션·CSRF·SSE를 통합 검증한다.
8. 사용 후 자동 게시를 중지한다. frontend와 aws를 각각 destroy하고 S3·ECR·DB·백업·프로젝트 토큰의 잔여를 확인한다.

생성·삭제 명령은 같은 Terraform **1.16.6**으로 실행한다.
버전·변수·Frontend 소스를 변경하면 계획 파일을 다시 만든다.
Frontend는 [자동 배포 순서](frontend-deployment.md), EC2는 [구축 순서](setup.md), 전체 삭제는 [정리 순서](teardown.md)를 따른다.

## 4. 네트워크·배포 연결

| 관련 번호 | 연결·역할 | 통신과 구현 상태 |
| --- | --- | --- |
| 01→AWS | 인프라 생성·삭제 | AWS API HTTPS 443. frontend와 aws의 state는 분리한다. |
| 01→11·12 | 로컬 Frontend 게시·확인 | 기본 apply가 S3 게시·캐시 갱신·HTML 확인을 실행한다. 실행 환경의 AWS 인증을 사용한다. |
| 01→07 | SSM 문서·실행 연결 | HTTPS 443. 서버 설정 변경은 SSM으로 적용한다. |
| 07·08→05 | 서버 설정·토큰 조회 | 논리적 적용 방향이다. 실제 SSM·토큰 조회는 EC2의 아웃바운드 443을 사용한다. |
| 14→15 | GitHub OIDC 인증 | HTTPS 443. 원본 저장소와 refs/heads/main으로 제한한다. |
| 14→11 | Frontend 정적 파일 게시 | HTTPS 443. 해시 파일을 먼저, index.html을 마지막에 게시한다. |
| 14→12 | CloudFront 캐시 갱신 | HTTPS 443. 갱신 완료 후 /와 /login을 확인한다. |
| 16→12→11 | 사용자 → CloudFront → S3 | HTTPS 443. HTTP는 HTTPS로 전환하고 S3 원본은 OAC로 읽는다. |
| 12→05 | /api·/api/* 원본 연결 | 후속 연결. HTTPS 443, 캐시 중지, 쿠키·인증 헤더·쿼리 전달. |
| 14→13 | Backend OCI push | 미구현. HTTPS 443, linux/arm64 이미지와 커밋 SHA 태그를 사용한다. |
| 05→13 | ECR 이미지 pull | 미구현. HTTPS 443, EC2 IAM Role과 digest로 이미지를 가져온다. |
| 01→11→05 | 기본 경로의 정적 파일 게시 | 로컬 live 빌드 압축 파일을 비공개 S3에 올린다. EC2는 SSM 명령에 따라 releases/*를 HTTPS 443으로 내려받고 해시를 확인한다. |
| 05→17 | DuckDNS IP 갱신 | 부팅 후와 약 15분 간격으로 확인한다. 프로젝트 토큰은 Parameter Store에서 읽는다. |
| 16→17 | DNS 조회 | 브라우저의 DNS 리졸버가 DuckDNS A 레코드로 EC2 공인 IPv4를 확인한다. |
| 16→18 | 기본 경로의 웹 접속 | HTTPS 443. Caddy가 정적 파일을 제공한다. HTTP 80은 HTTPS로 이동한다. |

DuckDNS 호스트명은 재배포 시 EC2의 정적 웹 접속 주소로 사용한다. Backend API 연결은 후속 작업이다.
정적 웹에는 TCP 80·443만 공개한다. Backend를 연결할 때 원본 호스트명과 인증서를 별도로 확정한다.
정적 SPA 경로만 `index.html`로 연결한다. API 오류에는 적용하지 않는다.
Backend 미연결 상태의 읽기 API는 JSON 503을 반환한다.
Backend·MySQL 내부 포트는 외부에 공개하지 않는다. MySQL 8.4의 운영 위치는 아직 확정하지 않았다.

## 5. 구현·검증 상태

- Terraform CLI: 현재 고정 버전은 1.16.6이다. 새 버전에서 모의 테스트와 실제 AWS 조회 계획을 검증했다.
- 실제 배포: 생성·게시·전체 삭제는 Terraform 1.10.0에서 검증한 기록이다. 2026-10-20에 CloudFront 로컬 게시를 확인했다. 2026-10-21에는 DuckDNS·EC2 게시를 확인한 뒤 관리 항목 21개를 모두 삭제했다.
- Frontend: Node.js 24·React·Vite, live 빌드와 테스트 검증 완료. 배포 당시 CloudFront에서 실제 로그인 화면을 확인했다. Actions 배포에는 [PR #2](https://github.com/OpenStudyService/OpenStudy-Frontend/pull/2) 병합과 변수 등록이 필요하다.
- Backend: Java 21·Spring Boot·Gradle 구성 확인. OCI·ECR·GitOps 배포, 실제 API 연결은 미구현이다.
- 현재 상태: `terraform/frontend`와 `terraform/aws`의 관리 리소스는 모두 0개다. DuckDNS의 A·AAAA 기록과 AWS에 저장한 프로젝트 토큰도 삭제했다.

## 근거와 상세 문서

빌드 구성은 [Frontend package.json](https://github.com/OpenStudyService/OpenStudy-Frontend/blob/main/package.json)과 [Backend build.gradle](https://github.com/OpenStudyService/OpenStudy-Backend/blob/main/build.gradle)을 기준으로 한다.
서비스 구성은 [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html), [ECR OCI 형식](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-manifest-formats.html), [GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)를 따른다.
Backend 배포 상세는 [GitOps 순서](gitops.md)를 따른다.
