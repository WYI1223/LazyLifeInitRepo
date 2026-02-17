//! Extension kernel registry contracts.

use crate::extension::manifest::{ExtensionManifest, ManifestEntrypoints, ManifestValidationError};
use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::{Display, Formatter};

/// Extension lifecycle status contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtensionHealth {
    Healthy,
    Degraded,
    Unavailable,
}

/// Internal source classification for one extension registration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtensionSource {
    FirstParty,
}

/// Registered extension snapshot in kernel registry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisteredExtension {
    pub manifest: ExtensionManifest,
    pub source: ExtensionSource,
}

/// Adapter contract used by first-party modules to register via kernel.
///
/// v0.2 baseline is declaration-only: no dynamic runtime loading.
pub trait ExtensionAdapter {
    fn manifest(&self) -> &ExtensionManifest;
    fn source(&self) -> ExtensionSource;
}

/// First-party adapter wrapper.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FirstPartyExtensionAdapter {
    manifest: ExtensionManifest,
}

impl FirstPartyExtensionAdapter {
    pub fn new(manifest: ExtensionManifest) -> Self {
        Self { manifest }
    }

    /// Built-in baseline adapter used to verify registry path in v0.2.
    pub fn notes_shell_baseline() -> Self {
        Self::new(ExtensionManifest {
            id: "builtin.notes.shell".to_string(),
            version: "0.1.0".to_string(),
            capabilities: vec![
                "command".to_string(),
                "parser".to_string(),
                "provider".to_string(),
                "ui_slot".to_string(),
            ],
            entrypoints: ManifestEntrypoints {
                init: Some("builtin.notes.init".to_string()),
                dispose: Some("builtin.notes.dispose".to_string()),
                health: Some("builtin.notes.health".to_string()),
                command_action: Some("builtin.notes.command.register".to_string()),
                input_parser: Some("builtin.notes.parser.register".to_string()),
                provider_spi: Some("builtin.notes.provider.register".to_string()),
                ui_slot: Some("builtin.notes.ui_slot.register".to_string()),
            },
        })
    }
}

impl ExtensionAdapter for FirstPartyExtensionAdapter {
    fn manifest(&self) -> &ExtensionManifest {
        &self.manifest
    }

    fn source(&self) -> ExtensionSource {
        ExtensionSource::FirstParty
    }
}

/// In-process extension registry for declaration contracts.
#[derive(Debug, Default)]
pub struct ExtensionRegistry {
    entries: BTreeMap<String, RegisteredExtension>,
    capability_index: BTreeMap<String, BTreeSet<String>>,
}

impl ExtensionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers one adapter after manifest declaration validation.
    pub fn register_adapter(
        &mut self,
        adapter: &impl ExtensionAdapter,
    ) -> Result<(), ExtensionKernelError> {
        let manifest = adapter.manifest().clone();
        manifest
            .validate()
            .map_err(ExtensionKernelError::InvalidManifest)?;
        let id = manifest.id.clone();
        if self.entries.contains_key(id.as_str()) {
            return Err(ExtensionKernelError::DuplicateExtensionId(id));
        }

        for capability in &manifest.capabilities {
            self.capability_index
                .entry(capability.clone())
                .or_default()
                .insert(manifest.id.clone());
        }

        self.entries.insert(
            manifest.id.clone(),
            RegisteredExtension {
                manifest,
                source: adapter.source(),
            },
        );
        Ok(())
    }

    /// Registers the default first-party baseline adapter.
    pub fn register_first_party_baseline(&mut self) -> Result<(), ExtensionKernelError> {
        let adapter = FirstPartyExtensionAdapter::notes_shell_baseline();
        self.register_adapter(&adapter)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, extension_id: &str) -> Option<&RegisteredExtension> {
        self.entries.get(extension_id)
    }

    pub fn list_by_capability(&self, capability: &str) -> Vec<&RegisteredExtension> {
        let Some(ids) = self.capability_index.get(capability) else {
            return vec![];
        };
        ids.iter().filter_map(|id| self.entries.get(id)).collect()
    }
}

/// Internal kernel registration errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExtensionKernelError {
    InvalidManifest(ManifestValidationError),
    DuplicateExtensionId(String),
}

impl Display for ExtensionKernelError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidManifest(err) => write!(f, "invalid extension manifest: {err}"),
            Self::DuplicateExtensionId(value) => {
                write!(f, "extension id already registered: {value}")
            }
        }
    }
}

impl Error for ExtensionKernelError {}

#[cfg(test)]
mod tests {
    use super::{
        ExtensionKernelError, ExtensionRegistry, ExtensionSource, FirstPartyExtensionAdapter,
    };

    #[test]
    fn registers_first_party_adapter() {
        let mut registry = ExtensionRegistry::new();
        registry
            .register_first_party_baseline()
            .expect("first-party baseline registration");

        assert_eq!(registry.len(), 1);
        let entry = registry
            .get("builtin.notes.shell")
            .expect("registered extension");
        assert_eq!(entry.source, ExtensionSource::FirstParty);
    }

    #[test]
    fn rejects_duplicate_extension_id() {
        let mut registry = ExtensionRegistry::new();
        let adapter = FirstPartyExtensionAdapter::notes_shell_baseline();
        registry
            .register_adapter(&adapter)
            .expect("first registration should succeed");
        let err = registry
            .register_adapter(&adapter)
            .expect_err("duplicate registration must fail");
        assert!(matches!(err, ExtensionKernelError::DuplicateExtensionId(_)));
    }

    #[test]
    fn builds_capability_index() {
        let mut registry = ExtensionRegistry::new();
        registry
            .register_first_party_baseline()
            .expect("first-party baseline registration");

        let command_extensions = registry.list_by_capability("command");
        assert_eq!(command_extensions.len(), 1);
        assert_eq!(command_extensions[0].manifest.id, "builtin.notes.shell");
    }
}
