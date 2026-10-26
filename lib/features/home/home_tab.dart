import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/app/shell/shell_controller.dart';
import 'package:omni_plan/core/backend/supabase_config.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_banner_carousel.dart';
import 'package:omni_plan/core/widgets/omni_glow_border.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_tool_tile.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/home/home_banners.dart';
import 'package:omni_plan/features/search/search_results.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Home, laid out like the Omni Docs home: greeting, glowing search bar,
/// banner carousel, then today's overview, today's tasks, projects,
/// milestones, quick actions and recent activity. Every number comes from
/// the stored plans.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// First word of the Omni Account display name, or of the email.
  String? _firstName() {
    if (!SupabaseConfig.initialized) return null;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    final meta = user.userMetadata?['display_name'];
    final source = meta is String && meta.trim().isNotEmpty
        ? meta.trim()
        : (user.email ?? '').split('@').first;
    final first = source.split(RegExp(r'\s+')).first;
    if (first.isEmpty) return null;
    return first[0].toUpperCase() + first.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final searching = _query.trim().isNotEmpty;
    final name = _firstName();

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: 96 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OmniReveal(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                OmniDesignTokens.pageInset,
                8,
                OmniDesignTokens.pageInset,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name == null ? _greeting() : '${_greeting()}, $name',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'What would you like to plan today?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OmniGlowBorder(
                    child: OmniSearchField(
                      controller: _search,
                      hintText: 'Search tasks, projects and templates...',
                      onChanged: (v) => setState(() => _query = v),
                      onClear: _query.isEmpty
                          ? null
                          : () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SearchResultsList(query: _query),
            )
          else ...[
            const SizedBox(height: 16),
            OmniReveal(
              index: 1,
              child: GestureDetector(
                onTap: () => openTemplates(context),
                child: OmniBannerCarousel(slides: homeBannerSlides()),
              ),
            ),
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniReveal(index: 2, child: _TodayOverview()),
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniReveal(index: 3, child: _TodayTasks()),
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniReveal(index: 4, child: _ActiveProjects()),
            const _UpcomingMilestones(),
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniReveal(index: 5, child: _QuickActions()),
            const _RecentActivity(),
          ],
        ],
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  final Widget child;
  const _Pad({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
    child: child,
  );
}

class _TodayOverview extends StatelessWidget {
  const _TodayOverview();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final shell = context.read<ShellController>();
    final now = DateTime.now();
    final open = store.tasks.where((t) => !t.isDone);
    final dueToday = open.where((t) => t.isDueOn(now) && !t.isOverdue(now)).length;
    final overdue = open.where((t) => t.isOverdue(now)).length;
    final upcoming = store.filterTasks(const TaskFilter(quick: TaskQuick.upcoming, showSubtasks: true)).length;
    final doneToday = store.tasks
        .where((t) => t.isDone && t.completedAt != null && dateOnly(t.completedAt!) == dateOnly(now))
        .length;

    return _Pad(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OmniSectionHeader(title: "Today's overview"),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: [
              MetricCard(
                label: 'Due today',
                value: dueToday,
                icon: Icons.today_rounded,
                color: OmniDesignTokens.primary,
                onTap: () => shell.showTasks(TaskQuick.today),
              ),
              MetricCard(
                label: 'Overdue',
                value: overdue,
                icon: Icons.warning_amber_rounded,
                color: OmniDesignTokens.categoryLinks,
                onTap: () => shell.showTasks(TaskQuick.overdue),
              ),
              MetricCard(
                label: 'Next 7 days',
                value: upcoming,
                icon: Icons.upcoming_rounded,
                color: OmniDesignTokens.categoryConverters,
                onTap: () => shell.showTasks(TaskQuick.upcoming),
              ),
              MetricCard(
                label: 'Completed today',
                value: doneToday,
                icon: Icons.task_alt_rounded,
                color: OmniDesignTokens.categoryCalculator,
                onTap: () => shell.showTasks(TaskQuick.completed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayTasks extends StatelessWidget {
  const _TodayTasks();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final shell = context.read<ShellController>();
    // Overdue first, then today's, as in My Tasks > Today.
    final today = store.filterTasks(const TaskFilter(quick: TaskQuick.today));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pad(
          child: OmniSectionHeader(
            title: "Today's tasks",
            actionLabel: today.isEmpty ? null : 'View all',
            onAction: () => shell.showTasks(TaskQuick.today),
          ),
        ),
        const SizedBox(height: 6),
        if (today.isEmpty)
          _Pad(
            child: OmniInlineEmpty(
              icon: Icons.wb_sunny_outlined,
              title: 'Nothing due today',
              message: 'Add a task, or plan the week ahead',
              onTap: () => newTask(context, dueDate: DateTime.now()),
            ),
          )
        else
          for (final t in today.take(5)) TaskRow(task: t, onTap: () => openTask(context, t)),
      ],
    );
  }
}

class _ActiveProjects extends StatelessWidget {
  const _ActiveProjects();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final shell = context.read<ShellController>();
    final active = store.activeProjects.take(3).toList();
    return _Pad(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OmniSectionHeader(
            title: 'My projects',
            actionLabel: active.isEmpty ? null : 'See all',
            onAction: () => shell.goTo(ShellController.projects),
          ),
          const SizedBox(height: 12),
          if (active.isEmpty)
            OmniInlineEmpty(
              icon: Icons.create_new_folder_outlined,
              title: 'No active projects',
              message: 'Start one, or use a ready-made template',
              accent: OmniDesignTokens.categoryConverters,
              onTap: () => openTemplates(context),
            )
          else
            for (final p in active) ...[
              ProjectCard(project: p, onTap: () => openProject(context, p)),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _UpcomingMilestones extends StatelessWidget {
  const _UpcomingMilestones();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final list = store.upcomingMilestones(days: 30).take(4).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: OmniDesignTokens.sectionGap - 10),
        const _Pad(child: OmniSectionHeader(title: 'Upcoming milestones')),
        const SizedBox(height: 4),
        for (final m in list) MilestoneRow(milestone: m, onTap: () => openMilestone(context, m)),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final shell = context.read<ShellController>();
    final tiles = <Widget>[
      OmniToolTile(label: 'New Task', icon: Icons.add_task_rounded, color: OmniDesignTokens.primary, onTap: () => newTask(context)),
      OmniToolTile(label: 'New Project', icon: Icons.create_new_folder_rounded, color: OmniDesignTokens.categoryConverters, onTap: () => newProject(context)),
      OmniToolTile(label: 'Calendar', icon: Icons.calendar_month_rounded, color: OmniDesignTokens.categoryLinks, onTap: () => openCalendar(context)),
      OmniToolTile(label: 'Templates', icon: Icons.dashboard_customize_rounded, color: OmniDesignTokens.categoryBusiness, onTap: () => openTemplates(context)),
      OmniToolTile(label: 'Goals', icon: Icons.flag_rounded, color: OmniDesignTokens.categoryNfc, onTap: () => openGoals(context)),
      OmniToolTile(label: 'Reports', icon: Icons.insights_rounded, color: OmniDesignTokens.categoryCalculator, onTap: () => openReports(context)),
      OmniToolTile(label: 'All Tasks', icon: Icons.checklist_rounded, color: OmniDesignTokens.categoryDeveloper, onTap: () => shell.showTasks(TaskQuick.all)),
      OmniToolTile(label: 'Overdue', icon: Icons.warning_amber_rounded, color: OmniDesignTokens.categoryText, onTap: () => shell.showTasks(TaskQuick.overdue)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pad(child: OmniSectionHeader(title: 'Quick actions')),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset - 4),
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 0.78,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: tiles,
          ),
        ),
      ],
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final items = store.recentItems(limit: 4);
    if (items.isEmpty) return const SizedBox.shrink();
    final fmt = PlanFormat(store.prefs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: OmniDesignTokens.sectionGap - 8),
        const _Pad(child: OmniSectionHeader(title: 'Recently opened')),
        const SizedBox(height: 4),
        for (final item in items)
          if (item is Project)
            OmniMenuRow(
              icon: item.iconData,
              iconColor: item.colorValue,
              useTile: true,
              title: item.name,
              subtitle: 'Project · ${_ago(item.lastOpenedAt)}',
              onTap: () => openProject(context, item),
            )
          else if (item is PlanTask)
            OmniMenuRow(
              icon: item.isDone ? Icons.task_alt_rounded : Icons.radio_button_unchecked_rounded,
              iconColor: item.isDone ? OmniDesignTokens.success : OmniDesignTokens.primary,
              useTile: true,
              title: item.title,
              subtitle: item.dueDate == null
                  ? 'Task · ${_ago(item.lastOpenedAt)}'
                  : 'Task · due ${fmt.due(item)}',
              onTap: () => openTask(context, item),
            ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    return '${d.inDays} days ago';
  }
}
