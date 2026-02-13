use lazynote_core::{Atom, AtomType, AtomValidationError, TaskStatus};
use uuid::Uuid;

#[test]
fn atom_new_sets_defaults() {
    let atom = Atom::new(AtomType::Note, "hello");

    assert!(!atom.uuid.is_nil());
    assert_eq!(atom.kind, AtomType::Note);
    assert_eq!(atom.content, "hello");
    assert_eq!(atom.task_status, None);
    assert_eq!(atom.event_start, None);
    assert_eq!(atom.event_end, None);
    assert_eq!(atom.hlc_timestamp, None);
    assert!(atom.is_active());
}

#[test]
fn soft_delete_and_restore_work() {
    let mut atom = Atom::new(AtomType::Task, "todo");

    atom.soft_delete();
    assert!(atom.is_deleted);
    assert!(!atom.is_active());

    atom.restore();
    assert!(!atom.is_deleted);
    assert!(atom.is_active());
}

#[test]
fn atom_serialization_uses_expected_wire_fields() {
    let atom_id = Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap();
    let mut atom = Atom::with_id(atom_id, AtomType::Task, "- [ ] ship PR-0004").unwrap();
    atom.task_status = Some(TaskStatus::InProgress);
    atom.event_start = Some(1_700_000_000_000);
    atom.event_end = Some(1_700_000_360_000);
    atom.hlc_timestamp = Some("2026-02-13T10:00:00Z#node-a#42".to_string());

    let json = serde_json::to_value(&atom).unwrap();
    assert_eq!(json["uuid"], atom_id.to_string());
    assert_eq!(json["type"], "task");
    assert_eq!(json["task_status"], "in_progress");
    assert_eq!(json["event_start"], 1_700_000_000_000_i64);
    assert_eq!(json["event_end"], 1_700_000_360_000_i64);
    assert_eq!(json["hlc_timestamp"], "2026-02-13T10:00:00Z#node-a#42");
    assert_eq!(json["is_deleted"], false);

    let decoded: Atom = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, atom);
}

#[test]
fn with_id_rejects_nil_uuid() {
    let err = Atom::with_id(Uuid::nil(), AtomType::Note, "invalid").unwrap_err();
    assert_eq!(err, AtomValidationError::NilUuid);
}

#[test]
fn validate_rejects_reversed_event_window() {
    let mut atom = Atom::new(AtomType::Event, "meeting");
    atom.event_start = Some(1_700_000_000_000);
    atom.event_end = Some(1_699_999_999_000);

    let err = atom.validate().unwrap_err();
    assert_eq!(
        err,
        AtomValidationError::InvalidEventWindow {
            start: 1_700_000_000_000,
            end: 1_699_999_999_000,
        }
    );
}

#[test]
fn deserialize_rejects_invalid_event_window() {
    let value = serde_json::json!({
        "uuid": "11111111-2222-4333-8444-555555555555",
        "type": "event",
        "content": "bad event",
        "task_status": null,
        "event_start": 200,
        "event_end": 100,
        "hlc_timestamp": null,
        "is_deleted": false
    });

    let err = serde_json::from_value::<Atom>(value).unwrap_err();
    assert!(
        err.to_string()
            .contains("event_end (100) must be >= event_start (200)"),
        "unexpected error: {err}"
    );
}
