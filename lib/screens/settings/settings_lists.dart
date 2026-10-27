import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/access.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';
import 'settings_screen.dart';

// 设置页的九个子页：成员、邀请、类目、客户、便签、打印、API Key、数据清理、反馈。
//
// 共同约束：写操作一律过 `guardWrite`（离线直接挡），失败文案用服务端原文；
// 成员/邀请/API Key/清理这四页服务端只对租户管理员开口，界面按 `isAdmin` 隐藏入口。

// ———————————————————————————————————————— 成员

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<MemberRow>> _rows =
      ValueLoader<List<MemberRow>>(() => _app.repos.settings.users());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setMembers),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.actRefresh,
            onPressed: _rows.loading ? null : _rows.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _ListBody<MemberRow>(
        loader: _rows,
        emptyTitle: l10n.commonEmptyTitle,
        builder: (BuildContext context, List<MemberRow> rows) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
          children: <Widget>[
            if (!_app.isAdmin)
              NoticeBanner(text: l10n.setMemberReadOnly, color: AppInk.info, icon: Icons.info_outline_rounded),
            SettingsGroup(
              title: l10n.setMembers,
              accent: AppInk.dashboard,
              note: l10n.setOwnerNote,
              children: <Widget>[
                for (final MemberRow row in rows)
                  TileRow(
                    icon: row.avatarUrl == null
                        ? Icons.person_rounded
                        : Icons.badge_outlined,
                    accent: row.isActive ? AppInk.finance : AppInk.textTertiary,
                    title: row.username,
                    subtitle: '${row.email} · ${_memberStatusLabel(row.status, l10n)}',
                    trailing: _app.isAdmin && row.id.isNotEmpty && row.role != 'super_admin'
                        ? const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary)
                        : StatusPill(label: _roleLabel(row.role, l10n), color: AppInk.orders, dense: true),
                    onTap: _app.isAdmin && row.role != 'super_admin'
                        ? () => _editMember(row)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMember(MemberRow row) async {
    final L10n l10n = _app.l10n;
    final bool isSelf = row.id == _app.profile.id;
    final Map<String, bool> perms = <String, bool>{
      for (final String key in Access.permissionKeys) key: row.permissions[key] == true,
    };

    await showDrawer<void>(
      context,
      title: row.username,
      accent: AppInk.dashboard,
      maxHeightFactor: 0.86,
      builder: (BuildContext sheetContext) => _PermissionEditor(
        initialRole: row.role,
        initialPerms: perms,
        locked: !_app.canWrite || isSelf,
        onSave: (String role, Map<String, bool> nextPerms) async {
          await Navigator.of(sheetContext).maybePop();
          if (await _write(() => _app.repos.settings.setPermissions(row.id, nextPerms, role: role)) &&
              mounted) {
            await _rows.refresh();
            _app.refreshProfileQuietly();
          }
        },
        onDelete: isSelf
            ? null
            : () async {
                final NavigatorState navigator = Navigator.of(sheetContext);
                final bool sure = await confirmAction(
                  sheetContext,
                  title: l10n.setRemoveMember,
                  message: l10n.setRemoveMemberConfirm(row.username),
                  confirmLabel: l10n.actDelete,
                  destructive: true,
                );
                if (!sure) return;
                await navigator.maybePop();
                if (await _write(() => _app.repos.settings.removeMember(row.id)) && mounted) {
                  await _rows.refresh();
                }
              },
      ),
    );
  }

  Future<bool> _write(Future<Object?> Function() action) async {
    final L10n l10n = _app.l10n;
    try {
      await _app.guardWrite<Object?>(action);
      if (!mounted) return false;
      showToast(context, l10n.commonSaved);
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      showToast(context, _app.describeError(error), danger: true);
      return false;
    }
  }

  static String _roleLabel(String role, L10n l10n) => memberRoleLabel(role, l10n);

  static String _memberStatusLabel(String status, L10n l10n) => memberStatusLabel(status, l10n);
}

/// 角色名与服务端 `normalizeRole` 的四枚取值一一对应；`super_admin` 只在跨租户时出现。
String memberRoleLabel(String role, L10n l10n) => switch (role) {
      'super_admin' => l10n.setRoleSuper,
      'admin' => l10n.setRoleAdmin,
      'tenant_admin' => l10n.setRoleTenantAdmin,
      _ => l10n.setRoleUser,
    };

String memberStatusLabel(String status, L10n l10n) =>
    status == 'active' ? l10n.setMemberActive : l10n.setMemberPending;

/// 权限键的中文名；服务端那 8 把键里 `reports` 没有模块位，单独给一句。
String permLabel(String key, L10n l10n) => switch (key) {
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

class _PermissionEditor extends StatefulWidget {
  const _PermissionEditor({
    required this.initialRole,
    required this.initialPerms,
    required this.locked,
    required this.onSave,
    this.onDelete,
  });

  final String initialRole;
  final Map<String, bool> initialPerms;
  final bool locked;
  final Future<void> Function(String role, Map<String, bool> perms) onSave;
  final VoidCallback? onDelete;

  @override
  State<_PermissionEditor> createState() => _PermissionEditorState();
}

class _PermissionEditorState extends State<_PermissionEditor> {
  late String _role = widget.initialRole;
  late final Map<String, bool> _perms = <String, bool>{...widget.initialPerms};

  /// admin / tenant_admin 在服务端被强制成全开，勾选框只是摆设。
  bool get _roleForcesAll => _role == 'admin' || _role == 'tenant_admin';

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PillTabs<String>(
          values: const <String>['user', 'tenant_user', 'admin', 'tenant_admin'],
          selected: _role,
          accent: AppInk.orders,
          scrollable: true,
          labelOf: (String value) => switch (value) {
            'admin' => l10n.setRoleAdmin,
            'tenant_admin' => l10n.setRoleTenantAdmin,
            'tenant_user' => l10n.setRoleUser,
            _ => l10n.setRoleUser,
          },
          onChanged: (String value) => setState(() => _role = value),
        ),
        const VGap(14),
        Text(l10n.setPermissions, style: Theme.of(context).textTheme.titleMedium),
        const VGap(6),
        if (_roleForcesAll)
          NoticeBanner(text: l10n.setAdminPermNote, color: AppInk.orders, icon: Icons.info_outline_rounded),
        for (final String key in Access.permissionKeys)
          SwitchListTile.adaptive(
            value: _roleForcesAll || (_perms[key] ?? false),
            onChanged: widget.locked || _roleForcesAll
                ? null
                : (bool value) => setState(() => _perms[key] = value),
            title: Text(permLabel(key, l10n), style: const TextStyle(fontSize: AppType.body)),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppInk.dashboard,
          ),
        const VGap(10),
        PrimaryButton(
          label: l10n.actSave,
          icon: Icons.check_rounded,
          color: AppInk.dashboard,
          onPressed: widget.locked ? null : () => widget.onSave(_role, _perms),
        ),
        if (widget.onDelete != null) ...<Widget>[
          const VGap(10),
          GhostButton(
            label: l10n.setRemoveMember,
            icon: Icons.person_remove_rounded,
            color: AppInk.danger,
            onPressed: widget.onDelete,
          ),
        ],
        const VGap(8),
      ],
    );
  }
}

// ———————————————————————————————————————— 邀请

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<Invitation>> _rows =
      ValueLoader<List<Invitation>>(() => _app.repos.settings.invitations());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setInvitations),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.actNew,
            onPressed: _app.canWrite ? _create : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: _app.canWrite
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: AppInk.info,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(l10n.setMemberInvite),
            )
          : null,
      body: _ListBody<Invitation>(
        loader: _rows,
        emptyTitle: l10n.setInviteEmpty,
        emptyHint: l10n.setInvitationsNote,
        emptyIcon: Icons.how_to_reg_rounded,
        accent: AppInk.info,
        builder: (BuildContext context, List<Invitation> rows) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 96),
          children: <Widget>[
            NoticeBanner(text: l10n.setInvitationsNote, color: AppInk.info, icon: Icons.info_outline_rounded),
            const VGap(12),
            for (final Invitation row in rows) _InviteCard(row: row, onChanged: _rows.refresh),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final L10n l10n = _app.l10n;
    String role = 'user';
    int hours = 168;
    final TextEditingController code = TextEditingController();
    final Map<String, bool> perms = <String, bool>{
      for (final String key in Access.permissionKeys) key: key == 'dashboard',
    };

    await showDrawer<void>(
      context,
      title: l10n.setMemberInvite,
      accent: AppInk.info,
      maxHeightFactor: 0.9,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter rebuild) => ListView(
          shrinkWrap: true,
          children: <Widget>[
            PillTabs<String>(
              values: const <String>['user', 'admin', 'tenant_admin'],
              selected: role,
              accent: AppInk.orders,
              labelOf: (String value) => switch (value) {
                'admin' => l10n.setRoleAdmin,
                'tenant_admin' => l10n.setRoleTenantAdmin,
                _ => l10n.setRoleUser,
              },
              onChanged: (String value) => rebuild(() => role = value),
            ),
            const VGap(14),
            AppTextField(
              label: l10n.authCode,
              controller: code,
              hint: l10n.setInviteCodeHint,
              inputFormatters: <TextInputFormatter>[
                UpperCaseFormatter(),
                FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const VGap(14),
            Text(l10n.setInviteValidity, style: Theme.of(context).textTheme.titleMedium),
            const VGap(6),
            PillTabs<int>(
              values: const <int>[24, 72, 168, 720],
              selected: hours,
              accent: AppInk.info,
              labelOf: (int value) => '$value${l10n.mpDaysSuffix}',
              onChanged: (int value) => rebuild(() => hours = value),
            ),
            const VGap(14),
            if (role == 'user') ...<Widget>[
              Text(l10n.setPermissions, style: Theme.of(context).textTheme.titleMedium),
              const VGap(4),
              for (final String key in Access.permissionKeys)
                SwitchListTile.adaptive(
                  value: perms[key] ?? false,
                  onChanged: (bool value) => rebuild(() => perms[key] = value),
                  title: Text(permLabel(key, l10n),
                      style: const TextStyle(fontSize: AppType.body)),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppInk.info,
                ),
            ] else
              NoticeBanner(
                text: l10n.setAdminPermNote,
                color: AppInk.orders,
                icon: Icons.info_outline_rounded,
              ),
            const VGap(16),
            PrimaryButton(
              label: l10n.actCreate,
              icon: Icons.add_rounded,
              color: AppInk.info,
              onPressed: () async {
                await Navigator.of(sheetContext).maybePop();
                try {
                  await _app.guardWrite<Object?>(() => _app.repos.settings.invite(
                        code: code.text.trim(),
                        role: role,
                        expiresHours: hours,
                        permissions: role == 'user' ? perms : null,
                      ));
                  if (!mounted) return;
                  showToast(this.context, l10n.commonSaved);
                  await _rows.refresh();
                } on Object catch (error) {
                  if (!mounted) return;
                  showToast(this.context, _app.describeError(error), danger: true);
                }
              },
            ),
            const VGap(8),
          ],
        ),
      ),
    );
    code.dispose();
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.row, required this.onChanged});

  final Invitation row;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final Color color = row.consumable
        ? AppInk.info
        : row.isUsed
            ? AppInk.finance
            : AppInk.textTertiary;
    final String status = row.isUsed
        ? l10n.setInviteUsed
        : row.isExpired
            ? l10n.setInviteExpired
            : l10n.setInvitePending;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RowCard(
        accent: color,
        title: row.code,
        subtitle: row.expiresAt == null
            ? '${memberRoleLabel(row.role, l10n)} · $status'
            : '${memberRoleLabel(row.role, l10n)} · $status · ${l10n.shrExpires} ${Fmt.dateTime(row.expiresAt)}',
        leading: Container(
          width: 54,
          alignment: Alignment.center,
          child: Text(
            row.code,
            style: TextStyle(
              fontSize: AppType.foot,
              fontWeight: AppType.heavy,
              letterSpacing: 1.2,
              color: color,
            ),
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: <Widget>[
            IconButton(
              tooltip: l10n.actCopy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: row.code));
                if (!context.mounted) return;
                showToast(context, l10n.commonCopied);
              },
              icon: const Icon(Icons.copy_rounded, size: 20),
              color: color,
            ),
            if (!row.isUsed)
              IconButton(
                tooltip: l10n.setRevoke,
                onPressed: () async {
                  final bool sure = await confirmAction(
                    context,
                    title: l10n.setRevoke,
                    message: l10n.setInviteRevokeConfirm(row.code),
                    confirmLabel: l10n.actDelete,
                    destructive: true,
                  );
                  if (!sure) return;
                  try {
                    await app.guardWrite<Object?>(() => app.repos.settings.revokeInvitation(row.id));
                    if (!context.mounted) return;
                    showToast(context, l10n.commonDeleted);
                    await onChanged();
                  } on Object catch (error) {
                    if (!context.mounted) return;
                    showToast(context, app.describeError(error), danger: true);
                  }
                },
                icon: const Icon(Icons.link_off_rounded, size: 20),
                color: AppInk.danger,
              ),
          ],
        ),
      ),
    );
  }
}

