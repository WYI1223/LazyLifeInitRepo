//! Atom use-case service.
//!
//! # Responsibility
//! - Provide stable CRUD entry points for core callers.
//! - Delegate persistence to repository implementations.
//!
//! # Invariants
//! - Service APIs never bypass repository validation/persistence contracts.
//! - Service layer remains storage-agnostic.

use crate::model::atom::{Atom, AtomId};
use crate::repo::atom_repo::{AtomListQuery, AtomRepository, RepoResult};

/// Use-case service wrapper for atom CRUD operations.
pub struct AtomService<R: AtomRepository> {
    repo: R,
}

impl<R: AtomRepository> AtomService<R> {
    pub fn new(repo: R) -> Self {
        Self { repo }
    }

    pub fn create_atom(&self, atom: &Atom) -> RepoResult<AtomId> {
        self.repo.create_atom(atom)
    }

    pub fn update_atom(&self, atom: &Atom) -> RepoResult<()> {
        self.repo.update_atom(atom)
    }

    pub fn get_atom(&self, id: AtomId, include_deleted: bool) -> RepoResult<Option<Atom>> {
        self.repo.get_atom(id, include_deleted)
    }

    pub fn list_atoms(&self, query: &AtomListQuery) -> RepoResult<Vec<Atom>> {
        self.repo.list_atoms(query)
    }

    pub fn soft_delete_atom(&self, id: AtomId) -> RepoResult<()> {
        self.repo.soft_delete_atom(id)
    }
}
