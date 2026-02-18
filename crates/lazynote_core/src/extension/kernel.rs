//! Extension kernel registry contracts.

use crate::extension::capability::RuntimeCapability;
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

/// Extension invocation kinds that require runtime capability checks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtensionInvocation {
    NetworkRequest,
    FileAccess,
    NotificationDispatch,
    CalendarAccess,
    ProviderSync,
}

impl ExtensionInvocation {
    fn required_capabilities(self) -> &'static [RuntimeCapability] {
        match self {
            Self::NetworkRequest => &[RuntimeCapability::Network],
            Self::FileAccess => &[RuntimeCapability::File],
            Self::NotificationDispatch => &[RuntimeCapability::Notification],
            Self::CalendarAccess => &[RuntimeCapability::Calendar],
            Self::ProviderSync => &[RuntimeCapability::Network, RuntimeCapability::Calendar],
        }
    }
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
    pub runtime_capabilities: BTreeSet<RuntimeCapability>,
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
            runtime_capabilities: vec![],
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
        let runtime_capabilities = manifest
            .declared_runtime_capabilities()
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
                runtime_capabilities,
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

    /// Enforces runtime capability declaration at extension invocation boundary.
    ///
    /// Deny-by-default: undeclared capability access is rejected.
    pub fn assert_runtime_capability(
        &self,
        extension_id: &str,
        capability: RuntimeCapability,
    ) -> Result<(), ExtensionKernelError> {
        let Some(entry) = self.entries.get(extension_id) else {
            return Err(ExtensionKernelError::ExtensionNotFound(
                extension_id.to_string(),
            ));
        };
        if entry.runtime_capabilities.contains(&capability) {
            return Ok(());
        }
        Err(ExtensionKernelError::CapabilityDenied {
            extension_id: extension_id.to_string(),
            capability,
        })
    }

    /// Enforces runtime capability declarations for one invocation kind.
    pub fn assert_invocation_allowed(
        &self,
        extension_id: &str,
        invocation: ExtensionInvocation,
    ) -> Result<(), ExtensionKernelError> {
        for capability in invocation.required_capabilities() {
            self.assert_runtime_capability(extension_id, *capability)?;
        }
        Ok(())
    }
}

/// Internal kernel registration errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExtensionKernelError {
    InvalidManifest(ManifestValidationError),
    DuplicateExtensionId(String),
    ExtensionNotFound(String),
    CapabilityDenied {
        extension_id: String,
        capability: RuntimeCapability,
    },
}

impl Display for ExtensionKernelError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidManifest(err) => write!(f, "invalid extension manifest: {err}"),
            Self::DuplicateExtensionId(value) => {
                write!(f, "extension id already registered: {value}")
            }
            Self::ExtensionNotFound(value) => write!(f, "extension id not found: {value}"),
            Self::CapabilityDenied {
                extension_id,
                capability,
            } => write!(
                f,
                "extension capability denied: extension `{extension_id}` missing `{}`",
                capability.as_str()
            ),
        }
    }
}

impl Error for ExtensionKernelError {}

#[cfg(test)]
mod tests {
    use crate::extension::capability::RuntimeCapability;
    use crate::extension::manifest::{
        ExtensionManifest, ManifestEntrypoints, ManifestValidationError,
    };

    use super::{
        ExtensionInvocation, ExtensionKernelError, ExtensionRegistry, ExtensionSource,
        FirstPartyExtensionAdapter,
    };

    fn runtime_manifest(runtime_capabilities: &[&str]) -> ExtensionManifest {
        ExtensionManifest {
            id: "builtin.test.invocation".to_string(),
            version: "0.1.0".to_string(),
            capabilities: vec!["provider".to_string()],
            runtime_capabilities: runtime_capabilities
                .iter()
                .map(|value| value.to_string())
                .collect(),
            entrypoints: ManifestEntrypoints {
                init: Some("builtin.test.init".to_string()),
                dispose: Some("builtin.test.dispose".to_string()),
                health: Some("builtin.test.health".to_string()),
                command_action: None,
                input_parser: None,
                provider_spi: Some("builtin.test.provider".to_string()),
                ui_slot: None,
            },
        }
    }

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

