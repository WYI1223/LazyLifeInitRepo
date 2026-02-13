//! Full-text search entry points.
//!
//! # Responsibility
//! - Expose query APIs backed by SQLite FTS5 index.
//! - Keep search result shaping inside core.
//!
//! # See also
//! - docs/releases/v0.1/prs/PR-0007-fts5-search.md

pub mod fts;
