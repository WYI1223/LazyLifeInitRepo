//! Connection bootstrap utilities for SQLite.
//!
//! # Responsibility
//! - Open file or in-memory SQLite connections.
//! - Configure connection pragmas required by core behavior.
//! - Trigger schema migrations before returning a usable connection.

use super::migrations::apply_migrations;
use super::DbResult;
use rusqlite::Connection;
use std::path::Path;
use std::time::Duration;

/// Opens a SQLite database file and applies all pending migrations.
pub fn open_db(path: impl AsRef<Path>) -> DbResult<Connection> {
    let mut conn = Connection::open(path)?;
    bootstrap_connection(&mut conn)?;
    Ok(conn)
}

/// Opens an in-memory SQLite database and applies all pending migrations.
pub fn open_db_in_memory() -> DbResult<Connection> {
    let mut conn = Connection::open_in_memory()?;
    bootstrap_connection(&mut conn)?;
    Ok(conn)
}

fn bootstrap_connection(conn: &mut Connection) -> DbResult<()> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    conn.busy_timeout(Duration::from_secs(5))?;
    apply_migrations(conn)?;
    Ok(())
}
