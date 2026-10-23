# DuckDNS 정적 웹 배포

[README로 돌아가기](../README.md)

`https://openstudy.duckdns.org`에서 Frontend 정적 화면을 제공하는 구성이다.
DuckDNS의 A 레코드는 EC2 공인 IPv4를 가리킨다.
EC2의 Nginx가 React 빌드 파일을 제공한다. 공식 ACME 모듈로 HTTPS 인증서를 발급·갱신한다.
이 경로는 `terraform/aws`에서 관리한다. CloudFront 경로인 `terraform/frontend`는 별도 선택 사항이다.
2026-10-21에 실제 배포를 확인한 뒤 전체 삭제했다. 이후 같은 날 재배포하고 서버 검증을 사용하는 테스트 로그인을 추가했다.
2026-10-22에 Nginx 1.30.6으로 다시 배포했다. 현재 HTTPS 정적 웹을 제공한다.
현재 예산 프로필은 `frontend_api_mode = "live"`다. 실제 앱 이미지가 없어 API는 503을 반환한다.
전체 네트워크와 선택형 RDS 배치는 [최신 AWS 아키텍처](deployment.md)를 따른다.

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

백엔드 없이 테스트 계정으로 화면을 사용하려면 로컬 변수에 다음 값을 추가한다.

```hcl
frontend_api_mode = "mock"
```

Frontend의 Git 제외 파일 `.env.mock.local`에 `TEST_LOGIN_EMAIL`과 `TEST_LOGIN_PASSWORD`를 설정한다.
배포 전에 같은 계정의 bcrypt 해시를 Parameter Store에 등록한다. macOS의 `htpasswd`와 AWS CLI를 사용한다.

```sh
python3 scripts/configure-test-login.py --source-dir ../OpenStudy-Frontend --account-id 123456789012
```

계정 ID는 실제 Terraform 대상 계정으로 바꾼다. 이 명령은 비밀번호를 출력하거나 명령 인자로 전달하지 않는다.
`/openstudy-prod/frontend/test-login`의 SecureString에는 이메일과 비밀번호 해시만 저장한다.
부팅 설정이 SSM의 기존 이메일·bcrypt 형식을 비공개 htpasswd 파일로 변환한다. Nginx는 이 파일을 읽고 `/api/test-login`에서 입력값을 검사한다. 비밀번호와 해시는 브라우저 번들에 포함하지 않는다.
mock 모드는 `build:demo`와 MSW 실행 파일을 함께 게시한다. 로그인과 업무 데이터는 각 브라우저 탭의 가상 데이터로 동작한다.
이메일과 지정 비밀번호가 일치해야 사장님 화면을 연다. 계정 값은 Terraform 변수·state·Git에 넣지 않는다.
기본 `frontend_api_mode = "live"`는 실제 `/api` 서버를 사용한다. live 모드는 MSW 실행 파일을 배포 압축 파일에서 제외한다.

서버의 비밀번호 검사는 [Nginx auth_basic](https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html)를 사용한다.

Nginx는 ACME·njs 모듈을 포함한 공식 Debian 이미지 `nginx:1.30.6`으로 고정한다.
설정 변수는 `frontend_nginx_image`다. 이전 `frontend_caddy_image` 설정은 이 이름으로 변경한다.
인증서와 ACME 계정 키는 `/var/lib/openstudy-nginx/acme`에 권한 700으로 보관한다.
컨테이너는 UID/GID 101로 실행한다. 호스트 80·443을 내부 8080·8443으로 연결한다.
EC2가 켜진 동안 Nginx가 갱신을 처리한다. 별도 인증서 갱신 컨테이너는 사용하지 않는다.
버전을 바꾸면 서버 설정을 SSM으로 다시 적용한다. 기존 EC2는 유지한다.

### API CORS

Nginx는 `/api`와 `/api/*`에 CORS를 적용한다. S3의 CORS 설정은 변경하지 않는다.
브라우저가 보는 Frontend 주소와 API 주소는 `https://openstudy.duckdns.org`를 사용한다.
S3는 비공개 배포 파일 저장소다. EC2가 파일을 내려받고 Nginx가 웹 화면을 제공한다.

