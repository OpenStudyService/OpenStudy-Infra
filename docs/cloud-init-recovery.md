# 초기 설정 실패 복구

[README로 돌아가기](../README.md) · [구축 절차 6단계](setup.md#6-ec2에서-갱신-실행)

## 1. 실패 원인 확인

EC2의 Session Manager에서 실행한다.

```sh
sudo cloud-init status --long
sudo tail -n 80 /var/log/cloud-init-output.log
```

`/download/2035.10.1/`에서 404 오류가 발생했다면 cloudflared 버전 오타다.
아래 절차는 이 오류로 최초 설정이 중단된 서버에 적용한다.

## 2. EC2의 설치 버전 수정

확인한 공식 배포 버전은 [2026.10.1](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.1)이다.
실패한 스크립트를 백업하고 해당 URL만 수정한다.

```sh
sudo cp -n /var/lib/cloud/instance/scripts/part-001 /root/openstudy-bootstrap.before-fix.sh
sudo sed -i 's|/download/2035\.10\.1/|/download/2026.10.1/|g' /var/lib/cloud/instance/scripts/part-001
sudo bash /var/lib/cloud/instance/scripts/part-001
```

백업은 cloud-init의 실행 디렉터리 밖에 보관한다.
설치 오류가 다시 발생하면 해당 출력부터 확인한다.

## 3. 서비스와 DNS 확인

재실행이 성공한 뒤 EC2에서 확인한다.

```sh
sudo systemctl is-active docker chronyd amazon-ssm-agent openstudy-duckdns.timer
swapon --show
sudo systemctl start openstudy-duckdns.service
sudo journalctl -u openstudy-duckdns.service -n 10 --no-pager
```

DuckDNS 로그에 `updated` 또는 `unchanged`가 나오면 [DNS 연결 확인](setup.md#7-dns-연결-확인)을 진행한다.
스크립트를 직접 재실행하므로 cloud-init의 최초 실패 기록은 남을 수 있다.
복구 결과는 서비스 상태와 DNS 응답으로 확인한다.

## 4. 로컬 변수도 수정

로컬 PC의 `terraform/aws/terraform.tfvars`에서 다음 값으로 수정한다.

```hcl
cloudflared_version = "2026.10.1"
```

기존 EC2의 복구는 2단계 명령으로 수행한다.
Terraform은 user data 변경 시 서버 교체를 계획할 수 있으므로 복구 목적으로 재적용하지 않는다.
