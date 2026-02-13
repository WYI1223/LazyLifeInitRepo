use lazynote_core::db::open_db_in_memory;
use lazynote_core::{
    Atom, AtomListQuery, AtomRepository, AtomService, AtomType, RepoError, SqliteAtomRepository,
    TaskStatus,
};
use std::collections::HashSet;

#[test]
fn create_and_get_roundtrip() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::new(&conn);

    let atom = Atom::new(AtomType::Note, "first note");
    let id = repo.create_atom(&atom).unwrap();

    let loaded = repo.get_atom(id, false).unwrap().unwrap();
    assert_eq!(loaded.uuid, atom.uuid);
    assert_eq!(loaded.kind, AtomType::Note);
    assert_eq!(loaded.content, "first note");
    assert!(!loaded.is_deleted);
}

#[test]
fn update_existing_atom() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::new(&conn);

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
fn update_not_found_returns_not_found() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::new(&conn);

    let atom = Atom::new(AtomType::Note, "missing");
    let err = repo.update_atom(&atom).unwrap_err();
    assert!(matches!(err, RepoError::NotFound(id) if id == atom.uuid));
}

#[test]
fn list_excludes_deleted_by_default_and_can_include_them() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::new(&conn);

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
    let repo = SqliteAtomRepository::new(&conn);

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
    let repo = SqliteAtomRepository::new(&conn);

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
    let repo = SqliteAtomRepository::new(&conn);

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
    let repo = SqliteAtomRepository::new(&conn);
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
