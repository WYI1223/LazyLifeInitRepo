use lazynote_core::db::migrations::latest_version;
use lazynote_core::db::{open_db, open_db_in_memory, DbError};
use rusqlite::Connection;

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