// ———————————————————————————————————————— 类目

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<Category>> _rows =
      ValueLoader<List<Category>>(() => _app.repos.products.categories());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setCategories)),
      floatingActionButton: _app.canWrite
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: AppInk.dashboard,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.setNewCategory),
            )
          : null,
      body: _ListBody<Category>(
        loader: _rows,
        emptyTitle: l10n.commonEmptyTitle,
        emptyHint: l10n.setCategoryEmptyHint,
        emptyIcon: Icons.category_outlined,
        accent: AppInk.dashboard,
        builder: (BuildContext context, List<Category> rows) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 96),
          children: <Widget>[
            SettingsGroup(
              title: l10n.setCategories,
              accent: AppInk.dashboard,
              children: <Widget>[
                for (final Category row in rows)
                  TileRow(
                    icon: Icons.folder_outlined,
                    accent: AppInk.dashboard,
                    title: row.name,
                    subtitle: l10n.setCategoryUsed(row.productCount),
                    trailing: RoundIconButton(
                      icon: Icons.edit_outlined,
                      size: 34,
                      color: AppInk.dashboard,
                      tooltip: l10n.actEdit,
                      onPressed: _app.canWrite ? () => _rename(row) : null,
                    ),
                    onTap: _app.canWrite ? () => _rename(row) : null,
                  ),
              ],
            ),
            const VGap(6),
            Text(l10n.setCategoryDeleteNote,
                style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary)),
          ],
        ),
      ),
    );
  }

  Future<void> _create() {
    final L10n l10n = _app.l10n;
    return _prompt(
        title: l10n.setNewCategory,
        initial: '',
        onSubmit: (String name) async {
          try {
            await _app.guardWrite<Object?>(() => _app.repos.products.createCategory(name));
            if (!mounted) return;
            showToast(context, l10n.commonSaved);
            await _rows.refresh();
          } on Object catch (error) {
            if (!mounted) return;
            showToast(context, _app.describeError(error), danger: true);
          }
        },
    );
  }

  Future<void> _rename(Category row) {
    final L10n l10n = _app.l10n;
    return _prompt(
        title: row.name,
        initial: row.name,
        onSubmit: (String name) async {
          try {
            await _app.guardWrite<Object?>(() => _app.repos.products.renameCategory(row.id, name));
            if (!mounted) return;
            showToast(context, l10n.commonSaved);
            await _rows.refresh();
          } on Object catch (error) {
            if (!mounted) return;
            showToast(context, _app.describeError(error), danger: true);
          }
        },
        onDelete: () async {
          final bool sure = await confirmAction(
            context,
            title: row.name,
            message: l10n.setCategoryDeleteConfirm(row.productCount),
            confirmLabel: l10n.actDelete,
            destructive: true,
          );
          if (!sure) return;
          try {
            await _app.guardWrite<Object?>(() => _app.repos.products.removeCategory(row.id));
            if (!mounted) return;
            showToast(context, l10n.commonDeleted);
            await _rows.refresh();
          } on Object catch (error) {
            if (!mounted) return;
            showToast(context, _app.describeError(error), danger: true);
          }
        },
    );
  }

  Future<void> _prompt({
    required String title,
    required String initial,
    required Future<void> Function(String name) onSubmit,
    VoidCallback? onDelete,
  }) async {
    final L10n l10n = _app.l10n;
    final TextEditingController controller = TextEditingController(text: initial);
    await showDrawer<void>(
      context,
      title: title,
      accent: AppInk.dashboard,
      maxHeightFactor: 0.5,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppTextField(
            label: l10n.prodName,
            controller: controller,
            autofocus: true,
            hint: l10n.setCategoryNotEmpty,
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            icon: Icons.check_rounded,
            color: AppInk.dashboard,
            onPressed: () async {
              final String name = controller.text.trim();
              if (name.isEmpty) {
                showToast(sheetContext, l10n.setCategoryNotEmpty);
                return;
              }
              await Navigator.of(sheetContext).maybePop();
              await onSubmit(name);
            },
          ),
          if (onDelete != null) ...<Widget>[
            const VGap(10),
            GhostButton(
              label: l10n.actDelete,
              icon: Icons.delete_outline_rounded,
              color: AppInk.danger,
              onPressed: () async {
                await Navigator.of(sheetContext).maybePop();
                onDelete();
              },
            ),
          ],
          const VGap(8),
        ],
      ),
    );
    controller.dispose();
  }
}

