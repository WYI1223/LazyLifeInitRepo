//! Note/tag repository contracts and SQLite implementation.
//!
//! # Responsibility
//! - Provide note-only persistence APIs on top of canonical `atoms`.
//! - Own tag-link replacement logic (`note_set_tags`) with atomic semantics.
//!
//! # Invariants
//! - All note queries are constrained to `type='note'` and `is_deleted=0`.
//! - `note_set_tags` replaces the whole tag set in a single transaction.
//! - Tag names are normalized to lowercase before persistence.
//!
//! # See also
//! - docs/releases/v0.1/prs/PR-0010B-notes-tags-core-ffi.md

use crate::model::atom::{Atom, AtomId, AtomType};
use crate::repo::atom_repo::{AtomRepository, RepoError, RepoResult, SqliteAtomRepository};
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter, Connection, Transaction, TransactionBehavior};
use std::collections::BTreeSet;
use uuid::Uuid;

const NOTES_DEFAULT_LIMIT: u32 = 10;
const NOTES_LIMIT_MAX: u32 = 50;

/// Read model for note list/detail use-cases.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteRecord {
    /// Stable atom id.
    pub atom_id: AtomId,
    /// Raw markdown source text.
    pub content: String,
    /// Derived plain-text preview (nullable).
    pub preview_text: Option<String>,
    /// Derived first markdown image path (nullable).
    pub preview_image: Option<String>,
    /// Update timestamp in epoch milliseconds.
    pub updated_at: i64,
    /// Note tags, normalized to lowercase.
    pub tags: Vec<String>,
}

/// Query options for note list use-cases.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NoteListQuery {
    /// Optional single-tag exact match filter.
    pub tag: Option<String>,
    /// Maximum rows to return. Defaults to 10 and clamps to 50.
    pub limit: Option<u32>,
    /// Number of rows to skip.
    pub offset: u32,
}

/// Repository interface for notes/tags operations.
pub trait NoteRepository {
    /// Creates one note atom and returns its stable id.
    fn create_note(&self, atom: &Atom) -> RepoResult<AtomId>;
    /// Replaces full note content and preview fields.
    fn update_note_full(
        &self,
        atom_id: AtomId,
        content: &str,
        preview_text: Option<&str>,
        preview_image: Option<&str>,
    ) -> RepoResult<()>;
    /// Gets one note by id.
    fn get_note(&self, atom_id: AtomId) -> RepoResult<Option<NoteRecord>>;
    /// Lists notes using single-tag filter + pagination.
    fn list_notes(&self, query: &NoteListQuery) -> RepoResult<Vec<NoteRecord>>;
    /// Replaces all tags for the given note atom in one transaction.
    fn set_note_tags(&mut self, atom_id: AtomId, tags: &[String]) -> RepoResult<()>;
    /// Returns all known tags sorted by name.
    fn list_tags(&self) -> RepoResult<Vec<String>>;
}

/// SQLite-backed notes/tags repository.
pub struct SqliteNoteRepository<'conn> {
    conn: &'conn mut Connection,
}

impl<'conn> SqliteNoteRepository<'conn> {
    /// Constructs a repository from a migrated/ready connection.
    pub fn try_new(conn: &'conn mut Connection) -> RepoResult<Self> {
        let _ = SqliteAtomRepository::try_new(conn)?;
        ensure_note_connection_ready(conn)?;
        Ok(Self { conn })
    }
}

