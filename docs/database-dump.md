# 로컬 DB 덤프 검증

[DB 배포 안내](database.md) · [E2E PR #11](https://github.com/OpenStudyService/OpenStudy-Infra/pull/11)

## 목적

동료가 제공한 `openstudy` mysqldump를 배포 전 확인한다.
원본 덤프는 로컬에 보관한다. Git과 CI 첨부 파일에 올리지 않는다.
덤프에는 직원·고객 정보, 비밀번호 해시, 세션, 인증 관련 데이터가 들어갈 수 있다.
현재 검증은 MySQL 8.4.11을 사용한다.

## 실행

Docker와 OpenSSL이 필요하다. 저장소 루트에서 실행한다.

```sh
python3 scripts/check-database.py \
  --dump-file /absolute/path/to/openstudy-dump.sql \
  --report artifacts/database/dump-validation.json
```

보고서 경로는 아직 없는 파일을 지정한다. 보고서는 권한 600으로 생성한다.
테이블별 행 수, 외래키 검사 수, Flyway 검증 결과, 원본 SHA-256만 기록한다.
직원 이메일, 비밀번호 해시, 세션 값, 고객 레코드는 출력하지 않는다.
`*-dump.sql`과 `artifacts/database/`는 Git에서 제외한다.

새 스키마 생성도 별도로 검증할 수 있다.

```sh
python3 scripts/check-database.py --report artifacts/database/fresh-validation.json
```

## 격리와 원본 보존

- 실행할 때마다 새 MySQL 컨테이너를 만든다. 외부 포트를 열지 않는다.
- 내부 전용 Docker 네트워크와 임시 메모리 DB를 사용한다.
- 기존 DB 주소를 입력하는 옵션은 없다. AWS API는 호출하지 않는다.
- 원본은 읽기 전용으로 읽는다. UTF-8 변환 없이 바이너리 값을 전달한다.
- 복원 계정은 임시 `openstudy` DB 권한만 가진다. FILE·전역 관리·루틴 생성 권한은 없다.
- MySQL 클라이언트는 `--binary-mode`, `--local-infile=0`, `--skip-reconnect`를 사용한다.
- 서버도 파일 가져오기를 끈다. 덤프 오류는 오류 번호와 줄 번호만 출력한다.
- 검증 후 컨테이너와 네트워크를 삭제한다. 다운로드한 이미지는 남는다.

덤프의 표준 `/*!50013 DEFINER=... SQL SECURITY DEFINER */` 줄은 임시 입력에서만 `SQL SECURITY INVOKER`로 바꾼다.
이는 원래 PC의 `openstudy_app@localhost` 계정을 복사하지 않고 뷰를 검사하기 위한 로컬 처리다.
원본 파일은 바뀌지 않는다. 이 처리를 운영 DB 복원 절차로 사용하지 않는다.
뷰 생성 권한과 클라이언트 동작은 [MySQL CREATE VIEW](https://dev.mysql.com/doc/refman/8.4/en/create-view.html)와 [클라이언트 옵션](https://dev.mysql.com/doc/refman/8.4/en/mysql-command-options.html)을 따른다.

## 검증 범위

복원 후 Flyway가 V1~V22의 체크섬과 성공 이력을 검사한다.
`migrate`를 두 번 실행해 모두 추가 적용이 0건인지 확인한다.
테이블 81개와 뷰 1개를 확인한다. 뷰 조회와 모든 외래키의 끊어진 참조도 검사한다.
앱 계정의 DDL 거부, 잘못된 TLS 인증서·호스트 이름 거부, 기존 V1 변경 거부도 확인한다.
외래키 검사는 mysqldump의 `FOREIGN_KEY_CHECKS=0` 때문에 필요한 별도 검사다.
Flyway 이력 검증은 임의의 수동 스키마 변경이나 업무 데이터의 정확성을 보장하지 않는다.

## 배포와 로그인 테스트

이 검증은 데이터의 운영 반영이나 실제 앱 로그인 테스트를 실행하지 않는다.
실제 DB에 복원하려면 대상 DB, 백업, 기존 데이터 처리, 세션·토큰 제거, 뷰 실행 계정을 별도로 정한다.
운영에 존재하는 테이블에 원본 덤프를 바로 적용하지 않는다. 덤프에는 `DROP TABLE`이 포함된다.
덤프는 비밀번호 원문을 제공하지 않는다. 저장된 세션이나 해시를 로그인에 재사용하지 않는다.
Playwright의 로그인·세션 검증에는 별도로 준비한 테스트 계정의 이메일과 비밀번호가 필요하다.
앱을 기동하면 예약 작업이 실행될 수 있으므로 `--dump-file`과 `--backend-jar`는 함께 사용할 수 없다.
