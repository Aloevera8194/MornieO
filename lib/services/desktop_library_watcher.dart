import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mornye/models/library_database_models.dart';
import 'package:mornye/services/platform_bridge.dart';
import 'package:mornye/utils/logger.dart';

final _log = AppLogger('LibraryWatcher');

/// Desktop library folder watching: the Rust backend watches the enabled
/// sources (`watchLibraryFolders`) and reports changed roots; this class
/// debounces them and runs the existing incremental source scan once the
/// folder has been quiet for [debounce]. A scan already running postpones
/// the next one instead of dropping it.
class DesktopLibraryWatcher {
  DesktopLibraryWatcher({
    required Future<void> Function(String sourceId) scanSource,
    required bool Function() isScanning,
    Future<List<String>> Function(List<String> paths)? watch,
    Future<void> Function()? unwatch,
    Stream<String>? changes,
    this.debounce = const Duration(seconds: 5),
  }) : _scanSource = scanSource,
       _isScanning = isScanning,
       _watch = watch ?? PlatformBridge.watchLibraryFolders,
       _unwatch = unwatch ?? PlatformBridge.unwatchLibraryFolders,
       _changes = changes ?? PlatformBridge.libraryFolderChangeEvents();

  final Future<void> Function(String sourceId) _scanSource;
  final bool Function() _isScanning;
  final Future<List<String>> Function(List<String> paths) _watch;
  final Future<void> Function() _unwatch;
  final Stream<String> _changes;
  final Duration debounce;

  /// Watched root path to source ID.
  Map<String, String> _roots = const {};
  final _pending = <String>{};
  StreamSubscription<String>? _subscription;
  Timer? _timer;
  bool _flushing = false;
  bool _disposed = false;

  @visibleForTesting
  Set<String> get pendingSourceIds => Set.unmodifiable(_pending);

  /// Watches the enabled, available [sources]. Unchanged sets are not
  /// re-registered.
  Future<void> updateSources(Iterable<LocalLibrarySource> sources) async {
    if (_disposed) return;
    _subscription ??= _changes.listen(_onChanged);
    final roots = {
      for (final source in sources)
        if (source.enabled && source.available && source.path.isNotEmpty)
          source.path: source.id,
    };
    if (mapEquals(roots, _roots)) return;
    _roots = roots;
    _pending.removeWhere((id) => !roots.containsValue(id));
    try {
      if (roots.isEmpty) {
        await _unwatch();
      } else {
        final watched = await _watch(roots.keys.toList(growable: false));
        _log.d('Watching ${watched.length} of ${roots.length} library folders');
      }
    } catch (error) {
      _log.w('Could not watch library folders: $error');
    }
  }

  void _onChanged(String root) {
    final sourceId = _roots[root];
    if (sourceId == null || _disposed) return;
    _pending.add(sourceId);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    if (_disposed || _pending.isEmpty) return;
    if (_flushing || _isScanning()) {
      _schedule();
      return;
    }
    _flushing = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final sourceId = _pending.first;
        _pending.remove(sourceId);
        _log.i('Library folder changed, scanning source $sourceId');
        try {
          await _scanSource(sourceId);
        } catch (error) {
          _log.w('Library rescan after a folder change failed: $error');
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    _pending.clear();
    if (_roots.isNotEmpty) {
      _roots = const {};
      try {
        await _unwatch();
      } catch (_) {
        // Shutting down; the backend drops its watcher with the process.
      }
    }
  }
}
