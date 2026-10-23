# 사용 후 AWS 전체 정리

[README로 돌아가기](../README.md)

정리는 OpenStudy의 AWS 리소스와 저장 데이터를 삭제하는 작업이다.
다음 실행에서는 서버와 데이터를 새로 구성한다.

## 1. 이전 환경의 삭제 설정 반영

현재 코드로 새로 만든 환경은 2단계로 이동한다.
이전 코드로 만든 EC2는 종료 방지와 디스크 보관 설정을 먼저 변경한다.
RDS를 생성했다면 [DB 삭제 순서](database.md#삭제)에 따라 삭제 보호를 먼저 해제한다.
전체 데이터를 삭제할 때는 최종 스냅샷 생략도 일반 적용으로 먼저 반영한다.

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

DuckDNS 경로의 배포용 S3는 `terraform/aws`로 생성·삭제한다.
S3·CloudFront·OIDC 배포 역할의 선택 경로는 `terraform/frontend`로 생성·삭제한다.
선택형 RDS MySQL·비공개 서브넷·마이그레이션 버킷은 `terraform/aws`에서 생성·삭제한다.
현재 기본값과 예산 프로필은 사용자 요청으로 자동 백업과 최종 스냅샷을 끈 상태다. 삭제 보호는 유지한다.
최종 스냅샷을 별도로 켠 구성에서는 해당 스냅샷이 Terraform 삭제 후에도 남는다.
현재 이 저장소에는 ECR 생성 코드가 없다.
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

기존 리소스의 삭제 설정을 변경해야 한다면 일반 `plan`에서 대상을 확인한 뒤 필요한 변경만 적용한다.
state가 비어 있으면 삭제를 위해 리소스를 다시 생성하지 않는다.
Terraform이 관리하지 않는 리소스는 `destroy`로 삭제되지 않는다.
기준은 [Terraform 삭제 안내](https://developer.hashicorp.com/terraform/cli/commands/destroy), [S3 삭제 설정](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket#force_destroy), [RDS 삭제 안내](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DeleteInstance.html)를 따른다.

## 4. 별도 등록한 토큰 삭제

AWS Parameter Store에서 `/openstudy-prod/` 아래 파라미터를 확인한다.
프로젝트에서 등록한 DuckDNS·Cloudflare 토큰과 테스트 로그인 설정도 삭제한다.
기본 경로와 리전을 사용했다면 다음 명령으로 정리한다.

```sh
aws ssm delete-parameters --region ap-northeast-2 \
  --names /openstudy-prod/duckdns/token /openstudy-prod/cloudflared/token /openstudy-prod/frontend/test-login
```

등록하지 않은 이름은 응답의 `InvalidParameters`에 표시할 수 있다.
프로젝트 접두사나 리전을 변경했다면 실제 등록 경로를 사용한다.

## 5. 다음 사용 때 재생성

Git의 코드, 로컬 `terraform.tfstate`와 변수 파일은 보관한다.
[Terraform 실행](../README.md#terraform-실행) 후 [DuckDNS 토큰 등록](setup.md#5-duckdns-토큰-저장)을 다시 진행한다.
새 EC2의 공인 IP와 DNS 응답이 일치하는지 확인한다.


## ECS 예산 구성 추가 정리

`enable_ecs=true`이면 ECS 서비스·태스크·ECR·CloudWatch 로그도 삭제 대상이다.
운영 스케줄을 사용하면 Scheduler와 Lambda도 같은 AWS 스택에서 삭제한다.
ECR은 이미지가 남아 있으면 삭제를 거부한다. 필요한 이미지를 보관한 후 저장소를 비운다.
태그가 있는 릴리스는 자동 정리하지 않는다. 보관 용량을 별도로 확인한다.
SSM에 별도로 등록한 `/openstudy-prod/apps/`의 앱 비밀번호는 Terraform 관리 대상이 아니다.
DB 스냅샷과 앱 파라미터도 프로젝트 전체 정리 범위에 맞춰 확인한다.
