//! FFI use-case API for Flutter-facing calls.
//!
//! # Responsibility
//! - Expose stable, use-case-level functions to Dart via FRB.
//! - Keep error semantics simple for early-stage UI integration.
//!
//! # Invariants
//! - Exported functions must not panic across FFI boundary.
//! - Return envelopes keep `ok/error_code/message` semantics stable.
//!
//! # See also
//! - docs/architecture/logging.md

use lazynote_core::db::open_db;
use lazynote_core::{
    core_version as core_version_inner, init_logging as init_logging_inner, ping as ping_inner,
    search_all, AtomId, AtomService, AtomType, FolderDeleteMode, NoteRecord, NoteService,
    NoteServiceError, ScheduleEventRequest, SearchQuery, SectionAtom, SqliteAtomRepository,
    SqliteNoteRepository, SqliteTreeRepository, TaskService, TaskServiceError, TreeRepoError,
    TreeService, TreeServiceError, WorkspaceNode, WorkspaceNodeKind,
};
use log::error;
use std::path::PathBuf;
use std::sync::Mutex;
use uuid::Uuid;

const ENTRY_DEFAULT_LIMIT: u32 = 10;
const ENTRY_SEARCH_MAX_LIMIT: u32 = 50;
const ENTRY_DB_FILE_NAME: &str = "lazynote_entry.sqlite3";
static ENTRY_DB_PATH_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Minimal health-check API for FRB smoke integration.
///
/// # FFI contract
/// - Sync call, non-blocking.
/// - UI-thread safe for current implementation.
/// - Never throws; always returns a UTF-8 string.
#[flutter_rust_bridge::frb(sync)]
pub fn ping() -> String {
    ping_inner().to_owned()
}

/// Expose core crate version through FFI.
///
/// # FFI contract
/// - Sync call, non-blocking.
/// - UI-thread safe for current implementation.
/// - Never throws; always returns a UTF-8 string.
#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    core_version_inner().to_owned()
}

/// Initializes Rust core logging once per process.
///
/// Input semantics:
/// - `level`: one of `trace|debug|info|warn|error` (case-insensitive).
/// - `log_dir`: absolute directory path where rolling logs are written.
///
/// # FFI contract
/// - Sync call; may perform small file-system setup work.
/// - Safe to call repeatedly with the same `level + log_dir` (idempotent).
/// - Reconfiguration attempts with different level or directory return error.
/// - Never panics; returns empty string on success and error message on failure.
#[flutter_rust_bridge::frb(sync)]
pub fn init_logging(level: String, log_dir: String) -> String {
    match init_logging_inner(level.as_str(), log_dir.as_str()) {
        Ok(()) => String::new(),
        Err(err) => err,
    }
}

/// Configures a process-local default SQLite path for entry APIs.
///
/// # FFI contract
/// - Sync call, non-blocking.
/// - Safe to call multiple times; latest successful path wins.
/// - Returns empty string on success, error message on validation/IO failure.
#[flutter_rust_bridge::frb(sync)]
pub fn configure_entry_db_path(db_path: String) -> String {
    match set_configured_entry_db_path(db_path.as_str()) {
        Ok(()) => String::new(),
        Err(err) => err,
    }
}

/// Search item returned by single-entry search API.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntrySearchItem {
    /// Stable atom ID in string form.
    pub atom_id: String,
    /// Atom projection kind (`note|task|event`).
    pub kind: String,
    /// Short snippet summary for result display.
    pub snippet: String,
}

/// Search response envelope for single-entry search flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntrySearchResponse {
    /// Whether search execution succeeded.
    pub ok: bool,
    /// Optional stable error code for machine branching.
    pub error_code: Option<String>,
    /// Search results (empty when no hits or scaffold mode).
    pub items: Vec<EntrySearchItem>,
    /// Human-readable response message for diagnostics.
    pub message: String,
    /// Effective applied search limit.
    pub applied_limit: u32,
}

/// Generic action response envelope for single-entry command flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryActionResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Optional created atom ID.
    pub atom_id: Option<String>,
    /// Human-readable response message for diagnostics/UI.
    pub message: String,
}

impl EntryActionResponse {
    fn success(message: impl Into<String>, atom_id: String) -> Self {
        Self {
            ok: true,
            atom_id: Some(atom_id),
            message: message.into(),
        }
    }

    fn failure(message: impl Into<String>) -> Self {
        Self {
            ok: false,
            atom_id: None,
            message: message.into(),
        }
    }
}

/// Note DTO returned by notes/tags APIs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteItem {
    /// Stable note atom id.
    pub atom_id: String,
    /// Raw markdown content.
    pub content: String,
    /// Derived plain-text preview.
    pub preview_text: Option<String>,
    /// Derived first markdown image path.
    pub preview_image: Option<String>,
    /// Update timestamp in epoch milliseconds.
    pub updated_at: i64,
    /// Normalized tags attached to the note.
    pub tags: Vec<String>,
}

/// Note create/update/get response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Returned note payload on success.
    pub note: Option<NoteItem>,
}

/// Note list response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesListResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Note list items sorted by `updated_at DESC, uuid ASC`.
    pub items: Vec<NoteItem>,
    /// Effective limit after normalization.
    pub applied_limit: u32,
}

/// Tags list response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TagsListResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Normalized tags known by storage.
    pub tags: Vec<String>,
}

/// Workspace action response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceActionResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
}

/// Workspace tree node DTO exposed over FFI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceNodeItem {
    /// Stable workspace node id.
    pub node_id: String,
    /// Node kind label (`folder|note_ref`).
    pub kind: String,
    /// Parent node id for non-root nodes.
    pub parent_node_id: Option<String>,
    /// Target note atom id for note_ref nodes.
    pub atom_id: Option<String>,
    /// User-facing display name.
    pub display_name: String,
    /// Deterministic sibling order key.
    pub sort_order: i64,
}

/// Workspace single-node response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceNodeResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Returned node payload on success.
    pub node: Option<WorkspaceNodeItem>,
}

/// Workspace children-list response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceListChildrenResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Child nodes in deterministic order.
    pub items: Vec<WorkspaceNodeItem>,
}

#[derive(Debug)]
enum WorkspaceFfiError {
    InvalidNodeId(String),
    InvalidParentNodeId(String),
    InvalidAtomId(String),
    InvalidDisplayName(String),
    InvalidDeleteMode(String),
    NodeNotFound(String),
    ParentNotFound(String),
    NodeNotFolder(String),
    ParentNotFolder(String),
    AtomNotFound(String),
    AtomNotNote(String),
    CycleDetected(String),
    DbBusy(String),
    DbError(String),
    Internal(String),
}

impl WorkspaceFfiError {
    fn code(&self) -> &'static str {
        match self {
            Self::InvalidNodeId(_) => "invalid_node_id",
            Self::InvalidParentNodeId(_) => "invalid_parent_node_id",
            Self::InvalidAtomId(_) => "invalid_atom_id",
            Self::InvalidDisplayName(_) => "invalid_display_name",
            Self::InvalidDeleteMode(_) => "invalid_delete_mode",
            Self::NodeNotFound(_) => "node_not_found",
            Self::ParentNotFound(_) => "parent_not_found",
            Self::NodeNotFolder(_) => "node_not_folder",
            Self::ParentNotFolder(_) => "parent_not_folder",
            Self::AtomNotFound(_) => "atom_not_found",
            Self::AtomNotNote(_) => "atom_not_note",
            Self::CycleDetected(_) => "cycle_detected",
            Self::DbBusy(_) => "db_busy",
            Self::DbError(_) => "db_error",
            Self::Internal(_) => "internal_error",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::InvalidNodeId(value) => format!("invalid node id: {value}"),
            Self::InvalidParentNodeId(value) => format!("invalid parent node id: {value}"),
            Self::InvalidAtomId(value) => format!("invalid atom id: {value}"),
            Self::InvalidDisplayName(value) => format!("invalid display name: {value}"),
            Self::InvalidDeleteMode(value) => {
                format!("invalid delete mode: {value}, expected dissolve|delete_all")
            }
            Self::NodeNotFound(value) => format!("workspace node not found: {value}"),
            Self::ParentNotFound(value) => format!("workspace parent not found: {value}"),
            Self::NodeNotFolder(value) => format!("workspace node is not a folder: {value}"),
            Self::ParentNotFolder(value) => format!("workspace parent is not a folder: {value}"),
            Self::AtomNotFound(value) => format!("workspace atom not found: {value}"),
            Self::AtomNotNote(value) => format!("workspace atom is not a note: {value}"),
            Self::CycleDetected(value) => format!("workspace cycle detected: {value}"),
            Self::DbBusy(value) => format!("workspace database busy: {value}"),
            Self::DbError(value) => format!("workspace database error: {value}"),
            Self::Internal(value) => format!("workspace internal error: {value}"),
        }
    }
}

#[derive(Debug)]
enum NotesFfiError {
    InvalidNoteId(String),
    InvalidTag(String),
    NoteNotFound(String),
    DbBusy(String),
    DbError(String),
    InvalidArgument(String),
    Internal(String),
}

