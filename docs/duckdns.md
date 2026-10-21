# DuckDNS 운영과 오류 해결

[README로 돌아가기](../README.md)

최초 설정은 [구축 절차의 1~7단계](setup.md)를 따른다.
Terraform이 갱신 서비스를 설치하고, 서버가 DuckDNS API로 공인 IP를 반영한다.
정적 웹페이지를 이 주소의 HTTPS로 제공하려면 [DuckDNS 정적 웹 배포](duckdns-frontend.md)를 따른다.

## 1. 갱신 상태 확인

Session Manager로 EC2에 접속한 뒤 실행한다.

```sh
sudo systemctl status openstudy-duckdns.timer --no-pager
sudo journalctl -u openstudy-duckdns.service --since '-30 min' --no-pager
```

| 로그 | 의미와 조치 |
| --- | --- |
| `updated` | IP 갱신을 완료했다. |
| `unchanged` | 마지막 성공 IP와 같아서 요청을 생략했다. |
| `blocked` | 호스트명 소유권과 토큰을 확인한 뒤 2단계를 진행한다. |
| `retry`·`deferred` | 일시 오류로 대기한다. 최소 30분 뒤 다시 시도한다. |
| `update failed` | 토큰 저장 경로·리전과 EC2 권한을 확인한다. |

다른 PC나 공유기의 갱신 프로그램이 같은 주소를 덮어쓰지 않게 한다.

## 2. 토큰 변경

1. AWS Parameter Store의 기존 DuckDNS 파라미터를 선택한다.
2. 본인 계정의 올바른 토큰으로 값을 저장해 새 버전을 만든다.
3. EC2에서 아래 명령을 실행한다.

```sh
sudo systemctl start openstudy-duckdns.service
```

새 파라미터 버전을 감지하면 갱신을 다시 시도한다.
토큰은 Git, Terraform 변수와 채팅에 기록하지 않는다.

## 3. 자동 갱신 중지

로컬 `terraform/aws/terraform.tfvars`에 `enable_duckdns = false`를 설정한다.
DuckDNS 정적 웹을 사용 중이면 `enable_frontend = false`도 함께 설정한다.
저장소 루트에서 계획을 확인하고 적용한다.

```sh
terraform -chdir=terraform/aws plan -out=aws.tfplan
terraform -chdir=terraform/aws apply aws.tfplan
```

SSM이 기존 서버의 타이머를 중지한다. EC2는 유지한다.

API 형식은 [DuckDNS 공식 명세](https://www.duckdns.org/spec.jsp)를 따른다.
