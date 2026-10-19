# Terraform으로 초기 설정 복구

[README로 돌아가기](../README.md) · [구축 절차 6단계](setup.md#6-ec2에서-갱신-실행)

## 1. 변수 수정

`2035.10.1` 다운로드의 404 오류는 버전 오타다.
로컬 `terraform/aws/terraform.tfvars`에서 확인한 [공식 배포 버전](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.1)으로 수정한다.

```hcl
cloudflared_version = "2026.10.1"
```

## 2. Terraform 적용

저장소 루트에서 실행한다.

```sh
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws plan -out=aws.tfplan
```

계획에서 기존 EC2를 교체하지 않는지 확인한 뒤 적용한다.

```sh
terraform -chdir=terraform/aws apply aws.tfplan
```

Terraform이 SSM으로 수정한 설치 스크립트를 기존 EC2에 적용한다.
설정 변경 시 SSM 실행 연결을 다시 생성하고, 성공할 때까지 최대 30분 동안 기다린다.
EC2의 최초 user data는 보관한다. 이후 설치 설정은 SSM 문서를 기준으로 관리한다.

## 3. 결과 확인

AWS 콘솔의 **Systems Manager → State Manager → openstudy-prod-configure-server**에서 실행 결과를 확인한다.
상태가 `Success`인지 확인한다.

EC2의 Session Manager에서 서비스를 확인한다.

```sh
sudo systemctl is-active docker chronyd amazon-ssm-agent openstudy-duckdns.timer
swapon --show
sudo journalctl -u openstudy-duckdns.service -n 10 --no-pager
```

이후 [DNS 연결 확인](setup.md#7-dns-연결-확인)을 진행한다.
cloud-init의 최초 실패 기록이 남아 있어도 SSM 실행과 서비스 상태로 복구 결과를 확인한다.

## 같은 설정을 다시 실행할 때

일시 오류를 해결한 뒤 같은 설정을 다시 실행하려면 SSM 실행 연결만 다시 생성한다.

```sh
terraform -chdir=terraform/aws plan -replace=aws_ssm_association.server -out=aws.tfplan
terraform -chdir=terraform/aws apply aws.tfplan
```

동작 기준은 [AWS State Manager 안내](https://docs.aws.amazon.com/systems-manager/latest/userguide/state-manager-about.html)를 따른다.