impl NotesFfiError {
    fn code(&self) -> &'static str {
        match self {
            Self::InvalidNoteId(_) => "invalid_note_id",
            Self::InvalidTag(_) => "invalid_tag",
            Self::NoteNotFound(_) => "note_not_found",
            Self::DbBusy(_) => "db_busy",
            Self::DbError(_) => "db_error",
            Self::InvalidArgument(_) => "invalid_argument",
            Self::Internal(_) => "internal_error",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::InvalidNoteId(value) => format!("invalid note id: {value}"),
            Self::InvalidTag(value) => format!("invalid tag: {value}"),
            Self::NoteNotFound(value) => format!("note not found: {value}"),
            Self::DbBusy(value) => format!("notes database busy: {value}"),
            Self::DbError(value) => format!("notes database error: {value}"),
            Self::InvalidArgument(value) => format!("invalid argument: {value}"),
            Self::Internal(value) => format!("internal error: {value}"),
        }
    }
}

/// Searches single-entry text using entry-level defaults.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Never panics.
/// - Returns deterministic envelope with applied limit.
/// - `kind`: optional `all|note|task|event` (case-insensitive).
/// - Returns `invalid_kind` when `kind` is outside allowed values.
#[flutter_rust_bridge::frb]
pub async fn entry_search(
    text: String,
    kind: Option<String>,
    limit: Option<u32>,
) -> EntrySearchResponse {
    entry_search_impl(text, kind, limit)
}

fn entry_search_impl(
    text: String,
    kind: Option<String>,
    limit: Option<u32>,
) -> EntrySearchResponse {
    let normalized_limit = normalize_entry_limit(limit);
    let query_text = text.trim().to_string();
    let parsed_kind = match parse_entry_search_kind(kind) {
        Ok(parsed) => parsed,
        Err(err) => {
            return EntrySearchResponse {
                ok: false,
                error_code: Some("invalid_kind".to_string()),
                items: Vec::new(),
                message: err,
                applied_limit: normalized_limit,
            };
        }
    };
    let db_path = resolve_entry_db_path();
    let conn = match open_db(&db_path) {
        Ok(conn) => conn,
        Err(err) => {
            return EntrySearchResponse {
                ok: false,
                error_code: Some("db_error".to_string()),
                items: Vec::new(),
                message: format!("entry_search failed: {err}"),
                applied_limit: normalized_limit,
            };
        }
    };

    let query = SearchQuery {
        text: query_text,
        kind: parsed_kind,
        limit: normalized_limit,
        raw_fts_syntax: false,
    };

    match search_all(&conn, &query) {
        Ok(hits) => {
            let items = hits
                .into_iter()
                .map(to_entry_search_item)
                .collect::<Vec<_>>();
            let message = if items.is_empty() {
                "No results.".to_string()
            } else {
                format!("Found {} result(s).", items.len())
            };
            EntrySearchResponse {
                ok: true,
                error_code: None,
                items,
                message,
                applied_limit: normalized_limit,
            }
        }
        Err(err) => EntrySearchResponse {
            ok: false,
            error_code: Some("internal_error".to_string()),
            items: Vec::new(),
            message: format!("entry_search failed: {err}"),
            applied_limit: normalized_limit,
        },
    }
}

fn parse_entry_search_kind(raw: Option<String>) -> Result<Option<AtomType>, String> {
    let Some(value) = raw else {
        return Ok(None);
    };
    let normalized = value.trim().to_ascii_lowercase();
    if normalized.is_empty() || normalized == "all" {
        return Ok(None);
    }
    match normalized.as_str() {
        "note" => Ok(Some(AtomType::Note)),
        "task" => Ok(Some(AtomType::Task)),
        "event" => Ok(Some(AtomType::Event)),
        _ => Err(format!(
            "invalid kind `{value}`; expected one of all|note|task|event"
        )),
    }
}

/// Creates a note from single-entry command flow.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb]
pub async fn entry_create_note(content: String) -> EntryActionResponse {
    entry_create_note_impl(content)
}

fn entry_create_note_impl(content: String) -> EntryActionResponse {
    match with_atom_service(|service| service.create_note(content.trim().to_string())) {
        Ok(atom_id) => EntryActionResponse::success("Note created.", atom_id.to_string()),
        Err(err) => EntryActionResponse::failure(format!("entry_create_note failed: {err}")),
    }
}

/// Creates a task from single-entry command flow.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb]
pub async fn entry_create_task(content: String) -> EntryActionResponse {
    entry_create_task_impl(content)
}

fn entry_create_task_impl(content: String) -> EntryActionResponse {
    match with_atom_service(|service| service.create_task(content.trim().to_string())) {
        Ok(atom_id) => EntryActionResponse::success("Task created.", atom_id.to_string()),
        Err(err) => EntryActionResponse::failure(format!("entry_create_task failed: {err}")),
    }
}

/// Schedules an event from single-entry command flow.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Accepts point (`end_epoch_ms=None`) and range (`Some(end)`) shapes.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb]
pub async fn entry_schedule(
    title: String,
    start_epoch_ms: i64,
    end_epoch_ms: Option<i64>,
) -> EntryActionResponse {
    entry_schedule_impl(title, start_epoch_ms, end_epoch_ms)
}

fn entry_schedule_impl(
    title: String,
    start_epoch_ms: i64,
    end_epoch_ms: Option<i64>,
) -> EntryActionResponse {
    let request = ScheduleEventRequest {
        title: title.trim().to_string(),
        start_epoch_ms,
        end_epoch_ms,
    };
    match with_atom_service(|service| service.schedule_event(&request)) {
        Ok(atom_id) => EntryActionResponse::success("Event scheduled.", atom_id.to_string()),
        Err(err) => EntryActionResponse::failure(format!("entry_schedule failed: {err}")),
    }
}

/// Creates one note from markdown content.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Applies markdown preview hooks (`preview_text`, `preview_image`).
/// - Returns typed envelope with stable error codes.
#[flutter_rust_bridge::frb]
pub async fn note_create(content: String) -> NoteResponse {
    note_create_impl(content)
}

fn note_create_impl(content: String) -> NoteResponse {
    match with_note_service(|service| service.create_note(content)) {
        Ok(note) => NoteResponse {
            ok: true,
            error_code: None,
            message: "Note created.".to_string(),
            note: Some(to_note_item(note)),
        },
        Err(err) => NoteResponse {
            ok: false,
            error_code: Some(err.code().to_string()),
            message: err.message(),
            note: None,
        },
    }
}

/// Fully replaces note content by stable id.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `content` is treated as full markdown source replacement.
/// - Returns typed envelope with stable error codes.
#[flutter_rust_bridge::frb]
pub async fn note_update(atom_id: String, content: String) -> NoteResponse {
    note_update_impl(atom_id, content)
}

fn note_update_impl(atom_id: String, content: String) -> NoteResponse {
    let parsed_id = match parse_note_id(atom_id.as_str()) {
        Ok(value) => value,
        Err(err) => return note_failure(err),
    };

    match with_note_service(|service| service.update_note(parsed_id, content)) {
        Ok(note) => NoteResponse {
            ok: true,
            error_code: None,
            message: "Note updated.".to_string(),
            note: Some(to_note_item(note)),
        },
        Err(err) => note_failure(err),
    }
}

/// Gets one note by stable id.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Returns typed envelope with stable error codes.
#[flutter_rust_bridge::frb]
pub async fn note_get(atom_id: String) -> NoteResponse {
    note_get_impl(atom_id)
}

fn note_get_impl(atom_id: String) -> NoteResponse {
    let parsed_id = match parse_note_id(atom_id.as_str()) {
        Ok(value) => value,
        Err(err) => return note_failure(err),
    };

    match with_note_service(|service| {
        service
            .get_note(parsed_id)
            .map_err(NoteServiceError::from)?
            .ok_or(NoteServiceError::NoteNotFound(parsed_id))
    }) {
        Ok(note) => NoteResponse {
            ok: true,
            error_code: None,
            message: "Note loaded.".to_string(),
            note: Some(to_note_item(note)),
        },
        Err(err) => note_failure(err),
    }
}

/// Lists notes with optional single-tag filter and pagination.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Returns only `AtomType::Note` rows.
/// - Limit normalization: default 10, max 50.
#[flutter_rust_bridge::frb]
pub async fn notes_list(
    tag: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
) -> NotesListResponse {
    notes_list_impl(tag, limit, offset)
}

fn notes_list_impl(
    tag: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
) -> NotesListResponse {
    let resolved_offset = offset.unwrap_or(0);

    match with_note_service(|service| service.list_notes(tag, limit, resolved_offset)) {
        Ok(result) => NotesListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} note(s).", result.items.len()),
            items: result.items.into_iter().map(to_note_item).collect(),
            applied_limit: result.applied_limit,
        },
        Err(err) => NotesListResponse {
            ok: false,
            error_code: Some(err.code().to_string()),
            message: err.message(),
            items: Vec::new(),
            applied_limit: lazynote_core::normalize_note_limit(limit),
        },
    }
}

/// Atomically replaces full tag set for one note.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `tags` is treated as complete replacement, not incremental patch.
/// - Returns typed envelope with stable error codes.
#[flutter_rust_bridge::frb]
pub async fn note_set_tags(atom_id: String, tags: Vec<String>) -> NoteResponse {
    note_set_tags_impl(atom_id, tags)
}

