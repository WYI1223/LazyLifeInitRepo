use lazynote_core::db::open_db_in_memory;
use lazynote_core::{
    AtomService, NoteService, NoteServiceError, SqliteAtomRepository, SqliteNoteRepository,
};
use rusqlite::params;

#[test]
fn create_and_update_note_derives_markdown_preview_fields() {
    let mut conn = open_db_in_memory().unwrap();
    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let service = NoteService::new(repo);

    let created = service
        .create_note("# Title\n\n![cover](images/first.png)\nBody with **markdown**")
        .unwrap();
    assert_eq!(created.preview_image.as_deref(), Some("images/first.png"));
    assert!(created
        .preview_text
        .as_deref()
        .unwrap_or("")
        .contains("Title"));

    let updated = service
        .update_note(
            created.atom_id,
            "Updated body with [link](https://example.com) and ![](second.png)",
        )
        .unwrap();
    assert_eq!(updated.preview_image.as_deref(), Some("second.png"));
    assert!(updated
        .preview_text
        .as_deref()
        .unwrap_or("")
        .contains("Updated"));
}

#[test]
fn notes_list_returns_note_only_and_stable_order() {
    let mut conn = open_db_in_memory().unwrap();
    {
        let atom_repo = SqliteAtomRepository::try_new(&conn).unwrap();
        let atom_service = AtomService::new(atom_repo);
        atom_service.create_task("task row").unwrap();
    }

    let (first_id, second_id) = {
        let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
        let service = NoteService::new(repo);
        let first = service.create_note("first note").unwrap();
        let second = service.create_note("second note").unwrap();
        (first.atom_id.to_string(), second.atom_id.to_string())
    };

    conn.execute(
        "UPDATE atoms SET updated_at = 2000 WHERE uuid = ?1;",
        params![first_id],
    )
    .unwrap();
    conn.execute(
        "UPDATE atoms SET updated_at = 1000 WHERE uuid = ?1;",
        params![second_id],
    )
    .unwrap();

    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let service = NoteService::new(repo);
    let listed = service.list_notes(None, Some(10), 0).unwrap();
    assert_eq!(listed.items.len(), 2);
    assert_eq!(listed.items[0].atom_id.to_string(), first_id);
    assert_eq!(listed.items[1].atom_id.to_string(), second_id);
}

#[test]
fn note_set_tags_replaces_full_set_with_lowercase_normalization() {
    let mut conn = open_db_in_memory().unwrap();
    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let mut service = NoteService::new(repo);
    let created = service.create_note("tag target").unwrap();

    let after_first = service
        .set_note_tags(
            created.atom_id,
            vec![
                "Work".to_string(),
                "IMPORTANT".to_string(),
                "work".to_string(),
            ],
        )
        .unwrap();
    assert_eq!(
        after_first.tags,
        vec!["important".to_string(), "work".to_string()]
    );

    let after_replace = service
        .set_note_tags(created.atom_id, vec!["Personal".to_string()])
        .unwrap();
    assert_eq!(after_replace.tags, vec!["personal".to_string()]);
}

#[test]
fn notes_list_supports_single_tag_filter() {
    let mut conn = open_db_in_memory().unwrap();
    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let mut service = NoteService::new(repo);
    let note_work = service.create_note("work note").unwrap();
    let note_other = service.create_note("other note").unwrap();
    service
        .set_note_tags(note_work.atom_id, vec!["Work".to_string()])
        .unwrap();
    service
        .set_note_tags(note_other.atom_id, vec!["Personal".to_string()])
        .unwrap();

    let filtered = service
        .list_notes(Some("WORK".to_string()), Some(10), 0)
        .unwrap();
    assert_eq!(filtered.items.len(), 1);
    assert_eq!(filtered.items[0].atom_id, note_work.atom_id);
}

#[test]
fn notes_list_limit_defaults_to_10_and_caps_at_50() {
    let mut conn = open_db_in_memory().unwrap();
    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let service = NoteService::new(repo);
    for idx in 0..60 {
        service.create_note(format!("note {idx}")).unwrap();
    }

    let defaulted = service.list_notes(None, None, 0).unwrap();
    assert_eq!(defaulted.applied_limit, 10);
    assert_eq!(defaulted.items.len(), 10);

    let capped = service.list_notes(None, Some(500), 0).unwrap();
    assert_eq!(capped.applied_limit, 50);
    assert_eq!(capped.items.len(), 50);
}

#[test]
fn set_note_tags_rejects_blank_tag_values() {
    let mut conn = open_db_in_memory().unwrap();
    let repo = SqliteNoteRepository::try_new(&mut conn).unwrap();
    let mut service = NoteService::new(repo);
    let created = service.create_note("tag target").unwrap();

    let err = service
        .set_note_tags(created.atom_id, vec!["   ".to_string()])
        .unwrap_err();
    assert!(matches!(err, NoteServiceError::InvalidTag(_)));
}
