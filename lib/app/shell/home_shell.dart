import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/app/shell/bottom_nav.dart';
import 'package:omni_plan/app/shell/shell_controller.dart';
import 'package:omni_plan/core/branding/plan_brand.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/create/create_sheet.dart';
import 'package:omni_plan/features/home/home_tab.dart';
import 'package:omni_plan/features/notifications/notifications_page.dart';
import 'package:omni_plan/features/pro/pro_page.dart';
import 'package:omni_plan/features/profile/profile_tab.dart';
import 'package:omni_plan/features/projects/projects_tab.dart';
import 'package:omni_plan/features/tasks/tasks_tab.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:provider/provider.dart';

/// The four-tab shell: Home, My Tasks, Projects, Profile, with the New
/// button docked in the middle of the bar. Same structure as the Omni Docs
/// shell (swipeable pages, 64 px app bar, notched bottom bar).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pages = PageController();
  late final ShellController _shell;
  StreamSubscription<String>? _reminderTaps;
  int _index = 0;

  /// While a tap on the bar animates to a page, ignore the pages it passes.
  int? _tapTarget;

  @override
  void initState() {
    super.initState();
    _shell = context.read<ShellController>();
    _shell.addListener(_onShellChanged);
    // A tapped reminder opens its task.
    _reminderTaps = ReminderService.instance.taps.listen((taskId) {
      if (!mounted) return;
      final task = context.read<PlanStore>().task(taskId);
      if (task != null) openTask(context, task);
    });
  }

  @override
  void dispose() {
    _reminderTaps?.cancel();
    _shell.removeListener(_onShellChanged);
    _pages.dispose();
    super.dispose();
  }

  void _onShellChanged() {
    final target = _shell.tab;
    if (target == _index) return;
    setState(() => _index = target);
    _tapTarget = target;
    _pages
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _tapTarget = null);
  }

  void _onPageChanged(int index) {
    final target = _tapTarget;
    if (target != null && index != target) return;
    if (index != _index) {
      HapticFeedback.selectionClick();
      setState(() => _index = index);
      _shell.goTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = context.select<PlanStore, int>((s) => s.unreadNotices);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        titleSpacing: 0,
        leadingWidth: 84,
        leading: _TopBarProPill(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProPage()),
          ),
        ),
        title: const PlanBrandAppBar(),
        actions: [
          IconButton(
            tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            ),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              backgroundColor: theme.colorScheme.error,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView(
        controller: _pages,
        onPageChanged: _onPageChanged,
        children: const [
          _KeepAlive(child: HomeTab()),
          _KeepAlive(child: TasksTab()),
          _KeepAlive(child: ProjectsTab()),
          _KeepAlive(child: ProfileTab()),
        ],
      ),
      bottomNavigationBar: BottomNav(currentIndex: _index, onTap: _shell.goTo),
      floatingActionButton: const _NewFab(),
      floatingActionButtonLocation: const _RaisedCenterDocked(),
    );
  }
}

/// Same top-left header treatment as Omni Docs and Omni Tools.
class _TopBarProPill extends StatelessWidget {
  final VoidCallback onTap;

  const _TopBarProPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: OmniDesignTokens.pageInset),
        child: OmniPressScale(
          scale: 0.92,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: const OmniProBadge(large: true),
          ),
        ),
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Docks the button in the bar's notch, a little above the bar's edge.
class _RaisedCenterDocked extends FloatingActionButtonLocation {
  const _RaisedCenterDocked();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.centerDocked.getOffset(geometry);
    return Offset(base.dx, base.dy - 10);
  }
}

/// The centre button: the Omni Docs flat teal circle, opening "Create new".
class _NewFab extends StatelessWidget {
  const _NewFab();

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Create new',
      child: Tooltip(
        message: 'Create new',
        child: OmniPressScale(
          scale: 0.92,
          child: Material(
            color: OmniDesignTokens.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.mediumImpact();
                showCreateSheet(context);
              },
              child: const SizedBox(
                width: _size,
                height: _size,
                child: Center(
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