impl NoteRepository for SqliteNoteRepository<'_> {
    fn create_note(&self, atom: &Atom) -> RepoResult<AtomId> {
        if atom.kind != AtomType::Note {
            return Err(RepoError::InvalidData(
                "note repository only accepts AtomType::Note".to_string(),
            ));
        }

        let repo = SqliteAtomRepository::try_new(self.conn)?;
        repo.create_atom(atom)
    }

    fn update_note_full(
        &self,
        atom_id: AtomId,
        content: &str,
        preview_text: Option<&str>,
        preview_image: Option<&str>,
    ) -> RepoResult<()> {
        let changed = self.conn.execute(
            "UPDATE atoms
             SET
                content = ?2,
                preview_text = ?3,
                preview_image = ?4,
                updated_at = (strftime('%s', 'now') * 1000)
             WHERE uuid = ?1
               AND type = 'note'
               AND is_deleted = 0;",
            params![atom_id.to_string(), content, preview_text, preview_image,],
        )?;

        if changed == 0 {
            return Err(RepoError::NotFound(atom_id));
        }

        Ok(())
    }

    fn get_note(&self, atom_id: AtomId) -> RepoResult<Option<NoteRecord>> {
        let uuid = atom_id.to_string();
        let mut stmt = self.conn.prepare(
            "SELECT
                uuid,
                content,
                preview_text,
                preview_image,
                updated_at
             FROM atoms
             WHERE uuid = ?1
               AND type = 'note'
               AND is_deleted = 0;",
        )?;

        let mut rows = stmt.query([uuid.as_str()])?;
        if let Some(row) = rows.next()? {
            let uuid_text: String = row.get("uuid")?;
            let parsed_id = parse_uuid(&uuid_text)?;
            let tags = load_tags_for_note(self.conn, &uuid_text)?;
            return Ok(Some(NoteRecord {
                atom_id: parsed_id,
                content: row.get("content")?,
                preview_text: row.get("preview_text")?,
                preview_image: row.get("preview_image")?,
                updated_at: row.get("updated_at")?,
                tags,
            }));
        }

        Ok(None)
    }

    fn list_notes(&self, query: &NoteListQuery) -> RepoResult<Vec<NoteRecord>> {
        let mut sql = String::from(
            "SELECT
                uuid,
                content,
                preview_text,
                preview_image,
                updated_at
             FROM atoms
             WHERE type = 'note'
               AND is_deleted = 0",
        );
        let mut bind_values: Vec<Value> = Vec::new();

        if let Some(tag) = query.tag.as_ref() {
            sql.push_str(
                " AND EXISTS (
                    SELECT 1
                    FROM atom_tags at
                    INNER JOIN tags t ON t.id = at.tag_id
                    WHERE at.atom_uuid = atoms.uuid
                      AND t.name = ? COLLATE NOCASE
                )",
            );
            bind_values.push(Value::Text(tag.clone()));
        }

        sql.push_str(" ORDER BY updated_at DESC, uuid ASC");
        let limit = normalize_note_limit(query.limit);
        sql.push_str(" LIMIT ?");
        bind_values.push(Value::Integer(i64::from(limit)));
        if query.offset > 0 {
            sql.push_str(" OFFSET ?");
            bind_values.push(Value::Integer(i64::from(query.offset)));
        }

        let mut stmt = self.conn.prepare(&sql)?;
        let mut rows = stmt.query(params_from_iter(bind_values))?;
        let mut notes = Vec::new();
        while let Some(row) = rows.next()? {
            let uuid_text: String = row.get("uuid")?;
            let parsed_id = parse_uuid(&uuid_text)?;
            let tags = load_tags_for_note(self.conn, &uuid_text)?;
            notes.push(NoteRecord {
                atom_id: parsed_id,
                content: row.get("content")?,
                preview_text: row.get("preview_text")?,
                preview_image: row.get("preview_image")?,
                updated_at: row.get("updated_at")?,
                tags,
            });
        }

        Ok(notes)
    }

    fn set_note_tags(&mut self, atom_id: AtomId, tags: &[String]) -> RepoResult<()> {
        let atom_id_text = atom_id.to_string();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if !note_exists_in_tx(&tx, atom_id_text.as_str())? {
            return Err(RepoError::NotFound(atom_id));
        }

        tx.execute(
            "DELETE FROM atom_tags WHERE atom_uuid = ?1;",
            [atom_id_text.as_str()],
        )?;

        for tag in tags {
            tx.execute(
                "INSERT OR IGNORE INTO tags (name) VALUES (?1);",
                [tag.as_str()],
            )?;
            tx.execute(
                "INSERT INTO atom_tags (atom_uuid, tag_id)
                 SELECT ?1, id
                 FROM tags
                 WHERE name = ?2 COLLATE NOCASE;",
                params![atom_id_text.as_str(), tag.as_str()],
            )?;
        }

        tx.execute(
            "UPDATE atoms
             SET updated_at = (strftime('%s', 'now') * 1000)
             WHERE uuid = ?1
               AND type = 'note'
               AND is_deleted = 0;",
            [atom_id_text.as_str()],
        )?;

        tx.commit()?;
        Ok(())
    }

    fn list_tags(&self) -> RepoResult<Vec<String>> {
        let mut stmt = self
            .conn
            .prepare("SELECT name FROM tags ORDER BY name COLLATE NOCASE ASC;")?;
        let mut rows = stmt.query([])?;
        let mut tags = Vec::new();
        while let Some(row) = rows.next()? {
            let value: String = row.get("name")?;
            tags.push(value.to_lowercase());
        }
        Ok(tags)
    }
}

