# DuckDNS 정적 웹 배포

[README로 돌아가기](../README.md)

`https://openstudy.duckdns.org`에서 Frontend 정적 화면을 제공하는 구성이다.
DuckDNS의 A 레코드는 EC2 공인 IPv4를 가리킨다.
EC2의 Caddy가 HTTPS 인증서를 발급·갱신하고 React 빌드 파일을 제공한다.
이 경로는 `terraform/aws`에서 관리한다. CloudFront 경로인 `terraform/frontend`는 별도 선택 사항이다.
2026-10-21에 실제 배포를 확인한 뒤 사용자 요청으로 전체 삭제했다. 현재 웹 서비스는 중지 상태다.

## 1. 토큰과 실행 환경 준비

Terraform 1.16.6, Node.js 24, npm, Python 3.9 이상, AWS CLI v2와 curl을 사용한다.
`OpenStudy-Frontend`를 `OpenStudy-Infra`와 같은 상위 폴더에 둔다.

DuckDNS에서 `openstudy.duckdns.org`을 소유한 계정으로 로그인한다.
토큰은 서울 리전 Parameter Store의 `/openstudy-prod/duckdns/token`에 `SecureString`으로 저장한다.
처음 저장하는 방법은 [토큰 저장 절차](setup.md#5-duckdns-토큰-저장)를 따른다.
토큰을 Terraform 변수·state·Git·로그·채팅에 기록하지 않는다.

## 2. Terraform 변수 설정

`terraform/aws/terraform.tfvars`에 아래 값을 설정한다.

```hcl
enable_frontend   = true
enable_duckdns    = true
duckdns_subdomain = "openstudy"
web_ingress_cidrs = ["0.0.0.0/0"]
```

TCP 80·443을 공개한다. SSH와 애플리케이션 내부 포트는 공개하지 않는다.
관리 접속과 파일 게시는 Session Manager를 사용한다.
계정 ID와 비용 검토 설정은 [EC2 구축 절차](setup.md#3-terraform-변수-설정)를 따른다.

Frontend 위치가 다르면 절대 경로를 추가한다.

```hcl
frontend_source_dir = "/absolute/path/to/OpenStudy-Frontend"
```

Caddy는 공식 이미지 `caddy:2.11.7-alpine`으로 고정한다.
버전을 바꾸면 서버 설정을 SSM으로 다시 적용한다. 기존 EC2는 유지한다.

## 3. 생성과 자동 게시

OpenStudy-Infra에서 실행한다.

```sh
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws plan -out=aws.tfplan
terraform -chdir=terraform/aws apply aws.tfplan
terraform -chdir=terraform/aws output -raw frontend_url
```

`apply`는 다음 순서로 실행한다.

1. EC2·네트워크·SSM과 비공개 S3 배포 파일 버킷을 생성한다.
2. EC2가 Parameter Store에서 토큰을 읽고 DuckDNS IP를 갱신한다.
3. Caddy 설정을 검사하고 HTTPS 웹 서버를 시작한다.
4. 게시 작업이 해당 EC2의 실제 SSM 설정 실행 성공을 기다린다.
5. 로컬에서 `npm ci --include=dev`, `npm run check`, `npm run build`를 실행한다.
6. 소스맵과 MSW 실행 파일을 제외한 압축 파일을 S3에 올린다.
7. SSM으로 압축 파일의 SHA-256을 확인하고 서버에 푼다.
8. 해시 자산을 먼저 복사한 뒤 현재 릴리스 링크를 한 번에 전환한다.
9. HTTPS `/`와 `/login`의 HTML이 빌드 결과와 일치하는지 확인한다.

설정이나 게시가 실패하면 Terraform 적용도 실패한다.
원인을 고친 뒤 새 계획을 만들고 다시 적용한다.
소스 변경은 다음 `apply`에서 다시 게시한다. 빌드 결과·의존성 폴더·문서는 소스 해시에 포함하지 않는다.

S3 버킷은 배포 압축 파일 전달에만 사용한다. 브라우저는 EC2에서 정적 파일을 받는다.
EC2의 S3 읽기 권한은 해당 버킷의 `releases/*`로 제한한다.
이전 해시 자산을 유지해 열려 있는 브라우저 탭도 기존 파일을 읽을 수 있게 한다.

## 4. 접속과 운영 확인

```sh
terraform -chdir=terraform/aws output public_ipv4
dig +short openstudy.duckdns.org A
curl -I https://openstudy.duckdns.org/login
```

DNS IP와 EC2 공인 IP가 같아야 한다.
HTTP는 HTTPS로 이동한다. 인증서 검증을 끄지 않는다.
일반 SPA 경로는 `index.html`을 반환한다. 없는 정적 파일은 404를 반환한다.
Backend는 별도 구현 범위다. `/api`와 `/api/*`는 JSON 503을 반환한다.

EC2의 공인 IP는 부팅 후와 약 15분마다 확인한다.
IP가 바뀌면 DuckDNS를 자동 갱신한다. 다른 장치에서 같은 DuckDNS 주소를 갱신하지 않는다.

SSM 접속 후 상태를 확인할 수 있다.

```sh
sudo systemctl is-active openstudy-web openstudy-duckdns.timer
sudo journalctl -u openstudy-duckdns.service -n 20 --no-pager
sudo docker logs --tail 40 openstudy-web
```

## 5. 전체 삭제

진행 중인 게시를 마친 뒤 삭제 계획을 적용한다.

```sh
terraform -chdir=terraform/aws plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/aws apply destroy.tfplan
terraform -chdir=terraform/aws state list
```

EC2·루트 디스크·Caddy 인증서·정적 파일·S3 배포 압축 파일과 관련 인프라를 삭제한다.
DuckDNS의 등록 이름과 외부에서 저장한 SSM 토큰은 Terraform state에 포함하지 않는다.
사용을 마치면 DuckDNS IP 기록을 비우고 [프로젝트 토큰 정리](teardown.md#4-별도-등록한-토큰-삭제)를 진행한다.
다시 생성할 때는 토큰을 재등록하고 새 계획을 만든다.

## 근거

- [DuckDNS 갱신 API](https://www.duckdns.org/spec.jsp)
- [Caddy 자동 HTTPS 조건](https://caddyserver.com/docs/automatic-https)
- [Caddy 2.11.7 공식 릴리스](https://github.com/caddyserver/caddy/releases/tag/v2.11.7)

## 실제 적용 기록

2026-10-21에 `https://openstudy.duckdns.org` 연결과 정적 파일 게시를 완료했다.
당시 EC2는 `i-01bb8eaa132e14815`이고, 공인 IP는 `43.203.123.190`이었다.
DuckDNS A 레코드와 공인 IP가 일치하는 것을 확인했다.
`/`, `/login`, `/invitations/accept`와 진입 JavaScript·CSS가 로컬 빌드와 일치하는 것을 확인했다.
HTTP 308의 HTTPS 이동과 없는 정적 파일의 404도 확인했다.
Backend 미연결 API는 JSON 503을 반환했다.

이후 같은 날 사용자 요청으로 Terraform 관리 항목 21개를 모두 삭제했다.
EC2 종료와 루트 EBS·S3 버킷·네트워크·IAM·SSM 구성 삭제를 AWS API로 확인했다.
DuckDNS A·AAAA 기록을 비웠다. 이름 등록은 유지한다.
Parameter Store의 `/openstudy-prod/duckdns/token`도 삭제했다.
`terraform/aws`와 `terraform/frontend`의 관리 리소스는 모두 0개다.
두 경로의 삭제 계획은 모두 `No changes`를 반환했다.
코드와 로컬 state·변수 파일은 보관한다.
