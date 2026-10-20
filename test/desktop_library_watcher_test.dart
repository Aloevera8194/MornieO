import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/models/library_database_models.dart';
import 'package:mornye/services/desktop_library_watcher.dart';

LocalLibrarySource _source(
  String id,
  String path, {
  bool enabled = true,
  bool available = true,
}) => LocalLibrarySource(
  id: id,
  path: path,
  displayName: id,
  enabled: enabled,
  available: available,
);

void main() {
  late StreamController<String> changes;
  late List<List<String>> watched;
  late List<String> scans;
  late int unwatches;
  var scanning = false;

  DesktopLibraryWatcher watcher() => DesktopLibraryWatcher(
    scanSource: (id) async => scans.add(id),
    isScanning: () => scanning,
    watch: (paths) async {
      watched.add(paths);
      return paths;
    },
    unwatch: () async => unwatches++,
    changes: changes.stream,
    debounce: const Duration(milliseconds: 60),
  );

  setUp(() {
    changes = StreamController<String>.broadcast();
    watched = [];
    scans = [];
    unwatches = 0;
    scanning = false;
  });

  test('watches enabled, available sources once per change of set', () async {
    final subject = watcher();
    addTearDown(subject.dispose);
    await subject.updateSources([
      _source('a', '/music/a'),
      _source('b', '/music/b', enabled: false),
      _source('c', '/music/c', available: false),
    ]);
    await subject.updateSources([_source('a', '/music/a')]);
    expect(watched, [
      ['/music/a'],
    ]);
    await subject.updateSources(const []);
    expect(unwatches, 1);
  });

  test(
    'a burst of changes scans each source once after the quiet period',
    () async {
      final subject = watcher();
      addTearDown(subject.dispose);
      await subject.updateSources([
        _source('a', '/music/a'),
        _source('b', '/music/b'),
      ]);
      for (var i = 0; i < 5; i++) {
        changes.add('/music/a');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      changes.add('/music/b');
      changes.add('/unknown');
      await Future<void>.delayed(Duration.zero);
      expect(scans, isEmpty);
      expect(subject.pendingSourceIds, {'a', 'b'});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(scans, ['a', 'b']);
      expect(subject.pendingSourceIds, isEmpty);
    },
  );

  test('a running scan postpones the rescan instead of dropping it', () async {
    final subject = watcher();
    addTearDown(subject.dispose);
    await subject.updateSources([_source('a', '/music/a')]);
    scanning = true;
    changes.add('/music/a');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(scans, isEmpty);
    scanning = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(scans, ['a']);
  });

  test('dispose cancels pending scans and stops watching', () async {
    final subject = watcher();
    await subject.updateSources([_source('a', '/music/a')]);
    changes.add('/music/a');
    await Future<void>.delayed(Duration.zero);
    await subject.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(scans, isEmpty);
    expect(unwatches, 1);
  });
}
