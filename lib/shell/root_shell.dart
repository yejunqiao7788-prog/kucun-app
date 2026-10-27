import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/access.dart';
import '../core/l10n.dart';
import '../design/tokens.dart';
import '../design/widgets/controls.dart';
import '../design/widgets/sheets.dart';
import '../design/widgets/surfaces.dart';
import '../design/widgets/thumb_bar.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/orders/order_create_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/products/products_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../state/app_state.dart';
import 'module_registry.dart';

/// 外壳：4 个页面位 + 中央「开单」动作键。
///
/// 中间那颗不是标签页而是动作 —— 开单是库存端最高频的写操作，
/// 值得一个独立落点；库存视图收进「商品」页的胶囊切换里，避免两位导航重复。
class RootShell extends StatefulWidget {
  const RootShell({super.key, this.initialTab = RootTabs.dashboard});

  final int initialTab;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index = widget.initialTab.clamp(0, 3);

  /// 0 = 商品，1 = 库存。跨页跳转（工作台的「库存」入口）用它投递段落。
  final ValueNotifier<int> _productsSegment = ValueNotifier<int>(0);

  @override
  void dispose() {
    _productsSegment.dispose();
    super.dispose();
  }

  void _selectTab(int index, {int? segment}) {
    if (index == RootTabs.products && segment != null) {
      _productsSegment.value = segment;
    }
    if (_index == index && segment == null) return;
    setState(() => _index = index);
  }

  Future<void> _openCreateOrder() async {
    final AppState app = AppState.of(context);
    if (!app.canWrite) {
      showToast(context, app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    await pushSheet<void>(context, child: const OrderCreateScreen());
    if (!mounted) return;
    app.refreshProfileQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    final List<ThumbSlot> slots = <ThumbSlot>[
      ThumbSlot(
        icon: Icons.space_dashboard_outlined,
        activeIcon: Icons.space_dashboard_rounded,
        label: l10n.navDashboard,
        accent: AppInk.dashboard,
      ),
      ThumbSlot(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2_rounded,
        label: l10n.navProducts,
        accent: AppInk.products,
      ),
      ThumbSlot(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long_rounded,
        label: l10n.navOrders,
        accent: AppInk.orders,
      ),
      ThumbSlot(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: l10n.navSettings,
        accent: AppInk.settings,
      ),
    ];

    return ShellScope(
      selectTab: _selectTab,
      openCreateOrder: _openCreateOrder,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _index,
          children: <Widget>[
            _guard(ModuleKey.dashboard, const DashboardScreen()),
            _guard(ModuleKey.products, ProductsScreen(segment: _productsSegment)),
            _guard(ModuleKey.orders, const OrdersScreen()),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: ThumbBar(
          slots: slots,
          selectedIndex: _index,
          actionLabel: l10n.navCreateOrder,
          actionAccent: AppInk.orders,
          onSelect: (int index) => _selectTab(index),
          onAction: _openCreateOrder,
        ),
      ),
    );
  }

  Widget _guard(ModuleKey key, Widget child) {
    final AppState app = AppState.of(context);
    if (app.canOpenModule(key)) return child;
    return _LockedModule(module: key);
  }
}

class _LockedModule extends StatelessWidget {
  const _LockedModule({required this.module});

  final ModuleKey module;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                app.renewalPending ? Icons.lock_clock_rounded : Icons.lock_outline_rounded,
                size: 44,
                color: app.renewalPending ? AppInk.danger : AppInk.warning,
              ),
              const VGap(14),
              Text(
                app.renewalPending ? l10n.commonExpiredBanner : l10n.commonNoPermission,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const VGap(18),
              if (app.renewalPending)
                PrimaryButton(
                  label: l10n.finRenew,
                  icon: Icons.arrow_circle_right_rounded,
                  color: AppInk.danger,
                  expanded: false,
                  onPressed: () => RootTabs.openSettings(context),
                )
              else
                GhostButton(
                  label: l10n.navDashboard,
                  onPressed: () => RootTabs.select(context, RootTabs.dashboard),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
