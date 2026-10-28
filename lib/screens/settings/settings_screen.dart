import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access.dart';
import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/l10n_table.dart';
import '../../data/entities.dart';
import '../../data/profile.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';
import '../me/business_numbers_card.dart';
import 'external_data_screen.dart';
import 'settings_lists.dart';

/// 「我的」：账号 + 经营数字 + 偏好 + 模块入口 + 租户管理。
///
/// 到期租户只能停在这一页：经营模块全部锁死，续费、反馈与导出留在这里，
/// 所以续费卡片必须在设置页内完成，不能跳到财务模块去。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState _app = context.read<AppState>();

  /// 经营数字由这一页持有，不是卡片自己持有：标签页随 IndexedStack 常驻，
  /// 卡片却会随滚动销毁重建，取数放在卡片里就等于每滑回来一次就重发一次请求。
  late final ValueLoader<BusinessNumbers> _numbers =
      ValueLoader<BusinessNumbers>(() async {
    final ApiResponse<DashboardStats> res = await _app.repos.dashboard.stats();
    return BusinessNumbers(res.data, res.stale);
  });

  @override
  void initState() {
    super.initState();
    unawaited(_numbers.load());
  }

  @override
  void dispose() {
    _numbers.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await _app.refreshProfileQuietly();
    await _numbers.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final UserProfile profile = app.profile;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 130),
          children: <Widget>[
            _Header(title: l10n.navSettings, subtitle: profile.tenantName),
            const VGap(14),
            if (!app.online)
              NoticeBanner(
                text: l10n.commonOfflineBanner,
                color: AppInk.warning,
                icon: Icons.wifi_off_rounded,
              ),
            if (app.renewalPending) ...<Widget>[
              NoticeBanner(
                text: l10n.commonExpiredBanner,
                color: AppInk.danger,
                icon: Icons.lock_clock_rounded,
              ),
              const VGap(12),
              const _RenewalCard(),
            ],
            _AccountCard(profile: profile),
            if (app.canOpenModule(ModuleKey.dashboard)) ...<Widget>[
              const VGap(14),
              BusinessNumbersCard(numbers: _numbers),
            ],
            const VGap(14),
            const _ModuleShortcuts(),
            const VGap(14),
            const _GeneralCard(),
            if (app.isAdmin) ...<Widget>[
              const VGap(14),
              const _AdminCard(),
            ],
            const VGap(14),
            const _DataCard(),
            const VGap(14),
            const _SignOutCard(),
            const VGap(10),
            Center(
              child: Text(
                '${Env.appName} ${l10n.setVersion(Env.appVersion)}',
                style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({ required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: AppType.huge,
            fontWeight: AppType.heavy,
            letterSpacing: -0.6,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const VGap(4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// 一组同类行：一个标题 + 一张卡，卡内用发丝线分隔。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.accent,
    required this.children,
    this.note,
  });

  final String title;
  final Color accent;
  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title, accent: accent, subtitle: note),
          const VGap(2),
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, thickness: 1, color: AppInk.hairline),
          ],
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final String initial =
        profile.displayName.isEmpty ? '?' : profile.displayName.characters.first.toUpperCase();

    return AppCard(
      accent: AppInk.dashboard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppInk.tint(AppInk.dashboard, alpha: 0.16),
                  borderRadius: Radii.control_,
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.heavy,
                    color: AppInk.dashboard,
                  ),
                ),
              ),
              const HGap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.displayName.isEmpty ? l10n.commonUnnamed : profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppType.head, fontWeight: AppType.semi),
                    ),
                    const VGap(3),
                    Text(
                      profile.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: _roleLabel(profile.role, l10n),
                color: profile.isSuperAdmin ? AppInk.orders : AppInk.dashboard,
              ),
            ],
          ),
          const VGap(14),
          KeyValueRow(label: l10n.setTenant, value: profile.tenantName, accent: AppInk.showroom),
          const VGap(10),
          KeyValueRow(
            label: l10n.setSubscription,
            value: _subLabel(profile, l10n),
            accent: profile.subscriptionExpired ? AppInk.danger : AppInk.finance,
          ),
          const VGap(10),
          KeyValueRow(
            label: l10n.shrExpires,
            value: profile.tenantExpiresAt == null
                ? l10n.shrNeverExpires
                : Fmt.date(profile.tenantExpiresAt),
            accent: AppInk.inventory,
          ),
          const VGap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String key in Access.permissionKeys)
                if (profile.permissions.containsKey(key) || profile.isSuperAdmin)
                  _PermChip(
                    label: _permLabel(key, l10n),
                    granted: profile.isSuperAdmin || profile.permissions[key] == true,
                  ),
            ],
          ),
        ],
      ),
    );
  }

  static String _roleLabel(String role, L10n l10n) => switch (role) {
        'super_admin' => l10n.setRoleSuper,
        'admin' => l10n.setRoleAdmin,
        'tenant_admin' => l10n.setRoleTenantAdmin,
        'tenant_user' => l10n.setRoleUser,
        _ => l10n.setRoleUser,
      };

  static String _subLabel(UserProfile profile, L10n l10n) {
    if (profile.subscriptionExpired) return l10n.setSubExpired;
    return switch (profile.subscriptionStatus) {
      'active' => l10n.setSubActive,
      'trial' => l10n.setSubTrial,
      _ => l10n.setSubTrial,
    };
  }

  static String _permLabel(String key, L10n l10n) => switch (key) {
        'dashboard' => l10n.navDashboard,
        'products' => l10n.navProducts,
        'inventory' => l10n.navInventory,
        'orders' => l10n.navOrders,
        'showrooms' => l10n.moduleShowroom,
        'ai' => l10n.moduleAi,
        'finance' => l10n.moduleFinance,
        'reports' => l10n.setPermReports,
        _ => key,
      };
}

