//! Workspace tree use-case service.
//!
//! # Responsibility
//! - Validate tree hierarchy invariants above repository layer.
//! - Provide folder/note_ref create, rename, move, and list operations.
//!
//! # Invariants
//! - Parent node must exist and be a folder when provided.
//! - Move operations must not create parent-child cycles.
//! - `note_ref` must target an active `AtomType::Note`.

use crate::model::atom::{AtomId, AtomType};
use crate::repo::tree_repo::{
    TreeRepoError, TreeRepository, WorkspaceNode, WorkspaceNodeId, WorkspaceNodeKind,
};
use std::collections::HashSet;
use std::error::Error;
use std::fmt::{Display, Formatter};

/// Folder delete mode for workspace tree.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FolderDeleteMode {
    /// Delete folder node only and move direct children to root.
    Dissolve,
    /// Delete folder subtree and soft-delete note atoms with no remaining refs.
    DeleteAll,
}

/// Errors from workspace tree service operations.
#[derive(Debug)]
pub enum TreeServiceError {
    /// Display name is blank after trim.
    InvalidDisplayName,
    /// Target node does not exist.
    NodeNotFound(WorkspaceNodeId),
    /// Parent node does not exist.
    ParentNotFound(WorkspaceNodeId),
    /// Parent exists but is not folder kind.
    ParentMustBeFolder(WorkspaceNodeId),
    /// Target node exists but is not folder kind.
    NodeMustBeFolder(WorkspaceNodeId),
    /// Target note atom does not exist or is soft-deleted.
    AtomNotFound(AtomId),
    /// Target atom exists but is not note type.
    AtomNotNote(AtomId),
    /// Move operation would create a cycle.
    CycleDetected {
        node_uuid: WorkspaceNodeId,
        parent_uuid: WorkspaceNodeId,
    },
    /// Repository-level failure.
    Repo(TreeRepoError),
}

impl Display for TreeServiceError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidDisplayName => write!(f, "display name must not be blank"),
            Self::NodeNotFound(id) => write!(f, "workspace node not found: {id}"),
            Self::ParentNotFound(id) => write!(f, "workspace parent not found: {id}"),
            Self::ParentMustBeFolder(id) => {
                write!(f, "workspace parent must be folder: {id}")
            }
            Self::NodeMustBeFolder(id) => write!(f, "workspace node must be folder: {id}"),
            Self::AtomNotFound(id) => write!(f, "atom not found: {id}"),
            Self::AtomNotNote(id) => write!(f, "atom is not a note: {id}"),
            Self::CycleDetected {
                node_uuid,
                parent_uuid,
            } => write!(
                f,
                "move would create cycle: node {node_uuid} under parent {parent_uuid}"
            ),
            Self::Repo(err) => write!(f, "{err}"),
        }
    }
}

impl Error for TreeServiceError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Repo(err) => Some(err),
            _ => None,
        }
    }
}

impl From<TreeRepoError> for TreeServiceError {
    fn from(value: TreeRepoError) -> Self {
        match value {
            TreeRepoError::NodeNotFound(node_uuid) => Self::NodeNotFound(node_uuid),
            TreeRepoError::NodeNotFolder(node_uuid) => Self::NodeMustBeFolder(node_uuid),
            other => Self::Repo(other),
        }
    }
}

/// Workspace tree service facade.
pub struct TreeService<R: TreeRepository> {
    repo: R,
}

impl<R: TreeRepository> TreeService<R> {
    /// Creates service from repository implementation.
    pub fn new(repo: R) -> Self {
        Self { repo }
    }

    /// Creates one folder under optional parent.
    pub fn create_folder(
        &self,
        parent_uuid: Option<WorkspaceNodeId>,
        display_name: impl Into<String>,
    ) -> Result<WorkspaceNode, TreeServiceError> {
        let normalized = normalize_display_name(display_name.into())?;
        if let Some(parent_uuid) = parent_uuid {
            self.ensure_parent_is_folder(parent_uuid)?;
        }
        self.repo
            .create_folder(parent_uuid, normalized.as_str())
            .map_err(Into::into)
    }

    /// Creates one note_ref under optional parent.
    pub fn create_note_ref(
        &self,
        parent_uuid: Option<WorkspaceNodeId>,
        atom_uuid: AtomId,
        display_name: Option<String>,
    ) -> Result<WorkspaceNode, TreeServiceError> {
        if let Some(parent_uuid) = parent_uuid {
            self.ensure_parent_is_folder(parent_uuid)?;
        }
        self.ensure_atom_is_note(atom_uuid)?;

        let normalized = match display_name {
            Some(value) => normalize_display_name(value)?,
            None => "Untitled note".to_string(),
        };

        self.repo
            .create_note_ref(parent_uuid, atom_uuid, normalized.as_str())
            .map_err(Into::into)
    }

