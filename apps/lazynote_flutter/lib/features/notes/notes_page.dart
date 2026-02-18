import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazynote_flutter/app/ui_slots/first_party_ui_slots.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_host.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';
import 'package:lazynote_flutter/features/notes/note_content_area.dart';
import 'package:lazynote_flutter/features/notes/note_explorer.dart';
import 'package:lazynote_flutter/features/notes/note_tab_manager.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';
import 'package:window_manager/window_manager.dart';

/// Notes feature page mounted in Workbench left pane (PR-0010C foundation).
class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    this.controller,
    this.onBackToWorkbench,
    this.uiSlotRegistry,
  });

  /// Optional external controller for tests.
  final NotesController? controller;

  /// Optional callback that returns to Workbench home section.
  final VoidCallback? onBackToWorkbench;
  final UiSlotRegistry? uiSlotRegistry;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NextTabIntent extends Intent {
  const _NextTabIntent();
}

class _PreviousTabIntent extends Intent {
  const _PreviousTabIntent();
}

enum _CloseDialogAction { cancel, retry }

class _NotesPageState extends State<NotesPage>
    with WidgetsBindingObserver, WindowListener {
  late final NotesController _controller;
  late final bool _ownsController;
  late final UiSlotRegistry _uiSlotRegistry;
  bool _windowCloseGuardEnabled = false;
  bool _preventCloseActive = false;
  bool _handlingWindowClose = false;
  bool _forceClosing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? NotesController();
    _ownsController = widget.controller == null;
    _uiSlotRegistry = widget.uiSlotRegistry ?? createFirstPartyUiSlotRegistry();
    _controller.addListener(_onControllerChanged);
    unawaited(_setupWindowCloseGuard());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.loadNotes();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    if (_windowCloseGuardEnabled) {
      unawaited(_teardownWindowCloseGuard());
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  bool get _supportsWindowCloseGuard {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.contains('TestWidgetsFlutterBinding')) {
      return false;
    }
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => true,
      TargetPlatform.macOS => true,
      TargetPlatform.linux => true,
      TargetPlatform.android => false,
      TargetPlatform.iOS => false,
      TargetPlatform.fuchsia => false,
    };
  }

  Future<void> _setupWindowCloseGuard() async {
    if (!_supportsWindowCloseGuard) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      _windowCloseGuardEnabled = true;
      await _syncWindowCloseInterception(force: true);
    } catch (_) {
      _windowCloseGuardEnabled = false;
    }
  }

  Future<void> _teardownWindowCloseGuard() async {
    try {
      windowManager.removeListener(this);
      await windowManager.setPreventClose(false);
    } catch (_) {}
    _windowCloseGuardEnabled = false;
    _preventCloseActive = false;
  }

  void _onControllerChanged() {
    if (!_windowCloseGuardEnabled || _forceClosing) {
      return;
    }
    unawaited(_syncWindowCloseInterception());
  }

  Future<void> _syncWindowCloseInterception({bool force = false}) async {
    if (!_windowCloseGuardEnabled) {
      return;
    }
    // Why: always-on close interception adds visible close latency even when
    // nothing is dirty. We only intercept while save work is pending.
    final shouldPrevent = _controller.hasPendingSaveWork;
    if (!force && shouldPrevent == _preventCloseActive) {
      return;
    }
    try {
      await windowManager.setPreventClose(shouldPrevent);
      _preventCloseActive = shouldPrevent;
    } catch (_) {}
  }

  Future<void> _closeWindowNow() async {
    _forceClosing = true;
    try {
      if (_windowCloseGuardEnabled && _preventCloseActive) {
        try {
          await windowManager.setPreventClose(false);
          _preventCloseActive = false;
        } catch (_) {}
      }
      try {
        // Why: prefer normal close path first so desktop shell exits quickly.
        await windowManager.close();
      } catch (_) {
        // Fallback: force destroy when close API is unavailable/fails.
        await windowManager.destroy();
      }
    } finally {
      _forceClosing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.flushPendingSave());
    }
  }

  @override
  void onWindowClose() {
    if (!_windowCloseGuardEnabled || _handlingWindowClose) {
      return;
    }
    _handlingWindowClose = true;
    unawaited(_handleWindowCloseRequest());
  }

  Future<void> _handleWindowCloseRequest() async {
    try {
      if (!_controller.hasPendingSaveWork) {
        await _closeWindowNow();
        return;
      }

      final flushed = await _controller.flushPendingSave().timeout(
        // Why: close flow should be best-effort and responsive. Do not block
        // desktop shutdown on long I/O stalls.
        const Duration(milliseconds: 450),
        onTimeout: () => false,
      );
      if (!mounted) {
        return;
      }
      if (flushed) {
        await _closeWindowNow();
        return;
      }

      final action = await showDialog<_CloseDialogAction>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Unsaved content'),
            content: const Text(
              'Save failed. Retry or back up content before closing.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(_CloseDialogAction.cancel);
                },
                child: const Text('Keep editing'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(context).pop(_CloseDialogAction.retry);
                },
                child: const Text('Retry save'),
              ),
            ],
          );
        },
      );

      if (action == _CloseDialogAction.retry) {
        final retried = await _controller.retrySaveCurrentDraft();
        if (retried && mounted) {
          await _closeWindowNow();
        }
      }
    } finally {
      _handlingWindowClose = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.tab, control: true):
            _NextTabIntent(),
        SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
            _PreviousTabIntent(),
      },
      child: Actions(
        actions: {
          _NextTabIntent: CallbackAction<_NextTabIntent>(
            onInvoke: (_) {
              _controller.activateNextOpenNote();
              return null;
            },
          ),
          _PreviousTabIntent: CallbackAction<_PreviousTabIntent>(
            onInvoke: (_) {
              _controller.activatePreviousOpenNote();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeader = constraints.maxWidth < 860;
                  // Why: keep the two-pane shell visually stable in Workbench
                  // regardless of host window resize jitter.
                  final paneHeight = constraints.maxHeight.isFinite
                      ? (constraints.maxHeight - 72).clamp(300, 640).toDouble()
                      : 640.0;
                  // Why: explorer should keep a stable shell width so note
                  // navigation does not reflow with content pane resizing.
                  const explorerWidth = 276.0;

                  return Column(
                    key: const Key('notes_page_root'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            key: const Key('notes_back_to_workbench_button'),
                            onPressed: widget.onBackToWorkbench,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: Text(
                              compactHeader ? 'Back' : 'Back to Workbench',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: kNotesPrimaryText,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Notes Shell',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: kNotesPrimaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (!compactHeader) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: kNotesSidebarBackground,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Ctrl+Tab switch',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: kNotesSecondaryText),
                              ),
                            ),
                          ],
                          IconButton(
                            key: const Key('notes_reload_button'),
                            tooltip: 'Reload notes',
                            onPressed:
                                (_controller.creatingNote ||
                                    _controller.createTagApplyInFlight)
                                ? null
                                : _controller.loadNotes,
                            icon: const Icon(
                              Icons.refresh,
                              color: kNotesPrimaryText,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: paneHeight,
                        child: Row(
                          children: [
                            SizedBox(
                              width: explorerWidth,
                              child: UiSlotListHost(
                                registry: _uiSlotRegistry,
                                slotId: UiSlotIds.notesSidePanel,
                                layer: UiSlotLayer.sidePanel,
                                slotContext: UiSlotContext({
                                  UiSlotContextKeys.notesController:
                                      _controller,
                                  UiSlotContextKeys.notesOnOpenNoteRequested:
                                      _controller.openNoteFromExplorer,
                                  UiSlotContextKeys
                                      .notesOnCreateNoteRequested: () async {
                                    await _controller.createNote();
                                    if (!context.mounted) {
                                      return;
                                    }
                                    final warning = _controller
                                        .takeCreateWarningMessage();
                                    if (warning == null) {
                                      return;
                                    }
                                    ScaffoldMessenger.maybeOf(context)
                                      ?..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(warning),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                  },
                                  UiSlotContextKeys
                                          .notesOnDeleteFolderRequested:
                                      (String folderId, String mode) {
                                        return _controller
                                            .deleteWorkspaceFolder(
                                              folderId: folderId,
                                              mode: mode,
                                            );
                                      },
                                }),
                                listBuilder: (context, children) {
                                  return children.isEmpty
                                      ? const SizedBox.shrink()
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: children
                                              .map(
                                                (child) =>
                                                    Expanded(child: child),
                                              )
                                              .toList(growable: false),
                                        );
                                },
                                fallbackBuilder: (context) {
                                  return NoteExplorer(
                                    controller: _controller,
                                    onOpenNoteRequested:
                                        _controller.openNoteFromExplorer,
                                    onCreateNoteRequested: () async {
                                      await _controller.createNote();
                                      if (!context.mounted) {
                                        return;
                                      }
                                      final warning = _controller
                                          .takeCreateWarningMessage();
                                      if (warning == null) {
                                        return;
                                      }
                                      ScaffoldMessenger.maybeOf(context)
                                        ?..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(warning),
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(
                                              seconds: 4,
                                            ),
                                          ),
                                        );
                                    },
                                    onDeleteFolderRequested: (folderId, mode) {
                                      return _controller.deleteWorkspaceFolder(
                                        folderId: folderId,
                                        mode: mode,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              indent: 12,
                              endIndent: 12,
                              color: kNotesDividerColor,
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  NoteTabManager(controller: _controller),
                                  Expanded(
                                    child: NoteContentArea(
                                      controller: _controller,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
