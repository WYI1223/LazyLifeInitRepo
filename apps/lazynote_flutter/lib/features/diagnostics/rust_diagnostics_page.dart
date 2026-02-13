import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/rust_bridge.dart';

/// Development-only diagnostics page for verifying Rust bridge runtime status.
class RustDiagnosticsPage extends StatefulWidget {
  const RustDiagnosticsPage({super.key});

  @override
  State<RustDiagnosticsPage> createState() => _RustDiagnosticsPageState();
}

class _RustDiagnosticsPageState extends State<RustDiagnosticsPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rust Diagnostics')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<RustHealthSnapshot>(
              future: _healthFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Initializing Rust bridge...'),
                    ],
                  );
                }

                if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 40,
                        color: Colors.red,
                      ),
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
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
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
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Refresh'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
