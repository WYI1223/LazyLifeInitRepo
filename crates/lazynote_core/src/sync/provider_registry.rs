//! In-process provider registry and selection hooks.

use crate::sync::provider_spi::ProviderSpi;
use crate::sync::provider_types::{
    ProviderAuthRequest, ProviderAuthResult, ProviderConflictMapRequest, ProviderConflictMapResult,
    ProviderErrorEnvelope, ProviderPullRequest, ProviderPullResult, ProviderPushRequest,
    ProviderPushResult, ProviderResult, ProviderStatus, SyncStage,
};
use std::collections::BTreeMap;
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::sync::Arc;

/// Provider registration/selection errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderRegistryError {
    InvalidProviderId(String),
    DuplicateProviderId(String),
    ProviderNotFound(String),
}

impl Display for ProviderRegistryError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidProviderId(value) => write!(f, "provider id is invalid: {value}"),
            Self::DuplicateProviderId(value) => {
                write!(f, "provider id already registered: {value}")
            }
            Self::ProviderNotFound(value) => write!(f, "provider not found: {value}"),
        }
    }
}

impl Error for ProviderRegistryError {}

/// Runtime provider SPI registry.
#[derive(Default)]
pub struct ProviderRegistry {
    providers: BTreeMap<String, Arc<dyn ProviderSpi>>,
    active_provider_id: Option<String>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers one provider adapter.
    pub fn register(
        &mut self,
        provider: Arc<dyn ProviderSpi>,
    ) -> Result<(), ProviderRegistryError> {
        let provider_id = provider.provider_id().trim().to_string();
        if !is_valid_provider_id(&provider_id) {
            return Err(ProviderRegistryError::InvalidProviderId(provider_id));
        }
        if self.providers.contains_key(provider_id.as_str()) {
            return Err(ProviderRegistryError::DuplicateProviderId(provider_id));
        }

        self.providers.insert(provider_id, provider);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.providers.len()
    }

    pub fn is_empty(&self) -> bool {
        self.providers.is_empty()
    }

    /// Returns sorted provider ids.
    pub fn provider_ids(&self) -> Vec<String> {
        self.providers.keys().cloned().collect()
    }

    /// Selects one active provider.
    pub fn select_active(&mut self, provider_id: &str) -> Result<(), ProviderRegistryError> {
        let normalized = provider_id.trim();
        if !self.providers.contains_key(normalized) {
            return Err(ProviderRegistryError::ProviderNotFound(
                normalized.to_string(),
            ));
        }
        self.active_provider_id = Some(normalized.to_string());
        Ok(())
    }

    /// Clears active provider selection.
    pub fn clear_active(&mut self) {
        self.active_provider_id = None;
    }

    /// Returns active provider id.
    pub fn active_provider_id(&self) -> Option<&str> {
        self.active_provider_id.as_deref()
    }

    /// Returns one provider by id.
    pub fn get(&self, provider_id: &str) -> Option<Arc<dyn ProviderSpi>> {
        self.providers.get(provider_id.trim()).cloned()
    }

    /// Returns active provider handle.
    pub fn active_provider(&self) -> Option<Arc<dyn ProviderSpi>> {
        let id = self.active_provider_id()?;
        self.get(id)
    }

    /// Returns status for one provider.
    pub fn provider_status(&self, provider_id: &str) -> Option<ProviderStatus> {
        self.get(provider_id).map(|provider| provider.status())
    }

    /// Returns status for current active provider.
    pub fn active_status(&self) -> Option<ProviderStatus> {
        self.active_provider().map(|provider| provider.status())
    }

    /// Executes auth against selected provider.
    pub fn auth_active(&self, request: ProviderAuthRequest) -> ProviderResult<ProviderAuthResult> {
        self.require_active(SyncStage::Auth)?.auth(request)
    }

    /// Executes pull against selected provider.
    pub fn pull_active(&self, request: ProviderPullRequest) -> ProviderResult<ProviderPullResult> {
        self.require_active(SyncStage::Pull)?.pull(request)
    }

    /// Executes push against selected provider.
    pub fn push_active(&self, request: ProviderPushRequest) -> ProviderResult<ProviderPushResult> {
        self.require_active(SyncStage::Push)?.push(request)
    }

    /// Executes conflict-map against selected provider.
    pub fn conflict_map_active(
        &self,
        request: ProviderConflictMapRequest,
    ) -> ProviderResult<ProviderConflictMapResult> {
        self.require_active(SyncStage::ConflictMap)?
            .conflict_map(request)
    }

    fn require_active(&self, stage: SyncStage) -> ProviderResult<Arc<dyn ProviderSpi>> {
        match self.active_provider() {
            Some(provider) => Ok(provider),
            None => Err(ProviderErrorEnvelope::new(
                "registry",
                stage,
                "provider_not_selected",
                "No active provider selected.",
                false,
            )),
        }
    }
}

