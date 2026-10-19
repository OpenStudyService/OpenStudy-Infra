# EC2와 DuckDNS 구축 순서

[README로 돌아가기](../README.md)

DuckDNS 등록 → AWS 확인 → 변수 설정 → EC2 생성 → 토큰 저장 → 연결 확인 순서로 진행한다.
Git, AWS CLI v2, Terraform 1.10 이상, Python 3.9 이상과 Bash를 준비한다.

## 1. DuckDNS 등록

1. [DuckDNS](https://www.duckdns.org)에 로그인한다.
2. 본인 계정에 `openstudy`를 등록한다. 이미 등록했다면 해당 이름을 확인한다.
3. 계정의 `token`을 확인한다. 이 토큰은 5단계에서 사용한다.

등록 주소는 `openstudy.duckdns.org`이어야 한다.
다른 계정이 사용 중인 이름은 등록할 수 없다.

## 2. 저장소와 AWS 준비

처음에는 저장소를 내려받는다. 기존 저장소는 해당 디렉터리에서 `git pull --ff-only`로 갱신한다.

```sh
git clone https://github.com/OpenStudyService/OpenStudy-Infra.git
cd OpenStudy-Infra
```

AWS CLI 인증을 처음 설정한다면 [aws configure 설정 방법](aws-configure.md)을 따른다.
설정 후 아래 명령으로 계정 ID를 확인한다.

```sh
aws sts get-caller-identity --query Account --output text
```

AWS Billing에서 `t4g.small`의 혜택과 크레딧을 확인한다.
EBS와 공인 IPv4 비용도 확인한다. 프리티어 여부만으로 전체 비용이 무료가 되지는 않는다.
이후 로컬 명령은 저장소 루트에서 실행한다.

## 3. Terraform 변수 설정

변수 파일이 없을 때만 예제를 복사한다.

```sh
cp -n terraform/aws/terraform.tfvars.example terraform/aws/terraform.tfvars
```

`terraform/aws/terraform.tfvars`에서 다음 값을 설정한다.

```hcl
aws_account_id      = "123456789012"
free_tier_confirmed = true
enable_duckdns      = true
duckdns_subdomain   = "openstudy"
```

`123456789012`를 2단계에서 확인한 계정 ID로 바꾼다.
`free_tier_confirmed`는 비용 검토를 마친 뒤 `true`로 설정한다.
토큰은 이 파일에 넣지 않는다.

## 4. EC2 생성

```sh
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws validate
terraform -chdir=terraform/aws plan -out=aws.tfplan
```

계획 내용을 확인한 뒤 적용한다.

```sh
terraform -chdir=terraform/aws apply aws.tfplan
```

기본 구성은 서울 리전의 `t4g.small`, 디스크 8GiB, 스왑 1GiB를 사용한다.
Terraform이 SSM 문서와 실행 연결을 생성해 서버 설정을 적용한다.
설정이 성공할 때까지 최대 30분 동안 기다린다.

## 5. DuckDNS 토큰 저장

저장할 파라미터 이름과 리전을 확인한다.

```sh
terraform -chdir=terraform/aws output duckdns_token_parameter_name
terraform -chdir=terraform/aws output aws_region
```

AWS 콘솔에서 같은 계정·리전을 선택한다.
**Systems Manager → Parameter Store → 파라미터 생성**으로 이동한다.

| 항목 | 입력값 |
| --- | --- |
| 이름 | 위 명령의 출력값. 기본값은 `/openstudy-prod/duckdns/token` |
| 등급 | Standard |
| 유형 | SecureString |
| KMS 키 | 기본 AWS 관리형 키 `alias/aws/ssm` |
| 값 | 1단계에서 확인한 DuckDNS token 문자열 |

토큰만 저장한다. JSON이나 설치 명령을 넣지 않는다.

## 6. EC2에서 갱신 실행

AWS 콘솔에서 **EC2 → 인스턴스 → 생성한 서버 → 연결 → Session Manager**로 접속한다.
서버 안에서 실행한다.

Terraform 적용이 실패했다면 [초기 설정 실패 복구](cloud-init-recovery.md)를 먼저 진행한다.
설정 완료 후 아래 명령으로 서비스를 확인한다.

```sh
sudo systemctl is-active docker chronyd amazon-ssm-agent openstudy-duckdns.timer
swapon --show
sudo systemctl start openstudy-duckdns.service
sudo journalctl -u openstudy-duckdns.service -n 10 --no-pager
```

로그의 `updated` 또는 `unchanged`를 확인한다.
이후 부팅 시와 약 15분 간격으로 공인 IP를 확인한다.
IP가 바뀌면 Terraform 재실행 없이 DNS를 갱신한다.

## 7. DNS 연결 확인

다시 로컬 터미널에서 실행한다.

```sh
terraform -chdir=terraform/aws output public_ipv4
dig +short openstudy.duckdns.org A
```

두 IP가 같으면 DNS 연결을 확인한 것이다.
EC2 중지·시작 후에는 AWS 콘솔의 현재 공인 IP와 비교한다.
오류가 나면 [DuckDNS 오류 해결](duckdns.md)을 따른다.

## 다음 작업과 운영

- 웹 접속은 웹 서버와 HTTPS 인증서를 구성한 뒤 확인한다.
- 직접 웹 접속을 열려면 `web_ingress_cidrs = ["0.0.0.0/0"]`로 바꾸고 계획·적용을 반복한다. TCP 80·443만 열린다.
- Cloudflare는 [추가 설정 문서](cloudflare-manual.md)를 따른다. 현재 DuckDNS 연결은 EC2 직접 연결이다.
- Terraform state를 보관한다. 여러 작업자가 적용하기 전에는 잠금을 지원하는 원격 저장소로 옮긴다.
- 설치 설정 변경은 SSM으로 적용한다. AMI와 최초 user data 변경으로 기존 EC2를 교체하지 않는다.