fn note_set_tags_impl(atom_id: String, tags: Vec<String>) -> NoteResponse {
    let parsed_id = match parse_note_id(atom_id.as_str()) {
        Ok(value) => value,
        Err(err) => return note_failure(err),
    };

    match with_note_service(|service| service.set_note_tags(parsed_id, tags)) {
        Ok(note) => NoteResponse {
            ok: true,
            error_code: None,
            message: "Note tags replaced.".to_string(),
            note: Some(to_note_item(note)),
        },
        Err(err) => note_failure(err),
    }
}

/// Lists normalized tags known by storage.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Returns typed envelope with stable error codes.
#[flutter_rust_bridge::frb]
pub async fn tags_list() -> TagsListResponse {
    tags_list_impl()
}

fn tags_list_impl() -> TagsListResponse {
    match with_note_service(|service| service.list_tags().map_err(NoteServiceError::from)) {
        Ok(tags) => TagsListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} tag(s).", tags.len()),
            tags,
        },
        Err(err) => TagsListResponse {
            ok: false,
            error_code: Some(err.code().to_string()),
            message: err.message(),
            tags: Vec::new(),
        },
    }
}

/// Lists workspace child nodes under optional parent.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `parent_node_id` is optional UUID string; `None` lists root-level nodes.
#[flutter_rust_bridge::frb]
pub async fn workspace_list_children(
    parent_node_id: Option<String>,
) -> WorkspaceListChildrenResponse {
    workspace_list_children_impl(parent_node_id)
}

fn workspace_list_children_impl(parent_node_id: Option<String>) -> WorkspaceListChildrenResponse {
    let parsed_parent = match parse_optional_parent_node_id(parent_node_id) {
        Ok(value) => value,
        Err(err) => return workspace_list_failure(err),
    };

    match with_tree_service(|service| service.list_children(parsed_parent)) {
        Ok(nodes) => WorkspaceListChildrenResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} workspace node(s).", nodes.len()),
            items: nodes.into_iter().map(to_workspace_node_item).collect(),
        },
        Err(err) => workspace_list_failure(err),
    }
}

/// Creates one workspace folder under optional parent.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `parent_node_id` is optional UUID string; `None` creates root-level folder.
#[flutter_rust_bridge::frb]
pub async fn workspace_create_folder(
    parent_node_id: Option<String>,
    name: String,
) -> WorkspaceNodeResponse {
    workspace_create_folder_impl(parent_node_id, name)
}

fn workspace_create_folder_impl(
    parent_node_id: Option<String>,
    name: String,
) -> WorkspaceNodeResponse {
    let parsed_parent = match parse_optional_parent_node_id(parent_node_id) {
        Ok(value) => value,
        Err(err) => return workspace_node_failure(err),
    };

    match with_tree_service(|service| service.create_folder(parsed_parent, name)) {
        Ok(node) => WorkspaceNodeResponse {
            ok: true,
            error_code: None,
            message: "Workspace folder created.".to_string(),
            node: Some(to_workspace_node_item(node)),
        },
        Err(err) => workspace_node_failure(err),
    }
}

/// Creates one workspace note_ref under optional parent.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `atom_id` must be UUID string of a note atom.
#[flutter_rust_bridge::frb]
pub async fn workspace_create_note_ref(
    parent_node_id: Option<String>,
    atom_id: String,
    display_name: Option<String>,
) -> WorkspaceNodeResponse {
    workspace_create_note_ref_impl(parent_node_id, atom_id, display_name)
}

fn workspace_create_note_ref_impl(
    parent_node_id: Option<String>,
    atom_id: String,
    display_name: Option<String>,
) -> WorkspaceNodeResponse {
    let parsed_parent = match parse_optional_parent_node_id(parent_node_id) {
        Ok(value) => value,
        Err(err) => return workspace_node_failure(err),
    };
    let parsed_atom_id = match parse_workspace_atom_id(atom_id.as_str()) {
        Ok(value) => value,
        Err(err) => return workspace_node_failure(err),
    };

    match with_tree_service(|service| {
        service.create_note_ref(parsed_parent, parsed_atom_id, display_name)
    }) {
        Ok(node) => WorkspaceNodeResponse {
            ok: true,
            error_code: None,
            message: "Workspace note reference created.".to_string(),
            node: Some(to_workspace_node_item(node)),
        },
        Err(err) => workspace_node_failure(err),
    }
}

/// Renames one workspace node.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `node_id` must be UUID string.
#[flutter_rust_bridge::frb]
pub async fn workspace_rename_node(node_id: String, new_name: String) -> WorkspaceActionResponse {
    workspace_rename_node_impl(node_id, new_name)
}

fn workspace_rename_node_impl(node_id: String, new_name: String) -> WorkspaceActionResponse {
    let parsed_id = match parse_workspace_node_id(node_id.as_str()) {
        Ok(value) => value,
        Err(err) => return workspace_failure(err),
    };
    match with_tree_service(|service| service.rename_node(parsed_id, new_name)) {
        Ok(()) => WorkspaceActionResponse {
            ok: true,
            error_code: None,
            message: "Workspace node renamed.".to_string(),
        },
        Err(err) => workspace_failure(err),
    }
}

/// Moves one workspace node under optional new parent and target order.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `new_parent_id = None` moves node to root level.
#[flutter_rust_bridge::frb]
pub async fn workspace_move_node(
    node_id: String,
    new_parent_id: Option<String>,
    target_order: Option<i64>,
) -> WorkspaceActionResponse {
    workspace_move_node_impl(node_id, new_parent_id, target_order)
}

fn workspace_move_node_impl(
    node_id: String,
    new_parent_id: Option<String>,
    target_order: Option<i64>,
) -> WorkspaceActionResponse {
    let parsed_id = match parse_workspace_node_id(node_id.as_str()) {
        Ok(value) => value,
        Err(err) => return workspace_failure(err),
    };
    let parsed_parent = match parse_optional_parent_node_id(new_parent_id) {
        Ok(value) => value,
        Err(err) => return workspace_failure(err),
    };

    match with_tree_service(|service| service.move_node(parsed_id, parsed_parent, target_order)) {
        Ok(()) => WorkspaceActionResponse {
            ok: true,
            error_code: None,
            message: "Workspace node moved.".to_string(),
        },
        Err(err) => workspace_failure(err),
    }
}

/// Deletes one workspace folder by explicit mode (`dissolve|delete_all`).
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - `node_id` must be UUID string of a folder node.
/// - `mode` must be one of `dissolve` or `delete_all`.
#[flutter_rust_bridge::frb]
pub async fn workspace_delete_folder(node_id: String, mode: String) -> WorkspaceActionResponse {
    workspace_delete_folder_impl(node_id, mode)
}

fn workspace_delete_folder_impl(node_id: String, mode: String) -> WorkspaceActionResponse {
    let parsed_id = match parse_workspace_node_id(node_id.as_str()) {
        Ok(value) => value,
        Err(err) => return workspace_failure(err),
    };

    let parsed_mode = match parse_folder_delete_mode(mode.as_str()) {
        Ok(value) => value,
        Err(err) => return workspace_failure(err),
    };

    match with_tree_service(|service| service.delete_folder(parsed_id, parsed_mode)) {
        Ok(()) => WorkspaceActionResponse {
            ok: true,
            error_code: None,
            message: "Workspace folder deleted.".to_string(),
        },
        Err(err) => workspace_failure(err),
    }
}

fn normalize_entry_limit(limit: Option<u32>) -> u32 {
    match limit {
        Some(0) => ENTRY_DEFAULT_LIMIT,
        Some(value) if value > ENTRY_SEARCH_MAX_LIMIT => ENTRY_SEARCH_MAX_LIMIT,
        Some(value) => value,
        None => ENTRY_DEFAULT_LIMIT,
    }
}

fn resolve_entry_db_path() -> PathBuf {
    if let Ok(raw) = std::env::var("LAZYNOTE_DB_PATH") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }

    match ENTRY_DB_PATH_OVERRIDE.lock() {
        Ok(guard) => {
            if let Some(path) = guard.as_ref() {
                return path.clone();
            }
        }
        Err(_) => {
            error!("event=db_path_resolve module=ffi status=error error_code=mutex_poisoned");
        }
    }

    std::env::temp_dir().join(ENTRY_DB_FILE_NAME)
}

fn set_configured_entry_db_path(db_path: &str) -> Result<(), String> {
    let trimmed = db_path.trim();
    if trimmed.is_empty() {
        return Err("db_path must not be empty".to_string());
    }

    let path = PathBuf::from(trimmed);
    if !path.is_absolute() {
        return Err("db_path must be an absolute path".to_string());
    }

    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|err| format!("failed to create db parent directory: {err}"))?;
        }
    }

    let mut guard = ENTRY_DB_PATH_OVERRIDE
        .lock()
        .map_err(|_| "entry db path lock poisoned".to_string())?;
    *guard = Some(path);
    Ok(())
}

