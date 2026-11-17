-- Explicitly approved on 2026-11-17: retain existing OWNER accounts and allow more.
-- The email unique key and application last-active-administrator guard remain.
ALTER TABLE employees DROP INDEX uk_employees_2;
