import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_glow_border.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_view_toggle.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

/// Every project, with status filters, search, sorting and a grid or list
/// view (the choice is remembered).
class ProjectsTab extends StatefulWidget {
  const ProjectsTab({super.key});

  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<ProjectsTab> {
  final _search = TextEditingController();
  String _query = '';
  ProjectFilter _filter = ProjectFilter.all;
  ProjectSort _sort = ProjectSort.updated;
  bool _overdueOnly = false;
  bool _noDateOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openSort() async {
    final result = await showModalBottomSheet<(ProjectSort, bool, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        var sort = _sort, overdue = _overdueOnly, noDate = _noDateOnly;
        return StatefulBuilder(
          builder: (context, set) => OmniBottomSheetScaffold(
            title: 'Sort and filter',
            child: Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<ProjectSort>(
                      initialValue: sort,
                      decoration: const InputDecoration(labelText: 'Sort by'),
                      items: [for (final s in ProjectSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
                      onChanged: (v) => set(() => sort = v ?? sort),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Only projects with overdue tasks'),
                      value: overdue,
                      onChanged: (v) => set(() => overdue = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Only projects without a target date'),
                      value: noDate,
                      onChanged: (v) => set(() => noDate = v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheet, (sort, overdue, noDate)),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        _sort = result.$1;
        _overdueOnly = result.$2;
        _noDateOnly = result.$3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final grid = store.prefs.projectsAsGrid;
    final q = _query.trim().toLowerCase();
    final list = [
      for (final p in store.allProjects)
        if (_filter.matches(p) &&
            (q.isEmpty || '${p.name} ${p.description} ${p.category}'.toLowerCase().contains(q)) &&
            (!_overdueOnly || store.overdueCountOf(p.id) > 0) &&
            (!_noDateOnly || p.dueDate == null))
          p,
    ]..sort((a, b) {
      // Favourites first, then the chosen order.
      final f = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
      return f != 0 ? f : compareProjects(a, b, _sort);
    });
    final count = store.projects.length;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final advanced = _sort != ProjectSort.updated || _overdueOnly || _noDateOnly;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 0),
            child: OmniPageTitle(
              title: 'Projects',
              subtitle: count == 1 ? '1 project' : '$count projects',
              trailing: FilledButton.tonalIcon(
                onPressed: () => newProject(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New project'),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 12),
            child: OmniGlowBorder(
              child: OmniSearchField(
                controller: _search,
                hintText: 'Search projects...',
                onFilter: _openSort,
                hasActiveFilter: advanced,
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
        ),
        SliverToBoxAdapter(
          child: OmniFilterChips<ProjectFilter>(
            items: [for (final f in ProjectFilter.values) (value: f, label: f.label, icon: null)],
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset - 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${list.length} shown · ${_sort.label}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                OmniViewToggleButton(
                  isGrid: grid,
                  onPressed: () => store.updatePrefs(store.prefs.copyWith(projectsAsGrid: !grid)),
                ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: OmniEmptyState(
              icon: _filter == ProjectFilter.archived ? Icons.archive_outlined : Icons.folder_open_rounded,
              title: count == 0
                  ? 'No projects yet'
                  : _filter == ProjectFilter.archived
                  ? 'Nothing archived'
                  : 'No matching projects',
              message: count == 0
                  ? 'Create a project, or start from a template with the tasks already laid out.'
                  : 'Try another filter or search.',
              actionLabel: 'New project',
              onAction: () => newProject(context),
              secondaryLabel: 'Browse templates',
              onSecondary: () => openTemplates(context),
            ),
          )
        else if (grid)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 96 + bottom),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProjectCard(project: list[i], grid: true, onTap: () => openProject(context, list[i])),
                childCount: list.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 96 + bottom),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => ProjectCard(project: list[i], onTap: () => openProject(context, list[i])),
            ),
          ),
      ],
    );
  }
}
