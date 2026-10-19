# OpenStudy-Infra

OpenStudy의 AWS 네트워크와 EC2를 Terraform으로 관리한다.
`openstudy.duckdns.org`을 EC2 공인 IP에 자동 연결한다.

## 기본 구성

- 서울 리전에 `t4g.small` 1대, gp3 8GiB, 스왑 1GiB를 구성한다.
- Docker와 DuckDNS 자동 갱신 서비스를 설치한다.
- Terraform이 SSM으로 서버 설정을 적용한다. 설정 변경 시 기존 EC2를 유지한다.
- 서버 관리는 AWS Session Manager를 사용한다.
- 인바운드 포트는 기본 차단한다. 필요하면 TCP 80·443을 허용한다.

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

## 실행 후 정리

적용을 완료했거나 `No changes`를 확인한 뒤 이전 계획 파일을 삭제한다.

```sh
rm -f terraform/aws/aws.tfplan terraform/aws/ssm-recovery.tfplan
```

`terraform.tfstate`, `terraform.tfstate.backup`, `.terraform.lock.hcl`과 `terraform.tfvars`는 유지한다.
이 정리는 계획 파일만 삭제한다. 기존 EC2와 Terraform state는 보관한다.

## 추가 문서

- [aws configure 설정 방법](docs/aws-configure.md)
- [초기 설정 실패 복구](docs/cloud-init-recovery.md)
- [DuckDNS 토큰 변경과 오류 해결](docs/duckdns.md)
- [Cloudflare 추가 설정](docs/cloudflare-manual.md)
- [GitOps 배포 순서](docs/gitops.md)
- [요구조건과 검증 상태](docs/requirements.md)

전체 로컬 검증은 [검증 스크립트](scripts/validate.sh)를 `./scripts/validate.sh`로 실행한다.
서버 설정 결과는 SSM 실행 상태와 DNS 응답으로 확인한다.
웹 서버·HTTPS·Cloudflare 연결은 후속 작업으로 진행한다.