class _PermChip extends StatelessWidget {
  const _PermChip({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final Color color = granted ? AppInk.finance : AppInk.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppInk.tint(color, alpha: granted ? 0.12 : 0.06),
        borderRadius: Radii.chip_,
        border: Border.all(color: AppInk.tint(color, alpha: granted ? 0.3 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            size: 13,
            color: color,
          ),
          const HGap(5),
          Text(label, style: TextStyle(fontSize: AppType.micro, color: color, fontWeight: AppType.semi)),
        ],
      ),
    );
  }
}

/// 底部导航只有四位，剩下四块模块从这里进 —— 权限位已经过滤，看不到就是没权。
class _ModuleShortcuts extends StatelessWidget {
  const _ModuleShortcuts();

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final List<ModuleEntry> visible =
        kSecondaryModules.where((ModuleEntry e) => app.canOpenModule(e.key)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return SettingsGroup(
      title: l10n.setModules,
      accent: AppInk.marketplace,
      children: <Widget>[
        for (final ModuleEntry entry in visible)
          TileRow(
            icon: entry.icon,
            accent: entry.accent,
            title: entry.titleOf(l10n),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
            onTap: () => entry.open(context),
          ),
      ],
    );
  }
}

class _GeneralCard extends StatelessWidget {
  const _GeneralCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final String langLabel = app.localeOverride == null
        ? l10n.setLangSystem
        : l10n.languageLabel(app.localeOverride!.languageCode);
    final String themeLabel = switch (app.themeChoice) {
      ThemeChoice.system => l10n.setThemeSystem,
      ThemeChoice.light => l10n.setThemeLight,
      ThemeChoice.dark => l10n.setThemeDark,
    };

