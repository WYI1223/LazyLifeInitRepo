//! Atom domain model.
//!
//! # Responsibility
//! - Define the canonical record shared by note/task/event projections.
//! - Provide lifecycle helpers for soft-delete semantics.
//!
//! # Invariants
//! - `uuid` is stable and never reused for another atom.
//! - `is_deleted` is the source of truth for tombstone state.
//! - `event_end` should not be earlier than `event_start` when both are set.
//!
//! # See also
//! - docs/architecture/data-model.md

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Stable identifier for every domain object projected from an Atom.
///
/// Kept as a type alias to make semantic intent explicit in signatures.
pub type AtomId = Uuid;

/// Unified category for all Atom projections.
///
/// A single Atom can be rendered by different views, but still keeps one
/// canonical identity and lifecycle in Core.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AtomType {
    /// Free-form markdown note.
    Note,
    /// Actionable task with status metadata.
    Task,
    /// Calendar event with optional start/end time.
    Event,
}

/// Task lifecycle state for `AtomType::Task`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    /// Created but not started.
    Todo,
    /// Work is in progress.
    InProgress,
    /// Completed successfully.
    Done,
    /// No longer actionable.
    Cancelled,
}

/// Canonical domain record for note/task/event data.
///
/// This model intentionally keeps task/event-specific fields optional, so
/// one storage shape can support multiple projections without data copying.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Atom {
    /// Stable global ID used for linking, sync mapping and auditing.
    pub uuid: AtomId,
    /// Serialized as `type` to match external schema naming.
    #[serde(rename = "type")]
    pub kind: AtomType,
    /// Markdown body (or plain text fallback for simple inputs).
    pub content: String,
    /// Meaningful only when `kind == AtomType::Task`.
    pub task_status: Option<TaskStatus>,
    /// Unix epoch milliseconds. Meaningful for event-like atoms.
    pub event_start: Option<i64>,
    /// Unix epoch milliseconds. Should be >= `event_start` when set.
    pub event_end: Option<i64>,
    /// Reserved for future CRDT/HLC merge strategy.
    pub hlc_timestamp: Option<String>,
    /// Soft delete tombstone to preserve sync/recovery history.
    pub is_deleted: bool,
}

impl Atom {
    /// Creates a new atom with a generated stable ID.
    ///
    /// # Invariants
    /// - Optional projection fields are initialized to `None`.
    /// - `is_deleted` starts as `false`.
    pub fn new(kind: AtomType, content: impl Into<String>) -> Self {
        Self::with_id(Uuid::new_v4(), kind, content)
    }

    /// Creates a new atom with a caller-provided stable ID.
    ///
    /// Used by import/sync paths where identity already exists externally.
    ///
    /// # Invariants
    /// - The provided `uuid` must remain stable for this atom lifetime.
    /// - This constructor does not validate task/event projection fields.
    pub fn with_id(uuid: AtomId, kind: AtomType, content: impl Into<String>) -> Self {
        Self {
            uuid,
            kind,
            content: content.into(),
            task_status: None,
            event_start: None,
            event_end: None,
            hlc_timestamp: None,
            is_deleted: false,
        }
    }

    /// Marks this Atom as softly deleted (tombstoned).
    pub fn soft_delete(&mut self) {
        self.is_deleted = true;
    }

    /// Clears soft delete flag.
    pub fn restore(&mut self) {
        self.is_deleted = false;
    }

    /// Returns whether this Atom should be considered visible/active.
    pub fn is_active(&self) -> bool {
        !self.is_deleted
    }
}
