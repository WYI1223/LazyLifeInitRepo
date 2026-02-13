//! Core domain logic for LazyNote.
//! This crate is the single source of truth for business invariants.

pub mod db;
pub mod model;
pub mod repo;
pub mod service;

pub use model::atom::{Atom, AtomId, AtomType, AtomValidationError, TaskStatus};
pub use repo::atom_repo::{
    AtomListQuery, AtomRepository, RepoError, RepoResult, SqliteAtomRepository,
};
pub use service::atom_service::AtomService;

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
