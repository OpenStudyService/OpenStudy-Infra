# Frontend 정적 웹 IaC

S3·CloudFront와 GitHub OIDC 배포 역할을 관리한다. EC2와 별도 state를 사용한다.
생성·자동 배포·전체 삭제는 [Frontend 배포 순서](../../docs/frontend-deployment.md)를 따른다.

Terraform 1.10.0을 사용한다. 저장소 루트의 `.terraform-version`을 따른다.
`terraform.tfvars.example`을 복사하고 실제 AWS 계정 ID를 입력한다.
정적 파일은 Terraform이 관리하지 않는다. Frontend의 GitHub Actions가 게시한다.
