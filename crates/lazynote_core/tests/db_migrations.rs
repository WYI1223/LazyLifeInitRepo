use lazynote_core::db::migrations::{apply_migrations, latest_version};
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
    assert_column_exists(&conn, "atoms", "preview_text");
    assert_column_exists(&conn, "atoms", "preview_image");
    assert_column_exists(&conn, "atoms", "start_at");
    assert_column_exists(&conn, "atoms", "end_at");
    assert_column_exists(&conn, "atoms", "recurrence_rule");
}

#[test]
fn migrated_preview_columns_accept_read_write_values() {
    let conn = open_db_in_memory().unwrap();
    let atom_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content, preview_text, preview_image)
         VALUES (?1, 'note', 'body', 'summary', 'cover.png');",
        [atom_id.as_str()],
    )
    .unwrap();

    let loaded: (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT preview_text, preview_image FROM atoms WHERE uuid = ?1;",
            [atom_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(loaded.0.as_deref(), Some("summary"));
    assert_eq!(loaded.1.as_deref(), Some("cover.png"));
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
fn open_db_enforces_wal_mode_after_migration_replay() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wal-check.db");

    let conn = open_db(&path).unwrap();
    assert_eq!(schema_version(&conn), latest_version());

    let journal_mode: String = conn
        .query_row("PRAGMA journal_mode;", [], |row| row.get(0))
        .unwrap();
    assert_eq!(journal_mode.to_lowercase(), "wal");
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
        "INSERT INTO atoms (uuid, type, content, start_at, end_at)
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

#[test]
fn migration_9_backfills_missing_root_note_refs_for_active_notes() {
    let mut conn = Connection::open_in_memory().unwrap();
    migrate_to_v8(&conn);

    let note_existing = Uuid::new_v4().to_string();
    let note_missing = Uuid::new_v4().to_string();
    let task_atom = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'note', 'existing');",
        [note_existing.as_str()],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'note', 'missing');",
        [note_missing.as_str()],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'task', 'task row');",
        [task_atom.as_str()],
    )
    .unwrap();

    let folder_id = Uuid::new_v4().to_string();
    let existing_ref_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO workspace_nodes (
            node_uuid, kind, parent_uuid, atom_uuid, display_name, sort_order, is_deleted
         ) VALUES (?1, 'folder', NULL, NULL, 'Group', 0, 0);",
        [folder_id.as_str()],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO workspace_nodes (
            node_uuid, kind, parent_uuid, atom_uuid, display_name, sort_order, is_deleted
         ) VALUES (?1, 'note_ref', ?2, ?3, 'ExistingRef', 0, 0);",
        [&existing_ref_id, &folder_id, &note_existing],
    )
    .unwrap();

    apply_migrations(&mut conn).unwrap();

    assert_eq!(schema_version(&conn), latest_version());

    let existing_count: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0;",
            [note_existing.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    let missing_count: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0;",
            [note_missing.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0;",
            [task_atom.as_str()],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(existing_count, 1);
    assert_eq!(missing_count, 1);
    assert_eq!(task_count, 0);

    let backfilled_parent: Option<String> = conn
        .query_row(
            "SELECT parent_uuid
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0
             LIMIT 1;",
            [note_missing.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert!(backfilled_parent.is_none());
}

#[test]
fn migration_9_backfill_sql_is_idempotent_on_replay() {
    let mut conn = Connection::open_in_memory().unwrap();
    migrate_to_v8(&conn);

    let note_missing = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO atoms (uuid, type, content) VALUES (?1, 'note', 'missing');",
        [note_missing.as_str()],
    )
    .unwrap();

    apply_migrations(&mut conn).unwrap();

    let count_after_migration: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0;",
            [note_missing.as_str()],
            |row| row.get(0),
        )
        .unwrap();

    conn.execute_batch(include_str!(
        "../src/db/migrations/0009_workspace_note_ref_backfill.sql"
    ))
    .unwrap();

    let count_after_replay: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM workspace_nodes
             WHERE kind = 'note_ref'
               AND atom_uuid = ?1
               AND is_deleted = 0;",
            [note_missing.as_str()],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(count_after_migration, 1);
    assert_eq!(count_after_replay, 1);
}

fn migrate_to_v8(conn: &Connection) {
    let migrations = [
        (1u32, include_str!("../src/db/migrations/0001_init.sql")),
        (2u32, include_str!("../src/db/migrations/0002_tags.sql")),
        (
            3u32,
            include_str!("../src/db/migrations/0003_external_mappings.sql"),
        ),
        (4u32, include_str!("../src/db/migrations/0004_fts.sql")),
        (
            5u32,
            include_str!("../src/db/migrations/0005_note_preview.sql"),
        ),
        (
            6u32,
            include_str!("../src/db/migrations/0006_time_matrix.sql"),
        ),
        (
            7u32,
            include_str!("../src/db/migrations/0007_workspace_tree.sql"),
        ),
        (
            8u32,
            include_str!("../src/db/migrations/0008_workspace_tree_delete_policy.sql"),
        ),
    ];

    for (version, sql) in migrations {
        conn.execute_batch(sql).unwrap();
        conn.execute_batch(&format!("PRAGMA user_version = {version};"))
            .unwrap();
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

fn assert_column_exists(conn: &Connection, table_name: &str, column_name: &str) {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table_name});"))
        .unwrap();
    let mut rows = stmt.query([]).unwrap();
    while let Some(row) = rows.next().unwrap() {
        let current: String = row.get(1).unwrap();
        if current == column_name {
            return;
        }
    }
    panic!("column {column_name} does not exist in table {table_name}");
}
