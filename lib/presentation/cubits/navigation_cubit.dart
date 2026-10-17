import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/tactile_decorations.dart';

/// The four primary tabs, in navigation-bar order.
enum AppTab { home, search, library, settings }

extension AppTabLabel on AppTab {
  /// `01 // HOME` — the Swiss ordinal the tab bar and headers share.
  String get ordinal => switch (this) {
    AppTab.home => '01',
    AppTab.search => '02',
    AppTab.library => '03',
    AppTab.settings => '04',
  };

  String get label => switch (this) {
    AppTab.home => 'HOME',
    AppTab.search => 'SEARCH',
    AppTab.library => 'LIBRARY',
    AppTab.settings => 'SETTINGS',
  };

  String get title => '$ordinal // $label';
}

/// Owns the `IndexedStack` index.
///
/// Deliberately trivial: the shell keeps all four screens alive, so switching
/// tabs is a single integer change with no rebuild of the tabs themselves.
class NavigationCubit extends Cubit<AppTab> {
  NavigationCubit() : super(AppTab.home);

  void select(AppTab tab) {
    if (tab == state) return;
    Haptics.tap();
    emit(tab);
  }

  void selectIndex(int index) {
    if (index < 0 || index >= AppTab.values.length) return;
    select(AppTab.values[index]);
  }
}
