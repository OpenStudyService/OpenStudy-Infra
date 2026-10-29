# AWS Terraform 실제 적용 검증

## 대상과 범위

2026-10-29 서울 리전의 OpenStudy AWS 계정에서 빈 Terraform state를 기준으로 검증했다.
검증 전 RDS와 OpenStudy EC2는 없었다. 기존 앱·마이그레이션 SecureString 두 개는 유지한다.
비용을 줄이기 위해 검증 후 이번에 만든 리소스를 정리한다.

예산 프로필에서 EC2, ECS, RDS와 운영 스케줄을 사용했다.
DuckDNS 토큰이 없어 웹 배포는 끄고 검증했다. Gateway·Backend 이미지는 지정하지 않았다.
실제 웹, API, HTTPS와 Backend 컨테이너 배포는 이번 검증에 포함하지 않는다.

## 적용과 확인

- 첫 Terraform 계획: 생성 43개, 변경·삭제 0개. 실제 적용 성공.
- RDS MySQL은 `available`, Single-AZ였다. ECS 클러스터는 `ACTIVE`, 연결된 EC2 호스트는 1개였다.
- SSM 서버 구성은 `Success`였다.
- 사전 준비한 SecureString을 사용해 전용 마이그레이션 계정과 앱 계정을 만들었다.
- 계정 생성에 사용한 임시 IAM 권한은 작업 후 제거했다.
- 마이그레이션 계획: 생성 9개, 변경·삭제 0개. 실제 Terraform 적용과 SSM Flyway 실행이 성공했다.
- 실제 RDS에서 Flyway V1 성공 이력과 업무·세션 테이블 65개 및 이력 테이블 1개를 확인했다.
- 앱 계정으로 SELECT, INSERT, UPDATE, DELETE를 수행했다. CREATE TABLE은 권한 부족으로 거부됐다.
- RDS 인증서와 호스트 이름을 확인하는 TLS 접속을 사용했다. 검증용 임시 테이블과 IAM 권한을 제거했다.
- 동일한 Terraform 설정으로 다시 계획한 결과 `No changes`였다.

## 정리 상태

검증 후 RDS 삭제 보호를 해제하고 Terraform 정리 계획을 확인했다.
실제 적용 결과는 생성·변경 0개, 삭제 52개다. RDS 목록은 비었고 검증용 EC2는 terminated 상태다.
RDS가 만든 관리자 시크릿은 삭제됐다. 기존 앱·마이그레이션 SecureString 두 개는 보존했다.
AWS 계정은 무료 플랜 ACTIVE로 조회됐다. 청구액은 지연될 수 있어 최종 비용은 확인하지 못했다.

## 스크린샷

브라우저에서 실제 명령 결과 화면을 캡처해 확인했다. 파일 첨부는 화면 캡처 권한과 브라우저 보안 정책의 제약으로 보류했다.
