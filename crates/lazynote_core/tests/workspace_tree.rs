use lazynote_core::db::open_db_in_memory;
use lazynote_core::{
    Atom, AtomRepository, AtomType, FolderDeleteMode, SqliteAtomRepository, SqliteTreeRepository,
    TreeService, TreeServiceError, WorkspaceNodeKind,
};
use uuid::Uuid;

fn setup() -> rusqlite::Connection {
    open_db_in_memory().unwrap()
}

fn insert_atom(conn: &rusqlite::Connection, atom: &Atom) {
    let repo = SqliteAtomRepository::try_new(conn).unwrap();
    repo.create_atom(atom).unwrap();
}

#[test]
fn migration_7_creates_workspace_nodes_table() {
    let conn = setup();

    let exists: i64 = conn
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'workspace_nodes'
            );",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(exists, 1);

    let mut stmt = conn.prepare("PRAGMA table_info(workspace_nodes);").unwrap();
    let mut rows = stmt.query([]).unwrap();
    let mut columns = Vec::new();
    while let Some(row) = rows.next().unwrap() {
        let column_name: String = row.get(1).unwrap();
        columns.push(column_name);
    }
    assert!(columns.contains(&"node_uuid".to_string()));
    assert!(columns.contains(&"kind".to_string()));
    assert!(columns.contains(&"parent_uuid".to_string()));
    assert!(columns.contains(&"atom_uuid".to_string()));
    assert!(columns.contains(&"display_name".to_string()));
    assert!(columns.contains(&"sort_order".to_string()));
}

#[test]
fn create_and_list_children_keeps_deterministic_order() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let root = service.create_folder(None, "Root").unwrap();
    let child_a = service
        .create_folder(Some(root.node_uuid), "Alpha")
        .unwrap();
    let child_b = service.create_folder(Some(root.node_uuid), "Beta").unwrap();

    let root_children = service.list_children(None).unwrap();
    assert_eq!(root_children.len(), 1);
    assert_eq!(root_children[0].node_uuid, root.node_uuid);

    let children = service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(children.len(), 2);
    assert_eq!(children[0].node_uuid, child_a.node_uuid);
    assert_eq!(children[1].node_uuid, child_b.node_uuid);
    assert_eq!(children[0].sort_order, 0);
    assert_eq!(children[1].sort_order, 1);
}

#[test]
fn create_note_ref_requires_active_note_atom() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let task_atom = Atom::new(AtomType::Task, "Task row");
    insert_atom(&conn, &task_atom);

    let err = service
        .create_note_ref(None, task_atom.uuid, Some("TaskRef".to_string()))
        .unwrap_err();
    assert!(matches!(err, TreeServiceError::AtomNotNote(id) if id == task_atom.uuid));
}

#[test]
fn create_note_ref_success_for_note_atom() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let note_atom = Atom::new(AtomType::Note, "Note row");
    insert_atom(&conn, &note_atom);

    let folder = service.create_folder(None, "Notes").unwrap();
    let note_ref = service
        .create_note_ref(Some(folder.node_uuid), note_atom.uuid, None)
        .unwrap();

    assert_eq!(note_ref.kind, WorkspaceNodeKind::NoteRef);
    assert_eq!(note_ref.parent_uuid, Some(folder.node_uuid));
    assert_eq!(note_ref.atom_uuid, Some(note_atom.uuid));
    assert_eq!(note_ref.display_name, "Untitled note");
}

#[test]
fn move_rejects_cycle_parenting() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let folder_a = service.create_folder(None, "A").unwrap();
    let folder_b = service
        .create_folder(Some(folder_a.node_uuid), "B")
        .unwrap();

    let err = service
        .move_node(folder_a.node_uuid, Some(folder_b.node_uuid), None)
        .unwrap_err();
    assert!(matches!(
        err,
        TreeServiceError::CycleDetected {
            node_uuid,
            parent_uuid
        } if node_uuid == folder_a.node_uuid && parent_uuid == folder_b.node_uuid
    ));
}

#[test]
fn move_rejects_note_ref_parent() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let note_atom = Atom::new(AtomType::Note, "Note row");
    insert_atom(&conn, &note_atom);

    let folder = service.create_folder(None, "Folder").unwrap();
    let note_ref = service
        .create_note_ref(None, note_atom.uuid, Some("Ref".to_string()))
        .unwrap();

    let err = service
        .move_node(folder.node_uuid, Some(note_ref.node_uuid), None)
        .unwrap_err();
    assert!(matches!(
        err,
        TreeServiceError::ParentMustBeFolder(parent_uuid) if parent_uuid == note_ref.node_uuid
    ));
}

