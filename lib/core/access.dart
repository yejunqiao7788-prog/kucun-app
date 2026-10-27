import '../data/profile.dart';

/// 九个模块的入口可见性。必须与服务端一致，但**服务端才是真闸门**：
/// 403 一律按无权限处理，App 不凭角色字符串自行推断（契约 §4.8）。
enum ModuleKey {
  dashboard,
  products,
  inventory,
  orders,
  showroom,
  marketplace,
  finance,
  ai,
  settings,
}

class Access {
  const Access._();

  /// 服务端 `PERMISSION_KEYS` 的八把键（`reports` 为历史遗留，无对应模块）。
  static const List<String> permissionKeys = <String>[
    'dashboard',
    'products',
    'inventory',
    'orders',
    'showrooms',
    'ai',
    'reports',
    'finance',
  ];

  static const List<String> adminRoles = <String>[
    'super_admin',
    'admin',
    'tenant_admin',
  ];

  /// 集市门单独一支：放行角色多一个 `owner`，与 `hasBusinessPermission` 不同。
  static const List<String> marketplaceRoles = <String>[
    'super_admin',
    'admin',
    'owner',
    'tenant_admin',
  ];

  static bool isAdmin(UserProfile? profile) =>
      profile != null && adminRoles.contains(profile.role);

  static bool hasPermission(UserProfile? profile, String key) {
    if (profile == null) return false;
    if (profile.role == 'super_admin') return true;
    if (profile.subscriptionExpired) return false;
    if (profile.role == 'admin') return true;
    return profile.permissions[key] == true;
  }

  static bool canOpen(UserProfile? profile, ModuleKey key) {
    if (profile == null) return false;
    switch (key) {
      case ModuleKey.settings:
        // 设置对任何登录用户开放：到期租户的续费与反馈都在这里。
        return true;
      case ModuleKey.showroom:
        return hasPermission(profile, 'showrooms');
      case ModuleKey.ai:
        return hasPermission(profile, 'ai') ||
            (!profile.permissions.containsKey('ai') &&
                profile.permissions['dashboard'] == true);
      case ModuleKey.marketplace:
        if (profile.subscriptionExpired) return false;
        return marketplaceRoles.contains(profile.role);
      case ModuleKey.dashboard:
      case ModuleKey.products:
      case ModuleKey.inventory:
      case ModuleKey.orders:
      case ModuleKey.finance:
        return hasPermission(profile, key.wireKey);
    }
  }
}

extension ModuleKeyWire on ModuleKey {
  String get wireKey => name;
}
