//! Atom repository contracts and SQLite implementation.
//!
//! # Responsibility
//! - Provide stable CRUD APIs over canonical `atoms` storage.
//! - Keep SQL details inside core persistence boundary.
//!
//! # Invariants
//! - Write paths must call `Atom::validate()` before SQL mutations.
//! - Read paths must reject invalid persisted state instead of masking it.
//!
//! # See also
//! - docs/releases/v0.1/prs/PR-0006-core-crud.md

use crate::db::DbError;
use crate::model::atom::{Atom, AtomId, AtomType, AtomValidationError, TaskStatus};
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter, Connection, Row};
use std::error::Error;
use std::fmt::{Display, Formatter};
use uuid::Uuid;

const ATOM_SELECT_SQL: &str = "SELECT
    uuid,
    type,
    content,
    task_status,
    event_start,
    event_end,
    hlc_timestamp,
    is_deleted
FROM atoms";

pub type RepoResult<T> = Result<T, RepoError>;

/// Generic repository error for atom persistence and query operations.
#[derive(Debug)]
pub enum RepoError {
    Validation(AtomValidationError),
    Db(DbError),
    NotFound(AtomId),
    InvalidData(String),
}

impl Display for RepoError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Validation(err) => write!(f, "{err}"),
            Self::Db(err) => write!(f, "{err}"),
            Self::NotFound(id) => write!(f, "atom not found: {id}"),
            Self::InvalidData(message) => write!(f, "invalid persisted atom data: {message}"),
        }
    }
}

impl Error for RepoError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Validation(err) => Some(err),
            Self::Db(err) => Some(err),
            Self::NotFound(_) => None,
            Self::InvalidData(_) => None,
        }
    }
}

impl From<AtomValidationError> for RepoError {
    fn from(value: AtomValidationError) -> Self {
        Self::Validation(value)
    }
}

impl From<DbError> for RepoError {
    fn from(value: DbError) -> Self {
        Self::Db(value)
    }
}

impl From<rusqlite::Error> for RepoError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Db(DbError::Sqlite(value))
    }
}

/// Query options for listing atoms.
#[derive(Debug, Clone, Default)]
pub struct AtomListQuery {
    pub kind: Option<AtomType>,
    pub include_deleted: bool,
    pub limit: Option<u32>,
    pub offset: u32,
}

/// Repository interface for atom CRUD operations.
pub trait AtomRepository {
    fn create_atom(&self, atom: &Atom) -> RepoResult<AtomId>;
    fn update_atom(&self, atom: &Atom) -> RepoResult<()>;
    fn get_atom(&self, id: AtomId, include_deleted: bool) -> RepoResult<Option<Atom>>;
    fn list_atoms(&self, query: &AtomListQuery) -> RepoResult<Vec<Atom>>;
    fn soft_delete_atom(&self, id: AtomId) -> RepoResult<()>;
}

/// SQLite-backed atom repository.
pub struct SqliteAtomRepository<'conn> {
    conn: &'conn Connection,
}

impl<'conn> SqliteAtomRepository<'conn> {
    pub fn new(conn: &'conn Connection) -> Self {
        Self { conn }
    }
}

