import 'package:flutter/material.dart';

import '../core/access.dart';
import '../core/l10n.dart';
import '../design/tokens.dart';
import '../design/widgets/sheets.dart';
import '../design/widgets/surfaces.dart';
import '../screens/ai/ai_screen.dart';
import '../screens/finance/finance_screen.dart';
import '../screens/market/market_screen.dart';
import '../screens/showroom/showroom_screen.dart';

/// 一个模块的入口描述：颜色即身份，图标即落点。
class ModuleEntry {
  const ModuleEntry({
    required this.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.screen,
  });

  final ModuleKey key;
  final IconData icon;
  final String Function(L10n) title;
  final Color accent;
  final Widget screen;

  String titleOf(L10n l10n) => title(l10n);

  /// 独立模块用全屏页承载，返回手势与网页端的一级页一致。
  void open(BuildContext context) =>
      pushSheet<void>(context, child: screen);
}

/// 工作台快捷入口：不进底部导航的四块。
final List<ModuleEntry> kSecondaryModules = <ModuleEntry>[
  ModuleEntry(
    key: ModuleKey.showroom,
    icon: Icons.storefront_outlined,
    accent: AppInk.showroom,
    title: (L10n l10n) => l10n.moduleShowroom,
    screen: const ShowroomScreen(),
  ),
  ModuleEntry(
    key: ModuleKey.marketplace,
    icon: Icons.store_outlined,
    accent: AppInk.marketplace,
    title: (L10n l10n) => l10n.moduleMarketplace,
    screen: const MarketScreen(),
  ),
  ModuleEntry(
    key: ModuleKey.finance,
    icon: Icons.account_balance_wallet_outlined,
    accent: AppInk.finance,
    title: (L10n l10n) => l10n.moduleFinance,
    screen: const FinanceScreen(),
  ),
  ModuleEntry(
    key: ModuleKey.ai,
    icon: Icons.auto_awesome_outlined,
    accent: AppInk.ai,
    title: (L10n l10n) => l10n.moduleAi,
    screen: const AiScreen(),
  ),
];

ModuleEntry? entryOf(ModuleKey key) {
  for (final ModuleEntry entry in kSecondaryModules) {
    if (entry.key == key) return entry;
  }
  return null;
}

/// 底部导航四位页面的落点常量。
class RootTabs {
  const RootTabs._();

  static const int dashboard = 0;
  static const int products = 1;
  static const int orders = 2;
  static const int settings = 3;

  static void select(BuildContext context, int index) =>
      ShellScope.maybeOf(context)?.selectTab(index);

  static void openOrders(BuildContext context) => select(context, orders);
  static void openProducts(BuildContext context) => select(context, products);
  static void openSettings(BuildContext context) => select(context, settings);

  /// 「库存」是商品页的第二段，不单占一位导航。
  static void openInventory(BuildContext context) =>
      ShellScope.maybeOf(context)?.selectTab(products, segment: 1);
}

extension ModuleJump on ModuleKey {
  int? get rootTabIndex {
    switch (this) {
      case ModuleKey.dashboard:
        return RootTabs.dashboard;
      case ModuleKey.products:
        return RootTabs.products;
      case ModuleKey.inventory:
        return RootTabs.products;
      case ModuleKey.orders:
        return RootTabs.orders;
      case ModuleKey.settings:
        return RootTabs.settings;
      case ModuleKey.showroom:
      case ModuleKey.marketplace:
      case ModuleKey.finance:
      case ModuleKey.ai:
        return null;
    }
  }

  /// 有页面位的切过去，没有的推独立全屏页。
  void jumpTo(BuildContext context) {
    final int? index = rootTabIndex;
    if (index != null) {
      RootTabs.select(context, index);
      return;
    }
    entryOf(this)?.open(context);
  }
}

/// 外壳向子页面暴露的两个动作：切标签、请求开单。
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.selectTab,
    required this.openCreateOrder,
    required super.child,
  });

  final void Function(int index, {int? segment}) selectTab;
  final VoidCallback openCreateOrder;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(covariant ShellScope oldWidget) => false;
}

/// 独立模块页的统一外壳：大标题 + 返回 + 模块色，滚动内容自带底部留白。
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({
    super.key,
    required this.title,
    required this.accent,
    required this.children,
    this.actions = const <Widget>[],
    this.onRefresh,
  });

  final String title;
  final Color accent;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final Widget body = SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 12),
              child: Row(
                children: <Widget>[
                  RoundBackButton(accent: accent),
                  const HGap(10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.heavy,
                        color: accent,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => children[index],
                childCount: children.length,
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      body: onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body),
    );
  }
}

class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(Icons.arrow_back_ios_new_rounded, color: accent, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: AppInk.tint(accent, alpha: 0.12),
      ),
    );
  }
}
