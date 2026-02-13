//! Repository layer abstractions and persistence implementations.
//!
//! # Responsibility
//! - Define use-case oriented data access contracts.
//! - Isolate SQLite query details from service/business orchestration.
//!
//! # Invariants
//! - Repository writes must enforce `Atom::validate()` before persistence.
//! - Repository APIs return semantic errors (`NotFound`) in addition to DB
//!   transport errors.
//!
//! # See also
//! - docs/releases/v0.1/prs/PR-0006-core-crud.md

pub mod atom_repo;
