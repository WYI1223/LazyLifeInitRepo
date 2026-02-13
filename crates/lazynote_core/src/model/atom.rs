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
use std::error::Error;
use std::fmt::{Display, Formatter};
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
///
/// # Known Risk (v0.1)
/// - Fields are public for iteration speed, so direct mutation can bypass
///   constructor and deserialization validation.
/// - Callers must validate before persistence/FFI boundaries.
/// - TODO(v0.2): make mutation paths private/typed to enforce invariants
///   structurally.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "AtomDe")]
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AtomValidationError {
    NilUuid,
    InvalidEventWindow { start: i64, end: i64 },
}

impl Display for AtomValidationError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NilUuid => write!(f, "uuid must not be nil"),
            Self::InvalidEventWindow { start, end } => {
                write!(f, "event_end ({end}) must be >= event_start ({start})")
            }
        }
    }
}

impl Error for AtomValidationError {}

#[derive(Debug, Deserialize)]
struct AtomDe {
    uuid: AtomId,
    #[serde(rename = "type")]
    kind: AtomType,
    content: String,
    task_status: Option<TaskStatus>,
    event_start: Option<i64>,
    event_end: Option<i64>,
    hlc_timestamp: Option<String>,
    is_deleted: bool,
}

impl TryFrom<AtomDe> for Atom {
    type Error = AtomValidationError;

    fn try_from(value: AtomDe) -> Result<Self, Self::Error> {
        let atom = Self {
            uuid: value.uuid,
            kind: value.kind,
            content: value.content,
            task_status: value.task_status,
            event_start: value.event_start,
            event_end: value.event_end,
            hlc_timestamp: value.hlc_timestamp,
            is_deleted: value.is_deleted,
        };
        atom.validate()?;
        Ok(atom)
    }
}

impl Atom {
    /// Creates a new atom with a generated stable ID.
    ///
    /// # Invariants
    /// - Optional projection fields are initialized to `None`.
    /// - `is_deleted` starts as `false`.
    pub fn new(kind: AtomType, content: impl Into<String>) -> Self {
        Self {
            uuid: Uuid::new_v4(),
            kind,
            content: content.into(),
            task_status: None,
            event_start: None,
            event_end: None,
            hlc_timestamp: None,
            is_deleted: false,
        }
    }

    /// Creates a new atom with generated stable ID and validates invariants.
    pub fn try_new(
        kind: AtomType,
        content: impl Into<String>,
    ) -> Result<Self, AtomValidationError> {
        let atom = Self::new(kind, content);
        atom.validate()?;
        Ok(atom)
    }

    /// Creates a new atom with a caller-provided stable ID.
    ///
    /// Used by import/sync paths where identity already exists externally.
    ///
    /// # Invariants
    /// - The provided `uuid` must remain stable for this atom lifetime.
    /// - `uuid` must not be nil.
    pub fn with_id(
        uuid: AtomId,
        kind: AtomType,
        content: impl Into<String>,
    ) -> Result<Self, AtomValidationError> {
        let atom = Self {
            uuid,
            kind,
            content: content.into(),
            task_status: None,
            event_start: None,
            event_end: None,
            hlc_timestamp: None,
            is_deleted: false,
        };
        atom.validate()?;
        Ok(atom)
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

    /// Validates core invariants before persistence/FFI boundary hand-off.
    ///
    /// # Known Risk (v0.1)
    /// - Because fields are currently `pub`, this check can be skipped by
    ///   callers after mutation.
    /// - Persistence/repository/FFI entry points must call `validate()`.
    ///
    /// # Errors
    /// - Returns [`AtomValidationError::NilUuid`] for nil IDs.
    /// - Returns [`AtomValidationError::InvalidEventWindow`] when event time
    ///   range is reversed.
    pub fn validate(&self) -> Result<(), AtomValidationError> {
        if self.uuid.is_nil() {
            return Err(AtomValidationError::NilUuid);
        }

        if let (Some(start), Some(end)) = (self.event_start, self.event_end) {
            if end < start {
                return Err(AtomValidationError::InvalidEventWindow { start, end });
            }
        }

        Ok(())
    }
}