fn with_atom_service(
    f: impl FnOnce(
        &AtomService<SqliteAtomRepository<'_>>,
    ) -> lazynote_core::RepoResult<lazynote_core::AtomId>,
) -> Result<lazynote_core::AtomId, String> {
    let db_path = resolve_entry_db_path();
    let conn = open_db(&db_path).map_err(|err| format!("entry DB open failed: {err}"))?;
    let repo = SqliteAtomRepository::try_new(&conn)
        .map_err(|err| format!("entry repo init failed: {err}"))?;
    let service = AtomService::new(repo);
    f(&service).map_err(|err| err.to_string())
}

fn with_note_service<T>(
    f: impl FnOnce(&mut NoteService<SqliteNoteRepository<'_>>) -> Result<T, NoteServiceError>,
) -> Result<T, NotesFfiError> {
    let db_path = resolve_entry_db_path();
    let mut conn = open_db(&db_path).map_err(map_db_error)?;
    let repo = SqliteNoteRepository::try_new(&mut conn).map_err(map_repo_error)?;
    let mut service = NoteService::new(repo);
    f(&mut service).map_err(map_note_service_error)
}

fn with_tree_service<T>(
    f: impl FnOnce(&TreeService<SqliteTreeRepository<'_>>) -> Result<T, TreeServiceError>,
) -> Result<T, WorkspaceFfiError> {
    let db_path = resolve_entry_db_path();
    let conn = open_db(&db_path).map_err(map_workspace_db_error)?;
    let repo = SqliteTreeRepository::try_new(&conn).map_err(map_tree_repo_error)?;
    let service = TreeService::new(repo);
    f(&service).map_err(map_tree_service_error)
}

fn parse_folder_delete_mode(raw: &str) -> Result<FolderDeleteMode, WorkspaceFfiError> {
    match raw.trim() {
        "dissolve" => Ok(FolderDeleteMode::Dissolve),
        "delete_all" => Ok(FolderDeleteMode::DeleteAll),
        other => Err(WorkspaceFfiError::InvalidDeleteMode(other.to_string())),
    }
}

fn parse_workspace_node_id(raw: &str) -> Result<Uuid, WorkspaceFfiError> {
    Uuid::parse_str(raw.trim()).map_err(|_| WorkspaceFfiError::InvalidNodeId(raw.to_string()))
}

fn parse_optional_parent_node_id(raw: Option<String>) -> Result<Option<Uuid>, WorkspaceFfiError> {
    match raw {
        None => Ok(None),
        Some(value) => {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                return Err(WorkspaceFfiError::InvalidParentNodeId(value));
            }
            Uuid::parse_str(trimmed)
                .map(Some)
                .map_err(|_| WorkspaceFfiError::InvalidParentNodeId(value))
        }
    }
}

fn parse_workspace_atom_id(raw: &str) -> Result<AtomId, WorkspaceFfiError> {
    Uuid::parse_str(raw.trim()).map_err(|_| WorkspaceFfiError::InvalidAtomId(raw.to_string()))
}

fn parse_note_id(raw: &str) -> Result<AtomId, NotesFfiError> {
    Uuid::parse_str(raw.trim()).map_err(|_| NotesFfiError::InvalidNoteId(raw.to_string()))
}

fn to_note_item(value: NoteRecord) -> NoteItem {
    NoteItem {
        atom_id: value.atom_id.to_string(),
        content: value.content,
        preview_text: value.preview_text,
        preview_image: value.preview_image,
        updated_at: value.updated_at,
        tags: value.tags,
    }
}

fn workspace_node_kind_label(kind: WorkspaceNodeKind) -> &'static str {
    match kind {
        WorkspaceNodeKind::Folder => "folder",
        WorkspaceNodeKind::NoteRef => "note_ref",
    }
}

fn to_workspace_node_item(node: WorkspaceNode) -> WorkspaceNodeItem {
    WorkspaceNodeItem {
        node_id: node.node_uuid.to_string(),
        kind: workspace_node_kind_label(node.kind).to_string(),
        parent_node_id: node.parent_uuid.map(|value| value.to_string()),
        atom_id: node.atom_uuid.map(|value| value.to_string()),
        display_name: node.display_name,
        sort_order: node.sort_order,
    }
}

fn note_failure(error: NotesFfiError) -> NoteResponse {
    NoteResponse {
        ok: false,
        error_code: Some(error.code().to_string()),
        message: error.message(),
        note: None,
    }
}

fn workspace_failure(error: WorkspaceFfiError) -> WorkspaceActionResponse {
    WorkspaceActionResponse {
        ok: false,
        error_code: Some(error.code().to_string()),
        message: error.message(),
    }
}

fn workspace_node_failure(error: WorkspaceFfiError) -> WorkspaceNodeResponse {
    WorkspaceNodeResponse {
        ok: false,
        error_code: Some(error.code().to_string()),
        message: error.message(),
        node: None,
    }
}

fn workspace_list_failure(error: WorkspaceFfiError) -> WorkspaceListChildrenResponse {
    WorkspaceListChildrenResponse {
        ok: false,
        error_code: Some(error.code().to_string()),
        message: error.message(),
        items: Vec::new(),
    }
}

fn map_note_service_error(err: NoteServiceError) -> NotesFfiError {
    match err {
        NoteServiceError::InvalidTag(value) => NotesFfiError::InvalidTag(value),
        NoteServiceError::NoteNotFound(atom_id) => NotesFfiError::NoteNotFound(atom_id.to_string()),
        NoteServiceError::Repo(repo_err) => map_repo_error(repo_err),
        NoteServiceError::InconsistentState(details) => {
            NotesFfiError::Internal(details.to_string())
        }
    }
}

fn map_repo_error(err: lazynote_core::RepoError) -> NotesFfiError {
    match err {
        lazynote_core::RepoError::NotFound(atom_id) => {
            NotesFfiError::NoteNotFound(atom_id.to_string())
        }
        lazynote_core::RepoError::Validation(validation) => {
            NotesFfiError::InvalidArgument(validation.to_string())
        }
        lazynote_core::RepoError::Db(db_err) => map_db_error(db_err),
        lazynote_core::RepoError::UninitializedConnection {
            expected_version,
            actual_version,
        } => NotesFfiError::DbError(format!(
            "repository requires schema {expected_version}, got {actual_version}"
        )),
        lazynote_core::RepoError::MissingRequiredTable(table) => {
            NotesFfiError::DbError(format!("missing required table `{table}`"))
        }
        lazynote_core::RepoError::MissingRequiredColumn { table, column } => {
            NotesFfiError::DbError(format!(
                "missing required column `{column}` in table `{table}`"
            ))
        }
        lazynote_core::RepoError::InvalidData(details) => NotesFfiError::Internal(details),
    }
}

fn map_db_error(err: lazynote_core::db::DbError) -> NotesFfiError {
    if is_db_busy(&err) {
        NotesFfiError::DbBusy(err.to_string())
    } else {
        NotesFfiError::DbError(err.to_string())
    }
}

fn map_workspace_db_error(err: lazynote_core::db::DbError) -> WorkspaceFfiError {
    if is_db_busy(&err) {
        WorkspaceFfiError::DbBusy(err.to_string())
    } else {
        WorkspaceFfiError::DbError(err.to_string())
    }
}

fn map_tree_repo_error(err: TreeRepoError) -> WorkspaceFfiError {
    match err {
        TreeRepoError::Db(db_err) => map_workspace_db_error(db_err),
        TreeRepoError::NodeNotFound(node_id) => {
            WorkspaceFfiError::NodeNotFound(node_id.to_string())
        }
        TreeRepoError::NodeNotFolder(node_id) => {
            WorkspaceFfiError::NodeNotFolder(node_id.to_string())
        }
        TreeRepoError::UninitializedConnection {
            expected_version,
            actual_version,
        } => WorkspaceFfiError::DbError(format!(
            "repository requires schema {expected_version}, got {actual_version}"
        )),
        TreeRepoError::MissingRequiredTable(table) => {
            WorkspaceFfiError::DbError(format!("missing required table `{table}`"))
        }
        TreeRepoError::MissingRequiredColumn { table, column } => WorkspaceFfiError::DbError(
            format!("missing required column `{column}` in table `{table}`"),
        ),
        TreeRepoError::InvalidData(details) => WorkspaceFfiError::Internal(details),
    }
}

fn map_tree_service_error(err: TreeServiceError) -> WorkspaceFfiError {
    match err {
        TreeServiceError::InvalidDisplayName => {
            WorkspaceFfiError::InvalidDisplayName("display name must not be blank".to_string())
        }
        TreeServiceError::NodeNotFound(node_id) => {
            WorkspaceFfiError::NodeNotFound(node_id.to_string())
        }
        TreeServiceError::ParentNotFound(node_id) => {
            WorkspaceFfiError::ParentNotFound(node_id.to_string())
        }
        TreeServiceError::ParentMustBeFolder(node_id) => {
            WorkspaceFfiError::ParentNotFolder(node_id.to_string())
        }
        TreeServiceError::NodeMustBeFolder(node_id) => {
            WorkspaceFfiError::NodeNotFolder(node_id.to_string())
        }
        TreeServiceError::AtomNotFound(atom_id) => {
            WorkspaceFfiError::AtomNotFound(atom_id.to_string())
        }
        TreeServiceError::AtomNotNote(atom_id) => {
            WorkspaceFfiError::AtomNotNote(atom_id.to_string())
        }
        TreeServiceError::CycleDetected {
            node_uuid,
            parent_uuid,
        } => WorkspaceFfiError::CycleDetected(format!("node={node_uuid} parent={parent_uuid}")),
        TreeServiceError::Repo(repo_err) => map_tree_repo_error(repo_err),
    }
}

