import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_glow_border.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_tool_tile.dart';
import 'package:omni_plan/core/widgets/omni_view_toggle.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:omni_plan/features/templates/template_models.dart';
import 'package:omni_plan/features/templates/template_sheets.dart';
import 'package:provider/provider.dart';

/// The template library, laid out like the Omni Docs Templates tab: title
/// with counts, glowing search bar, then sections as icon tiles.
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final searching = _query.trim().isNotEmpty;
    final custom = store.customTemplates;
    final recent = [
      for (final id in store.recentTemplates)
        if (TemplateLibrary.byId(id, custom) != null) TemplateLibrary.byId(id, custom)!,
    ];
    final favourites = [
      for (final id in store.favoriteTemplates)
        if (TemplateLibrary.byId(id, custom) != null) TemplateLibrary.byId(id, custom)!,
    ];
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: omniListAppBar(context, 'Templates'),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: 24 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: OmniPageTitle(
              title: 'Templates',
              subtitle: '${TemplateLibrary.templateCount} templates across ${TemplateLibrary.categoryCount} categories',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 8),
            child: OmniGlowBorder(
              child: OmniSearchField(
                controller: _search,
                hintText: 'Search templates...',
                onChanged: (v) => setState(() => _query = v),
                onClear: _query.isEmpty
                    ? null
                    : () {
                        _search.clear();
                        setState(() => _query = '');
                      },
              ),
            ),
          ),
          if (searching)
            ..._results(TemplateLibrary.search(_query, custom))
          else ...[
            if (favourites.isNotEmpty) ...[
              _header('Favourites'),
              for (final t in favourites) TemplateRow(template: t),
            ],
            if (recent.isNotEmpty) ...[
              _header('Recently used'),
              for (final t in recent.take(4)) TemplateRow(template: t),
            ],
            _header('Featured'),
            for (final t in TemplateLibrary.featured) TemplateRow(template: t),
            if (custom.isNotEmpty) ...[
              _header('My templates'),
              for (final t in custom) TemplateRow(template: t),
            ],
            const SizedBox(height: 8),
            _header('Categories'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset - 4),
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 0.72,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final c in templateCategories)
                    OmniToolTile(
                      label: c.name,
                      icon: c.icon,
                      color: c.color,
                      maxLines: 3,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TemplateCategoryPage(category: c)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 6),
    child: OmniSectionHeader(title: t),
  );

  List<Widget> _results(List<PlanTemplate> results) {
    if (results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 48),
          child: OmniEmptyState(icon: Icons.search_off_rounded, title: 'No templates found', message: 'Try a different keyword'),
        ),
      ];
    }
    return [
      _header('${results.length} ${results.length == 1 ? 'template' : 'templates'}'),
      for (final t in results) TemplateRow(template: t),
    ];
  }
}

/// One template in a list: icon tile, name, category and size.
class TemplateRow extends StatelessWidget {
  final PlanTemplate template;
  const TemplateRow({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final fav = store.isFavoriteTemplate(template.id);
    return OmniMenuRow(
      icon: template.icon,
      iconColor: template.color,
      useTile: true,
      title: template.name,
      subtitle:
          '${categoryById(template.categoryId).name} · ${template.topLevelTaskCount} tasks${template.milestones.isEmpty ? '' : ' · ${template.milestones.length} milestones'}',
      onTap: () => showTemplateDetailSheet(context, template),
      trailing: IconButton(
        tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
        onPressed: () => store.toggleFavoriteTemplate(template.id),
        icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
            color: fav ? Theme.of(context).colorScheme.primary : null),
      ),
    );
  }
}

/// A category's templates, with search and the grid / list switch.
class TemplateCategoryPage extends StatefulWidget {
  final TemplateCategory category;
  const TemplateCategoryPage({super.key, required this.category});

  @override
  State<TemplateCategoryPage> createState() => _TemplateCategoryPageState();
}

class _TemplateCategoryPageState extends State<TemplateCategoryPage> {
  String _query = '';
  bool _grid = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final q = _query.trim().toLowerCase();
    final all = TemplateLibrary.inCategory(c.id);
    final list = [
      for (final t in all)
        if (q.isEmpty || '${t.name} ${t.description} ${t.keywords.join(' ')}'.toLowerCase().contains(q)) t,
    ];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: omniListAppBar(context, c.name),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: OmniPageTitle(
              title: c.name,
              subtitle: '${all.length} templates',
              trailing: OmniViewToggleButton(isGrid: _grid, onPressed: () => setState(() => _grid = !_grid)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 8),
            child: OmniGlowBorder(
              child: OmniSearchField(
                hintText: 'Search ${c.name} templates...',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: OmniEmptyState(icon: Icons.search_off_rounded, title: 'No templates found', message: 'Try a different keyword'),
            )
          else if (_grid)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset - 4, 8, OmniDesignTokens.pageInset - 4, 0),
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 0.7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final t in list)
                    OmniToolTile(
                      label: t.name,
                      icon: t.icon,
                      color: t.color,
                      maxLines: 3,
                      onTap: () => showTemplateDetailSheet(context, t),
                    ),
                ],
              ),
            )
          else
            for (final t in list) TemplateRow(template: t),
        ],
      ),
    );
  }
}