impl AtomRepository for SqliteAtomRepository<'_> {
    fn create_atom(&self, atom: &Atom) -> RepoResult<AtomId> {
        atom.validate()?;

        self.conn.execute(
            "INSERT INTO atoms (
                uuid,
                type,
                content,
                task_status,
                event_start,
                event_end,
                hlc_timestamp,
                is_deleted
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);",
            params![
                atom.uuid.to_string(),
                atom_type_to_db(atom.kind),
                atom.content.as_str(),
                atom.task_status.map(task_status_to_db),
                atom.event_start,
                atom.event_end,
                atom.hlc_timestamp.as_deref(),
                bool_to_int(atom.is_deleted),
            ],
        )?;

        Ok(atom.uuid)
    }

    fn update_atom(&self, atom: &Atom) -> RepoResult<()> {
        atom.validate()?;

        let changed = self.conn.execute(
            "UPDATE atoms
             SET
                type = ?1,
                content = ?2,
                task_status = ?3,
                event_start = ?4,
                event_end = ?5,
                hlc_timestamp = ?6,
                is_deleted = ?7,
                updated_at = (strftime('%s', 'now') * 1000)
             WHERE uuid = ?8;",
            params![
                atom_type_to_db(atom.kind),
                atom.content.as_str(),
                atom.task_status.map(task_status_to_db),
                atom.event_start,
                atom.event_end,
                atom.hlc_timestamp.as_deref(),
                bool_to_int(atom.is_deleted),
                atom.uuid.to_string(),
            ],
        )?;

        if changed == 0 {
            return Err(RepoError::NotFound(atom.uuid));
        }

        Ok(())
    }

    fn get_atom(&self, id: AtomId, include_deleted: bool) -> RepoResult<Option<Atom>> {
        let mut stmt = self.conn.prepare(&format!(
            "{ATOM_SELECT_SQL}
             WHERE uuid = ?1
               AND (?2 = 1 OR is_deleted = 0);"
        ))?;

        let mut rows = stmt.query(params![id.to_string(), bool_to_int(include_deleted)])?;
        if let Some(row) = rows.next()? {
            return Ok(Some(parse_atom_row(row)?));
        }

        Ok(None)
    }

    fn list_atoms(&self, query: &AtomListQuery) -> RepoResult<Vec<Atom>> {
        let mut sql = format!("{ATOM_SELECT_SQL} WHERE 1 = 1");
        let mut bind_values: Vec<Value> = Vec::new();

        if !query.include_deleted {
            sql.push_str(" AND is_deleted = 0");
        }

        if let Some(kind) = query.kind {
            sql.push_str(" AND type = ?");
            bind_values.push(Value::Text(atom_type_to_db(kind).to_string()));
        }

        sql.push_str(" ORDER BY updated_at DESC, uuid ASC");

        if let Some(limit) = query.limit {
            sql.push_str(" LIMIT ?");
            bind_values.push(Value::Integer(i64::from(limit)));
            if query.offset > 0 {
                sql.push_str(" OFFSET ?");
                bind_values.push(Value::Integer(i64::from(query.offset)));
            }
        } else if query.offset > 0 {
            sql.push_str(" LIMIT -1 OFFSET ?");
            bind_values.push(Value::Integer(i64::from(query.offset)));
        }

        let mut stmt = self.conn.prepare(&sql)?;
        let mut rows = stmt.query(params_from_iter(bind_values))?;
        let mut atoms = Vec::new();

        while let Some(row) = rows.next()? {
            atoms.push(parse_atom_row(row)?);
        }

        Ok(atoms)
    }

    fn soft_delete_atom(&self, id: AtomId) -> RepoResult<()> {
        let changed = self.conn.execute(
            "UPDATE atoms
             SET
                is_deleted = 1,
                updated_at = (strftime('%s', 'now') * 1000)
             WHERE uuid = ?1;",
            [id.to_string()],
        )?;

        if changed == 0 {
            return Err(RepoError::NotFound(id));
        }

        Ok(())
    }
}

fn parse_atom_row(row: &Row<'_>) -> RepoResult<Atom> {
    let uuid_text: String = row.get("uuid")?;
    let uuid = Uuid::parse_str(&uuid_text).map_err(|_| {
        RepoError::InvalidData(format!("invalid uuid value `{uuid_text}` in atoms.uuid"))
    })?;

    let type_text: String = row.get("type")?;
    let kind = parse_atom_type(&type_text).ok_or_else(|| {
        RepoError::InvalidData(format!("invalid atom type `{type_text}` in atoms.type"))
    })?;

    let task_status = match row.get::<_, Option<String>>("task_status")? {
        Some(value) => Some(parse_task_status(&value).ok_or_else(|| {
            RepoError::InvalidData(format!(
                "invalid task status `{value}` in atoms.task_status"
            ))
        })?),
        None => None,
    };

    let is_deleted = match row.get::<_, i64>("is_deleted")? {
        0 => false,
        1 => true,
        other => {
            return Err(RepoError::InvalidData(format!(
                "invalid is_deleted value `{other}` in atoms.is_deleted"
            )));
        }
    };

    let atom = Atom {
        uuid,
        kind,
        content: row.get("content")?,
        task_status,
        event_start: row.get("event_start")?,
        event_end: row.get("event_end")?,
        hlc_timestamp: row.get("hlc_timestamp")?,
        is_deleted,
    };
    atom.validate()?;
    Ok(atom)
}

fn atom_type_to_db(kind: AtomType) -> &'static str {
    match kind {
        AtomType::Note => "note",
        AtomType::Task => "task",
        AtomType::Event => "event",
    }
}

fn parse_atom_type(value: &str) -> Option<AtomType> {
    match value {
        "note" => Some(AtomType::Note),
        "task" => Some(AtomType::Task),
        "event" => Some(AtomType::Event),
        _ => None,
    }
}

fn task_status_to_db(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Done => "done",
        TaskStatus::Cancelled => "cancelled",
    }
}

fn parse_task_status(value: &str) -> Option<TaskStatus> {
    match value {
        "todo" => Some(TaskStatus::Todo),
        "in_progress" => Some(TaskStatus::InProgress),
        "done" => Some(TaskStatus::Done),
        "cancelled" => Some(TaskStatus::Cancelled),
        _ => None,
    }
}

fn bool_to_int(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}
