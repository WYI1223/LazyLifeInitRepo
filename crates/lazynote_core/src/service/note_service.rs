//! Note use-case service.
//!
//! # Responsibility
//! - Provide note-specific create/update/get/list APIs.
//! - Derive markdown preview projections (`preview_text`, `preview_image`).
//! - Normalize and atomically replace note tags.
//!
//! # Invariants
//! - `note_update` uses full content replacement semantics.
//! - Note list is always sorted by `updated_at DESC, uuid ASC`.
//! - Tag names are normalized to lowercase and deduplicated.
//!
//! # See also
//! - docs/architecture/note-schema.md

use crate::model::atom::{Atom, AtomId, AtomType};
use crate::repo::atom_repo::{RepoError, RepoResult};
use crate::repo::note_repo::{
    normalize_note_limit, normalize_tag, normalize_tags, NoteListQuery, NoteRecord, NoteRepository,
};
use log::{error, info};
use once_cell::sync::Lazy;
use regex::Regex;
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::time::Instant;

static MARKDOWN_IMAGE_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"!\[[^\]]*]\(([^)]+)\)").expect("valid image regex"));
static MARKDOWN_LINK_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"\[([^\]]+)\]\(([^)]+)\)").expect("valid link regex"));
static MARKDOWN_SYMBOL_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r#"[\*_`#>~\-\[\]\(\)!]+"#).expect("valid markdown symbol regex"));
static WHITESPACE_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+").expect("valid ws regex"));

/// Service error for note use-cases.
#[derive(Debug)]
pub enum NoteServiceError {
    /// Tag input contains empty values.
    InvalidTag(String),
    /// Target note does not exist.
    NoteNotFound(AtomId),
    /// Persistence-layer failure.
    Repo(RepoError),
    /// Internal consistency mismatch between write and read-back.
    InconsistentState(&'static str),
}

impl Display for NoteServiceError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidTag(value) => write!(f, "invalid tag: `{value}`"),
            Self::NoteNotFound(atom_id) => write!(f, "note not found: {atom_id}"),
            Self::Repo(err) => write!(f, "{err}"),
            Self::InconsistentState(details) => write!(f, "inconsistent note state: {details}"),
        }
    }
}

impl Error for NoteServiceError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Repo(err) => Some(err),
            _ => None,
        }
    }
}

impl From<RepoError> for NoteServiceError {
    fn from(value: RepoError) -> Self {
        match value {
            RepoError::NotFound(atom_id) => Self::NoteNotFound(atom_id),
            other => Self::Repo(other),
        }
    }
}

/// List result envelope used by service callers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesListResult {
    /// List items sorted by `updated_at DESC, uuid ASC`.
    pub items: Vec<NoteRecord>,
    /// Effective normalized limit used by the query.
    pub applied_limit: u32,
}

/// Markdown-derived preview projection for notes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownPreview {
    /// Sanitized summary text.
    pub preview_text: Option<String>,
    /// First markdown image path.
    pub preview_image: Option<String>,
}

/// Note service facade over repository implementations.
pub struct NoteService<R: NoteRepository> {
    repo: R,
}

impl<R: NoteRepository> NoteService<R> {
    /// Creates a service using the provided repository implementation.
    pub fn new(repo: R) -> Self {
        Self { repo }
    }

    /// Creates one note from markdown content.
    pub fn create_note(&self, content: impl Into<String>) -> Result<NoteRecord, NoteServiceError> {
        let started_at = Instant::now();
        let content = content.into();
        let preview = derive_markdown_preview(content.as_str());
        let mut atom = Atom::new(AtomType::Note, content);
        atom.preview_text = preview.preview_text.clone();
        atom.preview_image = preview.preview_image.clone();

        let atom_id = match self.repo.create_note(&atom) {
            Ok(atom_id) => atom_id,
            Err(err) => {
                error!(
                    "event=note_create module=service status=error duration_ms={} error_code=repo_write_failed error={}",
                    started_at.elapsed().as_millis(),
                    err
                );
                return Err(err.into());
            }
        };

        match self.repo.get_note(atom_id) {
            Ok(Some(note)) => {
                info!(
                    "event=note_create module=service status=ok duration_ms={}",
                    started_at.elapsed().as_millis()
                );
                Ok(note)
            }
            Ok(None) => {
                error!(
                    "event=note_create module=service status=error duration_ms={} error_code=inconsistent_state",
                    started_at.elapsed().as_millis()
                );
                Err(NoteServiceError::InconsistentState(
                    "created note not found in read-back",
                ))
            }
            Err(err) => {
                error!(
                    "event=note_create module=service status=error duration_ms={} error_code=repo_read_failed error={}",
                    started_at.elapsed().as_millis(),
                    err
                );
                Err(err.into())
            }
        }
    }

