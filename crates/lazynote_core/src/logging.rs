//! Core logging bootstrap and safety policy.
//!
//! # Responsibility
//! - Initialize file-based rolling logs exactly once per process.
//! - Emit stable, metadata-only diagnostic events from core.
//!
//! # Invariants
//! - Logging init is idempotent for the same directory.
//! - Logging initialization must not panic.
//! - Re-initialization with a different directory is rejected.
//!
//! # See also
//! - docs/architecture/logging.md

use flexi_logger::{Cleanup, Criterion, FileSpec, Logger, LoggerHandle, Naming, WriteMode};
use log::{error, info};
use once_cell::sync::OnceCell;
use std::path::{Path, PathBuf};

const LOG_FILE_BASENAME: &str = "lazynote";
const MAX_LOG_FILE_SIZE_BYTES: u64 = 10 * 1024 * 1024;
const MAX_LOG_FILES: usize = 5;
const MAX_PANIC_PAYLOAD_CHARS: usize = 160;

static LOGGING_STATE: OnceCell<LoggingState> = OnceCell::new();
static PANIC_HOOK_INSTALLED: OnceCell<()> = OnceCell::new();

struct LoggingState {
    level: &'static str,
    log_dir: PathBuf,
    _logger: LoggerHandle,
}

/// Initializes core logging with level and directory.
///
/// Returns `Ok(())` when logging is active, or a human-readable error string
/// when initialization fails.
///
/// # Invariants
/// - Calling this function repeatedly with the same `log_dir` is idempotent.
/// - Calling this function repeatedly with a different `level` is rejected.
/// - Re-initialization with a different `log_dir` is rejected.
/// - Initialization never panics.
///
/// # Errors
/// - Returns an error when `level` is unsupported.
/// - Returns an error when `log_dir` is empty, non-absolute, or cannot be created.
/// - Returns an error when logger backend setup fails.
pub fn init_logging(level: &str, log_dir: &str) -> Result<(), String> {
    let normalized_level = normalize_level(level)?;
    let normalized_dir = normalize_log_dir(log_dir)?;

    if let Some(state) = LOGGING_STATE.get() {
        if state.log_dir == normalized_dir {
            if state.level != normalized_level {
                return Err(format!(
                    "logging already initialized with level `{}`; refusing to switch to `{}`",
                    state.level, normalized_level
                ));
            }
            return Ok(());
        }
        return Err(format!(
            "logging already initialized at `{}`; refusing to switch to `{}`",
            state.log_dir.display(),
            normalized_dir.display()
        ));
    }

    let init_level = normalized_level;
    let init_dir = normalized_dir.clone();

    let state = LOGGING_STATE.get_or_try_init(|| -> Result<LoggingState, String> {
        std::fs::create_dir_all(&init_dir).map_err(|err| {
            format!(
                "failed to create log directory `{}`: {err}",
                init_dir.display()
            )
        })?;

        let logger = Logger::try_with_str(init_level)
            .map_err(|err| format!("invalid log level `{init_level}`: {err}"))?
            .log_to_file(
                FileSpec::default()
                    .directory(init_dir.as_path())
                    .basename(LOG_FILE_BASENAME),
            )
            .rotate(
                Criterion::Size(MAX_LOG_FILE_SIZE_BYTES),
                Naming::Numbers,
                Cleanup::KeepLogFiles(MAX_LOG_FILES),
            )
            .write_mode(WriteMode::BufferAndFlush)
            .append()
            // Why: detailed_format adds timestamp + source location, enabling the
            // diagnostics viewer to parse and display a structured timestamp column.
            // Format: [YYYY-MM-DD HH:MM:SS.ffffff TZ] LEVEL [module] file:line: message
            .format_for_files(flexi_logger::detailed_format)
            .start()
            .map_err(|err| format!("failed to start logger: {err}"))?;

        install_panic_hook_once();

        info!(
            "event=app_start module=core status=ok platform={} build_mode={} version={}",
            std::env::consts::OS,
            build_mode(),
            env!("CARGO_PKG_VERSION")
        );
        info!(
            "event=core_init module=core status=ok level={} log_dir={}",
            init_level,
            init_dir.display()
        );

        Ok(LoggingState {
            level: init_level,
            log_dir: init_dir,
            _logger: logger,
        })
    })?;

    if state.log_dir != normalized_dir {
        return Err(format!(
            "logging already initialized at `{}`; refusing to switch to `{}`",
            state.log_dir.display(),
            normalized_dir.display()
        ));
    }
    if state.level != normalized_level {
        return Err(format!(
            "logging already initialized with level `{}`; refusing to switch to `{}`",
            state.level, normalized_level
        ));
    }

    Ok(())
}