/// Normalizes list limit according to notes contract.
pub fn normalize_note_limit(limit: Option<u32>) -> u32 {
    match limit {
        Some(0) => NOTES_DEFAULT_LIMIT,
        Some(value) if value > NOTES_LIMIT_MAX => NOTES_LIMIT_MAX,
        Some(value) => value,
        None => NOTES_DEFAULT_LIMIT,
    }
}

/// Normalizes one tag value according to notes contract.
pub fn normalize_tag(tag: &str) -> Option<String> {
    let trimmed = tag.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_lowercase())
    }
}

/// Normalizes and deduplicates tag values.
pub fn normalize_tags(tags: &[String]) -> Vec<String> {
    let mut unique = BTreeSet::new();
    for tag in tags {
        if let Some(value) = normalize_tag(tag) {
            unique.insert(value);
        }
    }
    unique.into_iter().collect()
}

fn parse_uuid(value: &str) -> RepoResult<AtomId> {
    Uuid::parse_str(value)
        .map_err(|_| RepoError::InvalidData(format!("invalid uuid value `{value}` in atoms.uuid")))
}

fn load_tags_for_note(conn: &Connection, atom_uuid: &str) -> RepoResult<Vec<String>> {
    let mut stmt = conn.prepare(
        "SELECT t.name
         FROM atom_tags at
         INNER JOIN tags t ON t.id = at.tag_id
         WHERE at.atom_uuid = ?1
         ORDER BY t.name COLLATE NOCASE ASC;",
    )?;
    let mut rows = stmt.query([atom_uuid])?;
    let mut tags = Vec::new();
    while let Some(row) = rows.next()? {
        let value: String = row.get(0)?;
        tags.push(value.to_lowercase());
    }
    Ok(tags)
}

fn note_exists_in_tx(tx: &Transaction<'_>, atom_uuid: &str) -> RepoResult<bool> {
    let exists: i64 = tx.query_row(
        "SELECT EXISTS(
            SELECT 1
            FROM atoms
             WHERE uuid = ?1
               AND type = 'note'
               AND is_deleted = 0
        );",
        [atom_uuid],
        |row| row.get(0),
    )?;
    Ok(exists == 1)
}

fn ensure_note_connection_ready(conn: &Connection) -> RepoResult<()> {
    for table in ["tags", "atom_tags"] {
        if !table_exists(conn, table)? {
            return Err(RepoError::MissingRequiredTable(table));
        }
    }

    for column in ["id", "name"] {
        if !table_has_column(conn, "tags", column)? {
            return Err(RepoError::MissingRequiredColumn {
                table: "tags",
                column,
            });
        }
    }

    for column in ["atom_uuid", "tag_id"] {
        if !table_has_column(conn, "atom_tags", column)? {
            return Err(RepoError::MissingRequiredColumn {
                table: "atom_tags",
                column,
            });
        }
    }

    Ok(())
}

fn table_exists(conn: &Connection, table: &str) -> RepoResult<bool> {
    let exists: i64 = conn.query_row(
        "SELECT EXISTS(
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?1
        );",
        [table],
        |row| row.get(0),
    )?;
    Ok(exists == 1)
}

fn table_has_column(conn: &Connection, table: &str, column: &str) -> RepoResult<bool> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table});"))?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let current: String = row.get(1)?;
        if current == column {
            return Ok(true);
        }
    }
    Ok(false)
}
