# OpenStudy-Infra

OpenStudy의 AWS 네트워크·EC2와 Frontend S3·CloudFront 호스팅을 Terraform으로 관리한다.
`openstudy.duckdns.org`을 EC2 공인 IP에 자동 연결한다.
필요할 때 생성하고 사용 후 AWS 리소스와 저장 데이터를 모두 삭제한다.

## 실행 환경

Terraform은 **1.10.0**으로 고정한다. 저장소의 `.terraform-version`을 따른다.
tfenv를 사용하면 저장소 안에서 `tfenv install`로 해당 버전을 준비한다.
`terraform version`의 첫 줄이 `Terraform v1.10.0`인지 확인한다.
계획 생성과 적용은 같은 버전으로 실행한다. 버전이나 변수를 바꾸면 계획을 다시 생성한다.

## 기본 구성

- 서울 리전에 `t4g.small` 1대, gp3 8GiB, 스왑 1GiB를 구성한다.
- Docker와 DuckDNS 자동 갱신 서비스를 설치한다.
- Terraform이 SSM으로 서버 설정을 적용한다. 설정 변경 시 기존 EC2를 유지한다.
- 서버 관리는 AWS Session Manager를 사용한다.
- 인바운드 포트는 기본 차단한다. 필요하면 TCP 80·443을 허용한다.

## Frontend 정적 웹 자동 배포

`terraform/frontend`는 EC2와 별도 state로 S3·CloudFront·OAC와 GitHub OIDC 배포 역할을 관리한다.
Frontend의 GitHub Actions는 검사·live 빌드·S3 게시·캐시 갱신을 실행한다.
실제 AWS 생성과 배포는 **[Frontend 자동 배포 순서](docs/frontend-deployment.md)**를 따른다.
이 코드 변경만으로 AWS 리소스를 생성하지 않는다.

## Backend 배포 설계

Backend OCI·ECR 자동 배포는 구현 예정이다.

- [Frontend](https://github.com/OpenStudyService/OpenStudy-Frontend): React·Vite의 `dist/`를 S3·CloudFront로 제공한다. IaC와 Actions 코드를 추가했다.
- [Backend](https://github.com/OpenStudyService/OpenStudy-Backend): GitHub Actions에서 ARM64 OCI 이미지를 빌드해 Amazon ECR에 저장한다. EC2가 이미지를 가져와 실행한다.
- GitHub OIDC로 AWS 배포 역할을 사용한다. 사용 후 S3·CloudFront·ECR도 전체 삭제한다.

흐름과 구현 순서는 [정적 호스팅·OCI 이미지 배포 설계](docs/deployment.md)를 따른다.

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
DB 생성 코드는 아직 없다. 별도로 만든 리소스는 state에 포함해야 Terraform이 삭제한다.

코드와 로컬 state·변수 파일은 보관한다.
다음 사용 시 Terraform을 다시 적용하고 DuckDNS 토큰을 재등록한다.

## 추가 문서

- [aws configure 설정 방법](docs/aws-configure.md)
- [AWS 전체 정리](docs/teardown.md)
- [초기 설정 실패 복구](docs/cloud-init-recovery.md)
- [DuckDNS 토큰 변경과 오류 해결](docs/duckdns.md)
- [Cloudflare 추가 설정](docs/cloudflare-manual.md)
- [GitOps 배포 순서](docs/gitops.md)
- [정적 호스팅·OCI 이미지 배포 설계](docs/deployment.md)
- [Frontend 자동 배포·생성·정리](docs/frontend-deployment.md)
- [요구조건과 검증 상태](docs/requirements.md)

전체 로컬 검증은 [검증 스크립트](scripts/validate.sh)를 `./scripts/validate.sh`로 실행한다.
서버 설정 결과는 SSM 실행 상태와 DNS 응답으로 확인한다.
Backend HTTPS 원본·실제 API·Cloudflare 연결은 후속 작업으로 진행한다.