/// Returns active logging status metadata.
///
/// Returns `None` when logging has not been initialized.
/// Returns `(level, log_dir)` when logging is active.
pub fn logging_status() -> Option<(&'static str, PathBuf)> {
    LOGGING_STATE
        .get()
        .map(|state| (state.level, state.log_dir.clone()))
}

/// Returns the default log level for current build mode.
///
/// - `debug` builds -> `debug`
/// - `release` builds -> `info`
pub fn default_log_level() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "info"
    }
}

fn normalize_level(level: &str) -> Result<&'static str, String> {
    match level.trim().to_ascii_lowercase().as_str() {
        "trace" => Ok("trace"),
        "debug" => Ok("debug"),
        "info" => Ok("info"),
        "warn" | "warning" => Ok("warn"),
        "error" => Ok("error"),
        other => Err(format!(
            "unsupported log level `{other}`; expected trace|debug|info|warn|error"
        )),
    }
}

fn normalize_log_dir(log_dir: &str) -> Result<PathBuf, String> {
    let trimmed = log_dir.trim();
    if trimmed.is_empty() {
        return Err("log_dir cannot be empty".to_string());
    }
    let path = Path::new(trimmed);
    if !path.is_absolute() {
        return Err(format!("log_dir must be an absolute path, got `{trimmed}`"));
    }
    Ok(path.to_path_buf())
}

fn build_mode() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
    }
}

fn install_panic_hook_once() {
    if PANIC_HOOK_INSTALLED.get().is_some() {
        return;
    }

    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        // Why: panic payload can include user-controlled text; sanitize and cap
        // length before logging to reduce privacy and log-bloat risk.
        let location = panic_info
            .location()
            .map(|loc| format!("{}:{}", loc.file(), loc.line()))
            .unwrap_or_else(|| "unknown".to_string());
        let payload = panic_payload_summary(panic_info);
        error!(
            "event=panic_captured module=core status=error location={} payload={}",
            location, payload
        );
        previous_hook(panic_info);
    }));

    let _ = PANIC_HOOK_INSTALLED.set(());
}

fn panic_payload_summary(info: &std::panic::PanicHookInfo<'_>) -> String {
    let payload = if let Some(message) = info.payload().downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = info.payload().downcast_ref::<String>() {
        message.clone()
    } else {
        "non-string panic payload".to_string()
    };

    sanitize_message(&payload, MAX_PANIC_PAYLOAD_CHARS)
}

fn sanitize_message(value: &str, max_chars: usize) -> String {
    let normalized = value.replace(['\n', '\r'], " ");
    let mut truncated = normalized.chars().take(max_chars).collect::<String>();
    if normalized.chars().count() > max_chars {
        truncated.push_str("...");
    }
    truncated
}

#[cfg(test)]
mod tests {
    use super::{
        init_logging, logging_status, normalize_level, normalize_log_dir, sanitize_message,
    };
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(suffix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after unix epoch")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "lazynote-logging-{suffix}-{}-{nanos}",
            std::process::id()
        ))
    }

    #[test]
    fn normalize_level_accepts_known_values() {
        assert_eq!(
            normalize_level("INFO").expect("INFO should normalize"),
            "info"
        );
        assert_eq!(
            normalize_level(" warning ").expect("warning should normalize"),
            "warn"
        );
    }

    #[test]
    fn normalize_log_dir_rejects_relative_path() {
        let error = normalize_log_dir("logs/dev").expect_err("relative paths must be rejected");
        assert!(error.contains("absolute"));
    }

    #[test]
    fn sanitize_message_removes_newlines_and_truncates() {
        let sanitized = sanitize_message("line1\nline2\rline3", 8);
        assert!(!sanitized.contains('\n'));
        assert!(!sanitized.contains('\r'));
        assert!(sanitized.ends_with("..."));
    }

    #[test]
    fn init_logging_is_idempotent_for_same_config_and_rejects_conflicts() {
        let log_dir = unique_temp_dir("idempotent");
        let log_dir_str = log_dir
            .to_str()
            .expect("temp dir should be valid UTF-8")
            .to_string();
        let second_dir = unique_temp_dir("different");
        let second_dir_str = second_dir
            .to_str()
            .expect("temp dir should be valid UTF-8")
            .to_string();

        init_logging("info", &log_dir_str).expect("first init should succeed");
        init_logging("info", &log_dir_str).expect("same config should be idempotent");

        let level_error =
            init_logging("debug", &log_dir_str).expect_err("level conflict should fail");
        assert!(level_error.contains("refusing to switch"));

        let dir_error =
            init_logging("info", &second_dir_str).expect_err("directory conflict should fail");
        assert!(dir_error.contains("refusing to switch"));

        let (active_level, active_dir) = logging_status().expect("logging should be active");
        assert_eq!(active_level, "info");
        assert_eq!(active_dir, log_dir);
    }
}
