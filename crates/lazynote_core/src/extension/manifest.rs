//! Extension manifest declaration and validation.

use crate::extension::capability::{parse_runtime_capability, RuntimeCapability};
use std::collections::BTreeSet;
use std::error::Error;
use std::fmt::{Display, Formatter};

/// Capability string for command action registration.
pub const CAPABILITY_COMMAND: &str = "command";
/// Capability string for input parser registration.
pub const CAPABILITY_PARSER: &str = "parser";
/// Capability string for provider SPI registration.
pub const CAPABILITY_PROVIDER: &str = "provider";
/// Capability string for UI slot metadata registration.
pub const CAPABILITY_UI_SLOT: &str = "ui_slot";

const SUPPORTED_CAPABILITIES: &[&str] = &[
    CAPABILITY_COMMAND,
    CAPABILITY_PARSER,
    CAPABILITY_PROVIDER,
    CAPABILITY_UI_SLOT,
];

/// Returns supported capability strings for manifest validation.
pub fn supported_capabilities() -> &'static [&'static str] {
    SUPPORTED_CAPABILITIES
}

/// Declarative extension manifest.
///
/// v0.2 baseline uses string capability enums. Bitflags/structured capability
/// model is intentionally deferred to future PRs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtensionManifest {
    /// Stable extension identifier, e.g. `builtin.notes.shell`.
    pub id: String,
    /// Manifest semantic version string (`major.minor.patch`).
    pub version: String,
    /// Declared capabilities (`command|parser|provider|ui_slot`).
    pub capabilities: Vec<String>,
    /// Declared runtime capabilities (`network|file|notification|calendar`).
    ///
    /// Empty declaration is valid and treated as deny-by-default during
    /// invocation-time capability checks.
    pub runtime_capabilities: Vec<String>,
    /// Entry point declarations (string identifiers only).
    pub entrypoints: ManifestEntrypoints,
}

impl ExtensionManifest {
    /// Validates declaration-level manifest invariants.
    pub fn validate(&self) -> Result<(), ManifestValidationError> {
        let normalized_id = self.id.trim();
        if normalized_id.is_empty() {
            return Err(ManifestValidationError::EmptyId);
        }
        if self.id != normalized_id {
            return Err(ManifestValidationError::NonCanonicalId(self.id.clone()));
        }
        if !is_valid_extension_id(normalized_id) {
            return Err(ManifestValidationError::InvalidId(self.id.clone()));
        }

        if self.version.trim().is_empty() {
            return Err(ManifestValidationError::EmptyVersion);
        }
        if !is_semver_triplet(self.version.trim()) {
            return Err(ManifestValidationError::InvalidVersion(
                self.version.clone(),
            ));
        }

        if self.capabilities.is_empty() {
            return Err(ManifestValidationError::MissingCapabilities);
        }

        let mut dedup = BTreeSet::<String>::new();
        for capability in &self.capabilities {
            let normalized = capability.trim();
            if normalized.is_empty() {
                return Err(ManifestValidationError::EmptyCapability);
            }
            if capability != normalized {
                return Err(ManifestValidationError::NonCanonicalCapability(
                    capability.clone(),
                ));
            }
            if !supported_capabilities().contains(&normalized) {
                return Err(ManifestValidationError::UnsupportedCapability(
                    normalized.to_string(),
                ));
            }
            if !dedup.insert(normalized.to_string()) {
                return Err(ManifestValidationError::DuplicateCapability(
                    normalized.to_string(),
                ));
            }

            match normalized {
                CAPABILITY_COMMAND => {
                    require_entrypoint(&self.entrypoints.command_action, "command_action")?;
                }
                CAPABILITY_PARSER => {
                    require_entrypoint(&self.entrypoints.input_parser, "input_parser")?;
                }
                CAPABILITY_PROVIDER => {
                    require_entrypoint(&self.entrypoints.provider_spi, "provider_spi")?;
                }
                CAPABILITY_UI_SLOT => {
                    require_entrypoint(&self.entrypoints.ui_slot, "ui_slot")?;
                }
                _ => {}
            }
        }

        self.declared_runtime_capabilities()?;
        require_entrypoint(&self.entrypoints.init, "init")?;
        require_entrypoint(&self.entrypoints.dispose, "dispose")?;
        require_entrypoint(&self.entrypoints.health, "health")?;
        Ok(())
    }