// ———————————————————————————————————————— 客户

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<Customer>> _rows =
      ValueLoader<List<Customer>>(() => _app.repos.settings.customers());
  final TextEditingController _keyword = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
    _keyword.addListener(() => setState(() => _query = _keyword.text.trim()));
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    final List<Customer> all = _rows.value ?? const <Customer>[];
    final List<Customer> rows = _query.isEmpty
        ? all
        : all
            .where((Customer c) =>
                c.name.toLowerCase().contains(_query.toLowerCase()) ||
                (c.phone ?? '').contains(_query))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setCustomers),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.actNew,
            onPressed: _app.canWrite ? () => _edit(null) : null,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      floatingActionButton: _app.canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _edit(null),
              backgroundColor: AppInk.products,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.actNew),
            )
          : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 8),
            child: SearchField(
              controller: _keyword,
              hintText: l10n.setCustomers,
            ),
          ),
          Expanded(
            child: _ListBody<Customer>(
              loader: _rows,
              emptyTitle: rows.isEmpty ? l10n.commonEmptyTitle : '',
              emptyHint: l10n.setCustomersInSettings,
              emptyIcon: Icons.people_alt_outlined,
              accent: AppInk.products,
              builder: (BuildContext context, List<Customer> _) => ListView(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 96),
                children: <Widget>[
                  for (final Customer row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RowCard(
                        accent: AppInk.products,
                        onTap: _app.canWrite ? () => _edit(row) : null,
                        leading: const Icon(Icons.person_outline_rounded, color: AppInk.products),
                        title: row.name.isEmpty ? l10n.commonUnnamed : row.name,
                        subtitle: row.phone == null || row.phone!.isEmpty
                            ? (row.notes ?? '—')
                            : row.notes == null || row.notes!.isEmpty
                                ? row.phone
                                : '${row.phone} · ${row.notes}',
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Customer? row) async {
    final L10n l10n = _app.l10n;
    final TextEditingController name = TextEditingController(text: row?.name ?? '');
    final TextEditingController phone = TextEditingController(text: row?.phone ?? '');
    final TextEditingController notes = TextEditingController(text: row?.notes ?? '');

    await showDrawer<void>(
      context,
      title: row == null ? l10n.actNew : row.name,
      accent: AppInk.products,
      maxHeightFactor: 0.72,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppTextField(label: l10n.ordCustomer, controller: name, autofocus: true),
          const VGap(12),
          AppTextField(
            label: l10n.setCustomerPhone,
            controller: phone,
            keyboardType: TextInputType.phone,
            hint: l10n.setCustomerInvalidPhone,
          ),
          const VGap(12),
          AppTextField(label: l10n.ordNotes, controller: notes, maxLines: 3),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            icon: Icons.check_rounded,
            color: AppInk.products,
            onPressed: () async {
              final String trimmed = name.text.trim();
              if (trimmed.isEmpty) {
                showToast(sheetContext, l10n.setCustomerNameRequired);
                return;
              }
              final Map<String, Object?> payload = <String, Object?>{
                'name': trimmed,
                'phone': phone.text.trim(),
                'notes': notes.text.trim(),
              };
              await Navigator.of(sheetContext).maybePop();
              try {
                await _app.guardWrite<Object?>(() => row == null
                    ? _app.repos.settings.createCustomer(payload)
                    : _app.repos.settings.updateCustomer(row.id, payload));
                if (!mounted) return;
                showToast(context, l10n.commonSaved);
                await _rows.refresh();
              } on Object catch (error) {
                if (!mounted) return;
                showToast(context, _app.describeError(error), danger: true);
              }
            },
          ),
          if (row != null) ...<Widget>[
            const VGap(10),
            GhostButton(
              label: l10n.actDelete,
              icon: Icons.delete_outline_rounded,
              color: AppInk.danger,
              onPressed: () async {
                final NavigatorState navigator = Navigator.of(sheetContext);
                final bool sure = await confirmAction(
                  sheetContext,
                  title: row.name,
                  message: l10n.setCustomerDeleteConfirm,
                  confirmLabel: l10n.actDelete,
                  destructive: true,
                );
                if (!sure) return;
                await navigator.maybePop();
                try {
                  await _app.guardWrite<Object?>(() => _app.repos.settings.removeCustomer(row.id));
                  if (!mounted) return;
                  showToast(context, l10n.commonDeleted);
                  await _rows.refresh();
                } on Object catch (error) {
                  if (!mounted) return;
                  showToast(context, _app.describeError(error), danger: true);
                }
              },
            ),
          ],
          const VGap(8),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    notes.dispose();
  }
}

// ———————————————————————————————————————— 便签

class MemosScreen extends StatefulWidget {
  const MemosScreen({super.key});

  @override
  State<MemosScreen> createState() => _MemosScreenState();
}

class _MemosScreenState extends State<MemosScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<Memo>> _rows =
      ValueLoader<List<Memo>>(() => _app.repos.settings.memos());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setMemos)),
      floatingActionButton: _app.canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _edit(null),
              backgroundColor: AppInk.showroom,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.note_add_rounded),
              label: Text(l10n.setMemoNew),
            )
          : null,
      body: _ListBody<Memo>(
        loader: _rows,
        emptyTitle: l10n.setMemoEmpty,
        emptyHint: l10n.setMemoEmptyHint,
        emptyIcon: Icons.sticky_note_2_outlined,
        accent: AppInk.showroom,
        builder: (BuildContext context, List<Memo> rows) {
          final List<Memo> open = rows.where((Memo m) => !m.completed).toList(growable: false);
          final List<Memo> done = rows.where((Memo m) => m.completed).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 96),
            children: <Widget>[
              for (final Memo row in open) _MemoCard(row: row, onChanged: _toggle, onEdit: _edit),
              if (done.isNotEmpty) ...<Widget>[
                const VGap(8),
                Text(l10n.setMemoDone,
                    style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary)),
                const VGap(6),
                for (final Memo row in done) _MemoCard(row: row, onChanged: _toggle, onEdit: _edit),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggle(Memo row) async {
    try {
      await _app.guardWrite<Object?>(
        () => _app.repos.settings.updateMemo(row.id, completed: !row.completed),
      );
      if (!mounted) return;
      await _rows.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _edit(Memo? row) async {
    final L10n l10n = _app.l10n;
    final TextEditingController content = TextEditingController(text: row?.content ?? '');
    String priority = row?.priority ?? 'normal';

    await showDrawer<void>(
      context,
      title: row == null ? l10n.setMemoNew : l10n.actEdit,
      accent: AppInk.showroom,
      maxHeightFactor: 0.66,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppTextField(
            label: l10n.setMemos,
            controller: content,
            autofocus: true,
            maxLines: 5,
            hint: l10n.setMemoEmptyHint,
          ),
          const VGap(12),
          PillTabs<String>(
            values: const <String>['normal', 'high'],
            selected: priority,
            accent: AppInk.showroom,
            labelOf: (String value) => value == 'high' ? l10n.setMemoHigh : l10n.setMemoNormal,
            onChanged: (String value) => setState(() => priority = value),
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            icon: Icons.check_rounded,
            color: AppInk.showroom,
            onPressed: () async {
              final String text = content.text.trim();
              if (text.isEmpty) {
                showToast(sheetContext, l10n.setMemoContentRequired);
                return;
              }
              await Navigator.of(sheetContext).maybePop();
              try {
                await _app.guardWrite<Object?>(() => row == null
                    ? _app.repos.settings.createMemo(text, priority: priority)
                    : _app.repos.settings.updateMemo(row.id, content: text, priority: priority));
                if (!mounted) return;
                showToast(context, l10n.commonSaved);
                await _rows.refresh();
              } on Object catch (error) {
                if (!mounted) return;
                showToast(context, _app.describeError(error), danger: true);
              }
            },
          ),
          if (row != null) ...<Widget>[
            const VGap(10),
            GhostButton(
              label: l10n.actDelete,
              icon: Icons.delete_outline_rounded,
              color: AppInk.danger,
              onPressed: () async {
                final NavigatorState navigator = Navigator.of(sheetContext);
                final bool sure = await confirmAction(
                  sheetContext,
                  title: l10n.setMemos,
                  message: l10n.setMemoDeleteConfirm,
                  confirmLabel: l10n.actDelete,
                  destructive: true,
                );
                if (!sure) return;
                await navigator.maybePop();
                try {
                  await _app.guardWrite<Object?>(() => _app.repos.settings.removeMemo(row.id));
                  if (!mounted) return;
                  showToast(context, l10n.commonDeleted);
                  await _rows.refresh();
                } on Object catch (error) {
                  if (!mounted) return;
                  showToast(context, _app.describeError(error), danger: true);
                }
              },
            ),
          ],
          const VGap(8),
        ],
      ),
    );
    content.dispose();
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.row, required this.onChanged, required this.onEdit});

  final Memo row;
  final Future<void> Function(Memo) onChanged;
  final void Function(Memo) onEdit;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final Color color = row.completed
        ? AppInk.textTertiary
        : row.isHigh
            ? AppInk.danger
            : AppInk.showroom;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RowCard(
        accent: color,
        onTap: () => onChanged(row),
        title: row.content,
        subtitle: l10n.elapsed(row.createdAt),
        badges: <Widget>[
          if (row.isHigh && !row.completed)
            StatusPill(label: l10n.setMemoHigh, color: AppInk.danger, dense: true),
        ],
        leading: Icon(
          row.completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: color,
        ),
        trailing: RoundIconButton(
          icon: Icons.edit_outlined,
          size: 32,
          color: color,
          tooltip: l10n.actEdit,
          onPressed: () => onEdit(row),
        ),
      ),
    );
  }
}

