/// Best-effort parsed metadata for a single log line produced by
/// [flexi_logger::detailed_format].
///
/// Expected detailed_format shape in flexi_logger 0.29:
///   `[YYYY-MM-DD HH:MM:SS.ffffff TZ] LEVEL [module::path] src/file.rs:line: message`
///
/// Legacy default_format shape (no timestamp):
///   `LEVEL [module::path] message`
///
/// When a line does not match known formats, [timestamp] and [level] are null
/// and [message] returns the raw line unchanged. Callers must treat all fields
/// as best-effort and never fail on an unrecognised line.
class LogLineMeta {
  const LogLineMeta({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.raw,
  });

  /// Extracted time in `HH:MM:SS.mmm` form, or null when not parseable.
  final String? timestamp;

  /// Lowercase severity level (`trace`|`debug`|`info`|`warn`|`error`),
  /// or null when not parseable.
  final String? level;

  /// Message body after structured metadata prefixes.
  /// Falls back to the full raw line when the format is unrecognised.
  final String message;

  /// Original unmodified line as read from the log file.
  final String raw;

  // Matches flexi_logger detailed_format:
  //   [2026-02-15 10:23:45.123456 +00:00] INFO [lazynote_core::logging] src/logging.rs:100: event=app_start
  //
  // Group 1 - HH:MM:SS.mmm (first 3 of the 6 fractional-second digits)
  // Group 2 - level token   (e.g. INFO)
  // Group 3 - message body  (everything after "file:line: ")
  static final RegExp _detailedPattern = RegExp(
    r'^\[\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2}\.\d{3})\d* [^\]]+\] (\w+) \[[^\]]+\] .+?:\d+: (.*)$',
  );

  // Backward-compatible matcher for the previously documented shape:
  //   [2026-02-15 10:23:45.123456 UTC] INFO [src/logging.rs:100] event=app_start
  static final RegExp _bracketFilePattern = RegExp(
    r'^\[\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2}\.\d{3})\d* [^\]]+\] (\w+) \[[^\]]*:\d+\] (.*)$',
  );

  // Legacy default_format matcher (no timestamp):
  //   INFO [lazynote_core::db::open] event=db_open module=db status=ok
  static final RegExp _defaultPattern = RegExp(
    r'^(TRACE|DEBUG|INFO|WARN|ERROR) \[[^\]]+\] (.*)$',
  );

  /// Parses [raw] and returns a [LogLineMeta].
  ///
  /// Always succeeds - returns a fallback with null metadata fields when the
  /// line does not match the expected format.
  static LogLineMeta parse(String raw) {
    // trimRight handles optional \r on Windows CRLF log files.
    final normalized = raw.trimRight();

    final detailed = _detailedPattern.firstMatch(normalized);
    if (detailed != null) {
      return LogLineMeta(
        timestamp: detailed.group(1),
        level: detailed.group(2)?.toLowerCase(),
        message: detailed.group(3) ?? '',
        raw: raw,
      );
    }

    final bracketFile = _bracketFilePattern.firstMatch(normalized);
    if (bracketFile != null) {
      return LogLineMeta(
        timestamp: bracketFile.group(1),
        level: bracketFile.group(2)?.toLowerCase(),
        message: bracketFile.group(3) ?? '',
        raw: raw,
      );
    }

    final defaultLine = _defaultPattern.firstMatch(normalized);
    if (defaultLine != null) {
      return LogLineMeta(
        timestamp: null,
        level: defaultLine.group(1)?.toLowerCase(),
        message: defaultLine.group(2) ?? '',
        raw: raw,
      );
    }

    return LogLineMeta(timestamp: null, level: null, message: raw, raw: raw);
  }
}
