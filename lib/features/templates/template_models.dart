import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/domain/models.dart';

/// A template section of the library (Personal, Academic...).
class TemplateCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  /// The project category a plan made from it gets.
  final String projectCategory;

  const TemplateCategory(
    this.id,
    this.name,
    this.icon,
    this.color, {
    String? projectCategory,
  }) : projectCategory = projectCategory ?? name;
}

class TemplateTask {
  final String title;

  /// Days after the plan's start date the task is due; null = no date.
  final int? dayOffset;
  final Priority priority;
  final List<String> subtasks;

  const TemplateTask(
    this.title, {
    this.dayOffset,
    this.priority = Priority.none,
    this.subtasks = const [],
  });

  /// Compact form used by the catalogue:
  /// `"Title @14 !high > First subtask; Second subtask"`.
  /// `@n` is the due day after the start, `!level` the priority, and the text
  /// after `>` the subtasks.
  factory TemplateTask.parse(String spec) {
    var head = spec;
    var subs = <String>[];
    final split = spec.indexOf(' > ');
    if (split >= 0) {
      head = spec.substring(0, split);
      subs = spec
          .substring(split + 3)
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    int? offset;
    var priority = Priority.none;
    final words = <String>[];
    for (final w in head.split(' ')) {
      if (w.startsWith('@') && int.tryParse(w.substring(1)) != null) {
        offset = int.parse(w.substring(1));
      } else if (w.startsWith('!') && w.length > 1) {
        priority = Priority.parse(w.substring(1), Priority.none);
      } else if (w.isNotEmpty) {
        words.add(w);
      }
    }
    return TemplateTask(
      words.join(' '),
      dayOffset: offset,
      priority: priority,
      subtasks: subs,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'dayOffset': dayOffset,
    'priority': priority.name,
    'subtasks': subtasks,
  };

  factory TemplateTask.fromJson(Map<String, dynamic> j) => TemplateTask(
    (j['title'] as String?) ?? 'Task',
    dayOffset: j['dayOffset'] is int ? j['dayOffset'] as int : null,
    priority: Priority.parse(j['priority']),
    subtasks: [
      for (final s in (j['subtasks'] as List? ?? const []))
        if (s is String && s.trim().isNotEmpty) s,
    ],
  );
}

class TemplateSection {
  final String name;
  final List<TemplateTask> tasks;

  const TemplateSection(this.name, this.tasks);

  Map<String, dynamic> toJson() => {
    'name': name,
    'tasks': [for (final t in tasks) t.toJson()],
  };

  factory TemplateSection.fromJson(Map<String, dynamic> j) => TemplateSection(
    (j['name'] as String?) ?? 'Section',
    [
      for (final t in (j['tasks'] as List? ?? const []))
        if (t is Map) TemplateTask.fromJson(Map<String, dynamic>.from(t)),
    ],
  );
}

class TemplateMilestone {
  final String title;
  final int dayOffset;

  const TemplateMilestone(this.title, this.dayOffset);

  Map<String, dynamic> toJson() => {'title': title, 'dayOffset': dayOffset};

  factory TemplateMilestone.fromJson(Map<String, dynamic> j) =>
      TemplateMilestone(
        (j['title'] as String?) ?? 'Milestone',
        j['dayOffset'] is int ? j['dayOffset'] as int : 0,
      );
}

/// A ready-made plan. Using it creates real, editable records; the template
/// itself never changes afterwards, and a plan keeps no link to later
/// versions of it (only [id] is remembered, for "recently used").
class PlanTemplate {
  final String id;
  final String name;
  final String categoryId;
  final String description;
  final IconData icon;
  final Color color;
  final List<TemplateSection> sections;
  final List<TemplateMilestone> milestones;

  /// The project icon key the plan gets.
  final String projectIcon;

  /// Suggested length in days, used to suggest a target date.
  final int? durationDays;
  final int version;

  /// Saved by the person from one of their projects.
  final bool custom;
  final List<String> keywords;

  const PlanTemplate({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.description,
    required this.icon,
    required this.color,
    required this.sections,
    this.milestones = const [],
    this.projectIcon = 'folder',
    this.durationDays,
    this.version = 1,
    this.custom = false,
    this.keywords = const [],
  });

  int get taskCount =>
      sections.fold(0, (n, s) => n + s.tasks.length + s.tasks.fold(0, (m, t) => m + t.subtasks.length));

  int get topLevelTaskCount => sections.fold(0, (n, s) => n + s.tasks.length);

  bool get usesDates =>
      milestones.isNotEmpty ||
      sections.any((s) => s.tasks.any((t) => t.dayOffset != null));

  /// The longest offset in the template, when it has dates.
  int? get span {
    int? max;
    for (final s in sections) {
      for (final t in s.tasks) {
        final o = t.dayOffset;
        if (o != null && (max == null || o > max)) max = o;
      }
    }
    for (final m in milestones) {
      if (max == null || m.dayOffset > max) max = m.dayOffset;
    }
    return durationDays ?? max;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categoryId': categoryId,
    'description': description,
    'projectIcon': projectIcon,
    'color': color.toARGB32(),
    'sections': [for (final s in sections) s.toJson()],
    'milestones': [for (final m in milestones) m.toJson()],
    'durationDays': durationDays,
    'version': version,
  };

  factory PlanTemplate.fromJson(Map<String, dynamic> j) {
    final iconKey = (j['projectIcon'] as String?) ?? 'folder';
    return PlanTemplate(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'My template',
      categoryId: (j['categoryId'] as String?) ?? 'custom',
      description: (j['description'] as String?) ?? '',
      icon: planIcon(iconKey),
      color: Color((j['color'] as int?) ?? OmniDesignTokens.primary.toARGB32()),
      projectIcon: iconKey,
      sections: [
        for (final s in (j['sections'] as List? ?? const []))
          if (s is Map) TemplateSection.fromJson(Map<String, dynamic>.from(s)),
      ],
      milestones: [
        for (final m in (j['milestones'] as List? ?? const []))
          if (m is Map) TemplateMilestone.fromJson(Map<String, dynamic>.from(m)),
      ],
      durationDays: j['durationDays'] is int ? j['durationDays'] as int : null,
      version: (j['version'] as int?) ?? 1,
      custom: true,
    );
  }
}