// ———————————————————————————————————————— 打印设置

class PrintSettingsScreen extends StatefulWidget {
  const PrintSettingsScreen({super.key});

  @override
  State<PrintSettingsScreen> createState() => _PrintSettingsScreenState();
}

class _PrintSettingsScreenState extends State<PrintSettingsScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<PrintSettings> _loader =
      ValueLoader<PrintSettings>(() => _app.repos.settings.printSettings());

  final TextEditingController _company = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _footer = TextEditingController();
  final TextEditingController _logo = TextEditingController();

  String _template = 'standard';
  bool _showPrice = true;
  bool _showSku = true;
  bool _showImage = false;
  bool _seeded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loader.load());
  }

  @override
  void dispose() {
    _company.dispose();
    _contact.dispose();
    _footer.dispose();
    _logo.dispose();
    super.dispose();
  }

  void _seed(PrintSettings values) {
    if (_seeded) return;
    _seeded = true;
    _company.text = values.companyName;
    _contact.text = values.contactInfo;
    _footer.text = values.footerText;
    _logo.text = values.logoUrl;
    _template = values.templateId;
    _showPrice = values.showPrice;
    _showSku = values.showSku;
    _showImage = values.showImage;
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setPrint)),
      body: AnimatedBuilder(
        animation: _loader,
        builder: (BuildContext context, Widget? child) {
          if (_loader.loading && _loader.value == null) {
            return const SkeletonList(count: 3, itemHeight: 140);
          }
          final PrintSettings? values = _loader.value;
          if (values == null) {
            return AppErrorView(
              message: _loader.errorText ?? l10n.commonErrorTitle,
              onRetry: _loader.refresh,
            );
          }
          _seed(values);
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 40),
            children: <Widget>[
              NoticeBanner(
                text: l10n.setPrintNote,
                color: AppInk.products,
                icon: Icons.print_outlined,
              ),
              const VGap(12),
              AppCard(
                accent: AppInk.products,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionHeader(title: l10n.setPrintTemplate, accent: AppInk.products),
                    PillTabs<String>(
                      values: const <String>['standard', 'compact'],
                      selected: _template,
                      accent: AppInk.products,
                      labelOf: (String v) => v == 'compact'
                          ? l10n.setPrintTemplateCompact
                          : l10n.setPrintTemplateStandard,
                      onChanged: (String v) => setState(() => _template = v),
                    ),
                    const VGap(6),
                    SwitchRow(
                      label: l10n.setPrintShowPrice,
                      value: _showPrice,
                      accent: AppInk.products,
                      onChanged: (bool v) => setState(() => _showPrice = v),
                    ),
                    SwitchRow(
                      label: l10n.setPrintShowSku,
                      value: _showSku,
                      accent: AppInk.products,
                      onChanged: (bool v) => setState(() => _showSku = v),
                    ),
                    SwitchRow(
                      label: l10n.setPrintShowImage,
                      value: _showImage,
                      accent: AppInk.products,
                      onChanged: (bool v) => setState(() => _showImage = v),
                    ),
                  ],
                ),
              ),
              const VGap(14),
              AppCard(
                accent: AppInk.products,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionHeader(title: l10n.setPrintHeader, accent: AppInk.products),
                    AppTextField(label: l10n.setPrintCompany, controller: _company),
                    const VGap(12),
                    AppTextField(label: l10n.setPrintContact, controller: _contact, maxLines: 2),
                    const VGap(12),
                    AppTextField(label: l10n.setPrintFooter, controller: _footer, maxLines: 2),
                    const VGap(12),
                    AppTextField(label: l10n.setPrintLogo, controller: _logo),
                  ],
                ),
              ),
              const VGap(18),
              PrimaryButton(
                label: _saving ? l10n.commonSaving : l10n.actSave,
                icon: Icons.check_rounded,
                color: AppInk.products,
                loading: _saving,
                onPressed: _app.canWrite && !_saving ? _save : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final L10n l10n = _app.l10n;
    final PrintSettings payload = PrintSettings(<String, Object?>{
      'template_id': _template,
      'company_name': _company.text.trim(),
      'contact_info': _contact.text.trim(),
      'footer_text': _footer.text.trim(),
      'logo_url': _logo.text.trim(),
      'show_price': _showPrice,
      'show_sku': _showSku,
      'show_image': _showImage,
    });
    setState(() => _saving = true);
    try {
      final PrintSettings saved = await _app.guardWrite<PrintSettings>(
        () => _app.repos.settings.savePrintSettings(payload),
      );
      if (!mounted) return;
      _seeded = false;
      _loader.value = saved;
      _seed(saved);
      setState(() => _saving = false);
      showToast(context, l10n.commonSaved);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }
}

