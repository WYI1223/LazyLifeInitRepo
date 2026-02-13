use lazynote_core::db::migrations::{apply_migrations, latest_version};
use lazynote_core::db::open_db_in_memory;
use lazynote_core::{
    search_all, Atom, AtomRepository, AtomType, SearchError, SearchQuery, SqliteAtomRepository,
};
use rusqlite::Connection;
use std::collections::HashSet;

#[test]
fn search_returns_created_atom() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let atom = Atom::new(AtomType::Note, "hello rust search");
    repo.create_atom(&atom).unwrap();

    let hits = search_all(&conn, &SearchQuery::new("rust")).unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].atom_id, atom.uuid);
    assert!(hits[0].snippet.contains("rust"));
}

#[test]
fn search_reflects_updated_content() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let mut atom = Atom::new(AtomType::Note, "alpha text");
    repo.create_atom(&atom).unwrap();

    atom.content = "beta text".to_string();
    repo.update_atom(&atom).unwrap();

    let old_hits = search_all(&conn, &SearchQuery::new("alpha")).unwrap();
    assert!(old_hits.is_empty());

    let new_hits = search_all(&conn, &SearchQuery::new("beta")).unwrap();
    assert_eq!(new_hits.len(), 1);
    assert_eq!(new_hits[0].atom_id, atom.uuid);
}

#[test]
fn search_excludes_soft_deleted_atoms() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let atom = Atom::new(AtomType::Task, "buy milk tomorrow");
    repo.create_atom(&atom).unwrap();
    repo.soft_delete_atom(atom.uuid).unwrap();

    let hits = search_all(&conn, &SearchQuery::new("milk")).unwrap();
    assert!(hits.is_empty());
}

#[test]
fn search_can_filter_by_type() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let note = Atom::new(AtomType::Note, "plan meeting agenda");
    let task = Atom::new(AtomType::Task, "plan vacation tasks");
    let event = Atom::new(AtomType::Event, "team planning session");
    repo.create_atom(&note).unwrap();
    repo.create_atom(&task).unwrap();
    repo.create_atom(&event).unwrap();

    let mut query = SearchQuery::new("plan");
    query.kind = Some(AtomType::Task);
    let hits = search_all(&conn, &query).unwrap();

    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].atom_id, task.uuid);
}

#[test]
fn search_limit_is_applied() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();

    let atom_a = Atom::new(AtomType::Note, "token common a");
    let atom_b = Atom::new(AtomType::Note, "token common b");
    let atom_c = Atom::new(AtomType::Note, "token common c");
    repo.create_atom(&atom_a).unwrap();
    repo.create_atom(&atom_b).unwrap();
    repo.create_atom(&atom_c).unwrap();

    let mut query = SearchQuery::new("token");
    query.limit = 2;
    let hits = search_all(&conn, &query).unwrap();

    assert_eq!(hits.len(), 2);
    let ids: HashSet<_> = hits.into_iter().map(|hit| hit.atom_id).collect();
    assert!(ids.is_subset(&HashSet::from([atom_a.uuid, atom_b.uuid, atom_c.uuid])));
}

#[test]
fn blank_query_returns_empty_results() {
    let conn = open_db_in_memory().unwrap();
    let hits = search_all(&conn, &SearchQuery::new("   ")).unwrap();
    assert!(hits.is_empty());
}

#[test]
fn limit_zero_returns_empty_results() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let atom = Atom::new(AtomType::Note, "query limit zero");
    repo.create_atom(&atom).unwrap();

    let mut query = SearchQuery::new("query");
    query.limit = 0;

    let hits = search_all(&conn, &query).unwrap();
    assert!(hits.is_empty());
}

#[test]
fn escaped_query_text_does_not_fail_on_common_symbols() {
    let conn = open_db_in_memory().unwrap();
    let repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let atom = Atom::new(AtomType::Note, "alpha beta");
    repo.create_atom(&atom).unwrap();

    let query = SearchQuery::new("a:b");
    let hits = search_all(&conn, &query).unwrap();
    assert!(hits.is_empty());
}

#[test]
fn raw_fts_syntax_reports_invalid_query() {
    let conn = open_db_in_memory().unwrap();

    let mut query = SearchQuery::new("\"unterminated");
    query.raw_fts_syntax = true;

    let err = search_all(&conn, &query).unwrap_err();
    assert!(matches!(err, SearchError::InvalidQuery { .. }));
}

#[test]
fn migration_bootstrap_indexes_existing_v3_atoms() {
    let mut conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
    conn.execute_batch(include_str!("../src/db/migrations/0001_init.sql"))
        .unwrap();
    conn.execute_batch(include_str!("../src/db/migrations/0002_tags.sql"))
        .unwrap();
    conn.execute_batch(include_str!(
        "../src/db/migrations/0003_external_mappings.sql"
    ))
    .unwrap();
    conn.execute_batch(
        "INSERT INTO atoms (uuid, type, content, is_deleted)
         VALUES ('11111111-2222-4333-8444-555555555555', 'note', 'legacy indexed term', 0);",
    )
    .unwrap();
    conn.execute_batch("PRAGMA user_version = 3;").unwrap();

    apply_migrations(&mut conn).unwrap();
    let current_version: u32 = conn
        .query_row("PRAGMA user_version;", [], |row| row.get(0))
        .unwrap();
    assert_eq!(current_version, latest_version());

    let hits = search_all(&conn, &SearchQuery::new("legacy")).unwrap();
    assert_eq!(hits.len(), 1);
}
