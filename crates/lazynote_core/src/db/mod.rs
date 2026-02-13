//! SQLite storage bootstrap and schema migration entry points.
//!
//! # Responsibility
//! - Open and configure SQLite connections for LazyNote core.
//! - Apply schema migrations in deterministic order.
//!
//! # Invariants
//! - Migration version is tracked via `PRAGMA user_version`.
//! - Core code must not read/write application data before migrations succeed.
//!
//! # See also
//! - docs/architecture/data-model.md

use std::error::Error;
use std::fmt::{Display, Formatter};

pub mod migrations;
mod open;

pub use open::{open_db, open_db_in_memory};

/// Result type for DB bootstrap/open/migration operations.
pub type DbResult<T> = Result<T, DbError>;

/// Database-layer error for connection bootstrap and schema migration.
#[derive(Debug)]
pub enum DbError {
    /// Raw SQLite error returned by `rusqlite`.
    Sqlite(rusqlite::Error),
    /// Internal migration registry definition is malformed.
    InvalidMigrationRegistry(&'static str),
    /// Database schema version is newer than this binary supports.
    UnsupportedSchemaVersion {
        db_version: u32,
        latest_supported: u32,
    },
}

impl Display for DbError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Sqlite(err) => write!(f, "{err}"),
            Self::InvalidMigrationRegistry(details) => {
                write!(f, "invalid migration registry: {details}")
            }
            Self::UnsupportedSchemaVersion {
                db_version,
                latest_supported,
            } => write!(
                f,
                "database schema version {db_version} is newer than supported {latest_supported}"
            ),
        }
    }
}

impl Error for DbError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Sqlite(err) => Some(err),
            Self::InvalidMigrationRegistry(_) => None,
            Self::UnsupportedSchemaVersion { .. } => None,
        }
    }
}

impl From<rusqlite::Error> for DbError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Sqlite(value)
    }
}