/// 一行的开关：与 TileRow 同宽同高，走系统原生控件（iOS 上是 UISwitch）。
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent,
    this.note,
  });

  final String label;
  final String? note;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontSize: AppType.body)),
      subtitle: note == null ? null : Text(note!, style: const TextStyle(fontSize: AppType.micro)),
      contentPadding: EdgeInsets.zero,
      activeThumbColor: accent ?? AppInk.dashboard,
    );
  }
}

// ———————————————————————————————————————— API Key

/// 与服务端 `TENANT_SCOPES` 一一对应；勾选为空会被服务端直接拒。
const List<String> kTenantScopes = <String>[
  'products:read',
  'products:write',
  'inventory:read',
  'inventory:write',
  'categories:read',
  'categories:write',
  'orders:read',
  'orders:write',
  'showrooms:read',
  'showrooms:write',
  'customers:read',
  'customers:write',
  'finance:read',
  'finance:write',
  'marketplace:read',
  'marketplace:write',
];

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<ApiKey>> _rows =
      ValueLoader<List<ApiKey>>(() => _app.repos.settings.apiKeys());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setApiKeys)),
      floatingActionButton: _app.canWrite
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: AppInk.ai,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.key_rounded),
              label: Text(l10n.setKeyNew),
            )
          : null,
      body: _ListBody<ApiKey>(
        loader: _rows,
        emptyTitle: l10n.setKeyEmpty,
        emptyHint: l10n.setApiKeysNote,
        emptyIcon: Icons.key_rounded,
        accent: AppInk.ai,
        builder: (BuildContext context, List<ApiKey> rows) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 96),
          children: <Widget>[
            NoticeBanner(text: l10n.setApiKeysNote, color: AppInk.ai, icon: Icons.info_outline_rounded),
            const VGap(12),
            for (final ApiKey row in rows) _ApiKeyCard(row: row, onChanged: _rows.refresh),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final L10n l10n = _app.l10n;
    final TextEditingController name = TextEditingController();
    final Set<String> scopes = <String>{'products:read'};
    int validDays = 0;

    await showDrawer<void>(
      context,
      title: l10n.setKeyNew,
      accent: AppInk.ai,
      maxHeightFactor: 0.9,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter rebuild) => ListView(
          shrinkWrap: true,
          children: <Widget>[
            AppTextField(label: l10n.setKeyName, controller: name, autofocus: true),
            const VGap(14),
            Text(l10n.setKeyScopes, style: Theme.of(context).textTheme.titleMedium),
            const VGap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String scope in kTenantScopes)
                  _ScopeChip(
                    label: scope,
                    selected: scopes.contains(scope),
                    onTap: () => rebuild(() {
                      if (scopes.contains(scope)) {
                        scopes.remove(scope);
                      } else {
                        scopes.add(scope);
                      }
                    }),
                  ),
              ],
            ),
            const VGap(14),
            Text(l10n.setKeyValidity, style: Theme.of(context).textTheme.titleMedium),
            const VGap(6),
            PillTabs<int>(
              values: const <int>[0, 30, 90, 365],
              selected: validDays,
              accent: AppInk.ai,
              labelOf: (int v) => v == 0 ? l10n.commonNone : '$v${l10n.mpDaysSuffix}',
              onChanged: (int v) => rebuild(() => validDays = v),
            ),
            const VGap(16),
            PrimaryButton(
              label: l10n.actCreate,
              icon: Icons.add_rounded,
              color: AppInk.ai,
              onPressed: () async {
                final String trimmed = name.text.trim();
                if (trimmed.isEmpty) {
                  showToast(sheetContext, l10n.setKeyNameRequired);
                  return;
                }
                if (scopes.isEmpty) {
                  showToast(sheetContext, l10n.setKeyScopeRequired);
                  return;
                }
                final DateTime? expires =
                    validDays == 0 ? null : DateTime.now().add(Duration(days: validDays));
                await Navigator.of(sheetContext).maybePop();
                try {
                  final ApiKeyCreated created = await _app.guardWrite<ApiKeyCreated>(
                    () => _app.repos.settings.createApiKey(
                      name: trimmed,
                      scopes: scopes.toList(growable: false),
                      expiresAt: expires?.toUtc().toIso8601String(),
                    ),
                  );
                  if (!mounted) return;
                  await _rows.refresh();
                  if (!mounted) return;
                  await _showPlaintext(created.plaintext);
                } on Object catch (error) {
                  if (!mounted) return;
                  showToast(this.context, _app.describeError(error), danger: true);
                }
              },
            ),
            const VGap(8),
          ],
        ),
      ),
    );
    name.dispose();
  }

  Future<void> _showPlaintext(String plaintext) async {
    final L10n l10n = _app.l10n;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.setKeyCreated),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.setKeyOnceNote, style: const TextStyle(fontSize: AppType.foot, color: AppInk.warning)),
            const VGap(10),
            SelectableText(plaintext, style: const TextStyle(fontFamily: 'monospace', fontSize: AppType.foot)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: plaintext));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.actCopy),
          ),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.actDone)),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppInk.ai : AppInk.textTertiary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppInk.tint(color, alpha: selected ? 0.16 : 0.05),
          borderRadius: Radii.chip_,
          border: Border.all(color: selected ? color : AppInk.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.micro,
            fontWeight: AppType.semi,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ApiKeyCard extends StatelessWidget {
  const _ApiKeyCard({required this.row, required this.onChanged});

  final ApiKey row;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final bool dead = !row.active || row.isExpired;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RowCard(
        accent: dead ? AppInk.textTertiary : AppInk.ai,
        title: row.name,
        subtitle: '${row.display} · '
            '${row.lastUsedAt == null ? l10n.setKeyNeverUsed : app.l10n.elapsed(row.lastUsedAt)}',
        leading: const Icon(Icons.key_rounded, color: AppInk.ai),
        badges: <Widget>[
          for (final String scope in row.scopes.take(4))
            StatusPill(label: scope, color: AppInk.ai, dense: true),
          if (row.scopes.length > 4)
            StatusPill(label: '+${row.scopes.length - 4}', color: AppInk.textTertiary, dense: true),
          if (dead) StatusPill(label: l10n.setKeyRevoked, color: AppInk.danger, dense: true),
        ],
        trailing: RoundIconButton(
          icon: Icons.delete_outline_rounded,
          size: 34,
          color: AppInk.danger,
          tooltip: l10n.setRevoke,
          onPressed: () async {
            final bool sure = await confirmAction(
              context,
              title: l10n.setRevoke,
              message: l10n.setKeyRevokeConfirm(row.name),
              confirmLabel: l10n.actDelete,
              destructive: true,
            );
            if (!sure) return;
            try {
              await app.guardWrite<Object?>(() => app.repos.settings.removeApiKey(row.id));
              if (!context.mounted) return;
              showToast(context, l10n.commonDeleted);
              await onChanged();
            } on Object catch (error) {
              if (!context.mounted) return;
              showToast(context, app.describeError(error), danger: true);
            }
          },
        ),
      ),
    );
  }
}

