# Frontend 자동 배포 순서

[README로 돌아가기](../README.md)

이 문서는 S3·CloudFront 경로다. DuckDNS 주소를 사용할 때는 [EC2 기반 정적 웹 배포](duckdns-frontend.md)를 따른다.

`terraform/frontend`는 EC2와 별도 state로 정적 웹 인프라를 관리한다.
비공개 Amazon S3, Amazon CloudFront·OAC·SPA 경로 함수와 GitHub OIDC 배포 역할을 생성한다.
기본 `apply`는 로컬 Frontend를 검사·live 빌드한 뒤 S3에 게시한다.
CloudFront 캐시 갱신과 `/`, `/login`의 HTML 확인까지 완료해야 적용이 성공한다.
GitHub Actions 배포는 선택 사항이다. 운영 API 연결은 별도로 진행한다.
전체 관계와 번호 설명은 [통합 아키텍처·배포 흐름](deployment.md)을 따른다.

## 1. AWS와 변수 준비

[AWS 인증](aws-configure.md)을 먼저 설정한다. 아래 명령은 OpenStudy-Infra에서 실행한다.
Terraform은 **1.16.6**을 사용한다. tfenv는 저장소의 `.terraform-version`을 자동으로 읽는다.

```sh
tfenv install
terraform version
```

첫 줄이 `Terraform v1.16.6`인지 확인한다. 변수 파일은 없을 때만 복사한다.

```sh
aws sts get-caller-identity
cp -n terraform/frontend/terraform.tfvars.example terraform/frontend/terraform.tfvars
```

`terraform.tfvars`의 `aws_account_id`를 실제 계정 ID로 변경한다.
계정에 GitHub OIDC Provider가 이미 있다면 `github_oidc_provider_arn`에 해당 ARN을 입력한다.
없으면 기본값으로 새로 생성한다. 다른 state가 관리하는 Provider는 가져오거나 삭제하지 않는다.
기존 Provider는 다음 명령으로 확인한다. ARN의 계정 ID는 실제 값으로 바꾼다.

```sh
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
```

`NoSuchEntity`이면 Provider가 없는 상태다. `github_oidc_provider_arn`을 주석으로 두면 Terraform이 생성한다.
이 state가 이미 생성한 Provider는 외부 Provider ARN으로 다시 지정하지 않는다.

## 2. 정적 웹 인프라 생성

Terraform 실행 환경에 Node.js 24, npm, AWS CLI, curl과 cmp가 필요하다.
AWS CLI는 Terraform과 같은 대상 계정으로 인증한다.
`OpenStudy-Infra`와 `OpenStudy-Frontend`를 같은 상위 폴더에 둔다.
Frontend에는 `scripts/deploy-static.sh`가 포함되어 있어야 한다. 로컬 배포에는 PR #2 병합이 필요하지 않다.
다른 폴더에 있다면 `terraform.tfvars`에 절대 경로를 지정한다.

```hcl
frontend_source_dir = "/absolute/path/to/OpenStudy-Frontend"
```

`deploy_frontend`의 기본값은 `true`다. 기존 변수 파일에도 기본값을 적용한다.
소스가 없으면 계획 단계에서 오류를 반환한다.
인프라만 생성하려면 `deploy_frontend = false`를 설정한다.

```sh
terraform -chdir=terraform/frontend init
terraform -chdir=terraform/frontend validate
terraform -chdir=terraform/frontend plan -out=frontend.tfplan
```

생성·변경 대상을 확인한 뒤 같은 Terraform 버전으로 적용한다. `No changes`이면 적용을 생략한다.
`plan`은 빌드하거나 게시하지 않는다.

```sh
terraform -chdir=terraform/frontend apply frontend.tfplan
terraform -chdir=terraform/frontend output -raw frontend_url
```

`apply`는 다음 순서로 실행한다.