    /// Replaces note content fully and recomputes preview projections.
    pub fn update_note(
        &self,
        atom_id: AtomId,
        content: impl Into<String>,
    ) -> Result<NoteRecord, NoteServiceError> {
        let started_at = Instant::now();
        let content = content.into();
        let preview = derive_markdown_preview(content.as_str());
        if let Err(err) = self.repo.update_note_full(
            atom_id,
            content.as_str(),
            preview.preview_text.as_deref(),
            preview.preview_image.as_deref(),
        ) {
            error!(
                "event=note_update module=service status=error duration_ms={} error_code=repo_write_failed error={}",
                started_at.elapsed().as_millis(),
                err
            );
            return Err(err.into());
        }

        match self.repo.get_note(atom_id) {
            Ok(Some(note)) => {
                info!(
                    "event=note_update module=service status=ok duration_ms={}",
                    started_at.elapsed().as_millis()
                );
                Ok(note)
            }
            Ok(None) => {
                error!(
                    "event=note_update module=service status=error duration_ms={} error_code=inconsistent_state atom_id={}",
                    started_at.elapsed().as_millis(),
                    atom_id
                );
                Err(NoteServiceError::InconsistentState(
                    "updated note not found in read-back",
                ))
            }
            Err(err) => {
                error!(
                    "event=note_update module=service status=error duration_ms={} error_code=repo_read_failed atom_id={} error={}",
                    started_at.elapsed().as_millis(),
                    atom_id,
                    err
                );
                Err(err.into())
            }
        }
    }

    /// Gets one note by stable ID.
    pub fn get_note(&self, atom_id: AtomId) -> RepoResult<Option<NoteRecord>> {
        self.repo.get_note(atom_id)
    }

    /// Lists notes using optional single-tag filter and pagination.
    pub fn list_notes(
        &self,
        tag: Option<String>,
        limit: Option<u32>,
        offset: u32,
    ) -> Result<NotesListResult, NoteServiceError> {
        let normalized_tag = match tag {
            Some(value) => match normalize_tag(value.as_str()) {
                Some(normalized) => Some(normalized),
                None => return Err(NoteServiceError::InvalidTag(value)),
            },
            None => None,
        };
        let applied_limit = normalize_note_limit(limit);
        let query = NoteListQuery {
            tag: normalized_tag,
            limit: Some(applied_limit),
            offset,
        };
        let items = self.repo.list_notes(&query)?;
        Ok(NotesListResult {
            items,
            applied_limit,
        })
    }

    /// Atomically replaces the full tag set for one note.
    pub fn set_note_tags(
        &mut self,
        atom_id: AtomId,
        tags: Vec<String>,
    ) -> Result<NoteRecord, NoteServiceError> {
        for tag in &tags {
            if tag.trim().is_empty() {
                return Err(NoteServiceError::InvalidTag(tag.clone()));
            }
        }

        let normalized = normalize_tags(&tags);
        self.repo.set_note_tags(atom_id, &normalized)?;
        self.repo
            .get_note(atom_id)?
            .ok_or(NoteServiceError::InconsistentState(
                "note missing after tag replacement",
            ))
    }

    /// Lists normalized tags known by storage.
    pub fn list_tags(&self) -> RepoResult<Vec<String>> {
        self.repo.list_tags()
    }
}

/// Derives note preview fields from markdown content.
///
/// Rules:
/// - `preview_image`: first markdown image path matched by regex.
/// - `preview_text`: markdown symbols removed, whitespace normalized, first
///   100 chars retained.
pub fn derive_markdown_preview(content: &str) -> MarkdownPreview {
    let preview_image = MARKDOWN_IMAGE_RE
        .captures(content)
        .and_then(|caps| caps.get(1).map(|m| m.as_str().trim().to_string()))
        .filter(|value| !value.is_empty());

    let without_images = MARKDOWN_IMAGE_RE.replace_all(content, " ");
    let without_links = MARKDOWN_LINK_RE.replace_all(&without_images, "$1");
    let without_symbols = MARKDOWN_SYMBOL_RE.replace_all(&without_links, " ");
    let normalized = WHITESPACE_RE.replace_all(&without_symbols, " ");
    let trimmed = normalized.trim();
    let preview_text = if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.chars().take(100).collect())
    };

    MarkdownPreview {
        preview_text,
        preview_image,
    }
}

#[cfg(test)]
mod tests {
    use super::derive_markdown_preview;

    #[test]
    fn preview_extracts_first_image_path() {
        let preview = derive_markdown_preview("x ![a](one.png) y ![b](two.png)");
        assert_eq!(preview.preview_image.as_deref(), Some("one.png"));
    }

    #[test]
    fn preview_strips_markdown_symbols_and_limits_length() {
        let source = "# title\n\n- [link](https://example.com)\n**bold** `code`";
        let preview = derive_markdown_preview(source);
        let text = preview.preview_text.expect("preview_text should exist");
        assert!(!text.contains('#'));
        assert!(!text.contains('*'));
        assert!(text.len() <= 100);
    }

    #[test]
    fn preview_handles_complex_markdown_and_unicode_text() {
        let source = r#"
# title heading

> quote line

![cover]( https://cdn.example.com/first.png )
Paragraph with [ref](https://example.com/path?q=1) and **bold** + `code`.

![second](two.png)
"#;
        let preview = derive_markdown_preview(source);
        assert_eq!(
            preview.preview_image.as_deref(),
            Some("https://cdn.example.com/first.png")
        );
        let text = preview.preview_text.expect("preview_text should exist");
        assert!(text.contains("title heading"));
        assert!(text.contains("quote line"));
        assert!(!text.contains("!["));
        assert!(!text.contains("]("));
        assert!(text.len() <= 100);
    }

    #[test]
    fn preview_returns_none_for_symbol_only_content() {
        let preview = derive_markdown_preview("### *** ``` ~~ []() ![]()");
        assert!(preview.preview_text.is_none());
        assert!(preview.preview_image.is_none());
    }
}
