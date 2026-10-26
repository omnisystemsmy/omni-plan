import 'package:flutter/foundation.dart';
import 'package:omni_plan/domain/rules.dart';

/// Which tab is showing, so any screen (Home cards, empty states) can switch
/// tabs, and which task list to show when it asks for one.
class ShellController extends ChangeNotifier {
  static const int home = 0;
  static const int tasks = 1;
  static const int projects = 2;
  static const int profile = 3;

  int _tab = home;
  TaskQuick? _taskFilter;

  int get tab => _tab;

  /// A filter for My Tasks to apply once; read with [takeTaskFilter].
  TaskQuick? get pendingTaskFilter => _taskFilter;

  void goTo(int tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Opens My Tasks on [filter].
  void showTasks(TaskQuick filter) {
    _taskFilter = filter;
    _tab = tasks;
    notifyListeners();
  }

  TaskQuick? takeTaskFilter() {
    final f = _taskFilter;
    _taskFilter = null;
    return f;
  }
}
