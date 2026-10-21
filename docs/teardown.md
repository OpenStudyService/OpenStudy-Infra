# 사용 후 AWS 전체 정리

[README로 돌아가기](../README.md)

정리는 OpenStudy의 AWS 리소스와 저장 데이터를 삭제하는 작업이다.
다음 실행에서는 서버와 데이터를 새로 구성한다.

## 1. 이전 환경의 삭제 설정 반영

현재 코드로 새로 만든 환경은 2단계로 이동한다.
이전 코드로 만든 EC2는 종료 방지와 디스크 보관 설정을 먼저 변경한다.

```sh
terraform -chdir=terraform/aws plan -out=teardown-prepare.tfplan
terraform -chdir=terraform/aws apply teardown-prepare.tfplan
```

EC2는 `disable_api_termination = false`를 사용한다.
루트 디스크는 `delete_on_termination = true`를 사용한다.

## 2. Terraform 리소스 삭제

Frontend 정적 호스팅을 생성했다면 먼저 [Frontend 전체 삭제](frontend-deployment.md#6-사용-후-전체-삭제)를 실행한다.
`terraform/aws`와 `terraform/frontend`의 state는 분리되어 있다. 한쪽 삭제가 다른 쪽 리소스를 삭제하지 않는다.
DuckDNS 정적 웹을 사용하면 `terraform/aws` 삭제에 EC2의 웹 파일·인증서와 비공개 S3 배포 파일 버킷도 포함한다.

저장소 루트에서 삭제 계획을 만든다.

```sh
terraform -chdir=terraform/aws plan -destroy -out=destroy.tfplan
```

계획의 삭제 대상을 확인한 뒤 적용한다.

```sh
terraform -chdir=terraform/aws apply destroy.tfplan
terraform -chdir=terraform/aws state list
```

state 목록에 관리 리소스가 남아 있지 않은지 확인한다.
현재 구성은 EC2·루트 EBS·VPC·서브넷·라우팅·보안 그룹·IAM·SSM 문서와 실행 연결을 삭제한다.

## 3. S3·CloudFront·ECR·DB·백업 확인

S3·CloudFront·OIDC 배포 역할은 `terraform/frontend`로 생성·삭제한다.
현재 이 저장소에는 ECR과 DB 생성 코드가 없다.
별도로 생성했다면 Terraform으로 가져와 같은 삭제 범위에 포함한다.

| 대상 | 전체 삭제 기준 |
| --- | --- |
| S3 | 버킷의 객체와 이전 버전까지 삭제한다. Terraform 버킷에 `force_destroy = true`를 적용한다. |
| CloudFront·OAC | 배포 비활성화가 완료된 뒤 배포와 OAC를 삭제한다. S3 원본 삭제와의 의존성을 구성한다. |
| Amazon ECR | 태그가 없는 이미지를 포함해 모든 이미지와 리포지토리를 삭제한다. |
| 배포 인증 | 프로젝트가 생성·소유한 GitHub OIDC Provider, IAM Role과 정책을 삭제한다. |
| RDS·Aurora | 삭제 방지를 해제한다. 최종 스냅샷과 자동 백업을 남기지 않는다. 기존 수동 스냅샷도 삭제한다. |
| DynamoDB | 테이블과 별도 생성한 백업을 삭제한다. |
| EBS | 종료한 서버의 디스크와 별도 스냅샷이 남아 있지 않은지 확인한다. |

설정을 변경했다면 삭제 계획을 만들기 전에 일반 `plan`과 `apply`로 반영한다.
Terraform이 관리하지 않는 리소스는 `destroy`로 삭제되지 않는다.
기준은 [Terraform 삭제 안내](https://developer.hashicorp.com/terraform/cli/commands/destroy), [S3 삭제 설정](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket#force_destroy), [RDS 삭제 안내](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DeleteInstance.html)를 따른다.

## 4. 별도 등록한 토큰 삭제

AWS Parameter Store에서 `/openstudy-prod/` 아래 파라미터를 확인한다.
프로젝트에서 등록한 DuckDNS·Cloudflare 토큰도 삭제한다.
기본 경로와 리전을 사용했다면 다음 명령으로 정리한다.

```sh
aws ssm delete-parameters --region ap-northeast-2 \
  --names /openstudy-prod/duckdns/token /openstudy-prod/cloudflared/token
```

등록하지 않은 이름은 응답의 `InvalidParameters`에 표시할 수 있다.
프로젝트 접두사나 리전을 변경했다면 실제 등록 경로를 사용한다.

## 5. 다음 사용 때 재생성

Git의 코드, 로컬 `terraform.tfstate`와 변수 파일은 보관한다.
[Terraform 실행](../README.md#terraform-실행) 후 [DuckDNS 토큰 등록](setup.md#5-duckdns-토큰-저장)을 다시 진행한다.
새 EC2의 공인 IP와 DNS 응답이 일치하는지 확인한다.