    /// Returns validated runtime capability declarations as a deduplicated set.
    pub fn declared_runtime_capabilities(
        &self,
    ) -> Result<BTreeSet<RuntimeCapability>, ManifestValidationError> {
        let mut dedup = BTreeSet::<RuntimeCapability>::new();
        for raw in &self.runtime_capabilities {
            let normalized = raw.trim();
            if normalized.is_empty() {
                return Err(ManifestValidationError::EmptyRuntimeCapability);
            }
            if raw != normalized {
                return Err(ManifestValidationError::NonCanonicalRuntimeCapability(
                    raw.clone(),
                ));
            }
            let capability = parse_runtime_capability(normalized).map_err(|err| match err {
                crate::extension::capability::RuntimeCapabilityError::EmptyCapability => {
                    ManifestValidationError::EmptyRuntimeCapability
                }
                crate::extension::capability::RuntimeCapabilityError::UnsupportedCapability(
                    value,
                ) => ManifestValidationError::UnsupportedRuntimeCapability(value),
            })?;
            if !dedup.insert(capability) {
                return Err(ManifestValidationError::DuplicateRuntimeCapability(
                    capability.as_str().to_string(),
                ));
            }
        }
        Ok(dedup)
    }
}

/// Declared entrypoint identifiers for one extension.
///
/// These are declaration-only identifiers in v0.2; runtime function loading is
/// intentionally out of scope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestEntrypoints {
    pub init: Option<String>,
    pub dispose: Option<String>,
    pub health: Option<String>,
    pub command_action: Option<String>,
    pub input_parser: Option<String>,
    pub provider_spi: Option<String>,
    pub ui_slot: Option<String>,
}

impl ManifestEntrypoints {
    /// Creates an empty entrypoint declaration.
    pub fn empty() -> Self {
        Self {
            init: None,
            dispose: None,
            health: None,
            command_action: None,
            input_parser: None,
            provider_spi: None,
            ui_slot: None,
        }
    }
}

fn require_entrypoint(
    value: &Option<String>,
    name: &'static str,
) -> Result<(), ManifestValidationError> {
    match value {
        Some(raw) if !raw.trim().is_empty() => Ok(()),
        _ => Err(ManifestValidationError::MissingEntrypoint(name)),
    }
}

fn is_valid_extension_id(value: &str) -> bool {
    let mut chars = value.chars();
    let first = match chars.next() {
        Some(c) => c,
        None => return false,
    };
    if !first.is_ascii_lowercase() && !first.is_ascii_digit() {
        return false;
    }

    let mut prev_separator = false;
    for c in chars {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            prev_separator = false;
            continue;
        }
        if c == '.' || c == '_' || c == '-' {
            if prev_separator {
                return false;
            }
            prev_separator = true;
            continue;
        }
        return false;
    }
    !prev_separator
}

fn is_semver_triplet(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();
    if parts.len() != 3 {
        return false;
    }
    parts
        .iter()
        .all(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
}

/// Internal manifest validation errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestValidationError {
    EmptyId,
    NonCanonicalId(String),
    InvalidId(String),
    EmptyVersion,
    InvalidVersion(String),
    MissingCapabilities,
    EmptyCapability,
    NonCanonicalCapability(String),
    UnsupportedCapability(String),
    DuplicateCapability(String),
    EmptyRuntimeCapability,
    NonCanonicalRuntimeCapability(String),
    UnsupportedRuntimeCapability(String),
    DuplicateRuntimeCapability(String),
    MissingEntrypoint(&'static str),
}

impl Display for ManifestValidationError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyId => write!(f, "manifest id must not be empty"),
            Self::NonCanonicalId(value) => {
                write!(
                    f,
                    "manifest id must be canonical (no surrounding whitespace): {value}"
                )
            }
            Self::InvalidId(value) => write!(f, "manifest id is invalid: {value}"),
            Self::EmptyVersion => write!(f, "manifest version must not be empty"),
            Self::InvalidVersion(value) => write!(
                f,
                "manifest version is invalid: {value} (expected major.minor.patch)"
            ),
            Self::MissingCapabilities => write!(f, "manifest capabilities must not be empty"),
            Self::EmptyCapability => write!(f, "manifest contains empty capability value"),
            Self::NonCanonicalCapability(value) => write!(
                f,
                "manifest capability must be canonical (no surrounding whitespace): {value}"
            ),
            Self::UnsupportedCapability(value) => {
                write!(f, "manifest capability is unsupported: {value}")
            }
            Self::DuplicateCapability(value) => {
                write!(f, "manifest capability is duplicated: {value}")
            }
            Self::EmptyRuntimeCapability => {
                write!(f, "manifest contains empty runtime capability value")
            }
            Self::NonCanonicalRuntimeCapability(value) => write!(
                f,
                "manifest runtime capability must be canonical (no surrounding whitespace): {value}"
            ),
            Self::UnsupportedRuntimeCapability(value) => {
                write!(f, "manifest runtime capability is unsupported: {value}")
            }
            Self::DuplicateRuntimeCapability(value) => {
                write!(f, "manifest runtime capability is duplicated: {value}")
            }
            Self::MissingEntrypoint(name) => {
                write!(f, "manifest missing required entrypoint: {name}")
            }
        }
    }
}

impl Error for ManifestValidationError {}

#[cfg(test)]
mod tests {
    use super::{
        ExtensionManifest, ManifestEntrypoints, ManifestValidationError, CAPABILITY_COMMAND,
        CAPABILITY_UI_SLOT,
    };

