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
use log::{error, info, warn};
use rusqlite::Connection;
use std::time::Instant;

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
    Migration {
        version: 4,
        sql: include_str!("0004_fts.sql"),
    },
    Migration {
        version: 5,
        sql: include_str!("0005_note_preview.sql"),
    },
    Migration {
        version: 6,
        sql: include_str!("0006_time_matrix.sql"),
    },
    Migration {
        version: 7,
        sql: include_str!("0007_workspace_tree.sql"),
    },
    Migration {
        version: 8,
        sql: include_str!("0008_workspace_tree_delete_policy.sql"),
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
///
/// # Invariants
/// - Migrations run in strictly increasing version order.
/// - `PRAGMA user_version` is updated after each successful migration step.
/// - Migration execution is wrapped in one transaction.
///
/// # Errors
/// - Returns [`DbError::UnsupportedSchemaVersion`] when DB schema is newer than
///   this binary supports.
/// - Returns [`DbError::Sqlite`] when any migration step or commit fails.
pub fn apply_migrations(conn: &mut Connection) -> DbResult<()> {
    let started_at = Instant::now();
    validate_registry(MIGRATIONS)?;

    let current_version = current_user_version(conn)?;
    let latest = latest_version();

    if current_version > latest {
        warn!(
            "event=db_migrate_done module=db status=error from_version={} to_version={} duration_ms={} error_code=unsupported_schema_version",
            current_version,
            latest,
            started_at.elapsed().as_millis()
        );
        return Err(DbError::UnsupportedSchemaVersion {
            db_version: current_version,
            latest_supported: latest,
        });
    }

    if current_version == latest {
        info!(
            "event=db_migrate_done module=db status=ok from_version={} to_version={} applied_count=0 duration_ms={}",
            current_version,
            latest,
            started_at.elapsed().as_millis()
        );
        return Ok(());
    }

    info!(
        "event=db_migrate_start module=db status=start from_version={} to_version={}",
        current_version, latest
    );

    let tx = conn.transaction()?;
    let mut applied_count = 0u32;
    for migration in MIGRATIONS {
        if migration.version <= current_version {
            continue;
        }

        let step_started_at = Instant::now();
        info!(
            "event=db_migrate_step_start module=db status=start target_version={}",
            migration.version
        );

        tx.execute_batch(migration.sql).map_err(|err| {
            error!(
                "event=db_migrate_step_done module=db status=error target_version={} duration_ms={} error_code=migration_sql_failed error={}",
                migration.version,
                step_started_at.elapsed().as_millis(),
                err
            );
            DbError::Sqlite(err)
        })?;

        tx.execute_batch(&format!("PRAGMA user_version = {};", migration.version))
            .map_err(|err| {
                error!(
                    "event=db_migrate_step_done module=db status=error target_version={} duration_ms={} error_code=user_version_update_failed error={}",
                    migration.version,
                    step_started_at.elapsed().as_millis(),
                    err
                );
                DbError::Sqlite(err)
            })?;

        applied_count += 1;
        info!(
            "event=db_migrate_step_done module=db status=ok target_version={} duration_ms={}",
            migration.version,
            step_started_at.elapsed().as_millis()
        );
    }

    tx.commit().map_err(|err| {
        error!(
            "event=db_migrate_done module=db status=error from_version={} to_version={} applied_count={} duration_ms={} error_code=commit_failed error={}",
            current_version,
            latest,
            applied_count,
            started_at.elapsed().as_millis(),
            err
        );
        DbError::Sqlite(err)
    })?;

    info!(
        "event=db_migrate_done module=db status=ok from_version={} to_version={} applied_count={} duration_ms={}",
        current_version,
        latest,
        applied_count,
        started_at.elapsed().as_millis()
    );

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