fn is_db_busy(err: &lazynote_core::db::DbError) -> bool {
    matches!(
        err,
        lazynote_core::db::DbError::Sqlite(rusqlite::Error::SqliteFailure(sqlite_err, _))
            if sqlite_err.code == rusqlite::ErrorCode::DatabaseBusy
                || sqlite_err.code == rusqlite::ErrorCode::DatabaseLocked
    )
}

fn to_entry_search_item(hit: lazynote_core::SearchHit) -> EntrySearchItem {
    EntrySearchItem {
        atom_id: hit.atom_id.to_string(),
        kind: atom_type_label(hit.kind).to_string(),
        snippet: hit.snippet,
    }
}

fn atom_type_label(kind: AtomType) -> &'static str {
    match kind {
        AtomType::Note => "note",
        AtomType::Task => "task",
        AtomType::Event => "event",
    }
}

// ---------------------------------------------------------------------------
// Tasks / Section APIs (v0.1.5)
// ---------------------------------------------------------------------------

/// Atom list item returned by section queries (Inbox/Today/Upcoming).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AtomListItem {
    /// Stable atom ID in string form.
    pub atom_id: String,
    /// Atom projection kind (`note|task|event`).
    pub kind: String,
    /// Raw markdown content.
    pub content: String,
    /// Derived plain-text preview.
    pub preview_text: Option<String>,
    /// Derived first markdown image path.
    pub preview_image: Option<String>,
    /// Normalized lowercase tags for this atom.
    pub tags: Vec<String>,
    /// Epoch ms — start boundary (NULL = no start).
    pub start_at: Option<i64>,
    /// Epoch ms — end boundary (NULL = no end).
    pub end_at: Option<i64>,
    /// Current task status string, or null if statusless.
    pub task_status: Option<String>,
    /// Update timestamp in epoch milliseconds.
    pub updated_at: i64,
}

/// Section list response envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AtomListResponse {
    /// Whether operation succeeded.
    pub ok: bool,
    /// Stable machine-readable error code for failure paths.
    pub error_code: Option<String>,
    /// Human-readable message for diagnostics/UI.
    pub message: String,
    /// Section items.
    pub items: Vec<AtomListItem>,
    /// Effective limit after normalization.
    pub applied_limit: u32,
}

const SECTION_DEFAULT_LIMIT: u32 = 50;
const SECTION_LIMIT_MAX: u32 = 50;

#[derive(Debug)]
#[allow(dead_code)] // Internal reserved for future use
enum AtomFfiError {
    InvalidAtomId(String),
    AtomNotFound(String),
    InvalidStatus(String),
    InvalidTimeRange(String),
    DbError(String),
    Internal(String),
}

impl AtomFfiError {
    fn code(&self) -> &'static str {
        match self {
            Self::InvalidAtomId(_) => "invalid_atom_id",
            Self::AtomNotFound(_) => "atom_not_found",
            Self::InvalidStatus(_) => "invalid_status",
            Self::InvalidTimeRange(_) => "invalid_time_range",
            Self::DbError(_) => "db_error",
            Self::Internal(_) => "internal_error",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::InvalidAtomId(v) => format!("invalid atom id: {v}"),
            Self::AtomNotFound(v) => format!("atom not found: {v}"),
            Self::InvalidStatus(v) => format!("invalid status: {v}"),
            Self::InvalidTimeRange(v) => format!("invalid time range: {v}"),
            Self::DbError(v) => format!("database error: {v}"),
            Self::Internal(v) => format!("internal error: {v}"),
        }
    }
}

fn map_task_service_error(err: TaskServiceError) -> AtomFfiError {
    match err {
        TaskServiceError::AtomNotFound(id) => AtomFfiError::AtomNotFound(id.to_string()),
        TaskServiceError::Repo(lazynote_core::RepoError::Validation(
            lazynote_core::AtomValidationError::InvalidEventWindow { start, end },
        )) => {
            AtomFfiError::InvalidTimeRange(format!("end_at ({end}) must be >= start_at ({start})"))
        }
        TaskServiceError::Repo(repo_err) => AtomFfiError::DbError(repo_err.to_string()),
    }
}

fn with_task_service<T>(
    f: impl FnOnce(&TaskService<'_, SqliteAtomRepository<'_>>) -> Result<T, TaskServiceError>,
) -> Result<T, AtomFfiError> {
    let db_path = resolve_entry_db_path();
    let conn = open_db(&db_path).map_err(|e| AtomFfiError::DbError(e.to_string()))?;
    let repo =
        SqliteAtomRepository::try_new(&conn).map_err(|e| AtomFfiError::DbError(e.to_string()))?;
    let service = TaskService::new(&repo, &conn);
    f(&service).map_err(map_task_service_error)
}

fn normalize_section_limit(limit: Option<u32>) -> u32 {
    match limit {
        Some(0) => SECTION_DEFAULT_LIMIT,
        Some(v) if v > SECTION_LIMIT_MAX => SECTION_LIMIT_MAX,
        Some(v) => v,
        None => SECTION_DEFAULT_LIMIT,
    }
}

fn to_atom_list_item(sa: SectionAtom) -> AtomListItem {
    AtomListItem {
        atom_id: sa.atom.uuid.to_string(),
        kind: atom_type_label(sa.atom.kind).to_string(),
        content: sa.atom.content,
        preview_text: sa.atom.preview_text,
        preview_image: sa.atom.preview_image,
        tags: sa.tags,
        start_at: sa.atom.start_at,
        end_at: sa.atom.end_at,
        task_status: sa.atom.task_status.map(|s| {
            match s {
                lazynote_core::TaskStatus::Todo => "todo",
                lazynote_core::TaskStatus::InProgress => "in_progress",
                lazynote_core::TaskStatus::Done => "done",
                lazynote_core::TaskStatus::Cancelled => "cancelled",
            }
            .to_string()
        }),
        updated_at: sa.updated_at,
    }
}

fn atom_list_failure(err: AtomFfiError, limit: u32) -> AtomListResponse {
    AtomListResponse {
        ok: false,
        error_code: Some(err.code().to_string()),
        message: err.message(),
        items: Vec::new(),
        applied_limit: limit,
    }
}

/// Lists inbox atoms (both `start_at` and `end_at` NULL).
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Excludes done/cancelled atoms.
#[flutter_rust_bridge::frb]
pub async fn tasks_list_inbox(limit: Option<u32>, offset: Option<u32>) -> AtomListResponse {
    tasks_list_inbox_impl(limit, offset)
}

fn tasks_list_inbox_impl(limit: Option<u32>, offset: Option<u32>) -> AtomListResponse {
    let norm_limit = normalize_section_limit(limit);
    let norm_offset = offset.unwrap_or(0);
    match with_task_service(|svc| svc.fetch_inbox(norm_limit, norm_offset)) {
        Ok(items) => AtomListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} inbox item(s).", items.len()),
            items: items.into_iter().map(to_atom_list_item).collect(),
            applied_limit: norm_limit,
        },
        Err(err) => atom_list_failure(err, norm_limit),
    }
}

/// Lists atoms active today based on time-matrix rules.
///
/// # FFI contract
/// - `bod_ms`/`eod_ms`: device-local day boundaries in epoch ms.
/// - Async call, DB-backed execution.
/// - Excludes done/cancelled atoms.
#[flutter_rust_bridge::frb]
pub async fn tasks_list_today(
    bod_ms: i64,
    eod_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    tasks_list_today_impl(bod_ms, eod_ms, limit, offset)
}

fn tasks_list_today_impl(
    bod_ms: i64,
    eod_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    let norm_limit = normalize_section_limit(limit);
    let norm_offset = offset.unwrap_or(0);
    match with_task_service(|svc| svc.fetch_today(bod_ms, eod_ms, norm_limit, norm_offset)) {
        Ok(items) => AtomListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} today item(s).", items.len()),
            items: items.into_iter().map(to_atom_list_item).collect(),
            applied_limit: norm_limit,
        },
        Err(err) => atom_list_failure(err, norm_limit),
    }
}

/// Lists atoms anchored entirely in the future.
///
/// # FFI contract
/// - `eod_ms`: end of today in epoch ms.
/// - Async call, DB-backed execution.
/// - Excludes done/cancelled atoms.
#[flutter_rust_bridge::frb]
pub async fn tasks_list_upcoming(
    eod_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    tasks_list_upcoming_impl(eod_ms, limit, offset)
}

fn tasks_list_upcoming_impl(
    eod_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    let norm_limit = normalize_section_limit(limit);
    let norm_offset = offset.unwrap_or(0);
    match with_task_service(|svc| svc.fetch_upcoming(eod_ms, norm_limit, norm_offset)) {
        Ok(items) => AtomListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} upcoming item(s).", items.len()),
            items: items.into_iter().map(to_atom_list_item).collect(),
            applied_limit: norm_limit,
        },
        Err(err) => atom_list_failure(err, norm_limit),
    }
}

