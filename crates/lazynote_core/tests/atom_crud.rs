use lazynote_core::db::migrations::latest_version;
use lazynote_core::db::open_db_in_memory;
use lazynote_core::{
    Atom, AtomListQuery, AtomRepository, AtomService, AtomType, RepoError, SqliteAtomRepository,
    TaskStatus,
};
use rusqlite::Connection;
use std::collections::HashSet;
use uuid::Uuid;

#[test]
fn create_and_get_roundtrip() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom = Atom::new(AtomType::Note, "first note");
    let id = repo.create_atom(&atom).unwrap();

    let loaded = repo.get_atom(id, false).unwrap().unwrap();
    assert_eq!(loaded.uuid, atom.uuid);
    assert_eq!(loaded.kind, AtomType::Note);
    assert_eq!(loaded.content, "first note");
    assert!(!loaded.is_deleted);
}

#[test]
fn create_and_get_roundtrip_preserves_preview_fields() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let mut atom = Atom::new(AtomType::Note, "preview body");
    atom.preview_text = Some("preview text".to_string());
    atom.preview_image = Some("cover.png".to_string());
    let id = repo.create_atom(&atom).unwrap();

    let loaded = repo.get_atom(id, false).unwrap().unwrap();
    assert_eq!(loaded.preview_text.as_deref(), Some("preview text"));
    assert_eq!(loaded.preview_image.as_deref(), Some("cover.png"));
}

#[test]
fn update_existing_atom() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let mut atom = Atom::new(AtomType::Note, "draft");
    repo.create_atom(&atom).unwrap();

    atom.kind = AtomType::Task;
    atom.content = "updated task".to_string();
    atom.task_status = Some(TaskStatus::InProgress);
    repo.update_atom(&atom).unwrap();

    let loaded = repo.get_atom(atom.uuid, false).unwrap().unwrap();
    assert_eq!(loaded.kind, AtomType::Task);
    assert_eq!(loaded.content, "updated task");
    assert_eq!(loaded.task_status, Some(TaskStatus::InProgress));
}

#[test]
fn update_atom_updates_preview_fields() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let mut atom = Atom::new(AtomType::Note, "draft");
    repo.create_atom(&atom).unwrap();

    atom.preview_text = Some("updated preview".to_string());
    atom.preview_image = Some("updated.png".to_string());
    repo.update_atom(&atom).unwrap();

    let loaded = repo.get_atom(atom.uuid, false).unwrap().unwrap();
    assert_eq!(loaded.preview_text.as_deref(), Some("updated preview"));
    assert_eq!(loaded.preview_image.as_deref(), Some("updated.png"));
}

#[test]
fn update_not_found_returns_not_found() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom = Atom::new(AtomType::Note, "missing");
    let err = repo.update_atom(&atom).unwrap_err();
    assert!(matches!(err, RepoError::NotFound(id) if id == atom.uuid));
}

#[test]
fn list_excludes_deleted_by_default_and_can_include_them() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom_a = Atom::new(AtomType::Note, "active");
    let atom_b = Atom::new(AtomType::Task, "deleted later");
    repo.create_atom(&atom_a).unwrap();
    repo.create_atom(&atom_b).unwrap();
    repo.soft_delete_atom(atom_b.uuid).unwrap();

    let visible = repo.list_atoms(&AtomListQuery::default()).unwrap();
    assert_eq!(visible.len(), 1);
    assert_eq!(visible[0].uuid, atom_a.uuid);

    let include_deleted = AtomListQuery {
        include_deleted: true,
        ..AtomListQuery::default()
    };
    let all = repo.list_atoms(&include_deleted).unwrap();
    assert_eq!(all.len(), 2);
}

#[test]
fn soft_delete_is_idempotent() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom = Atom::new(AtomType::Event, "weekly sync");
    repo.create_atom(&atom).unwrap();

    repo.soft_delete_atom(atom.uuid).unwrap();
    repo.soft_delete_atom(atom.uuid).unwrap();

    assert!(repo.get_atom(atom.uuid, false).unwrap().is_none());
    let deleted = repo.get_atom(atom.uuid, true).unwrap().unwrap();
    assert!(deleted.is_deleted);
}

#[test]
fn validation_failure_blocks_create_and_update() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let mut invalid = Atom::new(AtomType::Event, "bad range");
    invalid.event_start = Some(300);
    invalid.event_end = Some(100);

    let create_err = repo.create_atom(&invalid).unwrap_err();
    assert!(matches!(create_err, RepoError::Validation(_)));

    let mut valid = Atom::new(AtomType::Event, "good range");
    valid.event_start = Some(100);
    valid.event_end = Some(200);
    repo.create_atom(&valid).unwrap();

    valid.event_end = Some(50);
    let update_err = repo.update_atom(&valid).unwrap_err();
    assert!(matches!(update_err, RepoError::Validation(_)));
}