기본 허용 출처는 운영 DuckDNS의 HTTPS 주소 한 개다.
다른 Frontend 주소를 허용하려면 `terraform/aws/terraform.tfvars`에 정확한 출처를 추가한다.
출처는 프로토콜·호스트·포트로 구성한다. 경로와 마지막 `/`는 넣지 않는다.

```hcl
frontend_cors_allowed_origins = [
  "http://localhost:5173",
  "http://127.0.0.1:5173",
]
```

위 주소는 예시다. 실제 개발 서버 주소만 추가한다. 운영 주소는 자동으로 포함한다.
허용되지 않은 `Origin`이 있는 API 요청은 403으로 차단한다.
`Origin`이 없는 서버 간 API 요청은 기존 경로로 전달한다.
웹 화면과 `/assets/*`에는 API CORS 헤더를 추가하지 않는다.

허용한 출처의 API 응답에는 `Access-Control-Allow-Origin`과 `Access-Control-Allow-Credentials: true`를 설정한다.
`Vary: Origin`을 추가한다. 인증 오류와 Backend 미연결 503에도 같은 정책을 적용한다.
Gateway와 Service가 보낸 CORS 허용 헤더는 숨긴다. Nginx가 최종 응답 정책을 설정한다.

`OPTIONS`는 세션·테스트 로그인 검사와 Backend 연결 없이 204를 반환한다.
허용 메서드는 `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`다.
허용 요청 헤더는 `Accept`, `Authorization`, `Content-Type`, `X-CSRF-Token`, `X-Requested-With`다.
사전 요청 결과는 600초 동안 캐시할 수 있다.

CORS는 CSRF 검증을 대신하지 않는다.
Frontend는 `credentials: "include"`로 쿠키를 전송한다.
상태 변경 요청 전에 `GET /api/auth/csrf`로 `{ "token": "..." }`을 받고 `X-CSRF-Token`에 넣는다.
Backend는 이 토큰의 발급과 검증을 구현해야 한다. Nginx는 세션 쿠키와 CSRF 헤더를 전달한다.
서로 다른 사이트에서 세션 쿠키를 사용할 때는 Backend의 쿠키 `SameSite`·`Secure` 설정과 브라우저의 제3자 쿠키 정책도 확인한다.

설정은 다음 Terraform 적용 때 서버에 반영한다. CORS 코드 수정만으로 운영 설정이 바뀌지는 않는다.
2026-10-22 CORS 작업에서는 Terraform 적용과 서버 시작을 실행하지 않았다.

Terraform 검증과 AWS 모의 테스트 31개를 통과했다. Python 테스트 48개를 통과했다.
Python 검사에는 실제 로컬 Nginx 1.30.6을 사용하는 CORS HTTP 테스트 5개를 포함한다.
사전 요청·인증 오류·503·허용 출처·인코딩된 경로·쿠키·CSRF 헤더를 확인했다.
이 로컬 검사에서는 TLS·ACME·njs를 테스트용 구성으로 대체했다. 해당 모듈은 `scripts/check-nginx.py`로 별도 검증한다.
Docker는 재시작하지 않았다. live와 mock의 부팅 스크립트는 개발 출처 두 개를 포함해도 16KiB 이내다.

```sh
TEST_NGINX_BINARY=/absolute/path/to/nginx python3 -m unittest discover -s tests -p test_api_cors.py -v
```

