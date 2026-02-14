//! Core domain logic for LazyNote.
//! This crate is the single source of truth for business invariants.

/// Database open/migration APIs.
pub mod db;
/// Structured logging initialization and status APIs.
pub mod logging;
/// Canonical Atom data model.
pub mod model;
/// Persistence contracts and SQLite repository implementations.
pub mod repo;
/// FTS5 search APIs.
pub mod search;
/// Use-case orchestration services.
pub mod service;

/// Re-export logging entry points for FFI/UI layers.
pub use logging::{default_log_level, init_logging, logging_status};
/// Re-export canonical Atom model types.
pub use model::atom::{Atom, AtomId, AtomType, AtomValidationError, TaskStatus};
/// Re-export repository contracts and SQLite implementation.
pub use repo::atom_repo::{
    AtomListQuery, AtomRepository, RepoError, RepoResult, SqliteAtomRepository,
};
/// Re-export notes/tags repository models and implementation.
pub use repo::note_repo::{
    normalize_note_limit, normalize_tag, normalize_tags, NoteListQuery, NoteRecord, NoteRepository,
    SqliteNoteRepository,
};
/// Re-export search query/result models and search entry point.
pub use search::fts::{search_all, SearchError, SearchHit, SearchQuery, SearchResult};
/// Re-export atom service facade.
pub use service::atom_service::{AtomService, ScheduleEventRequest};
/// Re-export notes service facade and models.
pub use service::note_service::{
    derive_markdown_preview, MarkdownPreview, NoteService, NoteServiceError, NotesListResult,
};

/// Minimal health-check API for early integration.
pub fn ping() -> &'static str {
    "pong"
}

/// Returns the core crate version.
pub fn core_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::{core_version, ping};

    #[test]
    fn ping_returns_pong() {
        assert_eq!(ping(), "pong");
    }

    #[test]
    fn version_is_not_empty() {
        assert!(!core_version().is_empty());
    }
}
