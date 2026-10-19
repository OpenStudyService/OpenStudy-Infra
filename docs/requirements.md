# 요구조건과 검증 상태

[README로 돌아가기](../README.md)

## 현재 범위

Terraform으로 AWS와 SSM 서버 설정을 관리한다.
DuckDNS는 EC2 공인 IP를 자동 반영한다. Cloudflare는 수동 설정한다.
필요할 때 생성하고 사용 후 AWS 리소스와 저장 데이터를 모두 삭제한다.

| ID | 구성 | 상태 |
| --- | --- | --- |
| INF-NET-01 | `openstudy.duckdns.org`에 EC2 공인 IP 자동 반영 | 삭제 전 실환경 DNS와 EC2 공인 IP 일치 확인 |
| INF-NET-02 | CloudFront 정적 HTTPS·EC2 API 원본 TLS | 정적 HTTPS 코드·모의 테스트 완료, API 원본 TLS 후속 |
| INF-NET-03 | cloudflared 설치와 수동 Tunnel 연결 | 서버 코드 준비·연결 전 |
| INF-NET-04 | Cloudflare WAF·요청 제한 | 연결 조건 확인 필요 |
| INF-NET-05 | 기본 인바운드 차단·선택한 80·443 허용·Session Manager | 코드·모의 테스트 완료 |
| INF-SRV-01 | `t4g.small`·gp3 8GiB | 생성·전체 삭제 검증 완료·계정 혜택 별도 확인 |
| INF-SRV-02 | Docker·스왑 1GiB | 삭제 전 SSM 설정 성공·컨테이너 배포 전 |
| INF-SRV-03 | 보안 업데이트·Asia/Seoul·시간 동기화 | SSM 설정 성공·재부팅 검증 남음 |

DNS는 사용자 요청에 따라 DuckDNS로 구성한다. 관리 접속은 SSH 대신 Session Manager를 사용한다.
INF-NET-04와 INF-SRV-03은 [원문 명세](https://docs.google.com/document/d/1RMxQHpqLZzPtN-OPuPSDGE3THKxtgHXNu4XbcZmbFSA/edit?tab=t.0)의 권장 항목이다.

## 추가 배포 범위

[Frontend](https://github.com/OpenStudyService/OpenStudy-Frontend)의 React·Vite 정적 빌드는 S3·CloudFront로 제공하도록 설계한다.
[Backend](https://github.com/OpenStudyService/OpenStudy-Backend)는 GitHub Actions에서 ARM64 OCI 이미지를 빌드해 ECR에 저장하고 EC2에서 실행하도록 설계한다.
Frontend의 S3·CloudFront·OIDC 역할과 Actions 워크플로 코드를 추가했다.
실제 생성·배포와 Backend 연결은 [Frontend 배포 순서](frontend-deployment.md)를 따른다.
Backend ECR·OCI 배포 워크플로는 아직 구현하지 않았다.
구현 순서는 [배포 설계](deployment.md)를 따른다.

## 로컬 검증

2026-10-19에 AWS 모의 테스트 8개, 이전 Cloudflare 예제 테스트 5개와 Python 테스트 9개를 통과했다.
Frontend Terraform 모의 테스트 5개와 SPA 경로 테스트 3개도 통과했다.
Frontend 저장소의 검사·live 빌드와 배포 절차 테스트 3개를 통과했다. 실제 AWS 정적 웹 배포는 아직 실행하지 않았다.
ARM·x86 초기 설정의 Bash·Python 구문과 user data 크기 검사도 통과했다.
SSM 설정 전달과 설치 버전 변경 시 기존 EC2 보존도 검사했다.
모의 테스트 통과는 실제 배포 성공을 뜻하지 않는다.

2026-10-19에 Terraform 적용으로 SSM 문서·실행 연결·IAM 정책을 추가했다.
기존 EC2를 유지했고, SSM 실행의 `Success` 상태와 종료 코드 0을 확인했다.
DuckDNS의 A 레코드와 EC2 공인 IPv4가 일치하는 것도 확인했다.

같은 날 사용 종료 후 Terraform 관리 리소스 15개를 삭제했다.
현재 Terraform state에는 관리 리소스가 없다.
EC2 루트 EBS와 별도 등록한 DuckDNS 토큰도 삭제했다.
사용 가능한 AWS 리전 17개를 확인했다.
S3 버킷, RDS·Aurora, DynamoDB, EBS와 관련 스냅샷·백업은 남아 있지 않았다.

```sh
./scripts/validate.sh
```

## 다음 순서

1. [구축 절차](setup.md)로 AWS·DuckDNS 실제 연결을 확인한다.
2. Frontend 정적 호스팅을 생성·배포한다. Backend OCI·ECR 배포는 후속 구현한다.
3. `/api/*` 원본 HTTPS·세션·CSRF·SSE와 외부 포트 차단을 확인한다.
4. [Cloudflare 연결 조건](cloudflare-manual.md)을 확인하고 수동 설정한다.
5. [GitOps 자동 배포](gitops.md)를 구현한다.
6. 사용을 마치면 [AWS 전체 정리](teardown.md)로 리소스와 저장 데이터를 삭제한다.
