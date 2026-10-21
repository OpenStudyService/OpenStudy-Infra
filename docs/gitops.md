# GitOps 배포 순서

[README로 돌아가기](../README.md)

Backend는 Git의 배포 설정과 Amazon ECR 이미지를 서버가 가져오는 방식을 사용한다.
Frontend의 기본 경로는 DuckDNS → EC2 Caddy → 정적 파일이다.
`terraform/aws apply`가 검사·live 빌드·비공개 S3 압축 파일 전달·SSM 게시를 실행한다.
실행 절차는 [DuckDNS 정적 웹 배포](duckdns-frontend.md)를 따른다.
S3·CloudFront는 별도 선택 경로다. [자동 배포 순서](frontend-deployment.md)에 따라 로컬 Terraform 게시 또는 Actions를 사용한다.
Backend의 [배포 설계](deployment.md)에 해당하는 ECR·Actions·Compose·동기화 코드는 후속 작업으로 구현한다.
Terraform 생성·SSM 설정·정적 게시·OCI 배포·전체 삭제의 관계는 [통합 아키텍처](deployment.md#1-통합-아키텍처)에서 확인한다.

## 1. 인프라 준비

[구축 절차](setup.md)로 EC2와 `openstudy.duckdns.org` 연결을 먼저 구성한다.
Terraform은 인프라와 SSM을 통한 서버 설정을 관리한다.
GitOps는 애플리케이션 배포를 관리한다.

## 2. 애플리케이션 배포

1. 애플리케이션 저장소에서 테스트를 통과한 소스를 병합한다.
2. GitHub Actions가 Backend의 OCI 이미지를 빌드한다. `t4g.small`은 `linux/arm64`를 사용한다.
3. GitHub OIDC로 AWS 역할을 사용한다. 커밋 SHA 태그로 Private ECR에 push한다.
4. OpenStudy-Infra의 Compose 설정에서 해당 이미지 digest를 변경한다.
5. 서버가 변경한 설정을 가져와 검증한다. EC2 IAM Role로 ECR 이미지를 내려받는다.
6. 컨테이너를 갱신하고 헬스체크를 확인한다.
7. 성공한 배포 커밋을 기록한다.

이미지 다운로드와 설정 검증이 끝난 뒤 컨테이너를 변경한다.
Frontend는 선택한 배포 경로의 검사·live 빌드를 통과해야 한다.
DuckDNS 경로는 압축 파일을 비공개 S3에 올린 뒤 SSM으로 EC2의 현재 릴리스 링크를 전환한다.
S3·CloudFront 경로는 정적 파일 게시 후 캐시를 갱신한다.
두 경로 모두 HTTPS 응답을 확인한다. 정적 릴리스와 Backend digest를 배포 이력에 남긴다.

## 3. 자동 동기화

- 작업 디렉터리는 `/opt/openstudy`를 사용한다.
- 서버 부팅 시와 운영 중 일정 간격으로 설정을 가져온다.
- 잠금을 사용해 두 배포가 동시에 실행되지 않게 한다.
- 컨테이너에 재시작 정책, 헬스체크와 로그 용량 제한을 설정한다.
- 비공개 저장소는 읽기 전용 인증으로 접근한다.

## 4. 접속과 비밀값

서버 관리는 Session Manager를 사용한다. Backend와 DB의 내부 포트는 외부에 공개하지 않는다.
DuckDNS 경로의 `/api`와 `/api/*`는 현재 JSON 503을 반환한다. Backend 연결 시 Caddy의 API 프록시와 세션·CSRF·SSE를 검증한다.
S3·CloudFront 경로를 선택하면 `/api/*`를 Backend HTTPS 원본에 연결한다. 원본 인증서와 접근 허용 규칙을 별도로 구성한다.
Cloudflare 추가 연결은 [수동 설정](cloudflare-manual.md)의 연결 조건을 먼저 확인한다.

애플리케이션 비밀값은 `/etc/openstudy` 아래 접근 권한을 제한한 파일에 저장한다.
DuckDNS·Tunnel 토큰은 서로 다른 Parameter Store SecureString에 저장한다.
실제 비밀값은 Git, Terraform 변수와 로그에 기록하지 않는다.

## 5. 이전 버전 복구

1. 마지막 정상 배포 커밋, ECR digest와 Frontend 릴리스 버전을 확인한다.
2. 문제를 만든 설정 커밋을 `git revert`로 되돌리고 병합한다.
3. 서버 동기화 후 헬스체크와 실제 요청을 확인한다.

DB 변경은 별도 복구 절차를 사용한다. 이미지 복구만으로 DB가 복구되지는 않는다.

## 6. 사용 후 정리

현재 환경은 사용 후 [AWS 전체 정리](teardown.md)로 리소스와 저장 데이터를 모두 삭제한다.
DuckDNS 경로의 EC2·정적 파일·인증서·배포용 S3는 `terraform/aws`에서 삭제한다.
선택한 S3·CloudFront 구성은 `terraform/frontend`에서 별도로 삭제한다.
후속 ECR과 프로젝트 배포 역할도 같은 삭제 범위에 포함한다.
다음 실행에서는 인프라와 애플리케이션을 새로 구성한다. 이전 DB 내용은 복구하지 않는다.