#[test]
fn list_filters_by_atom_type() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let note = Atom::new(AtomType::Note, "note");
    let task = Atom::new(AtomType::Task, "task");
    let event = Atom::new(AtomType::Event, "event");
    repo.create_atom(&note).unwrap();
    repo.create_atom(&task).unwrap();
    repo.create_atom(&event).unwrap();

    let query = AtomListQuery {
        kind: Some(AtomType::Task),
        include_deleted: true,
        ..AtomListQuery::default()
    };

    let result = repo.list_atoms(&query).unwrap();
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].uuid, task.uuid);
}

#[test]
fn service_wraps_repository_calls() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let service = AtomService::new(repo);

    let atom = Atom::new(AtomType::Note, "from service");
    let id = service.create_atom(&atom).unwrap();

    let fetched = service.get_atom(id, false).unwrap().unwrap();
    assert_eq!(fetched.content, "from service");

    let ids: HashSet<_> = service
        .list_atoms(&AtomListQuery::default())
        .unwrap()
        .into_iter()
        .map(|item| item.uuid)
        .collect();
    assert!(ids.contains(&id));
}

#[test]
fn repository_rejects_uninitialized_connection() {
    let conn = Connection::open_in_memory().unwrap();

    let result = SqliteAtomRepository::try_new(&conn);
    match result {
        Err(RepoError::UninitializedConnection {
            expected_version,
            actual_version: 0,
        }) => assert!(expected_version > 0),
        Err(other) => panic!("unexpected error: {other}"),
        Ok(_) => panic!("expected uninitialized connection error"),
    }
}

#[test]
fn repository_rejects_connection_without_required_atoms_table() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(&format!("PRAGMA user_version = {};", latest_version()))
        .unwrap();

    let result = SqliteAtomRepository::try_new(&conn);
    assert!(matches!(
        result,
        Err(RepoError::MissingRequiredTable("atoms"))
    ));
}

#[test]
fn repository_rejects_connection_missing_required_atoms_column() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(
        "CREATE TABLE atoms (
            uuid TEXT PRIMARY KEY NOT NULL,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );",
    )
    .unwrap();
    conn.execute_batch(&format!("PRAGMA user_version = {};", latest_version()))
        .unwrap();

    let result = SqliteAtomRepository::try_new(&conn);
    assert!(matches!(
        result,
        Err(RepoError::MissingRequiredColumn {
            table: "atoms",
            column: "preview_text"
        })
    ));
}

#[test]
fn list_pagination_with_limit_and_offset_is_stable() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom_a = atom_with_fixed_id("00000000-0000-4000-8000-000000000001", "a");
    let atom_b = atom_with_fixed_id("00000000-0000-4000-8000-000000000002", "b");
    let atom_c = atom_with_fixed_id("00000000-0000-4000-8000-000000000003", "c");
    repo.create_atom(&atom_c).unwrap();
    repo.create_atom(&atom_a).unwrap();
    repo.create_atom(&atom_b).unwrap();

    conn.execute("UPDATE atoms SET updated_at = 1234567890000;", [])
        .unwrap();

    let query = AtomListQuery {
        include_deleted: true,
        limit: Some(2),
        offset: 1,
        ..AtomListQuery::default()
    };
    let page = repo.list_atoms(&query).unwrap();

    assert_eq!(page.len(), 2);
    assert_eq!(page[0].uuid, atom_b.uuid);
    assert_eq!(page[1].uuid, atom_c.uuid);
}

#[test]
fn list_pagination_with_offset_only_path_is_stable() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom_a = atom_with_fixed_id("00000000-0000-4000-8000-000000000001", "a");
    let atom_b = atom_with_fixed_id("00000000-0000-4000-8000-000000000002", "b");
    let atom_c = atom_with_fixed_id("00000000-0000-4000-8000-000000000003", "c");
    repo.create_atom(&atom_a).unwrap();
    repo.create_atom(&atom_b).unwrap();
    repo.create_atom(&atom_c).unwrap();

    conn.execute("UPDATE atoms SET updated_at = 1234567890000;", [])
        .unwrap();

    let query = AtomListQuery {
        include_deleted: true,
        offset: 1,
        ..AtomListQuery::default()
    };
    let page = repo.list_atoms(&query).unwrap();

    assert_eq!(page.len(), 2);
    assert_eq!(page[0].uuid, atom_b.uuid);
    assert_eq!(page[1].uuid, atom_c.uuid);
}

fn atom_with_fixed_id(id: &str, content: &str) -> Atom {
    Atom::with_id(Uuid::parse_str(id).unwrap(), AtomType::Note, content).unwrap()
}
