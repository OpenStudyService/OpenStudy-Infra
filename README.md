# OpenStudy-Infra

OpenStudy의 AWS 네트워크·EC2·선택형 Single-AZ RDS MySQL과 Frontend 정적 웹 배포를 Terraform으로 관리한다.
`openstudy.duckdns.org`을 EC2 공인 IP에 자동 연결하고 HTTPS 정적 웹을 제공한다.
필요할 때 생성하고 사용 후 AWS 리소스와 저장 데이터를 모두 삭제한다.

## 통합 아키텍처와 배포 흐름

![OpenStudy AWS 아키텍처](docs/images/openstudy-duckdns-deployment-numbered.png)

최신 서비스 배치와 운영 상태는 **[AWS 아키텍처 문서](docs/architecture.md)**를 따른다.
[draw.io 편집 파일](docs/images/openstudy-duckdns-deployment-numbered.drawio) · [SVG](docs/images/openstudy-duckdns-deployment-numbered.svg) · [HTML](docs/images/openstudy-duckdns-deployment-numbered.html)

Nginx와 향후 Gateway·Service 컨테이너 두 개를 EC2 한 대에 배치한다.
DB는 Single-AZ RDS Primary 한 대다. 자동 백업과 삭제 시 최종 스냅샷은 만들지 않는다.
평일 서울 시간 11:00~18:00 운영을 자동화한다. 실제 앱 이미지가 없어 ECS 앱 태스크는 미배포 상태다.
2026-10-23에 Terraform apply를 완료했다. EC2와 RDS는 교체하지 않았다.
Nginx CORS 설정과 정적 웹을 갱신했다. 운영 시간의 EC2 실행과 RDS 사용 가능 상태를 확인했다.
그림에는 작은 원형 번호와 짧은 영문 서비스 이름만 표시한다. 상세 설명은 그림 밖에 둔다.
최신 적용 결과는 [검증 기록](docs/requirements.md#2026-10-23-커밋과-terraform-적용)을 따른다.

## 실행 환경

Terraform은 **1.16.6**으로 고정한다. 저장소의 `.terraform-version`을 따른다.
tfenv를 사용하면 저장소 안에서 `tfenv install`로 해당 버전을 준비한다.
`terraform version`의 첫 줄이 `Terraform v1.16.6`인지 확인한다.
계획 생성과 적용은 같은 버전으로 실행한다. 버전이나 변수를 바꾸면 계획을 다시 생성한다.

2026-10-21 기준 고정 버전은 다음과 같다.

| 구성 | 버전 | 공식 릴리스 |
| --- | --- | --- |
| Terraform CLI | 1.16.6 | [릴리스](https://github.com/hashicorp/terraform/releases/tag/v1.16.6) |
| AWS 공급자 | 6.69.1 | [릴리스](https://github.com/hashicorp/terraform-provider-aws/releases/tag/v6.69.1) |
| Cloudflare 공급자 | 5.28.1 | [릴리스](https://github.com/cloudflare/terraform-provider-cloudflare/releases/tag/v5.28.1) |
| cloudflared | 2026.10.2 | [릴리스](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.2) |
| Nginx | 1.30.6 (Debian) | [릴리스](https://nginx.org/en/download.html) |

공급자는 각 스택의 `.terraform.lock.hcl`을 따른다.
기존 로컬 변수 파일에 `cloudflared_version`이 있으면 `2026.10.2`로 갱신한다.
이전 Terraform 버전으로 만든 계획 파일은 다시 사용하지 않는다.

## 기본 구성

- 서울 리전에 `t4g.small` 1대, gp3 8GiB, 스왑 1GiB를 구성한다.
- 현재 예산 프로필은 계정 제한에 맞춰 `c7i-flex.large`·AMD64·4GiB와 gp3 30GiB를 사용한다.
- Docker와 DuckDNS 자동 갱신 서비스를 설치한다.
- Terraform이 SSM으로 서버 설정을 적용한다. 설정 변경 시 기존 EC2를 유지한다.
- 서버 관리는 AWS Session Manager를 사용한다.
- 인바운드 포트는 기본 차단한다. 필요하면 TCP 80·443을 허용한다.

## Frontend 정적 웹 자동 배포

DuckDNS 주소는 `terraform/aws`에서 `enable_frontend = true`로 배포한다.
EC2의 Nginx가 HTTPS와 정적 파일을 제공한다. 비공개 S3는 배포 압축 파일 전달에 사용한다.
실제 실행과 전체 삭제는 [DuckDNS 정적 웹 배포](docs/duckdns-frontend.md)를 따른다.

`terraform/frontend`는 EC2와 별도 state로 S3·CloudFront·OAC와 GitHub OIDC 배포 역할을 관리한다.
기본 `apply`는 로컬 Frontend의 검사·live 빌드·S3 게시·캐시 갱신까지 실행한다.
Node.js 24·npm·AWS CLI와 같은 상위 폴더의 `OpenStudy-Frontend` 저장소가 필요하다.
`frontend_source_dir`로 다른 소스 위치를 지정할 수 있다.
GitHub Actions로 게시할 때는 `deploy_frontend = false`를 설정한다.
실제 AWS 생성과 배포는 **[Frontend 자동 배포 순서](docs/frontend-deployment.md)**를 따른다.
`terraform/aws apply`는 `enable_frontend = true`일 때 DuckDNS 정적 웹 게시까지 실행한다.

## Backend 배포 설계

RDS MySQL 8.4와 테이블 배포는 [DB 배포 문서](docs/database.md)를 따른다.
`enable_database = true`로 비공개 RDS 생성과 Flyway 스키마 적용을 연결한다.
기본값은 비활성화다. Backend 연결은 별도 작업이다.

ECS·ECR 기반은 구현했다. 앱 이미지 빌드와 GitHub Actions 연결은 후속 작업이다.

- [Frontend](https://github.com/OpenStudyService/OpenStudy-Frontend): React·Vite의 `dist/`를 DuckDNS·EC2 Nginx로 제공한다. S3·CloudFront는 별도 선택 경로다.
- [Backend](https://github.com/OpenStudyService/OpenStudy-Backend): 향후 GitHub Actions에서 서버에 맞는 OCI 이미지를 빌드해 Amazon ECR에 저장한다. 현재 예산 프로필의 플랫폼은 `linux/amd64`다.
- GitHub OIDC로 AWS 배포 역할을 사용한다. 사용 후 S3·CloudFront·ECR도 전체 삭제한다.

Terraform과 애플리케이션의 역할 및 전체 순서는 [통합 배포 문서](docs/deployment.md)를 따른다.

## 실행 순서

1. [DuckDNS 등록](docs/setup.md#1-duckdns-등록): `openstudy`를 등록하고 토큰을 확인한다.
2. [저장소와 AWS 준비](docs/setup.md#2-저장소와-aws-준비): AWS 인증과 계정 혜택을 확인한다.
3. [Terraform 변수 설정](docs/setup.md#3-terraform-변수-설정): 실제 계정 ID를 입력한다.
4. [EC2 생성](docs/setup.md#4-ec2-생성): Terraform 계획을 확인하고 적용한다.
5. [DuckDNS 토큰 저장](docs/setup.md#5-duckdns-토큰-저장): Parameter Store에 토큰을 등록한다.
6. [EC2에서 갱신 실행](docs/setup.md#6-ec2에서-갱신-실행): Session Manager로 접속해 갱신한다.
7. [DNS 연결 확인](docs/setup.md#7-dns-연결-확인): DNS 응답과 EC2 공인 IP를 비교한다.

명령은 **[처음부터 따라 하는 구축 절차](docs/setup.md)**를 따른다.
이후 부팅 시와 약 15분 간격으로 IP를 확인하고 변경 시 DNS를 갱신한다.

## Terraform 실행

현재 배포에는 예산 프로필을 계속 지정한다. 프로필을 빼면 기본값으로 되돌리는 변경이 생길 수 있다.

```sh
terraform -chdir=terraform/aws plan -var-file=profiles/budget.tfvars.example -out=budget.tfplan
terraform -chdir=terraform/aws apply budget.tfplan
```

변수 설정을 마친 뒤 저장소 루트에서 검증과 계획을 실행한다.

```sh
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws validate
terraform -chdir=terraform/aws plan -out=aws.tfplan
```

계획 내용을 확인하고 변경이 있으면 적용한다. `No changes`이면 적용을 생략한다.

```sh
terraform -chdir=terraform/aws apply aws.tfplan
```

서버 설정 변경은 SSM으로 반영한다. 기존 EC2는 유지한다.
같은 설정을 다시 실행하려면 [SSM 재실행 방법](docs/cloud-init-recovery.md#같은-설정을-다시-실행할-때)을 따른다.

## 사용 후 정리: AWS 전체 삭제

사용을 마치면 삭제 계획을 확인한다.

```sh
terraform -chdir=terraform/aws plan -destroy -out=destroy.tfplan
```

대상이 OpenStudy 리소스인지 확인한 뒤 삭제한다.

```sh
terraform -chdir=terraform/aws apply destroy.tfplan
```

EC2와 루트 디스크, 네트워크·IAM·SSM 구성을 삭제한다.
S3·DB·백업과 별도 등록한 토큰까지 확인하는 방법은 **[AWS 전체 정리](docs/teardown.md)**를 따른다.
Frontend를 생성했다면 `terraform/frontend`도 별도로 전체 삭제한다. [Frontend 정리](docs/frontend-deployment.md#6-사용-후-전체-삭제)를 따른다.
RDS를 생성했다면 먼저 [DB 삭제 순서](docs/database.md#삭제)에 따라 삭제 보호를 해제한다.
최종 스냅샷과 수동 백업은 별도로 확인한다.

코드와 로컬 state·변수 파일은 보관한다.
다음 사용 시 Terraform을 다시 적용하고 DuckDNS 토큰을 재등록한다.

## 추가 문서

- [aws configure 설정 방법](docs/aws-configure.md)
- [AWS 전체 정리](docs/teardown.md)
- [초기 설정 실패 복구](docs/cloud-init-recovery.md)
- [DuckDNS 토큰 변경과 오류 해결](docs/duckdns.md)
- [Cloudflare 추가 설정](docs/cloudflare-manual.md)
- [GitOps 배포 순서](docs/gitops.md)
- [Terraform IaC 통합 아키텍처·배포 흐름](docs/deployment.md)
- [Frontend 자동 배포·생성·정리](docs/frontend-deployment.md)
- [DuckDNS 정적 웹·HTTPS 배포](docs/duckdns-frontend.md)
- [요구조건과 검증 상태](docs/requirements.md)
- [RDS MySQL·테이블 배포](docs/database.md)
- [월 5만 원 ECS 구성과 비용](docs/ecs-budget.md)

전체 로컬 검증은 [검증 스크립트](scripts/validate.sh)를 `./scripts/validate.sh`로 실행한다.
서버 설정 결과는 SSM 실행 상태와 DNS 응답으로 확인한다.
Backend HTTPS 원본·실제 API·Cloudflare 연결은 후속 작업으로 진행한다.
