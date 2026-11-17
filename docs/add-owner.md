# OWNER 추가

V23부터 여러 OWNER를 허용한다. 기존 계정은 유지한다. 이메일은 계속 고유해야 한다.
운영 Backend의 `SPRING_FLYWAY_ENABLED=false`를 유지하고 Infra Flyway로 V23을 적용한다.
Backend의 최초 `OwnerBootstrap`은 그대로 사용한다. 이 명령은 OWNER가 있으면 추가하지 않는다.

추가 계정은 [AddOwner.java](../scripts/AddOwner.java)로 생성한다. 공개 API는 만들지 않는다.
실행 전에 기존 OWNER가 ACTIVE인지 확인한다. 이름, 이메일, 비밀번호를 준비한다.
비밀번호는 8자 이상, UTF-8 72바이트 이하여야 한다.

1. 배포한 Backend JAR의 `BOOT-INF/lib/spring-security-crypto-*.jar`를 추출한다.
2. Java 21로 `javac --release 21 -cp <crypto.jar> -d <classes> scripts/AddOwner.java`를 실행한다.
3. 같은 Backend JAR과 컴파일한 클래스를 격리 컨테이너에 읽기 전용으로 제공한다.
4. `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `OWNER_EMAIL`, `OWNER_NAME`, `OWNER_PASSWORD`를 비밀 저장소에서 환경으로 전달한다. 인수, 명령 본문, 로그에 비밀값을 넣지 않는다.
5. 앱 DML 계정과 `sslMode=VERIFY_IDENTITY` RDS 연결을 사용한다. `java -cp /app/app.jar -Dloader.path=<classes> -Dloader.main=AddOwner org.springframework.boot.loader.launch.PropertiesLauncher`를 실행한다.
6. 새 계정과 기존 OWNER의 로그인 및 OWNER 전용 API 접근을 확인한다. 새 계정으로 로그인·세션 E2E를 실행한다. 임시 비밀값과 임시 IAM 권한을 제거한다.

클래스 디렉터리는 컨테이너 사용자에게 탐색 권한을, 클래스 파일은 읽기 권한을 준다.
예를 들어 비밀값이 없는 클래스 디렉터리는 755, `.class` 파일은 644로 설정한다.
비밀 설정 파일은 별도로 보관하고 600 권한을 유지한다.

명령은 관리자 가드를 잠근 뒤 계정을 추가한다. BCrypt 비용 12로 비밀번호를 저장한다.
기존 이메일이 있으면 실패한다. 기존 계정의 이메일·권한·비밀번호를 바꾸지 않는다.
계정과 `OWNER_ADDED` 감사 이벤트는 같은 트랜잭션으로 저장한다. 실패하면 둘 다 취소한다.

격리 검증은 `python3 tests/check_add_owner.py --backend-jar <backend.jar> --classes <classes>`로 실행한다.
Docker MySQL에서 이전 스키마 거부, 두 OWNER 공존, 기존 계정 보존, 중복 이메일 거부,
비밀번호 검증, 감사 기록 실패 시 롤백, 활성 OWNER 부재와 관리자 가드 부재를 확인한다.
`scripts/check-database.py`는 새 DB 및 V22 덤프의 V23 업그레이드와 재실행을 검증한다.

이전 단일 OWNER 정책으로 되돌리려면 별도 계정 정리 결정을 먼저 받아야 한다.
추가 OWNER가 있는 상태에서 고유 인덱스를 다시 만들지 않는다.
기존 V1과 V23 체크섬을 바꾸거나 Flyway `repair`로 이력을 덮어쓰지 않는다.