/// Updates `task_status` for any atom type (universal completion).
///
/// # FFI contract
/// - `status`: one of `todo|in_progress|done|cancelled`, or null to clear (demote).
/// - Async call, DB-backed execution.
/// - Idempotent: setting the same status twice succeeds.
#[flutter_rust_bridge::frb]
pub async fn atom_update_status(atom_id: String, status: Option<String>) -> EntryActionResponse {
    atom_update_status_impl(atom_id, status)
}

fn atom_update_status_impl(atom_id: String, status: Option<String>) -> EntryActionResponse {
    let parsed_id = match Uuid::parse_str(atom_id.trim()) {
        Ok(id) => id,
        Err(_) => {
            let err = AtomFfiError::InvalidAtomId(atom_id);
            return EntryActionResponse {
                ok: false,
                atom_id: None,
                message: err.message(),
            };
        }
    };

    let parsed_status = match status.as_deref() {
        None => None,
        Some("todo") => Some(lazynote_core::TaskStatus::Todo),
        Some("in_progress") => Some(lazynote_core::TaskStatus::InProgress),
        Some("done") => Some(lazynote_core::TaskStatus::Done),
        Some("cancelled") => Some(lazynote_core::TaskStatus::Cancelled),
        Some(other) => {
            let err = AtomFfiError::InvalidStatus(other.to_string());
            return EntryActionResponse {
                ok: false,
                atom_id: None,
                message: err.message(),
            };
        }
    };

    match with_task_service(|svc| svc.update_status(parsed_id, parsed_status)) {
        Ok(()) => EntryActionResponse {
            ok: true,
            atom_id: Some(parsed_id.to_string()),
            message: "Status updated.".to_string(),
        },
        Err(err) => EntryActionResponse {
            ok: false,
            atom_id: None,
            message: err.message(),
        },
    }
}

// ---------------------------------------------------------------------------
// Calendar APIs (PR-0012A)
// ---------------------------------------------------------------------------

/// Lists atoms with both `start_at` and `end_at` that overlap the given time range.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Includes all statuses (done/cancelled shown on calendar).
/// - Range overlap: `start_at < range_end AND end_at > range_start`.
#[flutter_rust_bridge::frb]
pub async fn calendar_list_by_range(
    start_ms: i64,
    end_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    calendar_list_by_range_impl(start_ms, end_ms, limit, offset)
}

fn calendar_list_by_range_impl(
    start_ms: i64,
    end_ms: i64,
    limit: Option<u32>,
    offset: Option<u32>,
) -> AtomListResponse {
    let norm_limit = normalize_section_limit(limit);
    let norm_offset = offset.unwrap_or(0);
    match with_task_service(|svc| {
        svc.fetch_by_time_range(start_ms, end_ms, norm_limit, norm_offset)
    }) {
        Ok(items) => AtomListResponse {
            ok: true,
            error_code: None,
            message: format!("Loaded {} calendar event(s).", items.len()),
            items: items.into_iter().map(to_atom_list_item).collect(),
            applied_limit: norm_limit,
        },
        Err(err) => atom_list_failure(err, norm_limit),
    }
}

/// Updates only `start_at` and `end_at` for a calendar event.
///
/// # FFI contract
/// - Async call, DB-backed execution.
/// - Validates `end_ms >= start_ms`; returns `invalid_time_range` on failure.
/// - Returns `atom_not_found` when target atom does not exist.
#[flutter_rust_bridge::frb]
pub async fn calendar_update_event(
    atom_id: String,
    start_ms: i64,
    end_ms: i64,
) -> EntryActionResponse {
    calendar_update_event_impl(atom_id, start_ms, end_ms)
}

