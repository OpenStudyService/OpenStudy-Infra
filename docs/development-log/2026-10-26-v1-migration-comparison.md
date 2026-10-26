# Infra·Backend V1 파일 대조

작업일: 2026-10-26 (Asia/Seoul).
관련 이슈: [Infra #1](https://github.com/OpenStudyService/OpenStudy-Infra/issues/1).

## 범위와 결정

V3 마이그레이션 준비의 첫 작업으로 두 V1 SQL 파일을 대조한다.
원문 파일을 유지하고 읽기 전용 비교 도구를 추가한다.
비교 도구는 파일 SHA-256과 줄바꿈 차이를 보고한다.
Flyway checksum을 대신 계산하거나 DB에 접속하지 않는다.
파일 대조만으로 운영 DB의 버전·호환성·업그레이드 완료를 판단하지 않는다.

## 현재 DB 상태의 근거

사용자는 2026-10-26에 AWS RDS의 실제 테이블 목록이 비어 있다고 알려 주었다.
이 정보는 사용자 확인 결과이며 이번 작업에서 에이전트가 DB에 접속해 검증한 결과는 아니다.
과거 배포 문서의 V1 적용 기록을 현재 RDS 상태로 단정하지 않는다.
다음 작업에서 RDS 접속 주소·DB 이름·조회 권한과 실제 테이블 목록을 먼저 확인한다.
대상 DB가 비어 있으면 기존 V1 데이터 업그레이드가 아니라 V1 → V2 → V3 초기 적용 경로를 사용한다.
`flyway_schema_history`는 Backend 전용 테이블이 아니다.
Flyway가 연결한 DB의 기본 스키마 안에 만드는 적용 이력이다.
[공식 이력 테이블 설명](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/flyway-schema-history-table)을 참고한다.

## 비교 대상

| 항목 | Infra | Backend |
| --- | --- | --- |
| 저장소 | `OpenStudyService/OpenStudy-Infra` | `OpenStudyService/OpenStudy-Backend` |
| 소스 커밋 | `238b6f528fa2d7f17cc30a6516f6172517898083` | `3484d1c6abd31f79377779b606d9b43767660544` |
| 파일 | `database/migrations/V1__initial_schema.sql` | `src/main/resources/db/migration/V1__init_schema.sql` |
| Git blob | `94f6515b56669462f01f0390806be36f6f7b84ed` | `5a33c953f1960faf427ac2cc9bca947e50f4ee58` |
| 원문 바이트 수 | 76,214 | 76,215 |
| 끝 줄바꿈 | 없음 | LF 1개 |
| SHA-256 | `26eaa832cbe5c069f4c3ec4a13abf3607696c683b6daacc3e2024052fbab232c` | `6de869b4c0500eea08fc08eb7d4d9a464b9aaa3261f7aaf3e2a8c78c0f22d17e` |

원문: [Infra V1](https://github.com/OpenStudyService/OpenStudy-Infra/blob/238b6f528fa2d7f17cc30a6516f6172517898083/database/migrations/V1__initial_schema.sql), [Backend V1](https://github.com/OpenStudyService/OpenStudy-Backend/blob/3484d1c6abd31f79377779b606d9b43767660544/src/main/resources/db/migration/V1__init_schema.sql).
Backend 로컬 파일의 Git blob이 위 원격 커밋의 파일 blob과 같은지 확인한 뒤 비교했다.
비교 기준은 로컬 Backend 브랜치의 오래된 HEAD가 아니라 위 원격 커밋의 V1 파일이다.

## 실행 결과

Infra 저장소 루트에서 다음 명령을 실행했다.
재현할 때는 위 커밋의 Backend V1 파일을 입력한다.

```sh
python3 scripts/compare-v1-migrations.py \
  database/migrations/V1__initial_schema.sql \
  ../OpenStudy-Backend/src/main/resources/db/migration/V1__init_schema.sql
```

- 종료 코드: `0`.
- 분류: `line_endings_only`.
- 원문 바이트는 다르다. Backend 파일의 마지막 주석 뒤에 LF(`0x0A`) 1바이트가 추가되어 있다.
- 마지막 LF를 제외한 모든 바이트는 같다. 그 밖의 SQL·주석·공백 차이는 없다.
- 두 V1 파일과 기존 배포·마이그레이션 설정은 수정하지 않았다.

### 파일 이름과 Flyway 이력

파일 이름은 `V1__initial_schema.sql`과 `V1__init_schema.sql`로 다르다.
Flyway 설명도 각각 `initial schema`와 `init schema`로 해석된다.
SQL 내용의 대조 결과와 별도로 실제 적용 이력과 파일 이름을 확인해야 한다.

원문 SHA-256은 파일 무결성 확인용이다.
Flyway의 SQL checksum은 CRC32이며 SHA-256과 직접 비교하지 않는다.
[공식 validate 문서](https://documentation.red-gate.com/flyway/reference/commands/validate)와 [DESCRIPTION_MISMATCH 설명](https://documentation.red-gate.com/flyway/reference/exit-codes-and-error-codes/validate-error-codes)을 참고한다.
이번 대조로 실제 DB에서 checksum 또는 description 불일치가 발생한다고 확정하지 않는다.
이 차이를 없애기 위한 V1 변경·파일명 변경·자동 repair는 수행하지 않는다.

## 검증

- 실제 V1 파일 대조: `line_endings_only`, 종료 코드 0.
- 별도 바이트 대조: `Backend 원문 == Infra 원문 + LF 1바이트`를 확인했다.
- 비교 도구의 CLI 테스트 5개가 통과했다. 원문 일치·끝 줄바꿈·CRLF/CR·내용 변경·파일 누락과 입력 파일 보존을 확인했다.
- Python 전체 검사: 53개 중 48개 통과, Nginx 실행 파일을 지정하지 않은 CORS 검사 5개 건너뜀.
- Node 검사: 12개 통과.
- Terraform 1.16.6: fmt·3개 스택 init/validate 통과. 모의 검사 44개 통과(AWS 31개, Cloudflare 5개, Frontend 8개).
- Bootstrap 구문·크기 검사: 6개 구성 통과.
- `git diff --check`: 통과.
- `./scripts/validate.sh`: 기본 Terraform 1.15.5로는 저장소의 고정 버전 조건 때문에 중단됐다. 공식 Terraform 1.16.6을 임시 경로에 받아 배포 SHA-256을 확인한 뒤 전체 검사를 다시 실행했다. 재실행은 종료 코드 0으로 완료됐다.
- 전체 검사에서 Nginx CORS 검사 5개는 동일하게 건너뛰었다. 실제 AWS·Cloudflare 적용이나 DB 시험으로 집계하지 않는다.

## 후속 작업

이 PR은 Infra #1 첫 인수 조건의 파일 대조 부분만 준비한다.
실제 RDS 이력과의 대조가 남아 있으므로 해당 인수 조건은 미완료로 유지한다.

- 운영 RDS 접속 주소·DB 이름·조회 권한과 실제 테이블 목록을 읽기 전용으로 확인한다. `flyway_schema_history`가 있으면 `version`, `description`, `script`, `checksum`, `success`도 조회한다.
- 실제 적용 파일·이력과 고정한 Backend V1~V3 파일의 대응을 기록한다.
- 마이그레이션 실행 주체와 필요한 계정·TLS·비밀값 주입 방식을 정한다.
- 대상 DB가 비어 있으면 빈 DB의 V1~V3 초기 적용을 검증한다. 기존 V1 데이터가 확인된 경우 수동 백업·별도 복구 시험과 V1 복제본의 V3 업그레이드 시험을 진행한다.
- 실제 운영 적용과 로그인·JDBC 세션·재기동 검증 결과를 별도로 기록한다.

운영 DB 조회, AWS 변경, 백업·복구, V2/V3 적용과 앱 인증 시험은 이번 작업에서 실행하지 않았다.
자동 백업 정책과 기존 예산·배포 대상은 유지한다.
