//! Connection bootstrap utilities for SQLite.
//!
//! # Responsibility
//! - Open file or in-memory SQLite connections.
//! - Configure connection pragmas required by core behavior.
//! - Trigger schema migrations before returning a usable connection.
//!
//! # Invariants
//! - Returned connections have `foreign_keys=ON`.
//! - Returned connections have migrations fully applied.
//!
//! # See also
//! - docs/architecture/logging.md

use super::migrations::apply_migrations;
use super::DbResult;
use log::{error, info};
use rusqlite::Connection;
use std::path::Path;
use std::time::{Duration, Instant};

/// Opens a SQLite database file and applies all pending migrations.
///
/// # Side effects
/// - Performs connection bootstrap and migration checks.
/// - Emits `db_open` logging events with duration and status.
pub fn open_db(path: impl AsRef<Path>) -> DbResult<Connection> {
    let started_at = Instant::now();
    info!("event=db_open module=db status=start mode=file");

    let mut conn = match Connection::open(path) {
        Ok(conn) => conn,
        Err(err) => {
            error!(
                "event=db_open module=db status=error mode=file duration_ms={} error_code=db_open_failed error={}",
                started_at.elapsed().as_millis(),
                err
            );
            return Err(err.into());
        }
    };

    match bootstrap_connection(&mut conn) {
        Ok(()) => {
            info!(
                "event=db_open module=db status=ok mode=file duration_ms={}",
                started_at.elapsed().as_millis()
            );
            Ok(conn)
        }
        Err(err) => {
            error!(
                "event=db_open module=db status=error mode=file duration_ms={} error_code=db_bootstrap_failed error={}",
                started_at.elapsed().as_millis(),
                err
            );
            Err(err)
        }
    }
}

/// Opens an in-memory SQLite database and applies all pending migrations.
///
/// # Side effects
/// - Performs connection bootstrap and migration checks.
/// - Emits `db_open` logging events with duration and status.
pub fn open_db_in_memory() -> DbResult<Connection> {
    let started_at = Instant::now();
    info!("event=db_open module=db status=start mode=memory");

    let mut conn = match Connection::open_in_memory() {
        Ok(conn) => conn,
        Err(err) => {
            error!(
                "event=db_open module=db status=error mode=memory duration_ms={} error_code=db_open_failed error={}",
                started_at.elapsed().as_millis(),
                err
            );
            return Err(err.into());
        }
    };

    match bootstrap_connection(&mut conn) {
        Ok(()) => {
            info!(
                "event=db_open module=db status=ok mode=memory duration_ms={}",
                started_at.elapsed().as_millis()
            );
            Ok(conn)
        }
        Err(err) => {
            error!(
                "event=db_open module=db status=error mode=memory duration_ms={} error_code=db_bootstrap_failed error={}",
                started_at.elapsed().as_millis(),
                err
            );
            Err(err)
        }
    }
}

fn bootstrap_connection(conn: &mut Connection) -> DbResult<()> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    conn.busy_timeout(Duration::from_secs(5))?;
    apply_migrations(conn)?;
    Ok(())
}
