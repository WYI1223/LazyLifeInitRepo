//! Runtime capability declarations for extension security gates.

use std::error::Error;
use std::fmt::{Display, Formatter};

/// Runtime capability for extension invocation authorization.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum RuntimeCapability {
    Network,
    File,
    Notification,
    Calendar,
}

impl RuntimeCapability {
    /// Stable string id used in manifest declarations.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Network => RUNTIME_CAPABILITY_NETWORK,
            Self::File => RUNTIME_CAPABILITY_FILE,
            Self::Notification => RUNTIME_CAPABILITY_NOTIFICATION,
            Self::Calendar => RUNTIME_CAPABILITY_CALENDAR,
        }
    }

    /// User-facing short description.
    pub fn description(self) -> &'static str {
        match self {
            Self::Network => "Allow network access for provider sync and remote service calls.",
            Self::File => "Allow local file read/write access for import/export workflows.",
            Self::Notification => "Allow posting local notifications and reminder prompts.",
            Self::Calendar => "Allow reading/writing external calendar provider data.",
        }
    }
}

/// Manifest string value for network capability.
pub const RUNTIME_CAPABILITY_NETWORK: &str = "network";
/// Manifest string value for file capability.
pub const RUNTIME_CAPABILITY_FILE: &str = "file";
/// Manifest string value for notification capability.
pub const RUNTIME_CAPABILITY_NOTIFICATION: &str = "notification";
/// Manifest string value for calendar capability.
pub const RUNTIME_CAPABILITY_CALENDAR: &str = "calendar";

const SUPPORTED_RUNTIME_CAPABILITY_STRINGS: &[&str] = &[
    RUNTIME_CAPABILITY_NETWORK,
    RUNTIME_CAPABILITY_FILE,
    RUNTIME_CAPABILITY_NOTIFICATION,
    RUNTIME_CAPABILITY_CALENDAR,
];

/// Returns supported runtime capability declaration strings.
pub fn supported_runtime_capability_strings() -> &'static [&'static str] {
    SUPPORTED_RUNTIME_CAPABILITY_STRINGS
}

/// Parses one runtime capability from manifest string value.
pub fn parse_runtime_capability(value: &str) -> Result<RuntimeCapability, RuntimeCapabilityError> {
    let normalized = value.trim();
    if normalized.is_empty() {
        return Err(RuntimeCapabilityError::EmptyCapability);
    }

    match normalized {
        RUNTIME_CAPABILITY_NETWORK => Ok(RuntimeCapability::Network),
        RUNTIME_CAPABILITY_FILE => Ok(RuntimeCapability::File),
        RUNTIME_CAPABILITY_NOTIFICATION => Ok(RuntimeCapability::Notification),
        RUNTIME_CAPABILITY_CALENDAR => Ok(RuntimeCapability::Calendar),
        other => Err(RuntimeCapabilityError::UnsupportedCapability(
            other.to_string(),
        )),
    }
}

/// Runtime capability parse errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeCapabilityError {
    EmptyCapability,
    UnsupportedCapability(String),
}

impl Display for RuntimeCapabilityError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyCapability => write!(f, "runtime capability value must not be empty"),
            Self::UnsupportedCapability(value) => {
                write!(f, "runtime capability is unsupported: {value}")
            }
        }
    }
}

impl Error for RuntimeCapabilityError {}

#[cfg(test)]
mod tests {
    use super::{
        parse_runtime_capability, supported_runtime_capability_strings, RuntimeCapability,
        RuntimeCapabilityError,
    };

    #[test]
    fn parses_all_supported_runtime_capabilities() {
        assert_eq!(
            parse_runtime_capability("network").expect("network parse"),
            RuntimeCapability::Network
        );
        assert_eq!(
            parse_runtime_capability("file").expect("file parse"),
            RuntimeCapability::File
        );
        assert_eq!(
            parse_runtime_capability("notification").expect("notification parse"),
            RuntimeCapability::Notification
        );
        assert_eq!(
            parse_runtime_capability("calendar").expect("calendar parse"),
            RuntimeCapability::Calendar
        );
    }

    #[test]
    fn rejects_empty_runtime_capability() {
        let err = parse_runtime_capability("   ").expect_err("empty capability must fail");
        assert_eq!(err, RuntimeCapabilityError::EmptyCapability);
    }

    #[test]
    fn rejects_unsupported_runtime_capability() {
        let err =
            parse_runtime_capability("bluetooth").expect_err("unsupported capability must fail");
        assert_eq!(
            err,
            RuntimeCapabilityError::UnsupportedCapability("bluetooth".to_string())
        );
    }

    #[test]
    fn rejects_non_lowercase_runtime_capability_variants() {
        let err =
            parse_runtime_capability("Network").expect_err("capitalized capability must fail");
        assert_eq!(
            err,
            RuntimeCapabilityError::UnsupportedCapability("Network".to_string())
        );

        let err = parse_runtime_capability("NETWORK").expect_err("uppercase capability must fail");
        assert_eq!(
            err,
            RuntimeCapabilityError::UnsupportedCapability("NETWORK".to_string())
        );
    }

    #[test]
    fn exposes_user_facing_descriptions() {
        assert!(RuntimeCapability::Network.description().contains("network"));
        assert!(RuntimeCapability::File.description().contains("file"));
        assert!(RuntimeCapability::Notification
            .description()
            .contains("notification"));
        assert!(RuntimeCapability::Calendar
            .description()
            .contains("calendar"));
    }

    #[test]
    fn returns_supported_runtime_capability_strings() {
        let values = supported_runtime_capability_strings();
        assert!(values.contains(&"network"));
        assert!(values.contains(&"file"));
        assert!(values.contains(&"notification"));
        assert!(values.contains(&"calendar"));
    }
}
