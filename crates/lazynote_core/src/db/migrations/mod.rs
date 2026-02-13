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
    MIGRATIONS
        .iter()
        .map(|migration| migration.version)
        .max()
        .unwrap_or(0)
}

/// Applies all pending migrations on the provided connection.
pub fn apply_migrations(conn: &mut Connection) -> DbResult<()> {
    validate_registry(MIGRATIONS)?;

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

fn validate_registry(migrations: &[Migration]) -> DbResult<()> {
    let mut previous = 0;
    for migration in migrations {
        if migration.version == 0 {
            return Err(DbError::InvalidMigrationRegistry(
                "migration version must start from 1",
            ));
        }

        if migration.version <= previous {
            return Err(DbError::InvalidMigrationRegistry(
                "migration versions must be strictly increasing and unique",
            ));
        }

        previous = migration.version;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{validate_registry, Migration};
    use crate::db::DbError;

    #[test]
    fn registry_rejects_non_increasing_versions() {
        let migrations = [
            Migration {
                version: 1,
                sql: "SELECT 1;",
            },
            Migration {
                version: 1,
                sql: "SELECT 1;",
            },
        ];

        let err = validate_registry(&migrations).unwrap_err();
        assert!(matches!(err, DbError::InvalidMigrationRegistry(_)));
    }

    #[test]
    fn registry_rejects_zero_version() {
        let migrations = [Migration {
            version: 0,
            sql: "SELECT 1;",
        }];

        let err = validate_registry(&migrations).unwrap_err();
        assert!(matches!(err, DbError::InvalidMigrationRegistry(_)));
    }
}