    /// Lists child nodes under optional parent.
    pub fn list_children(
        &self,
        parent_uuid: Option<WorkspaceNodeId>,
    ) -> Result<Vec<WorkspaceNode>, TreeServiceError> {
        if let Some(parent_uuid) = parent_uuid {
            self.ensure_parent_is_folder(parent_uuid)?;
        }
        self.repo
            .list_children(parent_uuid, false)
            .map_err(Into::into)
    }

    /// Renames one node.
    pub fn rename_node(
        &self,
        node_uuid: WorkspaceNodeId,
        display_name: impl Into<String>,
    ) -> Result<(), TreeServiceError> {
        let normalized = normalize_display_name(display_name.into())?;
        self.repo
            .rename_node(node_uuid, normalized.as_str())
            .map_err(Into::into)
    }

    /// Moves one node under optional parent and optional sibling index.
    pub fn move_node(
        &self,
        node_uuid: WorkspaceNodeId,
        new_parent_uuid: Option<WorkspaceNodeId>,
        target_order: Option<i64>,
    ) -> Result<(), TreeServiceError> {
        self.repo
            .get_node(node_uuid, false)?
            .ok_or(TreeServiceError::NodeNotFound(node_uuid))?;

        if let Some(parent_uuid) = new_parent_uuid {
            if parent_uuid == node_uuid {
                return Err(TreeServiceError::CycleDetected {
                    node_uuid,
                    parent_uuid,
                });
            }

            self.ensure_parent_is_folder(parent_uuid)?;
            if self.would_create_cycle(node_uuid, parent_uuid)? {
                return Err(TreeServiceError::CycleDetected {
                    node_uuid,
                    parent_uuid,
                });
            }
        }

        self.repo
            .move_node(
                node_uuid,
                new_parent_uuid,
                target_order.map(|value| value.max(0)),
            )
            .map_err(Into::into)
    }

    /// Deletes a folder by mode.
    pub fn delete_folder(
        &self,
        folder_uuid: WorkspaceNodeId,
        mode: FolderDeleteMode,
    ) -> Result<(), TreeServiceError> {
        let folder = self
            .repo
            .get_node(folder_uuid, false)?
            .ok_or(TreeServiceError::NodeNotFound(folder_uuid))?;
        if folder.kind != WorkspaceNodeKind::Folder {
            return Err(TreeServiceError::NodeMustBeFolder(folder_uuid));
        }

        match mode {
            FolderDeleteMode::Dissolve => self.repo.delete_folder_dissolve(folder_uuid)?,
            FolderDeleteMode::DeleteAll => self.repo.delete_folder_delete_all(folder_uuid)?,
        }
        Ok(())
    }

    fn ensure_parent_is_folder(
        &self,
        parent_uuid: WorkspaceNodeId,
    ) -> Result<(), TreeServiceError> {
        let parent = self
            .repo
            .get_node(parent_uuid, false)?
            .ok_or(TreeServiceError::ParentNotFound(parent_uuid))?;
        if parent.kind != WorkspaceNodeKind::Folder {
            return Err(TreeServiceError::ParentMustBeFolder(parent_uuid));
        }
        Ok(())
    }

    fn ensure_atom_is_note(&self, atom_uuid: AtomId) -> Result<(), TreeServiceError> {
        match self.repo.atom_kind(atom_uuid)? {
            None => Err(TreeServiceError::AtomNotFound(atom_uuid)),
            Some(AtomType::Note) => Ok(()),
            Some(_) => Err(TreeServiceError::AtomNotNote(atom_uuid)),
        }
    }

    fn would_create_cycle(
        &self,
        node_uuid: WorkspaceNodeId,
        candidate_parent_uuid: WorkspaceNodeId,
    ) -> Result<bool, TreeServiceError> {
        let mut visited = HashSet::new();
        let mut cursor = Some(candidate_parent_uuid);
        while let Some(current) = cursor {
            if current == node_uuid {
                return Ok(true);
            }
            if !visited.insert(current) {
                return Ok(true);
            }

            let node = self
                .repo
                .get_node(current, false)?
                .ok_or(TreeServiceError::ParentNotFound(current))?;
            cursor = node.parent_uuid;
        }
        Ok(false)
    }
}

fn normalize_display_name(value: String) -> Result<String, TreeServiceError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(TreeServiceError::InvalidDisplayName);
    }
    Ok(trimmed.to_string())
}
