//! Atom use-case service.
//!
//! # Responsibility
//! - Provide stable CRUD entry points for core callers.
//! - Delegate persistence to repository implementations.
//!
//! # Invariants
//! - Service APIs never bypass repository validation/persistence contracts.
//! - Service layer remains storage-agnostic.

use crate::model::atom::{Atom, AtomId, AtomType, TaskStatus};
use crate::repo::atom_repo::{AtomListQuery, AtomRepository, RepoResult};
use crate::service::note_service::derive_markdown_preview;

/// Use-case service wrapper for atom CRUD operations.
pub struct AtomService<R: AtomRepository> {
    repo: R,
}

/// Request model for scheduling an event atom.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScheduleEventRequest {
    /// Event title/content stored in atom `content`.
    pub title: String,
    /// Event start in epoch milliseconds.
    pub start_epoch_ms: i64,
    /// Optional event end in epoch milliseconds.
    pub end_epoch_ms: Option<i64>,
}

impl<R: AtomRepository> AtomService<R> {
    /// Creates a service using the provided repository implementation.
    pub fn new(repo: R) -> Self {
        Self { repo }
    }

    /// Creates a new atom through repository persistence.
    pub fn create_atom(&self, atom: &Atom) -> RepoResult<AtomId> {
        self.repo.create_atom(atom)
    }

    /// Creates a note atom from single-entry command input.
    ///
    /// # Contract
    /// - Uses `AtomType::Note`.
    /// - Returns created stable atom ID.
    pub fn create_note(&self, content: impl Into<String>) -> RepoResult<AtomId> {
        let content = content.into();
        let preview = derive_markdown_preview(content.as_str());
        let mut atom = Atom::new(AtomType::Note, content);
        atom.preview_text = preview.preview_text;
        atom.preview_image = preview.preview_image;
        self.repo.create_atom(&atom)
    }

    /// Creates a task atom with default status `todo`.
    ///
    /// # Contract
    /// - Uses `AtomType::Task`.
    /// - Sets `task_status = Some(TaskStatus::Todo)`.
    /// - Returns created stable atom ID.
    pub fn create_task(&self, content: impl Into<String>) -> RepoResult<AtomId> {
        let mut atom = Atom::new(AtomType::Task, content);
        atom.task_status = Some(TaskStatus::Todo);
        self.repo.create_atom(&atom)
    }

    /// Schedules an event atom using point or range semantics.
    ///
    /// # Contract
    /// - Uses `AtomType::Event`.
    /// - Point event: `end_epoch_ms = None`.
    /// - Range event: `end_epoch_ms = Some(end)`.
    /// - Returns created stable atom ID.
    pub fn schedule_event(&self, request: &ScheduleEventRequest) -> RepoResult<AtomId> {
        let mut atom = Atom::new(AtomType::Event, request.title.clone());
        atom.event_start = Some(request.start_epoch_ms);
        atom.event_end = request.end_epoch_ms;
        self.repo.create_atom(&atom)
    }

    /// Updates an existing atom by stable ID.
    ///
    /// Returns repository-level not-found or validation errors unchanged.
    pub fn update_atom(&self, atom: &Atom) -> RepoResult<()> {
        self.repo.update_atom(atom)
    }

    /// Gets one atom by ID with optional deleted-row visibility.
    pub fn get_atom(&self, id: AtomId, include_deleted: bool) -> RepoResult<Option<Atom>> {
        self.repo.get_atom(id, include_deleted)
    }

    /// Lists atoms using filter and pagination options.
    pub fn list_atoms(&self, query: &AtomListQuery) -> RepoResult<Vec<Atom>> {
        self.repo.list_atoms(query)
    }

    /// Soft-deletes an atom by ID.
    pub fn soft_delete_atom(&self, id: AtomId) -> RepoResult<()> {
        self.repo.soft_delete_atom(id)
    }
}
