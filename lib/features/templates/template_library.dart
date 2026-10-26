import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_models.dart';

/// Read-only access to the built-in catalogue, plus the person's own saved
/// templates when a caller passes them in.
class TemplateLibrary {
  const TemplateLibrary._();

  static final Map<String, PlanTemplate> _byId = {
    for (final t in builtInTemplates) t.id: t,
  };

  static List<PlanTemplate> get builtIn => builtInTemplates;
  static int get templateCount => builtInTemplates.length;
  static int get categoryCount => templateCategories.length;

  static PlanTemplate? byId(String id, [List<PlanTemplate> custom = const []]) {
    final found = _byId[id];
    if (found != null) return found;
    for (final t in custom) {
      if (t.id == id) return t;
    }
    return null;
  }

  static List<PlanTemplate> inCategory(String categoryId) => [
    for (final t in builtInTemplates)
      if (t.categoryId == categoryId) t,
  ];

  static List<PlanTemplate> get featured => [
    for (final id in featuredTemplateIds)
      if (_byId[id] != null) _byId[id]!,
  ];

  /// Matches the name, description, category, section names and keywords.
  /// Name matches come first.
  static List<PlanTemplate> search(
    String query, [
    List<PlanTemplate> custom = const [],
  ]) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    final scored = <(int, PlanTemplate)>[];
    for (final t in [...custom, ...builtInTemplates]) {
      final name = t.name.toLowerCase();
      final hay = [
        name,
        t.description,
        categoryById(t.categoryId).name,
        ...t.keywords,
        for (final s in t.sections) s.name,
      ].join(' ').toLowerCase();
      if (!words.every(hay.contains)) continue;
      final score = name.startsWith(q)
          ? 0
          : name.contains(q)
          ? 1
          : 2;
      scored.add((score, t));
    }
    scored.sort((a, b) {
      final s = a.$1.compareTo(b.$1);
      return s != 0 ? s : a.$2.name.compareTo(b.$2.name);
    });
    return [for (final s in scored) s.$2];
  }
}
