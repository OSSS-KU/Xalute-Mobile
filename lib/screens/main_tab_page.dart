import 'package:flutter/material.dart';
import 'ecg_page.dart';
import 'setting_page.dart';
import 'survey_list_page.dart';
import 'vital_signs_page.dart';

// ─────────────────────────────────────────────
// 1) AppTab 모델
//    새 페이지를 추가할 때 이 리스트에만 항목을 추가하면 됩니다.
// ─────────────────────────────────────────────
class AppTab {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// 탭 전환 콜백을 받을 수 있는 페이지라면 builder를 사용합니다.
  /// 단순 페이지라면 [page]에 직접 위젯을 넣어도 됩니다.
  final Widget Function(TabController controller)? builder;
  final Widget? page;

  const AppTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.builder,
    this.page,
  }) : assert(builder != null || page != null,
  'builder 또는 page 중 하나는 반드시 제공해야 합니다.');
}

// ─────────────────────────────────────────────
// 2) TabController
//    MainTabPage의 탭 인덱스를 외부(하위 페이지)에서 변경할 수 있도록
//    ChangeNotifier로 노출합니다.
// ─────────────────────────────────────────────
class TabController extends ChangeNotifier {
  int _index = 0;

  int get index => _index;

  void jumpTo(int index) {
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────
// 3) MainTabPage
// ─────────────────────────────────────────────
class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});

  @override
  State<MainTabPage> createState() => _MainTabPageState();
}

class _MainTabPageState extends State<MainTabPage> {
  final TabController _tabController = TabController();

  // ── 탭 목록 ──────────────────────────────────
  // 새 탭을 추가할 때 이 리스트에 AppTab 항목을 추가하세요.
  // EcgPage처럼 탭 전환이 필요한 페이지는 builder:를 사용하고,
  // 단순 페이지는 page:를 사용합니다.
  late final List<AppTab> _tabs = [
    AppTab(
      label: 'ECG',
      icon: Icons.monitor_heart_outlined,
      activeIcon: Icons.monitor_heart,
      builder: (controller) => EcgPage(),
    ),
    AppTab(
      label: '바이탈',
      icon: Icons.favorite_border,
      activeIcon: Icons.favorite,
      page: const VitalSignsPage(),
    ),
    AppTab(
      label: '설문기록',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_turned_in,
      page: const SurveyListPage(),
    ),
    AppTab(
      label: '설정',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: const SettingPage(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {}); // 탭 변경 시 UI 갱신
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _tabController.index;

    return Scaffold(
      // IndexedStack: 탭 전환 시 각 페이지의 상태(State)를 유지합니다.
      body: IndexedStack(
        index: currentIndex,
        children: _tabs.map((tab) {
          return tab.builder != null
              ? tab.builder!(_tabController)
              : tab.page!;
        }).toList(),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => _tabController.jumpTo(index),
        type: BottomNavigationBarType.fixed, // 탭이 4개 이상이어도 일정한 크기 유지
        selectedItemColor: const Color(0xFFFB755B),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: _tabs
            .asMap()
            .entries
            .map(
              (entry) => BottomNavigationBarItem(
            icon: Icon(entry.value.icon),
            activeIcon: Icon(entry.value.activeIcon),
            label: entry.value.label,
          ),
        )
            .toList(),
      ),
    );
  }
}