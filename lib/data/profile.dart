import 'json_map.dart';

/// `GET /api/business/me` → `data.profile`。
///
/// `currency_symbol` 服务端兜底是 `$`（不是 ₴），金额一律取这个字段。
class UserProfile extends JsonMap {
  const UserProfile(super.json);

  static const UserProfile none = UserProfile(<String, Object?>{});

  factory UserProfile.fromData(Object? envelopeData) {
    if (envelopeData is Map) {
      final JsonMap outer = JsonMap.from(envelopeData);
      return UserProfile(outer.asMap('profile').json);
    }
    return UserProfile(<String, Object?>{});
  }

  String get id => asStringOr('id', '');
  String get email => asStringOr('email', '');
  String? get username => asString('username');
  String get displayName =>
      (username != null && username!.isNotEmpty) ? username! : email;
  String? get avatarUrl => asString('avatar_url');

  String get tenantId => asStringOr('tenant_id', '');
  String get tenantName => asStringOr('tenant_name', '未命名租户');
  DateTime? get tenantExpiresAt => asDate('tenant_expires_at');

  String get role => asStringOr('role', 'user');
  String get status => asStringOr('status', 'pending');
  bool get isSuperAdmin => role == 'super_admin';
  bool get isActive => status == 'active';

  String get subscriptionStatus => asStringOr('subscription_status', 'trial');
  bool get subscriptionExpired => asBool('subscription_expired');

  Map<String, bool> get permissions => asBoolMap('permissions');

  String get currencySymbol =>
      (asString('currency_symbol')?.isNotEmpty ?? false)
          ? asString('currency_symbol')!
          : r'$';

  /// 到期时工作台/商品/订单等全部锁死，只剩设置里的续费与反馈。
  bool get needsRenewal => subscriptionExpired && !isSuperAdmin;

  /// 距到期还有几天，算法与服务端 `getExpiresInDays` 一致（不足一天算一天，向上取整）。
  /// `tenant_expires_at` 为空就是永久租户，返回 null。
  int? get daysUntilExpiry {
    final DateTime? at = tenantExpiresAt;
    if (at == null) return null;
    return (at.difference(DateTime.now()).inMilliseconds / _msPerDay).ceil();
  }

  /// 服务端把「0–30 天内到期」当作 `expiring_30d`（超管财务看板那条 expiring 线就是它），
  /// 「我的」里提前露出续费入口沿用同一个口径，免得两边对「快到期」各说一套。
  bool get expiringSoon {
    final int? days = daysUntilExpiry;
    return days != null && days >= 0 && days <= 30;
  }

  /// 「我的」顶上的续费位什么时候出现：超管永不到期（服务端也不会给他打 expired 标记），
  /// 其余按服务端 `expiring_30d` 那一条线 —— 已到期或 30 天内到期。
  bool get shouldPromptRenewal => !isSuperAdmin && (subscriptionExpired || expiringSoon);

  DateTime? get updatedAt => asDate('updated_at');
}

const double _msPerDay = 24 * 60 * 60 * 1000;
