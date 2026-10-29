import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/data/profile.dart';

/// 「我的」顶上的续费位什么时候该出现，口径跟着服务端走：
/// `getExpiresInDays`（tenants.js:55，向上取整）+ `expiring_30d`（finance.js:327，0–30 天）。
void main() {
  group('到期天数与续费提示', () {
    test('永久租户没有天数，也不提示续费', () {
      final UserProfile profile = UserProfile(<String, Object?>{'role': 'tenant_admin'});
      expect(profile.daysUntilExpiry, isNull);
      expect(profile.expiringSoon, isFalse);
      expect(profile.shouldPromptRenewal, isFalse);
    });

    test('还剩大半年时这一页不摆付费位', () {
      final UserProfile profile = _profile(daysFromNow: 210);
      expect(profile.daysUntilExpiry, 210);
      expect(profile.expiringSoon, isFalse);
      expect(profile.shouldPromptRenewal, isFalse);
    });

    test('第 30 天开始提示，31 天不提示（不足一天算一天）', () {
      expect(_profile(daysFromNow: 30).daysUntilExpiry, 30);
      expect(_profile(daysFromNow: 30).expiringSoon, isTrue);
      expect(_profile(daysFromNow: 30.5).daysUntilExpiry, 31);
      expect(_profile(daysFromNow: 30.5).shouldPromptRenewal, isFalse);
      expect(_profile(daysFromNow: 0.5).expiringSoon, isTrue);
    });

    test('已到期：天数走成负数，靠服务端的 expired 标记提示', () {
      final UserProfile profile = _profile(daysFromNow: -3, expired: true);
      expect(profile.daysUntilExpiry, isNegative);
      expect(profile.expiringSoon, isFalse);
      expect(profile.shouldPromptRenewal, isTrue);
    });

    test('超管不受到期约束（服务端也从不给他打 expired）', () {
      expect(_profile(daysFromNow: 5, expired: true, role: 'super_admin').shouldPromptRenewal, isFalse);
    });
  });
}

UserProfile _profile({
  required double daysFromNow,
  bool expired = false,
  String role = 'tenant_admin',
}) {
  final DateTime expires =
      DateTime.now().add(Duration(milliseconds: (daysFromNow * 24 * 60 * 60 * 1000).round()));
  return UserProfile(<String, Object?>{
    'role': role,
    'subscription_expired': expired,
    'tenant_expires_at': expires.toUtc().toIso8601String(),
  });
}