fn is_valid_provider_id(value: &str) -> bool {
    if value.is_empty() {
        return false;
    }
    value
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

#[cfg(test)]
mod tests {
    use super::{ProviderRegistry, ProviderRegistryError};
    use crate::sync::provider_spi::ProviderSpi;
    use crate::sync::provider_types::{
        ProviderAuthRequest, ProviderAuthResult, ProviderAuthState, ProviderConflictMapRequest,
        ProviderConflictMapResult, ProviderHealth, ProviderPullRequest, ProviderPullResult,
        ProviderPushRequest, ProviderPushResult, ProviderResult, ProviderStatus,
    };
    use std::sync::Arc;

    struct MockProvider {
        provider_id: String,
    }

    impl MockProvider {
        fn new(provider_id: &str) -> Self {
            Self {
                provider_id: provider_id.to_string(),
            }
        }
    }

    impl ProviderSpi for MockProvider {
        fn provider_id(&self) -> &str {
            &self.provider_id
        }

        fn status(&self) -> ProviderStatus {
            ProviderStatus {
                provider_id: self.provider_id.clone(),
                health: ProviderHealth::Healthy,
                auth_state: ProviderAuthState::Authenticated,
                last_sync_at_ms: Some(123),
            }
        }

        fn auth(&self, _request: ProviderAuthRequest) -> ProviderResult<ProviderAuthResult> {
            Ok(ProviderAuthResult {
                state: ProviderAuthState::Authenticated,
                granted: true,
                expires_at_ms: Some(999),
            })
        }

        fn pull(&self, _request: ProviderPullRequest) -> ProviderResult<ProviderPullResult> {
            Ok(ProviderPullResult {
                records: vec![],
                next_cursor: Some("next".to_string()),
                has_more: false,
            })
        }

        fn push(&self, _request: ProviderPushRequest) -> ProviderResult<ProviderPushResult> {
            Ok(ProviderPushResult {
                accepted_count: 0,
                failed_count: 0,
                conflict_candidates: vec![],
            })
        }

        fn conflict_map(
            &self,
            _request: ProviderConflictMapRequest,
        ) -> ProviderResult<ProviderConflictMapResult> {
            Ok(ProviderConflictMapResult { decisions: vec![] })
        }
    }

    #[test]
    fn registers_and_selects_provider() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");
        assert_eq!(registry.len(), 1);
        assert!(registry.active_provider_id().is_none());

        registry
            .select_active("google_calendar")
            .expect("provider should be selectable");
        assert_eq!(registry.active_provider_id(), Some("google_calendar"));
    }

    #[test]
    fn rejects_invalid_or_duplicate_provider_id() {
        let mut registry = ProviderRegistry::new();
        let invalid = registry.register(Arc::new(MockProvider::new("Google Calendar")));
        assert!(matches!(
            invalid,
            Err(ProviderRegistryError::InvalidProviderId(_))
        ));
        let blank = registry.register(Arc::new(MockProvider::new("   ")));
        assert!(matches!(
            blank,
            Err(ProviderRegistryError::InvalidProviderId(_))
        ));

        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("first provider should register");
        let duplicate = registry.register(Arc::new(MockProvider::new("google_calendar")));
        assert!(matches!(
            duplicate,
            Err(ProviderRegistryError::DuplicateProviderId(_))
        ));
    }

    #[test]
    fn returns_provider_not_selected_error_for_active_calls() {
        let registry = ProviderRegistry::new();
        let err = registry
            .pull_active(ProviderPullRequest {
                cursor: None,
                limit: 10,
            })
            .expect_err("without active provider pull should fail");
        assert_eq!(err.code, "provider_not_selected");
    }

    #[test]
    fn select_active_accepts_trimmed_input_and_normalizes_storage() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");

        registry
            .select_active("  google_calendar  ")
            .expect("trimmed provider id should be selectable");
        assert_eq!(registry.active_provider_id(), Some("google_calendar"));
    }

    #[test]
    fn can_reselect_active_provider() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("google provider should register");
        registry
            .register(Arc::new(MockProvider::new("microsoft_todo")))
            .expect("microsoft provider should register");

        registry
            .select_active("google_calendar")
            .expect("google provider should select");
        assert_eq!(registry.active_provider_id(), Some("google_calendar"));

        registry
            .select_active("microsoft_todo")
            .expect("microsoft provider should select");
        assert_eq!(registry.active_provider_id(), Some("microsoft_todo"));
    }

    #[test]
    fn active_operations_fail_after_clear_active() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");
        registry
            .select_active("google_calendar")
            .expect("provider should select");

        registry.clear_active();
        let err = registry
            .pull_active(ProviderPullRequest {
                cursor: None,
                limit: 10,
            })
            .expect_err("active operations should fail after clear_active");
        assert_eq!(err.code, "provider_not_selected");
    }

    #[test]
    fn get_trims_input_and_returns_none_for_blank_value() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");

        assert!(registry.get("  google_calendar  ").is_some());
        assert!(registry.get("   ").is_none());
    }

    #[test]
    fn delegates_active_operations_to_selected_provider() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");
        registry
            .select_active("google_calendar")
            .expect("provider should select");

        let auth = registry
            .auth_active(ProviderAuthRequest {
                interactive: false,
                scopes: vec!["calendar.read".to_string()],
            })
            .expect("auth should succeed");
        assert!(auth.granted);

        let pull = registry
            .pull_active(ProviderPullRequest {
                cursor: None,
                limit: 100,
            })
            .expect("pull should succeed");
        assert_eq!(pull.next_cursor.as_deref(), Some("next"));
    }

    #[test]
    fn returns_active_status() {
        let mut registry = ProviderRegistry::new();
        registry
            .register(Arc::new(MockProvider::new("google_calendar")))
            .expect("provider should register");
        registry
            .select_active("google_calendar")
            .expect("provider should select");

        let status = registry.active_status().expect("active status");
        assert_eq!(status.provider_id, "google_calendar");
        assert_eq!(status.health, ProviderHealth::Healthy);
        assert_eq!(status.auth_state, ProviderAuthState::Authenticated);
    }
}