    fn valid_manifest() -> ExtensionManifest {
        ExtensionManifest {
            id: "builtin.notes.shell".to_string(),
            version: "0.1.0".to_string(),
            capabilities: vec![
                CAPABILITY_COMMAND.to_string(),
                CAPABILITY_UI_SLOT.to_string(),
            ],
            runtime_capabilities: vec!["network".to_string()],
            entrypoints: ManifestEntrypoints {
                init: Some("builtin.init".to_string()),
                dispose: Some("builtin.dispose".to_string()),
                health: Some("builtin.health".to_string()),
                command_action: Some("builtin.command.register".to_string()),
                input_parser: None,
                provider_spi: None,
                ui_slot: Some("builtin.ui.notes.sidebar".to_string()),
            },
        }
    }

    #[test]
    fn validates_baseline_manifest() {
        let manifest = valid_manifest();
        assert!(manifest.validate().is_ok());
    }

    #[test]
    fn rejects_missing_capabilities() {
        let mut manifest = valid_manifest();
        manifest.capabilities.clear();
        let err = manifest.validate().unwrap_err();
        assert_eq!(err, ManifestValidationError::MissingCapabilities);
    }

    #[test]
    fn rejects_duplicate_capabilities() {
        let mut manifest = valid_manifest();
        manifest.capabilities.push(CAPABILITY_COMMAND.to_string());
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::DuplicateCapability(CAPABILITY_COMMAND.to_string())
        );
    }

    #[test]
    fn rejects_unsupported_capabilities() {
        let mut manifest = valid_manifest();
        manifest.capabilities.push("runtime_loader".to_string());
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::UnsupportedCapability("runtime_loader".to_string())
        );
    }

    #[test]
    fn rejects_missing_required_entrypoint_for_capability() {
        let mut manifest = valid_manifest();
        manifest.entrypoints.command_action = None;
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::MissingEntrypoint("command_action")
        );
    }

    #[test]
    fn rejects_missing_lifecycle_entrypoint() {
        let mut manifest = valid_manifest();
        manifest.entrypoints.init = None;
        let err = manifest.validate().unwrap_err();
        assert_eq!(err, ManifestValidationError::MissingEntrypoint("init"));
    }

    #[test]
    fn rejects_invalid_id_format() {
        let mut manifest = valid_manifest();
        manifest.id = "Builtin Notes".to_string();
        let err = manifest.validate().unwrap_err();
        assert!(matches!(err, ManifestValidationError::InvalidId(_)));
    }

    #[test]
    fn rejects_non_canonical_id_with_surrounding_whitespace() {
        let mut manifest = valid_manifest();
        manifest.id = " builtin.notes.shell ".to_string();
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::NonCanonicalId(" builtin.notes.shell ".to_string())
        );
    }

    #[test]
    fn rejects_invalid_version_format() {
        let mut manifest = valid_manifest();
        manifest.version = "v1".to_string();
        let err = manifest.validate().unwrap_err();
        assert!(matches!(err, ManifestValidationError::InvalidVersion(_)));
    }

    #[test]
    fn rejects_non_canonical_capability_with_surrounding_whitespace() {
        let mut manifest = valid_manifest();
        manifest.capabilities = vec![" command ".to_string(), CAPABILITY_UI_SLOT.to_string()];
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::NonCanonicalCapability(" command ".to_string())
        );
    }

    #[test]
    fn rejects_duplicate_runtime_capability() {
        let mut manifest = valid_manifest();
        manifest.runtime_capabilities.push("network".to_string());
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::DuplicateRuntimeCapability("network".to_string())
        );
    }

    #[test]
    fn rejects_unsupported_runtime_capability() {
        let mut manifest = valid_manifest();
        manifest.runtime_capabilities.push("bluetooth".to_string());
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::UnsupportedRuntimeCapability("bluetooth".to_string())
        );
    }

    #[test]
    fn rejects_empty_runtime_capability() {
        let mut manifest = valid_manifest();
        manifest.runtime_capabilities = vec!["   ".to_string()];
        let err = manifest.validate().unwrap_err();
        assert_eq!(err, ManifestValidationError::EmptyRuntimeCapability);
    }

    #[test]
    fn rejects_runtime_capability_list_when_any_item_is_blank() {
        let mut manifest = valid_manifest();
        manifest.runtime_capabilities = vec!["network".to_string(), "   ".to_string()];
        let err = manifest.validate().unwrap_err();
        assert_eq!(err, ManifestValidationError::EmptyRuntimeCapability);
    }

    #[test]
    fn rejects_non_canonical_runtime_capability_with_surrounding_whitespace() {
        let mut manifest = valid_manifest();
        manifest.runtime_capabilities = vec![" network ".to_string()];
        let err = manifest.validate().unwrap_err();
        assert_eq!(
            err,
            ManifestValidationError::NonCanonicalRuntimeCapability(" network ".to_string())
        );
    }
}