1. S3·CloudFront와 배포 권한을 생성한다. S3 접근 정책이 준비될 때까지 기다린다.
2. AWS CLI의 대상 계정을 확인한다.
3. `npm ci --include=dev`, `npm run check`, `npm run build`를 실행한다.
4. live 모드와 `/api` 주소로 빌드한 정적 파일을 S3에 게시한다.
5. CloudFront 캐시 갱신이 끝나면 `/`와 `/login`의 응답이 새 HTML과 같은지 확인한다.

실패하면 `apply`도 실패한다. 생성한 인프라는 state에 남는다.
원인을 수정하고 새 계획을 생성한 뒤 다시 적용한다.
소스·설정·배포 스크립트가 바뀌면 다음 적용 때 다시 게시한다.
`node_modules`, `dist`, 문서 변경만으로는 다시 게시하지 않는다.
버전·변수·Frontend 소스를 변경했다면 `plan`을 다시 실행한다. 이전 계획 파일은 사용하지 않는다.
이 구성은 EC2를 생성하지 않는다. `destroy`는 빌드하거나 게시하지 않는다.
파일을 수동 삭제한 뒤 같은 소스를 다시 게시하려면 새 계획에 재실행을 지정한다.

```sh
terraform -chdir=terraform/frontend plan \
  -replace='terraform_data.frontend_deployment[0]' -out=frontend.tfplan
terraform -chdir=terraform/frontend apply frontend.tfplan
```

## 3. GitHub Actions 변수 등록

이 단계와 4단계는 GitHub Actions로 배포할 때만 필요하다.
`terraform.tfvars`에 `deploy_frontend = false`를 설정해 게시 경로를 Actions로 통일한다.
새 계획을 적용한 뒤 출력값을 확인한다.

```sh
terraform -chdir=terraform/frontend output -json github_actions_variables
```

OpenStudy-Frontend의 **Settings → Secrets and variables → Actions → Variables**에 출력값을 등록한다.
Secrets나 AWS Access Key를 등록하지 않는다.

| 변수 | 용도 |
| --- | --- |
| `AWS_ACCOUNT_ID` | 대상 AWS 계정 확인 |
| `AWS_REGION` | S3 리전 |
| `AWS_DEPLOY_ROLE_ARN` | OIDC 배포 역할 |
| `S3_BUCKET` | 게시 대상 버킷 |
| `CLOUDFRONT_DISTRIBUTION_ID` | 캐시 갱신 대상 |