// ———————————————————————————————————————— 数据清理（保留策略）

class RetentionScreen extends StatefulWidget {
  const RetentionScreen({super.key});

  @override
  State<RetentionScreen> createState() => _RetentionScreenState();
}

class _RetentionScreenState extends State<RetentionScreen> {
  late final AppState _app = context.read<AppState>();
  final TextEditingController _zero = TextEditingController();
  final TextEditingController _soft = TextEditingController();
  RetentionReport? _report;
  bool _busy = false;

  @override
  void dispose() {
    _zero.dispose();
    _soft.dispose();
    super.dispose();
  }

  Map<String, int?> get _window => <String, int?>{
        'zero': int.tryParse(_zero.text.trim()),
        'soft': int.tryParse(_soft.text.trim()),
      };

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    final RetentionReport? report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setRetention)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 40),
        children: <Widget>[
          NoticeBanner(text: l10n.setRetentionNote, color: AppInk.warning, icon: Icons.warning_amber_rounded),
          const VGap(12),
          AppCard(
            accent: AppInk.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(title: l10n.setRetentionPreview, accent: AppInk.warning),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: NumberField(
                        label: l10n.setRetentionZeroDays,
                        controller: _zero,
                        allowDecimal: false,
                        hint: l10n.commonNone,
                      ),
                    ),
                    const HGap(10),
                    Expanded(
                      child: NumberField(
                        label: l10n.setRetentionSoftDays,
                        controller: _soft,
                        allowDecimal: false,
                        hint: l10n.commonNone,
                      ),
                    ),
                  ],
                ),
                const VGap(14),
                PrimaryButton(
                  label: l10n.setRetentionPreview,
                  icon: Icons.visibility_outlined,
                  color: AppInk.warning,
                  loading: _busy,
                  onPressed: _busy ? null : _preview,
                ),
              ],
            ),
          ),
          if (report != null) ...<Widget>[
            const VGap(14),
            AppCard(
              accent: report.hasWork ? AppInk.danger : AppInk.finance,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(title: l10n.setRetentionResult, accent: AppInk.danger),
                  KeyValueRow(
                    label: l10n.setRetentionSoftDeleted,
                    value: Fmt.count(report.softDeletedCount),
                    accent: AppInk.warning,
                  ),
                  const VGap(10),
                  KeyValueRow(
                    label: l10n.setRetentionHardDeleted,
                    value: Fmt.count(report.hardDeletedCount),
                    accent: AppInk.danger,
                  ),
                  const VGap(10),
                  KeyValueRow(
                    label: l10n.setRetentionZeroDays,
                    value: '${report.zeroStockDays}${l10n.mpDaysSuffix}',
                    accent: AppInk.inventory,
                  ),
                  const VGap(10),
                  KeyValueRow(
                    label: l10n.setRetentionSoftDays,
                    value: '${report.softDeleteDays}${l10n.mpDaysSuffix}',
                    accent: AppInk.inventory,
                  ),
                  if (report.softDeleteCutoff != null) ...<Widget>[
                    const VGap(12),
                    Text(
                      '${l10n.setRetentionCutoff}: ${Fmt.dateTime(report.softDeleteCutoff)}',
                      style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
                    ),
                  ],
                  const VGap(16),
                  if (report.hasWork)
                    PrimaryButton(
                      label: l10n.setRetentionRun,
                      icon: Icons.cleaning_services_rounded,
                      color: AppInk.danger,
                      loading: _busy,
                      onPressed: _busy ? null : _run,
                    )
                  else
                    GhostButton(label: l10n.setRetentionNothing, onPressed: null),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final Map<String, int?> w = _window;
      final RetentionReport report = await _app.repos.products.retentionPreview(
        zeroStockDays: w['zero'],
        softDeleteDays: w['soft'],
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _run() async {
    final L10n l10n = _app.l10n;
    final RetentionReport? report = _report;
    if (report == null) return;
    final bool sure = await confirmAction(
      context,
      title: l10n.setRetentionRun,
      message: l10n.setRetentionRunConfirm(report.total),
      confirmLabel: l10n.actConfirm,
      destructive: true,
    );
    if (!sure) return;
    setState(() => _busy = true);
    try {
      final Map<String, int?> w = _window;
      final RetentionReport done = await _app.guardWrite<RetentionReport>(
        () => _app.repos.products.retentionCleanup(
          zeroStockDays: w['zero'],
          softDeleteDays: w['soft'],
        ),
      );
      if (!mounted) return;
      setState(() {
        _report = done;
        _busy = false;
      });
      showToast(context, l10n.setRetentionDone(done.total));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }
}

// ———————————————————————————————————————— 意见反馈

const List<String> kFeedbackCategories = <String>['bug', 'billing', 'marketplace', 'suggestion', 'other'];

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<FeedbackThread>> _rows =
      ValueLoader<List<FeedbackThread>>(() => _app.repos.settings.feedback());
  final TextEditingController _content = TextEditingController();
  String _category = 'bug';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setFeedback)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 40),
        children: <Widget>[
          AppCard(
            accent: AppInk.ai,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(title: l10n.setFeedback, subtitle: l10n.setFeedbackHint, accent: AppInk.ai),
                PillTabs<String>(
                  values: kFeedbackCategories,
                  selected: _category,
                  accent: AppInk.ai,
                  scrollable: true,
                  labelOf: (String v) => _categoryLabel(v, l10n),
                  onChanged: (String v) => setState(() => _category = v),
                ),
                const VGap(12),
                AppTextField(
                  label: l10n.setFeedbackContent,
                  controller: _content,
                  maxLines: 5,
                  hint: l10n.setFeedbackHint,
                ),
                const VGap(14),
                PrimaryButton(
                  label: l10n.setFeedbackSend,
                  icon: Icons.send_rounded,
                  color: AppInk.ai,
                  loading: _busy,
                  onPressed: _app.canWrite && !_busy ? _send : null,
                ),
              ],
            ),
          ),
          const VGap(16),
          _ListBody<FeedbackThread>(
            loader: _rows,
            emptyTitle: l10n.setFeedbackEmpty,
            emptyHint: l10n.setFeedbackHint,
            emptyIcon: Icons.chat_bubble_outline_rounded,
            accent: AppInk.ai,
            builder: (BuildContext context, List<FeedbackThread> rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.setFeedbackThreads, style: Theme.of(context).textTheme.titleMedium),
                const VGap(8),
                for (final FeedbackThread row in rows) _FeedbackCard(row: row),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final L10n l10n = _app.l10n;
    final String text = _content.text.trim();
    if (text.length < 5) {
      showToast(context, l10n.setFeedbackTooShort);
      return;
    }
    setState(() => _busy = true);
    try {
      await _app.guardWrite<Object?>(
        () => _app.repos.settings.submitFeedback(category: _category, content: text),
      );
      if (!mounted) return;
      _content.clear();
      setState(() => _busy = false);
      showToast(context, l10n.setFeedbackSent);
      await _rows.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  static String _categoryLabel(String category, L10n l10n) => switch (category) {
        'bug' => l10n.setFeedbackCatBug,
        'billing' => l10n.setFeedbackCatBilling,
        'marketplace' => l10n.setFeedbackCatMarketplace,
        'suggestion' => l10n.setFeedbackCatSuggestion,
        _ => l10n.setFeedbackCatOther,
      };
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.row});

  final FeedbackThread row;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RowCard(
        accent: row.answered ? AppInk.finance : AppInk.ai,
        title: row.content,
        subtitle: '${_FeedbackScreenState._categoryLabel(row.category, l10n)} · ${app.l10n.elapsed(row.createdAt)}',
        badges: <Widget>[
          if (row.mine) StatusPill(label: l10n.setFeedbackMine, color: AppInk.info, dense: true),
          StatusPill(
            label: row.answered ? l10n.setFeedbackAnswered : l10n.setFeedbackOpen,
            color: row.answered ? AppInk.finance : AppInk.textTertiary,
            dense: true,
          ),
        ],
        footRow: row.answered
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppInk.tint(AppInk.finance, alpha: 0.08),
                  borderRadius: Radii.chip_,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.setFeedbackReply,
                        style: const TextStyle(fontSize: AppType.micro, color: AppInk.finance)),
                    const VGap(4),
                    Text(row.reply, style: const TextStyle(fontSize: AppType.foot)),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

