//! SQLite FTS5-based search implementation.
//!
//! # Responsibility
//! - Provide keyword search over atom content.
//! - Return typed hits with stable IDs.
//!
//! # Invariants
//! - Only non-deleted atoms are returned.
//! - Result ordering is deterministic by rank and `updated_at`.

use crate::db::DbError;
use crate::model::atom::{AtomId, AtomType};
use rusqlite::types::Value;
use rusqlite::{params_from_iter, Connection, Row};
use std::error::Error;
use std::fmt::{Display, Formatter};
use uuid::Uuid;

/// Result type for search APIs.
pub type SearchResult<T> = Result<T, SearchError>;

/// Search-layer error for query parsing, DB interaction and result decoding.
#[derive(Debug)]
pub enum SearchError {
    /// User-provided query cannot be parsed by FTS5 syntax.
    InvalidQuery {
        query: String,
        message: String,
    },
    Db(DbError),
    InvalidData(String),
}

impl Display for SearchError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidQuery { query, message } => {
                write!(f, "invalid full-text query `{query}`: {message}")
            }
            Self::Db(err) => write!(f, "{err}"),
            Self::InvalidData(message) => write!(f, "invalid search row: {message}"),
        }
    }
}

impl Error for SearchError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::InvalidQuery { .. } => None,
            Self::Db(err) => Some(err),
            Self::InvalidData(_) => None,
        }
    }
}

impl From<DbError> for SearchError {
    fn from(value: DbError) -> Self {
        Self::Db(value)
    }
}

impl From<rusqlite::Error> for SearchError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Db(DbError::Sqlite(value))
    }
}

/// Search options for full-text query behavior.
#[derive(Debug, Clone)]
pub struct SearchQuery {
    /// User query text.
    pub text: String,
    /// Optional type filter.
    pub kind: Option<AtomType>,
    /// Maximum number of hits to return.
    pub limit: u32,
    /// Whether to pass text directly as raw FTS5 expression.
    ///
    /// Default is `false` to protect type-as-you-search UX from syntax errors.
    pub raw_fts_syntax: bool,
}

impl SearchQuery {
    /// Creates a query with default pagination and no type filter.
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            kind: None,
            limit: 20,
            raw_fts_syntax: false,
        }
    }
}

/// Single search hit returned by [`search_all`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchHit {
    pub atom_id: AtomId,
    pub kind: AtomType,
    pub snippet: String,
}

/// Searches atoms via FTS5 and returns ranked results.
///
/// Returns an empty list for blank queries.
pub fn search_all(conn: &Connection, query: &SearchQuery) -> SearchResult<Vec<SearchHit>> {
    let Some(match_expr) = build_match_expression(query)? else {
        return Ok(Vec::new());
    };

    if query.limit == 0 {
        return Ok(Vec::new());
    }

    let mut sql = String::from(
        "SELECT
            atoms.uuid AS uuid,
            atoms.type AS type,
            snippet(atoms_fts, 0, '[', ']', ' ... ', 10) AS snippet
         FROM atoms_fts
         JOIN atoms ON atoms.rowid = atoms_fts.rowid
         WHERE atoms_fts MATCH ?
           AND atoms.is_deleted = 0",
    );
    let mut bind_values: Vec<Value> = vec![Value::Text(match_expr.clone())];

    if let Some(kind) = query.kind {
        sql.push_str(" AND atoms.type = ?");
        bind_values.push(Value::Text(atom_type_to_db(kind).to_string()));
    }

    sql.push_str(" ORDER BY bm25(atoms_fts), atoms.updated_at DESC, atoms.uuid ASC LIMIT ?");
    bind_values.push(Value::Integer(i64::from(query.limit)));

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt
        .query(params_from_iter(bind_values))
        .map_err(|err| map_query_error(err, &match_expr))?;
    let mut hits = Vec::new();

    while let Some(row) = rows
        .next()
        .map_err(|err| map_query_error(err, &match_expr))?
    {
        hits.push(parse_search_hit(row)?);
    }

    Ok(hits)
}

fn parse_search_hit(row: &Row<'_>) -> SearchResult<SearchHit> {
    let uuid_text: String = row.get("uuid")?;
    let atom_id = Uuid::parse_str(&uuid_text)
        .map_err(|_| SearchError::InvalidData(format!("invalid uuid `{uuid_text}`")))?;

    let type_text: String = row.get("type")?;
    let kind = parse_atom_type(&type_text)
        .ok_or_else(|| SearchError::InvalidData(format!("invalid type `{type_text}`")))?;

    Ok(SearchHit {
        atom_id,
        kind,
        snippet: row.get("snippet")?,
    })
}

fn parse_atom_type(value: &str) -> Option<AtomType> {
    match value {
        "note" => Some(AtomType::Note),
        "task" => Some(AtomType::Task),
        "event" => Some(AtomType::Event),
        _ => None,
    }
}

fn atom_type_to_db(kind: AtomType) -> &'static str {
    match kind {
        AtomType::Note => "note",
        AtomType::Task => "task",
        AtomType::Event => "event",
    }
}

fn build_match_expression(query: &SearchQuery) -> SearchResult<Option<String>> {
    let text = query.text.trim();
    if text.is_empty() {
        return Ok(None);
    }

    if query.raw_fts_syntax {
        return Ok(Some(text.to_string()));
    }

    let terms = text
        .split_whitespace()
        .filter(|term| !term.is_empty())
        .map(escape_fts_term)
        .collect::<Vec<_>>();

    if terms.is_empty() {
        return Ok(None);
    }

    Ok(Some(terms.join(" AND ")))
}

fn escape_fts_term(raw: &str) -> String {
    let escaped = raw.replace('"', "\"\"");
    format!("\"{escaped}\"")
}

fn map_query_error(err: rusqlite::Error, query: &str) -> SearchError {
    if is_match_syntax_error(&err) {
        return SearchError::InvalidQuery {
            query: query.to_string(),
            message: err.to_string(),
        };
    }

    SearchError::Db(DbError::Sqlite(err))
}

fn is_match_syntax_error(err: &rusqlite::Error) -> bool {
    match err {
        rusqlite::Error::SqliteFailure(_, Some(message)) => {
            let msg = message.to_lowercase();
            (msg.contains("fts5") && msg.contains("syntax"))
                || msg.contains("malformed match expression")
                || msg.contains("unterminated")
        }
        _ => false,
    }
}
