use lazynote_core::{
    ExtensionKernelError, ExtensionManifest, ExtensionRegistry, FirstPartyExtensionAdapter,
    ManifestEntrypoints, RuntimeCapability,
};

fn manifest_with_runtime_capabilities(runtime_caps: &[&str]) -> ExtensionManifest {
    ExtensionManifest {
        id: "builtin.test.capability".to_string(),
        version: "0.1.0".to_string(),
        capabilities: vec!["command".to_string()],
        runtime_capabilities: runtime_caps.iter().map(|value| value.to_string()).collect(),
        entrypoints: ManifestEntrypoints {
            init: Some("builtin.test.init".to_string()),
            dispose: Some("builtin.test.dispose".to_string()),
            health: Some("builtin.test.health".to_string()),
            command_action: Some("builtin.test.command".to_string()),
            input_parser: None,
            provider_spi: None,
            ui_slot: None,
        },
    }
}

#[test]
fn runtime_capability_guard_denies_by_default_when_undeclared() {
    let mut registry = ExtensionRegistry::new();
    let adapter = FirstPartyExtensionAdapter::new(manifest_with_runtime_capabilities(&[]));
    registry
        .register_adapter(&adapter)
        .expect("adapter registration");

    for capability in [
        RuntimeCapability::Network,
        RuntimeCapability::File,
        RuntimeCapability::Notification,
        RuntimeCapability::Calendar,
    ] {
        let err = registry
            .assert_runtime_capability("builtin.test.capability", capability)
            .expect_err("undeclared runtime capability must be denied");
        assert!(matches!(err, ExtensionKernelError::CapabilityDenied { .. }));
    }
}

#[test]
fn runtime_capability_guard_covers_network_file_notification_calendar_paths() {
    let mut registry = ExtensionRegistry::new();
    let adapter = FirstPartyExtensionAdapter::new(manifest_with_runtime_capabilities(&[
        "network",
        "file",
        "notification",
        "calendar",
    ]));
    registry
        .register_adapter(&adapter)
        .expect("adapter registration");

    for capability in [
        RuntimeCapability::Network,
        RuntimeCapability::File,
        RuntimeCapability::Notification,
        RuntimeCapability::Calendar,
    ] {
        registry
            .assert_runtime_capability("builtin.test.capability", capability)
            .expect("declared runtime capability should be allowed");
    }
}

#[test]
fn runtime_capability_guard_rejects_partial_declaration_access() {
    let mut registry = ExtensionRegistry::new();
    let adapter = FirstPartyExtensionAdapter::new(manifest_with_runtime_capabilities(&["network"]));
    registry
        .register_adapter(&adapter)
        .expect("adapter registration");

    registry
        .assert_runtime_capability("builtin.test.capability", RuntimeCapability::Network)
        .expect("network capability should be allowed");

    for capability in [
        RuntimeCapability::File,
        RuntimeCapability::Notification,
        RuntimeCapability::Calendar,
    ] {
        let err = registry
            .assert_runtime_capability("builtin.test.capability", capability)
            .expect_err("undeclared runtime capability must be denied");
        assert!(matches!(err, ExtensionKernelError::CapabilityDenied { .. }));
    }
}

#[test]
fn runtime_capability_guard_is_stable_across_repeated_checks() {
    let mut registry = ExtensionRegistry::new();
    let adapter = FirstPartyExtensionAdapter::new(manifest_with_runtime_capabilities(&[
        "network", "calendar",
    ]));
    registry
        .register_adapter(&adapter)
        .expect("adapter registration");

    for _ in 0..3 {
        registry
            .assert_runtime_capability("builtin.test.capability", RuntimeCapability::Network)
            .expect("declared capability should remain allowed");
        registry
            .assert_runtime_capability("builtin.test.capability", RuntimeCapability::Calendar)
            .expect("declared capability should remain allowed");
    }

    for _ in 0..3 {
        let err = registry
            .assert_runtime_capability("builtin.test.capability", RuntimeCapability::File)
            .expect_err("undeclared capability should remain denied");
        assert!(matches!(err, ExtensionKernelError::CapabilityDenied { .. }));
    }
}