    #[test]
    fn denies_undeclared_runtime_capability_by_default() {
        let mut registry = ExtensionRegistry::new();
        registry
            .register_first_party_baseline()
            .expect("first-party baseline registration");

        let err = registry
            .assert_runtime_capability("builtin.notes.shell", RuntimeCapability::Network)
            .expect_err("undeclared runtime capability must be denied");
        assert!(matches!(err, ExtensionKernelError::CapabilityDenied { .. }));
    }

    #[test]
    fn reports_extension_not_found_for_runtime_capability_check() {
        let registry = ExtensionRegistry::new();
        let err = registry
            .assert_runtime_capability("missing.extension", RuntimeCapability::File)
            .expect_err("missing extension should fail");
        assert!(matches!(err, ExtensionKernelError::ExtensionNotFound(_)));
    }

    #[test]
    fn invocation_guard_enforces_single_capability_actions() {
        let mut registry = ExtensionRegistry::new();
        let adapter =
            FirstPartyExtensionAdapter::new(runtime_manifest(&["network", "notification"]));
        registry
            .register_adapter(&adapter)
            .expect("runtime extension registration");

        registry
            .assert_invocation_allowed(
                "builtin.test.invocation",
                ExtensionInvocation::NetworkRequest,
            )
            .expect("network invocation should be allowed");
        registry
            .assert_invocation_allowed(
                "builtin.test.invocation",
                ExtensionInvocation::NotificationDispatch,
            )
            .expect("notification invocation should be allowed");

        let file_err = registry
            .assert_invocation_allowed("builtin.test.invocation", ExtensionInvocation::FileAccess)
            .expect_err("file invocation should be denied");
        assert!(matches!(
            file_err,
            ExtensionKernelError::CapabilityDenied {
                capability: RuntimeCapability::File,
                ..
            }
        ));
    }

    #[test]
    fn invocation_guard_enforces_multi_capability_provider_sync() {
        let mut registry = ExtensionRegistry::new();
        let adapter = FirstPartyExtensionAdapter::new(runtime_manifest(&["network"]));
        registry
            .register_adapter(&adapter)
            .expect("runtime extension registration");

        let err = registry
            .assert_invocation_allowed("builtin.test.invocation", ExtensionInvocation::ProviderSync)
            .expect_err("provider sync should be denied without calendar capability");
        assert!(matches!(
            err,
            ExtensionKernelError::CapabilityDenied {
                capability: RuntimeCapability::Calendar,
                ..
            }
        ));
    }

    #[test]
    fn invocation_guard_allows_provider_sync_when_requirements_are_declared() {
        let mut registry = ExtensionRegistry::new();
        let adapter = FirstPartyExtensionAdapter::new(runtime_manifest(&["network", "calendar"]));
        registry
            .register_adapter(&adapter)
            .expect("runtime extension registration");

        registry
            .assert_invocation_allowed("builtin.test.invocation", ExtensionInvocation::ProviderSync)
            .expect("provider sync should be allowed");
        registry
            .assert_invocation_allowed(
                "builtin.test.invocation",
                ExtensionInvocation::CalendarAccess,
            )
            .expect("calendar access should be allowed");
    }

    #[test]
    fn rejects_registration_with_non_canonical_capability_strings() {
        let mut registry = ExtensionRegistry::new();
        let mut manifest = runtime_manifest(&["network"]);
        manifest.capabilities = vec![" provider ".to_string()];
        let adapter = FirstPartyExtensionAdapter::new(manifest);

        let err = registry
            .register_adapter(&adapter)
            .expect_err("non-canonical capability should be rejected");
        assert!(matches!(
            err,
            ExtensionKernelError::InvalidManifest(ManifestValidationError::NonCanonicalCapability(
                _
            ))
        ));
    }
}
