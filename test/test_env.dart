import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:omni_plan/data/plan_store.dart';

/// In-memory stand-in for the Hive box, used by widget tests. Widget tests
/// run on a fake clock, which cannot drive real file I/O; the Hive-backed
/// paths are covered by store_test.dart instead.
class MemoryBox implements Box<String> {
  final Map<dynamic, String> _data = {};
  bool _open = true;

  @override
  Iterable<dynamic> get keys => _data.keys.toList();

  @override
  int get length => _data.length;

  @override
  bool get isOpen => _open;

  @override
  String? get(dynamic key, {String? defaultValue}) => _data[key] ?? defaultValue;

  @override
  bool containsKey(dynamic key) => _data.containsKey(key);

  @override
  Future<void> put(dynamic key, String value) async => _data[key] = value;

  @override
  Future<void> putAll(Map<dynamic, String> entries) async => _data.addAll(entries);

  @override
  Future<void> delete(dynamic key) async => _data.remove(key);

  @override
  Future<int> clear() async {
    final n = _data.length;
    _data.clear();
    return n;
  }

  @override
  Future<void> close() async => _open = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A throwaway device: Hive in a temp directory.
class TestEnv {
  final Directory dir;
  TestEnv._(this.dir);

  static Future<TestEnv> create() async {
    final dir = Directory.systemTemp.createTempSync('omni_plan_test');
    Hive.init(dir.path);
    return TestEnv._(dir);
  }

  Future<PlanStore> store(String scope) async {
    final s = PlanStore();
    await s.open(scope);
    return s;
  }

  Future<void> dispose() async {
    await Hive.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// A store on a [MemoryBox], for widget tests.
Future<PlanStore> memoryStore([String scope = 'local']) async {
  final s = PlanStore();
  await s.openWith(MemoryBox(), scope);
  return s;
}

/// flutter_test draws with a placeholder font unless the real one is
/// loaded; load Poppins so layout in tests matches the device.
Future<void> loadPoppins() async {
  final loader = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Poppins-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
