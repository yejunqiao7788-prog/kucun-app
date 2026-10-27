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

  DateTime? get updatedAt => asDate('updated_at');
}
