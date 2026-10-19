# Cloudflare 추가 설정 순서

[README로 돌아가기](../README.md)

현재 경로는 `openstudy.duckdns.org → EC2 공인 IP`이다.
이 설정만으로 Cloudflare HTTPS·WAF·Tunnel이 연결되지는 않는다.
Cloudflare는 수동 설정한다. `terraform/cloudflare`는 현재 적용하지 않는다.

## 1. 호스트명 연결 조건 확인

먼저 DuckDNS 호스트명을 받을 수 있는 Cloudflare 연결 방식을 확정한다.
Cloudflare for SaaS를 검토한다면 제공자 측 Cloudflare zone이 필요하다.
DuckDNS에서 필요한 DNS 설정과 소유권·인증서 검증이 가능한지도 확인한다.
현재는 이 조건을 확인하지 않은 상태다.

조건을 충족한 뒤 아래 순서로 진행한다.
세부 조건은 [공식 구성 안내](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/)를 따른다.

## 2. Tunnel 생성

1. Cloudflare 대시보드의 Tunnels에서 `openstudy-prod`를 생성한다.
2. cloudflared 실행 토큰을 확인한다.
3. Backend 연결 대상을 `http://127.0.0.1:8080`으로 설정한다.

EC2에는 cloudflared가 설치되어 있으므로 설치 명령을 중복 실행하지 않는다.

## 3. Tunnel 토큰 저장

저장소 루트에서 파라미터 이름을 확인한다.

```sh
terraform -chdir=terraform/aws output -raw tunnel_token_parameter_name
```

AWS Parameter Store에 위 이름으로 Standard 등급의 SecureString을 생성한다.
기본 SSM 키를 사용하고 값에는 Tunnel 토큰만 넣는다.
기본 경로는 `/openstudy-prod/cloudflared/token`이다. DuckDNS 토큰과 구분한다.

## 4. 연결 확인

EC2에서 실행한다.

```sh
sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager
```

대시보드에서 Tunnel의 Healthy 상태를 확인한다.
그다음 공개 호스트명, HTTPS 인증서와 WAF 적용을 확인한다.
Backend를 아직 배포하지 않았다면 정상 웹 응답 확인은 후속 작업으로 남긴다.
