# Frontend 정적 웹 IaC

S3·CloudFront와 GitHub OIDC 배포 역할을 관리한다. EC2와 별도 state를 사용한다.
생성·자동 배포·전체 삭제는 [Frontend 배포 순서](../../docs/frontend-deployment.md)를 따른다.

Terraform 1.10.0을 사용한다. 저장소 루트의 `.terraform-version`을 따른다.
`terraform.tfvars.example`을 복사하고 실제 AWS 계정 ID를 입력한다.
`apply`는 기본으로 로컬 Frontend를 검사·live 빌드하고 정적 파일을 게시한다.
S3 업로드와 CloudFront 캐시 갱신 후 `/`와 `/login`의 HTML을 확인한다.
Terraform 실행 환경에 Node.js 24, npm, AWS CLI와 AWS 인증이 필요하다.
Frontend는 기본으로 이 저장소 옆의 `OpenStudy-Frontend`에서 읽는다.
다른 위치는 `frontend_source_dir`에 지정한다. 소스 변경 시 다음 `apply`에서 다시 게시한다.

인프라만 생성하거나 GitHub Actions로 게시하려면 `deploy_frontend = false`를 설정한다.
DuckDNS·EC2 정적 웹은 `terraform/aws`에서 관리한다.
S3·CloudFront 경로를 선택할 때만 이 디렉터리를 별도로 적용한다.