    return SettingsGroup(
      title: l10n.setGeneral,
      accent: AppInk.settings,
      children: <Widget>[
        TileRow(
          icon: Icons.translate_rounded,
          accent: AppInk.info,
          title: l10n.setLanguage,
          subtitle: langLabel,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => _pickLanguage(context, app),
        ),
        TileRow(
          icon: Icons.dark_mode_rounded,
          accent: AppInk.orders,
          title: l10n.setTheme,
          subtitle: themeLabel,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => _pickTheme(context, app),
        ),
        TileRow(
          icon: Icons.chat_bubble_outline_rounded,
          accent: AppInk.ai,
          title: l10n.setFeedback,
          subtitle: l10n.setFeedbackHint,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const FeedbackScreen()),
        ),
      ],
    );
  }

  Future<void> _pickLanguage(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    await showDrawer<void>(
      context,
      title: l10n.setLanguage,
      accent: AppInk.info,
      maxHeightFactor: 0.6,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ChoiceRow(
            label: l10n.setLangSystem,
            note: l10n.setLangFollowNote,
            selected: app.localeOverride == null,
            onTap: () async {
              await app.followSystemLanguage();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          ),
          for (final String code in kLangOrder)
            _ChoiceRow(
              label: l10n.languageLabel(code),
              selected: app.localeOverride?.languageCode == code,
              onTap: () async {
                await app.setLanguage(code);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
          const VGap(8),
          Text(l10n.setLangNote,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary)),
        ],
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    final List<(ThemeChoice, String, IconData)> options = <(ThemeChoice, String, IconData)>[
      (ThemeChoice.system, l10n.setThemeSystem, Icons.brightness_auto_rounded),
      (ThemeChoice.light, l10n.setThemeLight, Icons.light_mode_rounded),
      (ThemeChoice.dark, l10n.setThemeDark, Icons.dark_mode_rounded),
    ];
    await showDrawer<void>(
      context,
      title: l10n.setTheme,
      accent: AppInk.orders,
      maxHeightFactor: 0.55,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (ThemeChoice choice, String label, IconData icon) in options)
            _ChoiceRow(
              label: label,
              icon: icon,
              selected: app.themeChoice == choice,
              onTap: () async {
                await app.setThemeChoice(choice);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
    this.icon,
  });

  final String label;
  final String? note;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppInk.dashboard : AppInk.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.control_,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: color),
              const HGap(10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: TextStyle(fontSize: AppType.body, fontWeight: AppType.semi, color: color)),
                  if (note != null)
                    Text(note!,
                        style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected ? AppInk.dashboard : AppInk.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 只有租户管理员能改租户的东西；普通成员连列表都拿不到（服务端按 id 过滤）。
class _AdminCard extends StatelessWidget {
  const _AdminCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return SettingsGroup(
      title: l10n.setTeam,
      accent: AppInk.orders,
      note: l10n.setTeamNote,
      children: <Widget>[
        TileRow(
          icon: Icons.groups_rounded,
          accent: AppInk.dashboard,
          title: l10n.setMembers,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const MembersScreen()),
        ),
        TileRow(
          icon: Icons.how_to_reg_rounded,
          accent: AppInk.info,
          title: l10n.setInvitations,
          subtitle: l10n.setInvitationsNote,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const InvitationsScreen()),
        ),
        TileRow(
          icon: Icons.qr_code_rounded,
          accent: AppInk.ai,
          title: l10n.setApiKeys,
          subtitle: l10n.setApiKeysNote,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const ApiKeysScreen()),
        ),
        TileRow(
          icon: Icons.print_outlined,
          accent: AppInk.products,
          title: l10n.setPrint,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const PrintSettingsScreen()),
        ),
      ],
    );
  }
}