#[test]
fn move_with_target_order_reorders_siblings() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let root = service.create_folder(None, "Root").unwrap();
    let child_a = service
        .create_folder(Some(root.node_uuid), "Alpha")
        .unwrap();
    let child_b = service.create_folder(Some(root.node_uuid), "Beta").unwrap();
    let child_c = service
        .create_folder(Some(root.node_uuid), "Gamma")
        .unwrap();

    service
        .move_node(child_c.node_uuid, Some(root.node_uuid), Some(0))
        .unwrap();

    let children = service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(children.len(), 3);
    assert_eq!(children[0].node_uuid, child_c.node_uuid);
    assert_eq!(children[1].node_uuid, child_a.node_uuid);
    assert_eq!(children[2].node_uuid, child_b.node_uuid);
    assert_eq!(children[0].sort_order, 0);
    assert_eq!(children[1].sort_order, 1);
    assert_eq!(children[2].sort_order, 2);
}

#[test]
fn move_target_order_uses_visible_sibling_index_only() {
    let conn = setup();
    let atom_repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let note_hidden = Atom::new(AtomType::Note, "hidden");
    let note_a = Atom::new(AtomType::Note, "a");
    let note_b = Atom::new(AtomType::Note, "b");
    insert_atom(&conn, &note_hidden);
    insert_atom(&conn, &note_a);
    insert_atom(&conn, &note_b);

    let root = service.create_folder(None, "Root").unwrap();
    let hidden_ref = service
        .create_note_ref(
            Some(root.node_uuid),
            note_hidden.uuid,
            Some("hidden".to_string()),
        )
        .unwrap();
    let ref_a = service
        .create_note_ref(Some(root.node_uuid), note_a.uuid, Some("A".to_string()))
        .unwrap();
    let ref_b = service
        .create_note_ref(Some(root.node_uuid), note_b.uuid, Some("B".to_string()))
        .unwrap();

    atom_repo.soft_delete_atom(note_hidden.uuid).unwrap();
    let before = service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(before.len(), 2);
    assert_eq!(before[0].node_uuid, ref_a.node_uuid);
    assert_eq!(before[1].node_uuid, ref_b.node_uuid);

    service
        .move_node(ref_a.node_uuid, Some(root.node_uuid), Some(1))
        .unwrap();

    let after = service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(after.len(), 2);
    assert_eq!(after[0].node_uuid, ref_b.node_uuid);
    assert_eq!(after[1].node_uuid, ref_a.node_uuid);

    // Hidden dangling sibling should remain hidden and not occupy visible order slots.
    let hidden_still_filtered = after
        .iter()
        .all(|item| item.node_uuid != hidden_ref.node_uuid);
    assert!(hidden_still_filtered);
}

#[test]
fn create_folder_rejects_unknown_parent() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);
    let unknown_parent = Uuid::new_v4();

    let err = service
        .create_folder(Some(unknown_parent), "x")
        .unwrap_err();
    assert!(matches!(
        err,
        TreeServiceError::ParentNotFound(parent_uuid) if parent_uuid == unknown_parent
    ));
}

#[test]
fn deleted_note_reference_is_filtered_and_restores_on_atom_restore() {
    let conn = setup();
    let atom_repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let tree_service = TreeService::new(tree_repo);

    let note_atom = Atom::new(AtomType::Note, "note");
    insert_atom(&conn, &note_atom);
    let root = tree_service.create_folder(None, "Root").unwrap();
    let note_ref = tree_service
        .create_note_ref(
            Some(root.node_uuid),
            note_atom.uuid,
            Some("ref".to_string()),
        )
        .unwrap();

    let before_delete = tree_service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(before_delete.len(), 1);
    assert_eq!(before_delete[0].node_uuid, note_ref.node_uuid);

    atom_repo.soft_delete_atom(note_atom.uuid).unwrap();
    let after_delete = tree_service.list_children(Some(root.node_uuid)).unwrap();
    assert!(after_delete.is_empty());

    let mut restored = atom_repo.get_atom(note_atom.uuid, true).unwrap().unwrap();
    restored.is_deleted = false;
    atom_repo.update_atom(&restored).unwrap();

    let after_restore = tree_service.list_children(Some(root.node_uuid)).unwrap();
    assert_eq!(after_restore.len(), 1);
    assert_eq!(after_restore[0].node_uuid, note_ref.node_uuid);
}

#[test]
fn delete_folder_dissolve_moves_direct_children_to_root() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let note_a = Atom::new(AtomType::Note, "A");
    let note_b = Atom::new(AtomType::Note, "B");
    insert_atom(&conn, &note_a);
    insert_atom(&conn, &note_b);

    let folder = service.create_folder(None, "Group").unwrap();
    let direct_note_ref = service
        .create_note_ref(
            Some(folder.node_uuid),
            note_a.uuid,
            Some("Direct".to_string()),
        )
        .unwrap();
    let child_folder = service
        .create_folder(Some(folder.node_uuid), "ChildFolder")
        .unwrap();
    let nested_note_ref = service
        .create_note_ref(
            Some(child_folder.node_uuid),
            note_b.uuid,
            Some("Nested".to_string()),
        )
        .unwrap();

    service
        .delete_folder(folder.node_uuid, FolderDeleteMode::Dissolve)
        .unwrap();

    let root_children = service.list_children(None).unwrap();
    let root_ids: Vec<_> = root_children.iter().map(|item| item.node_uuid).collect();
    assert!(root_ids.contains(&direct_note_ref.node_uuid));
    assert!(root_ids.contains(&child_folder.node_uuid));
    assert!(!root_ids.contains(&folder.node_uuid));

    let nested_children = service.list_children(Some(child_folder.node_uuid)).unwrap();
    assert_eq!(nested_children.len(), 1);
    assert_eq!(nested_children[0].node_uuid, nested_note_ref.node_uuid);
}

