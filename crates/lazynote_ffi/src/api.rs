//! FFI use-case API for Flutter-facing calls.
//!
//! # Responsibility
//! - Expose stable, use-case-level functions to Dart via FRB.
//! - Keep error semantics simple for early-stage UI integration.
//!
//! # Invariants
//! - Exported functions must not panic across FFI boundary.
//! - Return values are UTF-8 strings with stable meaning.
//!
//! # See also
//! - docs/architecture/logging.md

use lazynote_core::db::open_db;
use lazynote_core::{
    core_version as core_version_inner, init_logging as init_logging_inner, ping as ping_inner,
    search_all, AtomService, AtomType, ScheduleEventRequest, SearchQuery, SqliteAtomRepository,
};
use std::path::PathBuf;
use std::sync::OnceLock;

const ENTRY_DEFAULT_LIMIT: u32 = 10;
const ENTRY_LIMIT_MAX: u32 = 10;
const ENTRY_DB_FILE_NAME: &str = "lazynote_entry.sqlite3";
static ENTRY_DB_PATH: OnceLock<PathBuf> = OnceLock::new();

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

/// Searches single-entry text using entry-level defaults.
///
/// # FFI contract
/// - Sync call, DB-backed execution.
/// - Never panics.
/// - Returns deterministic envelope with applied limit.
#[flutter_rust_bridge::frb(sync)]
pub fn entry_search(text: String, limit: Option<u32>) -> EntrySearchResponse {
    let normalized_limit = normalize_entry_limit(limit);
    let query_text = text.trim().to_string();
    let db_path = resolve_entry_db_path();
    let conn = match open_db(&db_path) {
        Ok(conn) => conn,
        Err(err) => {
            return EntrySearchResponse {
                items: Vec::new(),
                message: format!("entry_search failed: {err}"),
                applied_limit: normalized_limit,
            };
        }
    };

    let query = SearchQuery {
        text: query_text,
        kind: None,
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
                items,
                message,
                applied_limit: normalized_limit,
            }
        }
        Err(err) => EntrySearchResponse {
            items: Vec::new(),
            message: format!("entry_search failed: {err}"),
            applied_limit: normalized_limit,
        },
    }
}

/// Creates a note from single-entry command flow.
///
/// # FFI contract
/// - Sync call, DB-backed execution.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb(sync)]
pub fn entry_create_note(content: String) -> EntryActionResponse {
    match with_atom_service(|service| service.create_note(content.trim().to_string())) {
        Ok(atom_id) => EntryActionResponse::success("Note created.", atom_id.to_string()),
        Err(err) => EntryActionResponse::failure(format!("entry_create_note failed: {err}")),
    }
}

/// Creates a task from single-entry command flow.
///
/// # FFI contract
/// - Sync call, DB-backed execution.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb(sync)]
pub fn entry_create_task(content: String) -> EntryActionResponse {
    match with_atom_service(|service| service.create_task(content.trim().to_string())) {
        Ok(atom_id) => EntryActionResponse::success("Task created.", atom_id.to_string()),
        Err(err) => EntryActionResponse::failure(format!("entry_create_task failed: {err}")),
    }
}

/// Schedules an event from single-entry command flow.
///
/// # FFI contract
/// - Sync call, DB-backed execution.
/// - Accepts point (`end_epoch_ms=None`) and range (`Some(end)`) shapes.
/// - Never panics.
/// - Returns operation result and created atom ID on success.
#[flutter_rust_bridge::frb(sync)]
pub fn entry_schedule(
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

fn normalize_entry_limit(limit: Option<u32>) -> u32 {
    match limit {
        Some(0) => ENTRY_DEFAULT_LIMIT,
        Some(value) if value > ENTRY_LIMIT_MAX => ENTRY_LIMIT_MAX,
        Some(value) => value,
        None => ENTRY_DEFAULT_LIMIT,
    }
}

fn resolve_entry_db_path() -> PathBuf {
    ENTRY_DB_PATH
        .get_or_init(|| {
            if let Ok(raw) = std::env::var("LAZYNOTE_DB_PATH") {
                let trimmed = raw.trim();
                if !trimmed.is_empty() {
                    return PathBuf::from(trimmed);
                }
            }
            std::env::temp_dir().join(ENTRY_DB_FILE_NAME)
        })
        .clone()
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

#[cfg(test)]
mod tests {
    use super::{
        core_version, entry_create_note, entry_create_task, entry_schedule, entry_search,
        init_logging, ping,
    };
    use lazynote_core::db::open_db;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn ping_returns_pong() {
        assert_eq!(ping(), "pong");
    }

    #[test]
    fn version_is_not_empty() {
        assert!(!core_version().is_empty());
    }

    #[test]
    fn init_logging_rejects_empty_log_dir() {
        let error = init_logging("info".to_string(), String::new());
        assert!(!error.is_empty());
    }

    #[test]
    fn init_logging_rejects_unsupported_level() {
        let error = init_logging("verbose".to_string(), "tmp/logs".to_string());
        assert!(!error.is_empty());
    }

    #[test]
    fn entry_search_normalizes_limit_and_finds_created_note() {
        let token = unique_token("entry-search");
        let created = entry_create_note(format!("note {token}"));
        assert!(created.ok, "{}", created.message);
        let created_id = created
            .atom_id
            .clone()
            .expect("created note should return atom_id");

        let response = entry_search(token, Some(42));
        assert_eq!(response.applied_limit, 10);
        assert!(response.items.iter().any(|item| item.atom_id == created_id));
    }

    #[test]
    fn entry_create_task_sets_default_todo_status() {
        let task = entry_create_task("todo".to_string());
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
        let title = unique_token("entry-schedule-point");
        let response = entry_schedule(title, 1_700_000_000_000, None);
        assert!(response.ok, "{}", response.message);
        let atom_id = response.atom_id.expect("schedule should return atom_id");

        let conn = open_db(super::resolve_entry_db_path()).expect("open db");
        let (kind, start, end): (String, Option<i64>, Option<i64>) = conn
            .query_row(
                "SELECT type, event_start, event_end FROM atoms WHERE uuid = ?1",
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
        let response = entry_schedule("bad range".to_string(), 2_000, Some(1_000));
        assert!(!response.ok);
        assert!(response.message.contains("event_end"));
    }

    fn unique_token(prefix: &str) -> String {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time went backwards")
            .as_nanos();
        format!("{prefix}-{nanos}")
    }
}