/// 业务资料：任何成员都能维护，订单与商品页都依赖这几张表。
class _DataCard extends StatelessWidget {
  const _DataCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return SettingsGroup(
      title: l10n.setData,
      accent: AppInk.inventory,
      children: <Widget>[
        TileRow(
          icon: Icons.category_outlined,
          accent: AppInk.dashboard,
          title: l10n.setCategories,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const CategoriesScreen()),
        ),
        TileRow(
          icon: Icons.people_alt_outlined,
          accent: AppInk.products,
          title: l10n.setCustomers,
          subtitle: l10n.setCustomersInSettings,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const CustomersScreen()),
        ),
        TileRow(
          icon: Icons.sticky_note_2_outlined,
          accent: AppInk.showroom,
          title: l10n.setMemos,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const MemosScreen()),
        ),
        TileRow(
          icon: Icons.rss_feed_rounded,
          accent: AppInk.inventory,
          title: l10n.setExternal,
          subtitle: l10n.setExternalNote,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => pushSheet<void>(context, child: const ExternalDataScreen()),
        ),
        TileRow(
          icon: Icons.download_rounded,
          accent: AppInk.finance,
          title: l10n.setExport,
          subtitle: l10n.setExportNote,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
          onTap: () => _export(context, app),
        ),
        if (app.isAdmin)
          TileRow(
            icon: Icons.cleaning_services_rounded,
            accent: AppInk.warning,
            title: l10n.setRetention,
            subtitle: l10n.setRetentionNote,
            trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
            onTap: () => pushSheet<void>(context, child: const RetentionScreen()),
          ),
        if (app.isAdmin)
          TileRow(
            icon: Icons.delete_forever_rounded,
            accent: AppInk.danger,
            title: l10n.setResetData,
            subtitle: l10n.setResetNote,
            danger: true,
            trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
            onTap: () => _resetData(context, app),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    showToast(context, l10n.commonLoading);
    try {
      final JsonMap data = await app.repos.settings.fullExport();
      if (!context.mounted) return;
      await showDrawer<void>(
        context,
        title: l10n.setExport,
        accent: AppInk.finance,
        maxHeightFactor: 0.7,
        builder: (BuildContext sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String key in _exportKeys)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KeyValueRow(
                  label: _exportLabel(key, l10n),
                  // 这个接口只回五张裸数组，没有 counts 字段，计数只能自己取数组长度。
                  value: Fmt.count(data.asList(key).length),
                  accent: AppInk.finance,
                ),
              ),
            const VGap(6),
            PrimaryButton(
              label: l10n.setExportCopy,
              icon: Icons.copy_rounded,
              color: AppInk.finance,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonEncode(data.json)));
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                showToast(context, l10n.commonCopied);
              },
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }

  static const List<String> _exportKeys = <String>[
    'products',
    'orders',
    'order_items',
    'customers',
    'payment_records',
  ];

  static String _exportLabel(String key, L10n l10n) => switch (key) {
        'products' => l10n.navProducts,
        'orders' => l10n.navOrders,
        'order_items' => l10n.ordItems,
        'customers' => l10n.setCustomers,
        _ => l10n.finRecords,
      };

  Future<void> _resetData(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    final bool sure = await confirmAction(
      context,
      title: l10n.setResetData,
      message: l10n.setResetConfirm('RESET_TENANT_DATA'),
      confirmLabel: l10n.actConfirm,
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    try {
      await app.guardWrite<void>(() => app.repos.products.resetTenantData());
      if (!context.mounted) return;
      showToast(context, l10n.setResetDone);
      await app.refreshProfileQuietly();
    } on Object catch (error) {
      if (!context.mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }
}

class _SignOutCard extends StatelessWidget {
  const _SignOutCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    return AppCard(
      accent: AppInk.danger,
      padding: const EdgeInsets.all(12),
      child: GhostButton(
        label: l10n.authSignOut,
        icon: Icons.logout_rounded,
        color: AppInk.danger,
        onPressed: () async {
          final bool sure = await confirmAction(
            context,
            title: l10n.authSignOut,
            message: l10n.setSignOutConfirm,
            confirmLabel: l10n.authSignOut,
            destructive: true,
          );
          if (!sure || !context.mounted) return;
          await app.signOut();
        },
      ),
    );
  }
}

/// 到期续费：与财务模块同一套服务端票据，但不依赖经营权限位。
class _RenewalCard extends StatefulWidget {
  const _RenewalCard();

  @override
  State<_RenewalCard> createState() => _RenewalCardState();
}

class _RenewalCardState extends State<_RenewalCard> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<PlanBoard> _plans =
      ValueLoader<PlanBoard>(() => _app.repos.settings.plans());
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_plans.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return AnimatedBuilder(
      animation: _plans,
      builder: (BuildContext context, Widget? child) {
        final PlanBoard? board = _plans.value;
        return AppCard(
          accent: AppInk.danger,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(title: l10n.finPlans, subtitle: l10n.setRenewNote, accent: AppInk.danger),
              if (_plans.loading && board == null)
                const SkeletonList(count: 2, itemHeight: 56)
              else if (_plans.errorText != null && board == null)
                AppErrorView(message: _plans.errorText!, onRetry: _plans.refresh)
              else if (board == null || !board.anyPayable)
                Text(l10n.setNoPayableChannel, style: Theme.of(context).textTheme.bodyMedium)
              else
                for (final PlanChannel channel in board.channels)
                  if (channel.payable)
                    for (final PlanRow plan in channel.plans)
                      if (plan.hasPrice)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PlanTile(
                            plan: plan,
                            channel: channel,
                            busy: _busy,
                            onPay: _pay,
                          ),
                        ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pay(PlanRow plan, PlanChannel channel) async {
    final L10n l10n = _app.l10n;
    setState(() => _busy = true);
    try {
      final PaymentTicket ticket = await _app.guardWrite<PaymentTicket>(
        () => _app.repos.settings.createPayment(planType: plan.planType, channel: channel.name),
      );
      final Uri? uri = ticket.pageUrl == null ? null : Uri.tryParse(ticket.pageUrl!);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      showToast(context, l10n.finPayOpen);
      await _poll(ticket.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _poll(String paymentId) async {
    for (int attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final PaymentTicket ticket = await _app.repos.settings.paymentStatus(paymentId);
        if (ticket.succeeded) {
          await _app.loadProfile();
          if (!mounted) return;
          setState(() => _busy = false);
          showToast(context, _app.l10n.finPaidOk);
          return;
        }
        if (ticket.terminal) {
          if (!mounted) return;
          setState(() => _busy = false);
          showToast(context, ticket.failureReason ?? _app.l10n.commonErrorTitle, danger: true);
          return;
        }
      } on Object {
        // 轮询失败只当「还没回来」，终态会由下一次重试看到。
        continue;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, _app.l10n.setPayStillPending);
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.channel,
    required this.busy,
    required this.onPay,
  });

  final PlanRow plan;
  final PlanChannel channel;
  final bool busy;
  final Future<void> Function(PlanRow, PlanChannel) onPay;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    final String symbol = channel.currency == 'UAH' ? '₴' : r'$';
    return RowCard(
      accent: AppInk.finance,
      onTap: busy ? null : () => onPay(plan, channel),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppInk.tint(AppInk.finance, alpha: 0.14),
          borderRadius: Radii.chip_,
        ),
        child: Text(
          Fmt.money(plan.amount, symbol: symbol, compact: true),
          style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.heavy, color: AppInk.finance),
        ),
      ),
      title: _planLabel(plan.planType, l10n),
      subtitle: '${l10n.setExpiresInDays(plan.days)} · ${channel.name}',
      trailing: Icon(
        busy ? Icons.hourglass_top_rounded : Icons.arrow_circle_right_rounded,
        color: AppInk.danger,
      ),
    );
  }

  static String _planLabel(String planType, L10n l10n) => switch (planType) {
        'monthly' => l10n.finPlanMonthly,
        'yearly' => l10n.finPlanYearly,
        _ => planType,
      };
}