#[test]
fn delete_folder_delete_all_soft_deletes_unique_atoms_only() {
    let conn = setup();
    let atom_repo = SqliteAtomRepository::try_new(&conn).unwrap();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let note_only_in_target = Atom::new(AtomType::Note, "target-only");
    let note_shared = Atom::new(AtomType::Note, "shared");
    insert_atom(&conn, &note_only_in_target);
    insert_atom(&conn, &note_shared);

    let target_folder = service.create_folder(None, "Target").unwrap();
    let other_folder = service.create_folder(None, "Other").unwrap();

    service
        .create_note_ref(
            Some(target_folder.node_uuid),
            note_only_in_target.uuid,
            Some("target-only".to_string()),
        )
        .unwrap();
    let shared_ref_in_target = service
        .create_note_ref(
            Some(target_folder.node_uuid),
            note_shared.uuid,
            Some("shared-target".to_string()),
        )
        .unwrap();
    let shared_ref_in_other = service
        .create_note_ref(
            Some(other_folder.node_uuid),
            note_shared.uuid,
            Some("shared-other".to_string()),
        )
        .unwrap();

    service
        .delete_folder(target_folder.node_uuid, FolderDeleteMode::DeleteAll)
        .unwrap();

    let target_children_err = service
        .list_children(Some(target_folder.node_uuid))
        .unwrap_err();
    assert!(matches!(
        target_children_err,
        TreeServiceError::ParentNotFound(id) if id == target_folder.node_uuid
    ));

    let root_children = service.list_children(None).unwrap();
    let root_ids: Vec<_> = root_children.iter().map(|item| item.node_uuid).collect();
    assert!(!root_ids.contains(&target_folder.node_uuid));
    assert!(root_ids.contains(&other_folder.node_uuid));

    let shared_in_other_children = service.list_children(Some(other_folder.node_uuid)).unwrap();
    assert_eq!(shared_in_other_children.len(), 1);
    assert_eq!(
        shared_in_other_children[0].node_uuid,
        shared_ref_in_other.node_uuid
    );

    let deleted_ref_in_target_visible = root_children
        .iter()
        .any(|item| item.node_uuid == shared_ref_in_target.node_uuid);
    assert!(!deleted_ref_in_target_visible);

    let only_target_atom = atom_repo
        .get_atom(note_only_in_target.uuid, true)
        .unwrap()
        .unwrap();
    assert!(only_target_atom.is_deleted);

    let shared_atom = atom_repo.get_atom(note_shared.uuid, true).unwrap().unwrap();
    assert!(!shared_atom.is_deleted);
}

#[test]
fn move_node_rolls_back_when_reorder_fails() {
    let conn = setup();
    let tree_repo = SqliteTreeRepository::try_new(&conn).unwrap();
    let service = TreeService::new(tree_repo);

    let source_root = service.create_folder(None, "Source").unwrap();
    let _source_a = service
        .create_folder(Some(source_root.node_uuid), "A")
        .unwrap();
    let _source_b = service
        .create_folder(Some(source_root.node_uuid), "B")
        .unwrap();
    let moving = service
        .create_folder(Some(source_root.node_uuid), "Moving")
        .unwrap();

    let target_root = service.create_folder(None, "Target").unwrap();
    let _target_x = service
        .create_folder(Some(target_root.node_uuid), "X")
        .unwrap();
    let target_y = service
        .create_folder(Some(target_root.node_uuid), "Y")
        .unwrap();

    conn.execute_batch(&format!(
        "CREATE TRIGGER workspace_nodes_fail_sort_update_test
         BEFORE UPDATE OF sort_order ON workspace_nodes
         WHEN NEW.node_uuid = '{}'
         BEGIN
             SELECT RAISE(ABORT, 'forced sort failure');
         END;",
        target_y.node_uuid
    ))
    .unwrap();

    let move_result = service.move_node(moving.node_uuid, Some(target_root.node_uuid), Some(0));
    assert!(move_result.is_err());

    let source_children = service.list_children(Some(source_root.node_uuid)).unwrap();
    let source_ids: Vec<_> = source_children.iter().map(|item| item.node_uuid).collect();
    assert!(source_ids.contains(&moving.node_uuid));

    let target_children = service.list_children(Some(target_root.node_uuid)).unwrap();
    let target_ids: Vec<_> = target_children.iter().map(|item| item.node_uuid).collect();
    assert!(!target_ids.contains(&moving.node_uuid));
}