- [Nginx 응답 헤더와 상속](https://nginx.org/en/docs/http/ngx_http_headers_module.html)
- [MDN CORS와 인증 정보](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS)
- [Spring Security CSRF](https://docs.spring.io/spring-security/reference/servlet/exploits/csrf.html)

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
3. Nginx 설정을 검사하고 웹 서버를 시작한다. ACME 모듈이 HTTP-01로 인증서를 발급한다.
4. 게시 작업이 해당 EC2의 실제 SSM 설정 실행 성공을 기다린다.
5. 로컬에서 `npm ci --include=dev`, `npm run check`와 선택 모드의 빌드를 실행한다. live는 `npm run build`, mock은 `npm run build:demo`를 사용한다.
6. 소스맵을 제외한 압축 파일을 S3에 올린다. MSW 실행 파일은 mock 모드에서만 포함한다.
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

EC2·루트 디스크·Nginx 인증서·정적 파일·S3 배포 압축 파일과 관련 인프라를 삭제한다.
DuckDNS의 등록 이름과 외부에서 저장한 SSM 토큰은 Terraform state에 포함하지 않는다.
사용을 마치면 DuckDNS IP 기록을 비우고 [프로젝트 토큰 정리](teardown.md#4-별도-등록한-토큰-삭제)를 진행한다.
다시 생성할 때는 토큰을 재등록하고 새 계획을 만든다.

## 근거

- [DuckDNS 갱신 API](https://www.duckdns.org/spec.jsp)
- [Nginx 자동 HTTPS 조건](https://nginx.org/en/docs/http/ngx_http_acme_module.html)
- [Nginx 1.30.6 공식 릴리스](https://nginx.org/en/download.html)

## 실제 적용 기록 (이전 웹서버 구성)

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

같은 날 EC2 `i-0fcecee1a11a6647b`와 공인 IP `15.165.75.174`로 다시 배포했다.
당시 `frontend_api_mode = "mock"`을 사용했다. 테스트 계정의 원문은 Git 제외 환경 파일에 보관한다.
서버에는 Parameter Store의 bcrypt 해시만 전달한다. 브라우저 빌드에 비밀번호가 없는 것을 확인했다.
실제 `/api/test-login`에서 올바른 비밀번호 200과 잘못된 비밀번호 401을 확인했다.
공개 사이트에서 로그인한 뒤 새로고침해도 사장님 대시보드가 유지되는 것을 확인했다.


## Nginx 전환

2026-10-22 사용자 요청으로 Caddy를 Nginx로 교체했다.
위 실제 적용 기록은 이전 웹서버에 대한 이력이다. Nginx의 AWS 적용 기록은 아니다.
일반 API는 이미지 연결 전 503을 반환한다. 이미지 연결 후 `host.docker.internal:8081`로 중계한다.
프록시에서 요청 경로·쿼리·인증·쿠키를 전달한다. 응답 버퍼링을 꺼 SSE를 전달한다.
테스트 로그인은 njs 콘텐츠 단계 전에 auth_basic으로 검사한다. 잘못된 계정은 JSON 401을 반환한다.
인증서 발급에는 DuckDNS가 현재 공인 IP를 가리키고 외부 TCP 80이 열려 있어야 한다.


### AWS 적용 전 검증 기록

Terraform 검증과 모의 테스트 25개를 통과했다.
Python 테스트 43개와 Node 테스트 12개를 통과했다.
부팅 스크립트 다섯 구성의 셸·내장 Python 구문과 16KiB 제한을 확인했다.
공식 `nginx:1.30.6` 이미지의 ARM64·AMD64 매니페스트를 확인했다.
새 AWS 계획은 빈 state 기준 생성 59개, 변경·삭제 0개다. 적용하지 않았다.
로컬 Docker 데몬이 응답하지 않아 실제 Nginx 실행 검증은 진행하지 못했다.
사용자 요청에 따라 Docker를 재시작하지 않는다.
실제 HTTP·TLS·bcrypt 로그인·API 프록시 동작과 ACME 인증서 발급은 아직 검증 전이다.

Docker가 정상인 환경에서는 다음 명령으로 격리된 로컬 검증을 실행한다.
테스트 인증서는 테스트 연결에서만 신뢰한다. 실제 도메인·토큰·AWS 리소스에는 접근하지 않는다.

```sh
python3 scripts/check-nginx.py
```

### 2026-10-22 실제 Nginx 적용

EC2 `i-0870c4a9e10cebd94`에 공식 Debian `nginx:1.30.6`을 배포했다.
계정에서 허용한 `c7i-flex.large`·AMD64·4GiB를 사용한다. 배치 영역은 `ap-northeast-2b`다.
서버의 `nginx -t`와 Nginx 서비스 상태 검사를 통과했다.
ACME 모듈이 Let's Encrypt 운영 인증서를 발급했다. 공개 HTTPS 연결에서 인증서 검증을 통과했다.
Frontend typecheck·lint·테스트 37개·live 빌드와 Terraform의 게시 검증을 통과했다.
`/`와 `/login`은 200, 없는 정적 파일은 404, HTTP 요청은 HTTPS 308을 반환했다.
앱 이미지가 없는 live 모드의 `/api/health`는 503을 반환했다.
이번 적용에서는 bcrypt 로그인과 실제 앱 API 프록시를 실행 검증하지 않았다.
로컬 Docker는 재시작하지 않았다.
