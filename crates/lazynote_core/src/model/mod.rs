//! Unified domain model for note/task/event projections.
//!
//! # Responsibility
//! - Define canonical data structures used by core business logic.
//! - Keep a single atom-centric shape for multiple UI projections.
//!
//! # Invariants
//! - Every domain object is identified by a stable `AtomId`.
//! - Deletion is represented by soft-delete tombstones, not hard delete.
//!
//! # See also
//! - docs/architecture/data-model.md

pub mod atom;
