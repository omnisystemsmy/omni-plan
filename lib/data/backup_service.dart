import 'dart:convert';
import 'dart:io';

import 'package:omni_plan/core/app_info.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';
import 'package:omni_plan/features/templates/template_models.dart';

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// What a backup file holds, worked out before anything is changed.
class BackupPreview {
  final DateTime? createdAt;
  final String? appVersion;

  /// Valid entries, keyed as in the store.
  final Map<String, Object?> entries;
  final Map<String, int> counts;

  /// Entries that could not be read and are left out.
  final int skipped;

  /// References to records missing from the backup that were removed
  /// (for example a task pointing at a deleted project).
  final int repairedLinks;

  /// Entries whose key already exists on this device.
  final int overlapping;

  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.entries,
    required this.counts,
    required this.skipped,
    required this.repairedLinks,
    required this.overlapping,
  });

  int count(String kind) => counts[kind] ?? 0;
}

/// Saves all of an account's plans to one file and puts them back.
///
/// Scope: projects, sections, tasks and subtasks (with checklists,
/// recurrence, reminders and dependencies), milestones, goals, the
/// person's own templates, template favourites and recent use, planning
/// preferences, the notification list and the history. Not included: the
/// app theme (a device setting) and the Omni account itself.
///
/// The file is JSON with a format name, a version and an FNV-1a checksum of
/// the entries, so a damaged or edited file is refused instead of restored.
class BackupService {
  const BackupService._();

  static const String format = 'omni_plan_backup';
  static const int version = 1;
  static const int maxBytes = 50 * 1024 * 1024;
  static const String extension = 'omniplan';

  static const Map<String, String> kinds = {
    'p:': 'projects',
    's:': 'sections',
    't:': 'tasks',
    'm:': 'milestones',
    'g:': 'goals',
    'ct:': 'templates',
    'a:': 'history',
    'n:': 'notifications',
    'meta:': 'settings',
  };

  static String _kindOf(String key) {
    for (final e in kinds.entries) {
      if (key.startsWith(e.key)) return e.value;
    }
    return '';
  }

  /// 64-bit FNV-1a over the canonical JSON of the entries.
  static String checksum(Map<String, Object?> entries) {
    final keys = entries.keys.toList()..sort();
    final canonical = jsonEncode([for (final k in keys) [k, entries[k]]]);
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final b in utf8.encode(canonical)) {
      hash ^= b;
      hash *= prime; // wraps at 64 bits on the Dart VM
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  static String build(PlanStore store, {DateTime? now}) {
    final entries = store.snapshot();
    final counts = <String, int>{};
    for (final k in entries.keys) {
      final kind = _kindOf(k);
      if (kind.isNotEmpty) counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return jsonEncode({
      'format': format,
      'version': version,
      'app': AppInfo.name,
      'appVersion': AppInfo.version,
      'createdAt': (now ?? DateTime.now()).toIso8601String(),
      'counts': counts,
      'checksum': checksum(entries),
      'entries': entries,
    });
  }

  static Future<File> write(String json, Directory dir, {DateTime? now}) async {
    final stamp = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    var name = 'Omni Plan backup $stamp.$extension';
    var n = 2;
    while (await File('${dir.path}/$name').exists()) {
      name = 'Omni Plan backup $stamp ($n).$extension';
      n++;
    }
    final file = File('${dir.path}/$name');
    await file.writeAsString(json, flush: true);
    // Read it back: a backup is only reported once it is complete and valid.
    final written = await file.readAsString();
    if (written.length != json.length || inspectRaw(written) == null) {
      throw const BackupException('The backup file was not written completely.');
    }
    return file;
  }

  /// The decoded file when its envelope and checksum are right, else null.
  static Map<String, Object?>? inspectRaw(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['format'] != format) return null;
      final entries = j['entries'];
      if (entries is! Map) return null;
      final map = {for (final e in entries.entries) '${e.key}': e.value as Object?};
      return j['checksum'] == checksum(map) ? map : null;
    } catch (_) {
      return null;
    }
  }

