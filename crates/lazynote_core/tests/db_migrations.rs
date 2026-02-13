use lazynote_core::db::migrations::latest_version;
use lazynote_core::db::{open_db, open_db_in_memory, DbError};
use rusqlite::Connection;
use uuid::Uuid;

#[test]
fn open_db_in_memory_applies_all_migrations() {
    let conn = open_db_in_memory().unwrap();

    assert_eq!(schema_version(&conn), latest_version());
    assert_table_exists(&conn, "atoms");
    assert_table_exists(&conn, "tags");
    assert_table_exists(&conn, "atom_tags");
    assert_table_exists(&conn, "external_mappings");
}

#[test]
fn opening_same_database_twice_is_idempotent() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("lazynote.db");

    let conn_first = open_db(&path).unwrap();
    assert_eq!(schema_version(&conn_first), latest_version());
    drop(conn_first);

    let conn_second = open_db(&path).unwrap();
    assert_eq!(schema_version(&conn_second), latest_version());
    assert_table_exists(&conn_second, "atoms");
}

#[test]
fn opening_database_with_newer_schema_version_returns_error() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("future.db");

    let conn = Connection::open(&path).unwrap();
    conn.execute_batch("PRAGMA user_version = 999;").unwrap();
    drop(conn);

    let err = open_db(&path).unwrap_err();
    match err {
        DbError::UnsupportedSchemaVersion {
            db_version,
            latest_supported,
        } => {
            assert_eq!(db_version, 999);
            assert_eq!(latest_supported, latest_version());
        }
        other => panic!("unexpected error: {other}"),
    }
}

#[test]
fn migration_fails_on_schema_drift_without_advancing_version() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("drift.db");

    let conn = Connection::open(&path).unwrap();
    conn.execute_batch(
        "CREATE TABLE atoms (
            uuid TEXT PRIMARY KEY NOT NULL,
            type TEXT NOT NULL,
            content TEXT NOT NULL
        );",
    )
    .unwrap();
    drop(conn);

    let err = open_db(&path).unwrap_err();
    assert!(matches!(err, DbError::Sqlite(_)));

    let conn = Connection::open(&path).unwrap();
    assert_eq!(schema_version(&conn), 0);
}

#[test]
fn atoms_reject_invalid_event_window() {
    let conn = open_db_in_memory().unwrap();

    let result = conn.execute(
        "INSERT INTO atoms (uuid, type, content, event_start, event_end)
         VALUES (?1, 'event', 'invalid', 200, 100);",
        [Uuid::new_v4().to_string()],
    );

    assert!(result.is_err());
}

#[test]
fn deleting_atom_cascades_atom_tags() {
    let conn = open_db_in_memory().unwrap();
    let atom_id = Uuid::new_v4().to_string();

    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'note', 'hello');",
        [atom_id.as_str()],
    )
    .unwrap();
    conn.execute("INSERT INTO tags (name) VALUES ('work');", [])
        .unwrap();
    let tag_id = conn.last_insert_rowid();

    conn.execute(
        "INSERT INTO atom_tags (atom_uuid, tag_id) VALUES (?1, ?2);",
        rusqlite::params![atom_id, tag_id],
    )
    .unwrap();
    conn.execute("DELETE FROM atoms WHERE uuid = ?1;", [atom_id.as_str()])
        .unwrap();

    let link_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM atom_tags WHERE atom_uuid = ?1;",
            [atom_id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(link_count, 0);
}

#[test]
fn external_mappings_enforce_unique_provider_external_id() {
    let conn = open_db_in_memory().unwrap();
    let atom_a = Uuid::new_v4().to_string();
    let atom_b = Uuid::new_v4().to_string();

    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'event', 'a');",
        [atom_a.as_str()],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'event', 'b');",
        [atom_b.as_str()],
    )
    .unwrap();

    conn.execute(
        "INSERT INTO external_mappings (provider, external_id, atom_uuid)
         VALUES ('gcal', 'event-1', ?1);",
        [atom_a.as_str()],
    )
    .unwrap();

    let duplicate = conn.execute(
        "INSERT INTO external_mappings (provider, external_id, atom_uuid)
         VALUES ('gcal', 'event-1', ?1);",
        [atom_b.as_str()],
    );

    assert!(duplicate.is_err());
}

fn schema_version(conn: &Connection) -> u32 {
    conn.query_row("PRAGMA user_version;", [], |row| row.get(0))
        .unwrap()
}

fn assert_table_exists(conn: &Connection, table_name: &str) {
    let exists: i64 = conn
        .query_row(
            "SELECT EXISTS(
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = ?1
            );",
            [table_name],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(exists, 1, "table {table_name} does not exist");
}
