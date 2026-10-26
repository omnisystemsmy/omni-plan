import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_plan/app/shell/home_shell.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:provider/provider.dart';

/// Opens the plans of the signed-in account ([scope] = its user id) and then
/// shows the shell. Switching accounts swaps the data underneath; nothing of
/// one account is ever shown to another.
///
/// While it is open, every change to the plans re-schedules the device
/// reminders and refreshes the notification list.
class PlanWorkspace extends StatefulWidget {
  final String scope;

  const PlanWorkspace({super.key, required this.scope});

  @override
  State<PlanWorkspace> createState() => _PlanWorkspaceState();
}

class _PlanWorkspaceState extends State<PlanWorkspace> with WidgetsBindingObserver {
  late final PlanStore _store;
  Object? _error;
  bool _ready = false;
  Timer? _noticeDebounce;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _store = context.read<PlanStore>();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void didUpdateWidget(covariant PlanWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      setState(() => _ready = false);
      _open();
    }
  }

  Future<void> _open() async {
    try {
      await _store.open(widget.scope);
      _store.removeListener(_onChanged);
      _store.addListener(_onChanged);
      await _store.refreshNotices();
      ReminderService.instance.scheduleSync(_store);
      _ticker?.cancel();
      // Due-today and overdue entries follow the clock, not only edits.
      _ticker = Timer.periodic(const Duration(minutes: 15), (_) => _store.refreshNotices());
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onChanged() {
    if (!_store.isOpen) return;
    ReminderService.instance.scheduleSync(_store);
    _noticeDebounce?.cancel();
    _noticeDebounce = Timer(const Duration(seconds: 1), () => _store.refreshNotices());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _store.isOpen) {
      _store.refreshNotices();
      ReminderService.instance.scheduleSync(_store);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onChanged);
    _noticeDebounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: OmniEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Your plans could not be opened',
          message: '$_error',
          actionLabel: 'Try again',
          onAction: () {
            setState(() => _error = null);
            _open();
          },
        ),
      );
    }
    if (!_ready) return const Scaffold(body: SizedBox.shrink());
    return const HomeShell();
  }
}