배포 역할은 `OpenStudyService/OpenStudy-Frontend`의 `main` 브랜치만 허용한다.
다른 저장소를 사용할 때는 Terraform의 `github_repository`도 변경한다.
`AWS_DEPLOY_ROLE_ARN`이 없으면 Actions는 검사·빌드만 실행한다.
Frontend의 [자동 배포 PR #2](https://github.com/OpenStudyService/OpenStudy-Frontend/pull/2)를 원본 `main`에 병합한 뒤 사용한다.

## 4. 자동 배포와 확인

1. Frontend의 변경을 `main`에 병합한다. PR에서는 검사·빌드만 실행한다.
2. Actions의 **Frontend CI and S3 deployment** 성공을 확인한다. 첫 배포는 **Run workflow**로 실행할 수 있다.
3. 배포 작업은 해시 파일을 먼저 게시한다. `index.html`은 마지막에 게시한다.
4. CloudFront 캐시 갱신 완료 후 `/`와 `/login`이 새 HTML과 같은지 자동 확인한다.
5. CloudFront 주소에서 직접 새로고침과 화면 이동을 확인한다.

해시 파일은 1년 캐시를 사용한다. HTML은 `no-cache`를 사용한다.
열려 있는 브라우저 탭을 위해 이전 해시 파일은 유지한다. 사용 후 전체 정리 때 함께 삭제한다.
소스맵과 MSW 실행 파일은 게시하지 않는다. 두 배포를 동시에 실행하지 않는다.
새 `main` 커밋이 있으면 이전 커밋의 게시를 생략한다.
로컬 Terraform 게시와 Actions 게시를 동시에 실행하지 않는다.
이전 버전 복구는 정상 커밋으로 되돌린 뒤 같은 배포 절차를 실행한다.

## 5. Backend 연결

기본값은 정적 웹만 제공한다. `/api`와 `/api/*`를 HTML로 바꾸지 않는다.
Backend 미연결 상태에서는 로그인 등 실제 API 기능을 사용할 수 없다.
읽기 API는 JSON 503을 반환한다. 정적 원본은 쓰기 메서드를 허용하지 않는다.

Backend HTTPS 인증서와 접속 허용 규칙을 준비한 뒤 아래 변수를 설정하고 계획·적용을 반복한다.

```hcl
api_origin_domain_name = "openstudy.duckdns.org"
```

API는 HTTPS 원본으로 전달한다. 캐시는 끄고 쿠키·인증 헤더·쿼리를 전달한다.
요청 Host는 원본 호스트명으로 설정한다. API에는 SPA 경로 함수를 적용하지 않는다.
세션·CSRF·SSE는 Backend 연결 후 통합 검증한다. SSE는 60초보다 짧은 간격으로 데이터를 보내야 한다.

## 6. 사용 후 전체 삭제

Actions를 사용했다면 먼저 Frontend의 GitHub 변수 `AWS_DEPLOY_ROLE_ARN`을 삭제해 자동 게시를 중지한다.
진행 중인 배포가 끝났는지 확인한 뒤 실행한다.

```sh
terraform -chdir=terraform/frontend plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/frontend apply destroy.tfplan
terraform -chdir=terraform/frontend state list
```

CloudFront·OAC·SPA 함수·캐시 정책, S3 객체·버킷과 배포 역할을 삭제한다.
이 state가 생성한 OIDC Provider도 삭제한다. 외부에서 재사용한 Provider는 삭제하지 않는다.
EC2도 사용했다면 [AWS 전체 정리](teardown.md)에서 `terraform/aws` 삭제를 별도로 실행한다.
state·변수 파일은 보관한다. 다시 생성한 뒤 새 Actions 변수로 갱신한다.

## 검증과 기준

`./scripts/validate.sh`는 실제 AWS 생성 없이 모의 테스트를 실행한다. Node.js와 Terraform이 필요하다.
로컬 게시 테스트는 AWS 인증 실패, 계정 불일치, 검사·빌드·게시 실패가 적용을 중지하는지 확인한다.
구성은 [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)와 [GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)를 따른다.

## 실제 적용 기록

2026-10-20에 기본 로컬 배포 경로를 실제 AWS에 적용했다.

- 배포 당시 주소: `d14goo9a4tr1w0.cloudfront.net`. 현재는 삭제한 주소다.
- CloudFront: `EHC94BW0NZ1HF`, 배포 당시 상태 `Deployed`
- Terraform: 13개 항목 생성, 변경·삭제 0개. 적용 후 재검사는 `No changes`다.
- 정적 파일: S3 객체 11개. 소스맵과 MSW 실행 파일은 게시하지 않았다.
- 접속 확인: `/`, `/login`, `/invitations/accept`의 HTML과 진입 JavaScript·CSS가 빌드 결과와 일치한다.
- Backend: 배포 당시 미연결 상태였다. 로그인 화면은 표시했지만 실제 API는 JSON 503을 반환했다.

## 실제 삭제 기록

2026-10-20에 사용자 요청으로 `plan -destroy`를 만든 뒤 적용했다.
AWS 리소스 12개와 로컬 게시 항목 1개를 삭제했다. S3 정적 파일 11개도 함께 삭제했다.
AWS API에서 버킷·CloudFront 배포·OAC·SPA 함수·캐시 정책·IAM 역할·OIDC Provider가 없는 것을 확인했다.
`terraform/frontend`와 `terraform/aws`의 관리 리소스는 모두 0개다.
두 경로의 삭제 계획도 `No changes`를 반환했다.
코드와 로컬 state·변수 파일은 보관한다. 다시 배포할 때는 새 계획을 생성한다.