  static BackupPreview inspect(String text, PlanStore store) {
    if (text.length > maxBytes) {
      throw const BackupException('This file is too large to be a backup.');
    }
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const BackupException('This is not an Omni Plan backup. The file could not be read.');
    }
    if (j is! Map || j['format'] != format) {
      throw const BackupException('This is not an Omni Plan backup.');
    }
    final v = j['version'];
    if (v is! int || v < 1) throw const BackupException('This backup has no valid version.');
    if (v > version) {
      throw const BackupException('This backup was made by a newer version of Omni Plan. Update the app to restore it.');
    }
    final raw = j['entries'];
    if (raw is! Map) throw const BackupException('This backup holds no plans.');
    final entries = {for (final e in raw.entries) '${e.key}': e.value as Object?};
    if (j['checksum'] != checksum(entries)) {
      throw const BackupException('This backup file is damaged or was changed after it was made, so it cannot be restored safely.');
    }

    // Parse every entry with the real models; unreadable ones are left out.
    final valid = <String, Object?>{};
    var skipped = 0;
    final projects = <String>{}, sections = <String, String>{}, tasks = <String>{}, milestones = <String, String>{}, goals = <String>{};
    for (final e in entries.entries) {
      final k = e.key;
      final value = e.value;
      try {
        Map<String, dynamic> m() => Map<String, dynamic>.from(value as Map);
        if (k.startsWith('p:')) {
          projects.add(Project.fromJson(m()).id);
        } else if (k.startsWith('s:')) {
          final s = ProjectSection.fromJson(m());
          sections[s.id] = s.projectId;
        } else if (k.startsWith('t:')) {
          tasks.add(PlanTask.fromJson(m()).id);
        } else if (k.startsWith('m:')) {
          final ms = Milestone.fromJson(m());
          milestones[ms.id] = ms.projectId;
        } else if (k.startsWith('g:')) {
          goals.add(Goal.fromJson(m()).id);
        } else if (k.startsWith('ct:')) {
          PlanTemplate.fromJson(m());
        } else if (k.startsWith('a:')) {
          ActivityEntry.fromJson(m());
        } else if (k.startsWith('n:')) {
          PlanNotice.fromJson(m());
        } else if (k == 'meta:prefs') {
          PlanPreferences.fromJson(m());
        } else if (k.startsWith('meta:')) {
          if (value is! List) throw const FormatException('list expected');
        } else {
          throw const FormatException('unknown entry');
        }
        valid[k] = value;
      } catch (_) {
        skipped++;
      }
    }

    // Repair references to records the backup does not contain.
    var repaired = 0;
    for (final k in valid.keys.toList()) {
      final value = valid[k];
      if (value is! Map) continue;
      final m = Map<String, dynamic>.from(value);
      var changed = false;
      void drop(String field, bool Function(Object?) ok) {
        final ref = m[field];
        if (ref != null && ref != '' && !ok(ref)) {
          m[field] = null;
          changed = true;
          repaired++;
        }
      }

      if (k.startsWith('t:')) {
        drop('projectId', projects.contains);
        drop('parentId', tasks.contains);
        drop('sectionId', (id) => sections[id] == m['projectId']);
        drop('milestoneId', (id) => milestones[id] == m['projectId']);
        final deps = (m['dependsOn'] as List?) ?? const [];
        final kept = [for (final d in deps) if (tasks.contains(d)) d];
        if (kept.length != deps.length) {
          m['dependsOn'] = kept;
          changed = true;
          repaired += deps.length - kept.length;
        }
      } else if (k.startsWith('p:')) {
        drop('goalId', goals.contains);
      } else if (k.startsWith('s:') || k.startsWith('m:')) {
        if (!projects.contains(m['projectId'])) {
          // A section or milestone without its project cannot be restored.
          valid.remove(k);
          skipped++;
          continue;
        }
      }
      if (changed) valid[k] = m;
    }

    final existing = store.snapshot().keys.toSet();
    final counts = <String, int>{};
    for (final k in valid.keys) {
      final kind = _kindOf(k);
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return BackupPreview(
      createdAt: DateTime.tryParse('${j['createdAt']}'),
      appVersion: j['appVersion'] as String?,
      entries: valid,
      counts: counts,
      skipped: skipped,
      repairedLinks: repaired,
      overlapping: valid.keys.where((k) => !k.startsWith('meta:') && existing.contains(k)).length,
    );
  }

  /// Replaces everything on this device with the backup (all or nothing).
  static Future<void> restoreReplacing(BackupPreview preview, PlanStore store) =>
      store.replaceAll(preview.entries);

  /// Adds what is not on this device yet; existing records are kept as they
  /// are. Returns the number of records added.
  static Future<int> restoreMerging(BackupPreview preview, PlanStore store) =>
      store.mergeIn(preview.entries);
}