fn calendar_update_event_impl(atom_id: String, start_ms: i64, end_ms: i64) -> EntryActionResponse {
    let parsed_id = match Uuid::parse_str(atom_id.trim()) {
        Ok(id) => id,
        Err(_) => {
            let err = AtomFfiError::InvalidAtomId(atom_id);
            return EntryActionResponse {
                ok: false,
                atom_id: None,
                message: err.message(),
            };
        }
    };

    match with_task_service(|svc| svc.update_event_times(parsed_id, start_ms, end_ms)) {
        Ok(()) => EntryActionResponse {
            ok: true,
            atom_id: Some(parsed_id.to_string()),
            message: "Event times updated.".to_string(),
        },
        Err(err) => EntryActionResponse {
            ok: false,
            atom_id: None,
            message: err.message(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{
        calendar_list_by_range_impl, calendar_update_event_impl, configure_entry_db_path,
        core_version, entry_create_note_impl, entry_create_task_impl, entry_schedule_impl,
        entry_search_impl, init_logging, map_db_error, map_repo_error, map_workspace_db_error,
        note_create_impl, note_get_impl, note_set_tags_impl, note_update_impl, notes_list_impl,
        ping, tags_list_impl, workspace_create_folder_impl, workspace_create_note_ref_impl,
        workspace_delete_folder_impl, workspace_list_children_impl, workspace_move_node_impl,
        workspace_rename_node_impl, NotesFfiError, WorkspaceFfiError,
    };
    use lazynote_core::db::open_db;
    use lazynote_core::{SqliteTreeRepository, TreeService};
    use std::sync::{Mutex, MutexGuard};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_DB_LOCK: Mutex<()> = Mutex::new(());

    fn acquire_test_db_lock() -> MutexGuard<'static, ()> {
        TEST_DB_LOCK
            .lock()
            .expect("ffi api test db lock should not be poisoned")
    }

    #[test]
    fn ping_returns_pong() {
        let _guard = acquire_test_db_lock();
        assert_eq!(ping(), "pong");
    }

    #[test]
    fn version_is_not_empty() {
        let _guard = acquire_test_db_lock();
        assert!(!core_version().is_empty());
    }

    #[test]
    fn init_logging_rejects_empty_log_dir() {
        let _guard = acquire_test_db_lock();
        let error = init_logging("info".to_string(), String::new());
        assert!(!error.is_empty());
    }

    #[test]
    fn init_logging_rejects_unsupported_level() {
        let _guard = acquire_test_db_lock();
        let error = init_logging("verbose".to_string(), "tmp/logs".to_string());
        assert!(!error.is_empty());
    }

    #[test]
    fn configure_entry_db_path_rejects_empty_path() {
        let _guard = acquire_test_db_lock();
        let error = configure_entry_db_path(String::new());
        assert!(!error.is_empty());
    }

    #[test]
    fn configure_entry_db_path_rejects_relative_path() {
        let _guard = acquire_test_db_lock();
        let error = configure_entry_db_path("relative/path.sqlite3".to_string());
        assert!(!error.is_empty());
    }

    #[test]
    fn entry_search_normalizes_limit_and_finds_created_note() {
        let _guard = acquire_test_db_lock();
        let token = unique_token("entry-search");
        let created = entry_create_note_impl(format!("note {token}"));
        assert!(created.ok, "{}", created.message);
        let created_id = created
            .atom_id
            .clone()
            .expect("created note should return atom_id");

        let response = entry_search_impl(token, None, Some(200));
        assert_eq!(response.applied_limit, 50);
        assert!(response.ok, "{}", response.message);
        assert!(response.error_code.is_none());
        assert!(response.items.iter().any(|item| item.atom_id == created_id));
    }

    #[test]
    fn entry_search_rejects_invalid_kind() {
        let _guard = acquire_test_db_lock();
        let response = entry_search_impl("hello".to_string(), Some("memo".to_string()), Some(7));
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_kind"));
        assert_eq!(response.applied_limit, 7);
    }

    #[test]
    fn entry_search_filters_results_by_kind() {
        let _guard = acquire_test_db_lock();
        let token = unique_token("entry-search-kind");

        let note = entry_create_note_impl(format!("note {token}"));
        assert!(note.ok, "{}", note.message);

        let task = entry_create_task_impl(format!("task {token}"));
        assert!(task.ok, "{}", task.message);

        let note_response = entry_search_impl(token.clone(), Some("note".to_string()), Some(50));
        assert!(note_response.ok, "{}", note_response.message);
        assert!(!note_response.items.is_empty());
        assert!(note_response.items.iter().all(|item| item.kind == "note"));

        let task_response = entry_search_impl(token, Some("task".to_string()), Some(50));
        assert!(task_response.ok, "{}", task_response.message);
        assert!(!task_response.items.is_empty());
        assert!(task_response.items.iter().all(|item| item.kind == "task"));
    }

    #[test]
    fn entry_create_task_sets_default_todo_status() {
        let _guard = acquire_test_db_lock();
        let task = entry_create_task_impl("todo".to_string());
        assert!(task.ok, "{}", task.message);
        let atom_id = task.atom_id.expect("task create should return atom_id");

        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let (kind, status): (String, Option<String>) = conn
            .query_row(
                "SELECT type, task_status FROM atoms WHERE uuid = ?1",
                [atom_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .expect("query task row");
        assert_eq!(kind, "task");
        assert_eq!(status.as_deref(), Some("todo"));
    }

    #[test]
    fn entry_schedule_supports_point_shape() {
        let _guard = acquire_test_db_lock();
        let title = unique_token("entry-schedule-point");
        let response = entry_schedule_impl(title, 1_700_000_000_000, None);
        assert!(response.ok, "{}", response.message);
        let atom_id = response.atom_id.expect("schedule should return atom_id");

        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let (kind, start, end): (String, Option<i64>, Option<i64>) = conn
            .query_row(
                "SELECT type, start_at, end_at FROM atoms WHERE uuid = ?1",
                [atom_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("query event row");
        assert_eq!(kind, "event");
        assert_eq!(start, Some(1_700_000_000_000));
        assert_eq!(end, None);
    }

    #[test]
    fn entry_schedule_rejects_reversed_time_range() {
        let _guard = acquire_test_db_lock();
        let response = entry_schedule_impl("bad range".to_string(), 2_000, Some(1_000));
        assert!(!response.ok);
        assert!(response.message.contains("end_at"));
    }

    #[test]
    fn note_create_and_get_returns_typed_payload() {
        let _guard = acquire_test_db_lock();
        let created = note_create_impl("# heading ![](first.png)".to_string());
        assert!(created.ok, "{}", created.message);
        assert!(created.error_code.is_none());
        let atom_id = created
            .note
            .as_ref()
            .expect("note payload should exist")
            .atom_id
            .clone();

        let loaded = note_get_impl(atom_id);
        assert!(loaded.ok, "{}", loaded.message);
        assert!(loaded.error_code.is_none());
        assert_eq!(
            loaded
                .note
                .as_ref()
                .and_then(|note| note.preview_image.as_deref()),
            Some("first.png")
        );
    }

    #[test]
    fn note_update_uses_full_replace_and_updates_preview() {
        let _guard = acquire_test_db_lock();
        let created = note_create_impl("first body".to_string());
        assert!(created.ok, "{}", created.message);
        let atom_id = created
            .note
            .as_ref()
            .expect("created note payload")
            .atom_id
            .clone();

        let updated = note_update_impl(atom_id, "second body ![](two.png)".to_string());
        assert!(updated.ok, "{}", updated.message);
        assert_eq!(
            updated
                .note
                .as_ref()
                .and_then(|note| note.preview_image.as_deref()),
            Some("two.png")
        );
    }

    #[test]
    fn notes_list_caps_limit_and_filters_single_tag() {
        let _guard = acquire_test_db_lock();
        let first = note_create_impl("work note".to_string());
        assert!(first.ok, "{}", first.message);
        let first_id = first.note.as_ref().expect("first note").atom_id.clone();
        let second = note_create_impl("other note".to_string());
        assert!(second.ok, "{}", second.message);
        let second_id = second.note.as_ref().expect("second note").atom_id.clone();

        let tag_set = note_set_tags_impl(
            first_id.clone(),
            vec![
                "Work".to_string(),
                "work".to_string(),
                "Important".to_string(),
            ],
        );
        assert!(tag_set.ok, "{}", tag_set.message);

        let filtered = notes_list_impl(Some("work".to_string()), Some(200), Some(0));
        assert!(filtered.ok, "{}", filtered.message);
        assert_eq!(filtered.applied_limit, 50);
        assert!(filtered.items.iter().any(|item| item.atom_id == first_id));
        assert!(!filtered.items.iter().any(|item| item.atom_id == second_id));
    }

    #[test]
    fn notes_list_rejects_blank_tag_with_invalid_tag_error_code() {
        let _guard = acquire_test_db_lock();
        let created = note_create_impl("blank tag filter source".to_string());
        assert!(created.ok, "{}", created.message);

        let response = notes_list_impl(Some("   ".to_string()), Some(20), Some(0));
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_tag"));
    }

    #[test]
    fn note_set_tags_normalizes_values_and_refreshes_updated_at() {
        let _guard = acquire_test_db_lock();
        let created = note_create_impl("tag update target".to_string());
        assert!(created.ok, "{}", created.message);
        let atom_id = created
            .note
            .as_ref()
            .expect("created note payload")
            .atom_id
            .clone();

        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        conn.execute(
            "UPDATE atoms SET updated_at = 1000 WHERE uuid = ?1;",
            [atom_id.as_str()],
        )
        .expect("set old updated_at");

        let tagged = note_set_tags_impl(
            atom_id,
            vec![
                "Work".to_string(),
                "work".to_string(),
                "Important".to_string(),
            ],
        );
        assert!(tagged.ok, "{}", tagged.message);
        let note = tagged.note.expect("note payload should exist");
        assert_eq!(note.tags, vec!["important".to_string(), "work".to_string()]);
        assert!(note.updated_at > 1000);
    }

    #[test]
    fn note_get_invalid_id_returns_error_code() {
        let _guard = acquire_test_db_lock();
        let response = note_get_impl("not-a-uuid".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_note_id"));
    }

    #[test]
    fn invalid_persisted_data_maps_to_internal_error() {
        let mapped = map_repo_error(lazynote_core::RepoError::InvalidData(
            "broken row".to_string(),
        ));
        assert!(matches!(mapped, NotesFfiError::Internal(details) if details == "broken row"));
    }

    #[test]
    fn sqlite_busy_maps_to_db_busy_error_code() {
        let mapped = map_db_error(lazynote_core::db::DbError::Sqlite(
            rusqlite::Error::SqliteFailure(
                rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_BUSY),
                Some("database is busy".to_string()),
            ),
        ));
        assert!(matches!(mapped, NotesFfiError::DbBusy(_)));
    }

    #[test]
    fn sqlite_locked_maps_to_db_busy_error_code() {
        let mapped = map_db_error(lazynote_core::db::DbError::Sqlite(
            rusqlite::Error::SqliteFailure(
                rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_LOCKED),
                Some("database is locked".to_string()),
            ),
        ));
        assert!(matches!(mapped, NotesFfiError::DbBusy(_)));
    }

    #[test]
    fn workspace_sqlite_busy_maps_to_db_busy_error_code() {
        let mapped = map_workspace_db_error(lazynote_core::db::DbError::Sqlite(
            rusqlite::Error::SqliteFailure(
                rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_BUSY),
                Some("database is busy".to_string()),
            ),
        ));
        assert!(matches!(mapped, WorkspaceFfiError::DbBusy(_)));
    }

    #[test]
    fn workspace_sqlite_locked_maps_to_db_busy_error_code() {
        let mapped = map_workspace_db_error(lazynote_core::db::DbError::Sqlite(
            rusqlite::Error::SqliteFailure(
                rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_LOCKED),
                Some("database is locked".to_string()),
            ),
        ));
        assert!(matches!(mapped, WorkspaceFfiError::DbBusy(_)));
    }

    #[test]
    fn tags_list_returns_normalized_values() {
        let _guard = acquire_test_db_lock();
        let created = note_create_impl("tag source".to_string());
        assert!(created.ok, "{}", created.message);
        let atom_id = created
            .note
            .as_ref()
            .expect("created note payload")
            .atom_id
            .clone();
        let tagged = note_set_tags_impl(atom_id, vec!["Work".to_string(), "HOME".to_string()]);
        assert!(tagged.ok, "{}", tagged.message);

        let tags = tags_list_impl();
        assert!(tags.ok, "{}", tags.message);
        assert!(tags.tags.contains(&"work".to_string()));
        assert!(tags.tags.contains(&"home".to_string()));
    }

    fn create_workspace_folder(name: &str) -> String {
        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let repo = SqliteTreeRepository::try_new(&conn).expect("init tree repo");
        let service = TreeService::new(repo);
        service
            .create_folder(None, name.to_string())
            .expect("create workspace folder")
            .node_uuid
            .to_string()
    }

    fn create_workspace_note_ref_node() -> String {
        let created_note = note_create_impl("workspace note".to_string());
        assert!(created_note.ok, "{}", created_note.message);
        let atom_id = created_note
            .note
            .as_ref()
            .expect("note payload")
            .atom_id
            .clone();
        let parsed_atom_id = uuid::Uuid::parse_str(atom_id.as_str()).expect("parse atom id");

        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let repo = SqliteTreeRepository::try_new(&conn).expect("init tree repo");
        let service = TreeService::new(repo);
        service
            .create_note_ref(None, parsed_atom_id, Some("note-ref".to_string()))
            .expect("create workspace note_ref")
            .node_uuid
            .to_string()
    }

    fn create_workspace_folder_via_ffi(name: &str) -> String {
        let response = workspace_create_folder_impl(None, name.to_string());
        assert!(response.ok, "{}", response.message);
        response
            .node
            .expect("workspace node payload")
            .node_id
            .to_string()
    }

    #[test]
    fn workspace_create_folder_returns_node_payload() {
        let _guard = acquire_test_db_lock();
        let name = unique_token("workspace-folder");
        let response = workspace_create_folder_impl(None, name.clone());
        assert!(response.ok, "{}", response.message);
        let node = response.node.expect("workspace node payload");
        assert_eq!(node.kind, "folder");
        assert_eq!(node.display_name, name);
        assert!(uuid::Uuid::parse_str(node.node_id.as_str()).is_ok());
        assert!(node.parent_node_id.is_none());
        assert!(node.atom_id.is_none());
    }

    #[test]
    fn workspace_create_folder_rejects_invalid_parent_node_id() {
        let _guard = acquire_test_db_lock();
        let response = workspace_create_folder_impl(
            Some("not-a-uuid".to_string()),
            "invalid parent".to_string(),
        );
        assert!(!response.ok);
        assert_eq!(
            response.error_code.as_deref(),
            Some("invalid_parent_node_id")
        );
    }

    #[test]
    fn workspace_create_folder_maps_parent_not_found_error_code() {
        let _guard = acquire_test_db_lock();
        let missing_parent = uuid::Uuid::new_v4().to_string();
        let response =
            workspace_create_folder_impl(Some(missing_parent), "child-folder".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("parent_not_found"));
    }

    #[test]
    fn workspace_create_folder_maps_parent_not_folder_error_code() {
        let _guard = acquire_test_db_lock();
        let parent_note_ref = create_workspace_note_ref_node();
        let response =
            workspace_create_folder_impl(Some(parent_note_ref), "child-folder".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("parent_not_folder"));
    }

    #[test]
    fn workspace_list_children_returns_created_root_folder() {
        let _guard = acquire_test_db_lock();
        let name = unique_token("workspace-list-root");
        let created_id = create_workspace_folder_via_ffi(name.as_str());

        let response = workspace_list_children_impl(None);
        assert!(response.ok, "{}", response.message);
        assert!(
            response
                .items
                .iter()
                .any(|item| item.node_id == created_id && item.display_name == name),
            "created root folder should appear in list_children(None)"
        );
    }

    #[test]
    fn workspace_create_note_ref_rejects_invalid_atom_id() {
        let _guard = acquire_test_db_lock();
        let response = workspace_create_note_ref_impl(None, "not-a-uuid".to_string(), None);
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_atom_id"));
    }

    #[test]
    fn workspace_create_note_ref_maps_atom_not_found_error_code() {
        let _guard = acquire_test_db_lock();
        let missing_atom = uuid::Uuid::new_v4().to_string();
        let response = workspace_create_note_ref_impl(None, missing_atom, None);
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("atom_not_found"));
    }

    #[test]
    fn workspace_create_note_ref_rejects_non_note_atom() {
        let _guard = acquire_test_db_lock();
        let created = entry_create_task_impl("workspace task".to_string());
        assert!(created.ok, "{}", created.message);
        let atom_id = created.atom_id.expect("task atom id");
        let response = workspace_create_note_ref_impl(None, atom_id, None);
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("atom_not_note"));
    }

    #[test]
    fn workspace_rename_node_rejects_blank_name() {
        let _guard = acquire_test_db_lock();
        let node_id = create_workspace_folder_via_ffi("rename-target");
        let response = workspace_rename_node_impl(node_id, "   ".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_display_name"));
    }

    #[test]
    fn workspace_move_node_rejects_cycle() {
        let _guard = acquire_test_db_lock();
        let parent_id = create_workspace_folder_via_ffi("move-parent");
        let child_response =
            workspace_create_folder_impl(Some(parent_id.clone()), "move-child".to_string());
        assert!(child_response.ok, "{}", child_response.message);
        let child_id = child_response
            .node
            .expect("child node payload")
            .node_id
            .to_string();

        let move_response = workspace_move_node_impl(parent_id, Some(child_id), None);
        assert!(!move_response.ok);
        assert_eq!(move_response.error_code.as_deref(), Some("cycle_detected"));
    }

    #[test]
    fn workspace_delete_folder_rejects_invalid_node_id() {
        let _guard = acquire_test_db_lock();
        let response =
            workspace_delete_folder_impl("not-a-uuid".to_string(), "dissolve".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_node_id"));
    }

    #[test]
    fn workspace_delete_folder_rejects_invalid_mode() {
        let _guard = acquire_test_db_lock();
        let folder_id = create_workspace_folder("invalid-mode");
        let response = workspace_delete_folder_impl(folder_id, "archive".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("invalid_delete_mode"));
    }

    #[test]
    fn workspace_delete_folder_maps_node_not_found_error_code() {
        let _guard = acquire_test_db_lock();
        let random_id = uuid::Uuid::new_v4().to_string();
        let response = workspace_delete_folder_impl(random_id, "dissolve".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("node_not_found"));
    }

    #[test]
    fn workspace_delete_folder_maps_node_not_folder_error_code() {
        let _guard = acquire_test_db_lock();
        let node_id = create_workspace_note_ref_node();
        let response = workspace_delete_folder_impl(node_id, "dissolve".to_string());
        assert!(!response.ok);
        assert_eq!(response.error_code.as_deref(), Some("node_not_folder"));
    }

    #[test]
    fn workspace_delete_folder_supports_both_modes() {
        let _guard = acquire_test_db_lock();
        let dissolve_folder = create_workspace_folder("dissolve-ok");
        let delete_all_folder = create_workspace_folder("delete-all-ok");

        let dissolve_response =
            workspace_delete_folder_impl(dissolve_folder, "dissolve".to_string());
        assert!(dissolve_response.ok, "{}", dissolve_response.message);
        assert!(dissolve_response.error_code.is_none());

        let delete_all_response =
            workspace_delete_folder_impl(delete_all_folder, "delete_all".to_string());
        assert!(delete_all_response.ok, "{}", delete_all_response.message);
        assert!(delete_all_response.error_code.is_none());
    }

    // -----------------------------------------------------------------------
    // Calendar API tests (PR-0012A)
    // -----------------------------------------------------------------------

    /// Helper: creates an event atom with given start/end times via entry_schedule.
    fn create_test_event(title: &str, start_ms: i64, end_ms: i64) -> String {
        let resp = entry_schedule_impl(title.to_string(), start_ms, Some(end_ms));
        assert!(resp.ok, "create_test_event failed: {}", resp.message);
        resp.atom_id.expect("event should return atom_id")
    }

    #[test]
    fn calendar_list_by_range_returns_overlapping_events() {
        let _guard = acquire_test_db_lock();
        // Event: 10:00–12:00 (10_000–12_000)
        let inside_id = create_test_event("overlap", 10_000, 12_000);
        // Event: 20:00–22:00 (20_000–22_000) — outside range
        let _outside_id = create_test_event("outside", 20_000, 22_000);

        // Query range: 9:00–13:00 (9_000–13_000)
        let resp = calendar_list_by_range_impl(9_000, 13_000, None, None);
        assert!(resp.ok, "{}", resp.message);
        assert!(
            resp.items.iter().any(|i| i.atom_id == inside_id),
            "overlapping event should be in results"
        );
        assert!(
            !resp.items.iter().any(|i| i.atom_id == _outside_id),
            "non-overlapping event should not be in results"
        );
    }

    #[test]
    fn calendar_list_by_range_includes_done_events() {
        let _guard = acquire_test_db_lock();
        let event_id = create_test_event("done-cal", 30_000, 32_000);

        // Mark as done
        let status_resp =
            super::atom_update_status_impl(event_id.clone(), Some("done".to_string()));
        assert!(status_resp.ok, "{}", status_resp.message);

        // Query should still include it
        let resp = calendar_list_by_range_impl(29_000, 33_000, None, None);
        assert!(resp.ok, "{}", resp.message);
        assert!(
            resp.items.iter().any(|i| i.atom_id == event_id),
            "done event should appear in calendar range query"
        );
    }

    #[test]
    fn calendar_update_event_validates_time_range() {
        let _guard = acquire_test_db_lock();
        let event_id = create_test_event("validate-range", 40_000, 42_000);

        // end < start should fail
        let resp = calendar_update_event_impl(event_id, 42_000, 40_000);
        assert!(!resp.ok);
        assert!(
            resp.message.contains("invalid time range"),
            "should contain error message, got: {}",
            resp.message
        );
    }

    #[test]
    fn calendar_update_event_not_found() {
        let _guard = acquire_test_db_lock();
        let fake_id = uuid::Uuid::new_v4().to_string();
        let resp = calendar_update_event_impl(fake_id, 50_000, 52_000);
        assert!(!resp.ok);
        assert!(
            resp.message.contains("not found"),
            "should contain not found, got: {}",
            resp.message
        );
    }

    #[test]
    fn calendar_update_event_success() {
        let _guard = acquire_test_db_lock();
        let event_id = create_test_event("update-times", 60_000, 62_000);

        // Read original updated_at
        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let original_updated_at: i64 = conn
            .query_row(
                "SELECT updated_at FROM atoms WHERE uuid = ?1",
                [event_id.as_str()],
                |row| row.get(0),
            )
            .expect("read updated_at");

        // Update times
        let resp = calendar_update_event_impl(event_id.clone(), 70_000, 75_000);
        assert!(resp.ok, "{}", resp.message);
        assert_eq!(resp.atom_id.as_deref(), Some(event_id.as_str()));

        // Verify times changed
        let (start, end, new_updated_at): (Option<i64>, Option<i64>, i64) = conn
            .query_row(
                "SELECT start_at, end_at, updated_at FROM atoms WHERE uuid = ?1",
                [event_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read updated event");
        assert_eq!(start, Some(70_000));
        assert_eq!(end, Some(75_000));
        assert!(
            new_updated_at >= original_updated_at,
            "updated_at should advance"
        );
    }

    fn unique_token(prefix: &str) -> String {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time went backwards")
            .as_nanos();
        format!("{prefix}-{nanos}")
    }
}
