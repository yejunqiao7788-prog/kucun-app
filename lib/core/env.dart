/// 生产环境常量。
///
/// anon key 是 Supabase 的公开匿名 key（与网页端构建产物里的那一枚相同），
/// 权限由数据库 RLS 与服务端 `assertTenant` 把关，不靠这串字符保密。
/// 服务端密钥（`service_role`、`yb_live_…`、支付与 AI 密钥）永远不进 App。
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rmpprdxcrrbxkcoigcoo.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtcHByZHhjcnJieGtjb2lnY29vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc2NTkzNzcsImV4cCI6MjA5MzIzNTM3N30.7vSgFldLFumMIktlWLxoFS_YsrZ5bD277IddB2vCGNc',
  );

  /// 库存端只用 `business.js` 这一支函数。
  static const String apiBase = String.fromEnvironment(
    'BUSINESS_API_BASE',
    defaultValue: 'https://app.torgseek.com/api/business',
  );

  /// 公域域名：展厅 `/s/:token`、集市 `/market/p/:slug` 都指向 `www.`，不是 `app.`。
  static const String siteBase = String.fromEnvironment(
    'PUBLIC_SITE_URL',
    defaultValue: 'https://www.torgseek.com',
  );

  /// 网页端控制台：App 内做不了 IAP 的订阅/充值动作跳这里。
  static const String consoleBase = String.fromEnvironment(
    'PUBLIC_APP_URL',
    defaultValue: 'https://app.torgseek.com',
  );

  static const String publicImagesBucket = 'product-images';
  static const String privateAssetsBucket = 'mp-assets';

  static const Duration normalTimeout = Duration(seconds: 30);
  static const Duration heavyTimeout = Duration(seconds: 60);

  static const String appName = 'TorgSeek库存';
  // 改版本号时和 pubspec.yaml 的 version 一起改，设置页底部读的是这里。
  static const String appVersion = '2.1.9';
}
