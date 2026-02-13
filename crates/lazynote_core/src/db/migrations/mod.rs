//! SQLite migration registry and executor.
//!
//! # Responsibility
//! - Register schema migrations in strictly increasing order.
//! - Apply pending migrations atomically.
//!
//! # Invariants
//! - `version` values must remain monotonic.
//! - Applied migration version is mirrored to `PRAGMA user_version`.
//!
//! # See also
//! - docs/releases/v0.1/prs/PR-0005-sqlite-schema-migrations.md

use crate::db::{DbError, DbResult};
use rusqlite::Connection;

#[derive(Debug, Clone, Copy)]
struct Migration {
    version: u32,
    sql: &'static str,
}

const MIGRATIONS: &[Migration] = &[
    Migration {
        version: 1,
        sql: include_str!("0001_init.sql"),
    },
    Migration {
        version: 2,
        sql: include_str!("0002_tags.sql"),
    },
    Migration {
        version: 3,
        sql: include_str!("0003_external_mappings.sql"),
    },
];

/// Returns the latest migration version known by this binary.
pub fn latest_version() -> u32 {
    MIGRATIONS.last().map_or(0, |migration| migration.version)
}

/// Applies all pending migrations on the provided connection.
pub fn apply_migrations(conn: &mut Connection) -> DbResult<()> {
    let current_version = current_user_version(conn)?;
    let latest = latest_version();

    if current_version > latest {
        return Err(DbError::UnsupportedSchemaVersion {
            db_version: current_version,
            latest_supported: latest,
        });
    }

    if current_version == latest {
        return Ok(());
    }

    let tx = conn.transaction()?;
    for migration in MIGRATIONS {
        if migration.version <= current_version {
            continue;
        }

        tx.execute_batch(migration.sql)?;
        tx.execute_batch(&format!("PRAGMA user_version = {};", migration.version))?;
    }
    tx.commit()?;

    Ok(())
}

fn current_user_version(conn: &Connection) -> DbResult<u32> {
    let version = conn.query_row("PRAGMA user_version;", [], |row| row.get::<_, u32>(0))?;
    Ok(version)
}
