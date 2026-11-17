import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.Locale;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/** Offline addition after V23. Never replaces or promotes an existing account. */
public final class AddOwner {
    public static void main(String[] args) {
        try {
            add();
        } catch (Exception failure) {
            // JDBC and validation exceptions can contain credentials. Keep output fixed.
            System.err.println("OWNER addition rejected; no account changes committed. Check schema, guard and email conflict.");
            System.exit(1);
        }
    }

    private static String required(String key) {
        String value = System.getenv(key);
        if (value == null || value.isBlank()) throw new IllegalArgumentException();
        return value;
    }

    private static void add() throws Exception {
        String email = required("OWNER_EMAIL").strip().toLowerCase(Locale.ROOT);
        String name = required("OWNER_NAME").strip();
        String password = required("OWNER_PASSWORD");
        if (email.length() > 254 || !email.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
                || name.codePointCount(0, name.length()) > 100
                || password.codePointCount(0, password.length()) < 8
                || password.getBytes(StandardCharsets.UTF_8).length > 72) throw new IllegalArgumentException();
        String hash = new BCryptPasswordEncoder(12).encode(password);
        try (Connection db = DriverManager.getConnection(required("DB_URL"), required("DB_USERNAME"), required("DB_PASSWORD"))) {
            db.setAutoCommit(false);
            try {
                try (var query = db.prepareStatement("SELECT id FROM administration_guard WHERE id=1 FOR UPDATE");
                        var rows = query.executeQuery()) {
                    if (!rows.next()) throw new IllegalStateException();
                }
                try (var query = db.prepareStatement("SELECT COUNT(*) FROM information_schema.statistics "
                        + "WHERE table_schema=DATABASE() AND table_name='employees' AND column_name='owner_slot' AND non_unique=0");
                        var rows = query.executeQuery()) {
                    if (!rows.next() || rows.getLong(1) != 0) throw new IllegalStateException();
                }
                boolean activeOwner = false;
                try (var query = db.prepareStatement("SELECT global_role,status FROM employees ORDER BY id FOR UPDATE");
                        var rows = query.executeQuery()) {
                    while (rows.next()) activeOwner |= "OWNER".equals(rows.getString(1)) && "ACTIVE".equals(rows.getString(2));
                }
                if (!activeOwner) throw new IllegalStateException();
                try (var query = db.prepareStatement("SELECT id FROM employees WHERE email=? FOR UPDATE")) {
                    query.setString(1, email);
                    try (var rows = query.executeQuery()) {
                        if (rows.next()) throw new IllegalStateException();
                    }
                }
                long id;
                try (var insert = db.prepareStatement("INSERT INTO employees "
                        + "(email,password_hash,name,nickname,global_role,status) VALUES (?,?,?,?,'OWNER','ACTIVE')",
                        Statement.RETURN_GENERATED_KEYS)) {
                    insert.setString(1, email);
                    insert.setString(2, hash);
                    insert.setString(3, name);
                    insert.setString(4, name);
                    if (insert.executeUpdate() != 1) throw new IllegalStateException();
                    try (var keys = insert.getGeneratedKeys()) {
                        if (!keys.next()) throw new IllegalStateException();
                        id = keys.getLong(1);
                    }
                }
                try (var audit = db.prepareStatement("INSERT INTO audit_events (entity_type,entity_id,action,reason) "
                        + "VALUES ('employee',?,'OWNER_ADDED','Explicit offline operator addition; existing accounts retained')")) {
                    audit.setLong(1, id);
                    if (audit.executeUpdate() != 1) throw new IllegalStateException();
                }
                db.commit();
                System.out.println("Additional OWNER created with audit event. Existing accounts retained.");
            } catch (Exception failure) {
                db.rollback();
                throw failure;
            }
        }
    }
}
