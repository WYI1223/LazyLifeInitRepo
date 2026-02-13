import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/rust_bridge.dart';

/// Standalone diagnostics page wrapper.
class RustDiagnosticsPage extends StatelessWidget {
  const RustDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rust Diagnostics')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: RustDiagnosticsContent(),
        ),
      ),
    );
  }
}

/// Reusable diagnostics content that can be embedded in Workbench left pane.
class RustDiagnosticsContent extends StatefulWidget {
  const RustDiagnosticsContent({super.key});

  @override
  State<RustDiagnosticsContent> createState() => _RustDiagnosticsContentState();
}

class _RustDiagnosticsContentState extends State<RustDiagnosticsContent> {
  late Future<RustHealthSnapshot> _healthFuture;

  @override
  void initState() {
    super.initState();
    _healthFuture = RustBridge.runHealthCheck();
  }

  void _reload() {
    setState(() {
      _healthFuture = RustBridge.runHealthCheck();
    });
  }

  String _buildErrorHint(Object error) {
    final text = error.toString();
    if (text.contains('Failed to load dynamic library')) {
      return '$text\n\nHint: run `cd crates && cargo build -p lazynote_ffi --release` first.';
    }
    return text;
  }

  Widget _buildLoggingStatus() {
    final snapshot = RustBridge.latestLoggingInitSnapshot;
    if (snapshot == null) {
      return const Text('Logging init status: not attempted in this process.');
    }

    final statusText = snapshot.isSuccess ? 'ok' : 'error';
    final errorText = snapshot.errorMessage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('logging_init status: $statusText'),
            Text('level: ${snapshot.level}'),
            Text('logDir: ${snapshot.logDir}'),
            if (errorText != null) Text('error: $errorText'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RustHealthSnapshot>(
      future: _healthFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Initializing Rust bridge...'),
              const SizedBox(height: 16),
              _buildLoggingStatus(),
            ],
          );
        }

        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Rust bridge initialization failed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _buildErrorHint(snapshot.error!),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reload, child: const Text('Retry')),
              const SizedBox(height: 16),
              _buildLoggingStatus(),
            ],
          );
        }

        final health = snapshot.data!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 40,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            const Text(
              'Rust bridge connected',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('ping: ${health.ping}'),
            Text('coreVersion: ${health.coreVersion}'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: const Text('Refresh')),
            const SizedBox(height: 16),
            _buildLoggingStatus(),
          ],
        );
      },
    );
  }
}