// ———————————————————————————————————————— 共用列表容器

/// 一个 `ValueLoader<List<T>>` 的四态展示：骨架 / 失败 / 空 / 内容。
class _ListBody<T> extends StatelessWidget {
  const _ListBody({
    required this.loader,
    required this.builder,
    required this.emptyTitle,
    this.emptyHint,
    this.emptyIcon,
    this.accent,
  });

  final ValueLoader<List<T>> loader;
  final Widget Function(BuildContext, List<T>) builder;
  final String emptyTitle;
  final String? emptyHint;
  final IconData? emptyIcon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(Localizations.localeOf(context));
    return AnimatedBuilder(
      animation: loader,
      builder: (BuildContext context, Widget? child) {
        if (loader.loading && loader.value == null) return const SkeletonList();
        final List<T>? rows = loader.value;
        if (rows == null) {
          return AppErrorView(
            message: loader.errorText ?? l10n.commonErrorTitle,
            onRetry: loader.refresh,
          );
        }
        if (rows.isEmpty) {
          return AppEmpty(
            title: emptyTitle,
            hint: emptyHint,
            icon: emptyIcon ?? Icons.inbox_rounded,
            accent: accent,
          );
        }
        return builder(context, rows);
      },
    );
  }
}

/// 邀请码只允许大写字母与数字，边打边折叠大小写。
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      TextEditingValue(
        text: newValue.text.toUpperCase(),
        selection: newValue.selection,
        composing: TextRange.empty,
      );
}
