import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/access.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/env.dart';
import '../core/formatters.dart';
import '../core/l10n.dart';
import '../core/offline_cache.dart';
import '../core/session.dart';
import '../core/storage_service.dart';
import '../data/profile.dart';
import '../data/repositories.dart';

enum ThemeChoice { system, light, dark }

/// 全局应用状态：会话 + 租户画像 + 可达性 + 偏好。
///
/// 三条硬规矩：
/// 1. 租户 id 只从 `GET /me` 取，客户端不猜；
/// 2. 权限以服务端为准，App 只做入口显隐；
/// 3. 离线只读，写操作一律关掉（不排队、不补发）。
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState._();

  static Future<AppState> bootstrap() async {
    // 只在 main() 里调一次：GoTrue 的 initialize 二次调用会直接断言失败。
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      debug: false,
    );
    final AppState state = AppState._();
    await state._start();
    return state;
  }

  static AppState of(BuildContext context) => Provider.of<AppState>(context);

  late final SessionManager session = SessionManager();
  late final ApiClient api = ApiClient(session: session);
  late final StorageService storage = StorageService(session);
  late final Repos repos = Repos(api, () => profile.tenantId);

  UserProfile profile = UserProfile.none;
  ThemeChoice themeChoice = ThemeChoice.system;
  Locale? localeOverride;
  bool booting = true;
  bool signedIn = false;
  bool profileLoading = false;
  String? bootError;

  /// 402 时全局挂起经营模块，只留设置里的续费与反馈。
  bool renewalPending = false;

  bool get online => api.online.value;
  bool get isAdmin => Access.isAdmin(profile);
  bool get canWrite => online && session.isSignedIn;
  L10n get l10n => L10n.of(localeOverride ?? WidgetsBinding.instance.platformDispatcher.locale);

  Future<void> _start() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedLang = prefs.getString('kucun.lang');
    if (savedLang != null) localeOverride = Locale(savedLang);
    final int themeIndex = prefs.getInt('kucun.theme') ?? ThemeChoice.system.index;
    themeChoice = ThemeChoice.values[themeIndex.clamp(0, ThemeChoice.values.length - 1)];

    signedIn = session.isSignedIn;
    await OfflineCache.instance.useTenant(null);
    api.online.addListener(_onConnectivityChanged);
    session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    if (signedIn) {
      session.startHeartbeat();
      await loadProfile();
    }
    booting = false;
    notifyListeners();
  }

  void _onConnectivityChanged() => notifyListeners();

  void _onSessionChanged() {
    signedIn = session.isSignedIn;
    if (!signedIn) {
      profile = UserProfile.none;
      renewalPending = false;
      unawaited(OfflineCache.instance.dropAll());
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      session.onResumed();
    }
  }

  // ---------------------------------------------------------------- 会话

  Future<void> signIn({required String email, required String password}) async {
    await session.signIn(email: email, password: password);
    signedIn = true;
    bootError = null;
    notifyListeners();
    await loadProfile();
  }

  Future<void> signOut() async {
    await session.signOut();
    await OfflineCache.instance.dropAll();
    profile = UserProfile.none;
    signedIn = false;
    renewalPending = false;
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) => session.sendPasswordReset(email);

  /// 自助注册：建租户 + 管理员账号一步到位（契约 §5.2）。
  Future<void> registerTenant({
    required String email,
    required String password,
    required String username,
    required String tenantName,
  }) async {
    await api.post(
      '/register',
      body: <String, Object?>{
        'email': email.trim(),
        'password': password,
        'username': username.trim(),
        'tenant_name': tenantName.trim(),
      },
    );
    await signIn(email: email, password: password);
  }

  /// 邀请链路：先查邀请拿租户名，再注册并落到该租户。
  Future<UserProfile> lookupInvitation(String code) async {
    final Object? data = await api.post(
      '/invitations/lookup',
      body: <String, Object?>{'code': code.trim()},
    );
    return UserProfile.fromData(data);
  }

  Future<void> registerByInvitation({
    required String code,
    required String email,
    required String password,
    required String username,
  }) async {
    await api.post(
      '/invitations/register',
      body: <String, Object?>{
        'code': code.trim(),
        'email': email.trim(),
        'password': password,
        'username': username.trim(),
      },
    );
    await signIn(email: email, password: password);
  }

  // ---------------------------------------------------------------- 画像

  Future<void> loadProfile() async {
    profileLoading = true;
    bootError = null;
    notifyListeners();
    try {
      final Object? data = await api.get('/me', cache: false).then((ApiResponse<Object?> r) => r.data);
      profile = UserProfile.fromData(data);
      await OfflineCache.instance.useTenant(profile.tenantId);
      renewalPending = profile.needsRenewal;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await signOut();
        bootError = l10n.authSignedOutElsewhere;
      } else if (error.isSubscriptionExpired) {
        renewalPending = true;
      } else {
        bootError = describeError(error);
      }
    } on Object {
      bootError = l10n.commonErrorTitle;
    } finally {
      profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfileQuietly() async {
    if (!session.isSignedIn) return;
    try {
      final Object? data = await api
          .get('/me', tenantId: profile.tenantId.isEmpty ? null : profile.tenantId, cache: false)
          .then((ApiResponse<Object?> r) => r.data);
      profile = UserProfile.fromData(data);
      renewalPending = profile.needsRenewal;
      notifyListeners();
    } on ApiException catch (error) {
      if (error.isSubscriptionExpired) {
        renewalPending = true;
        notifyListeners();
      } else if (error.isUnauthorized) {
        await signOut();
      }
    }
  }

  bool canOpenModule(ModuleKey key) {
    if (renewalPending && key != ModuleKey.settings) return false;
    return Access.canOpen(profile, key);
  }

  // ---------------------------------------------------------------- 偏好

  Future<void> setLanguage(String code) async {
    localeOverride = Locale(code);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('kucun.lang', code);
    notifyListeners();
  }

  /// 跟随系统是一次性的，不写盘（契约 §5.6）。
  Future<void> followSystemLanguage() async {
    localeOverride = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('kucun.lang');
    notifyListeners();
  }

  Future<void> setThemeChoice(ThemeChoice choice) async {
    themeChoice = choice;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kucun.theme', choice.index);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 错误

  /// 唯一的服务端错误出口：401 清会话、402 跳续费、其余原样展示服务端文案。
  String describeError(Object error) {
    if (error is ApiException) {
      if (error.isUnauthorized) {
        unawaited(signOut());
        return l10n.authSignedOutElsewhere;
      }
      if (error.isSubscriptionExpired) {
        renewalPending = true;
        notifyListeners();
        return l10n.commonExpiredBanner;
      }
      if (error.isRateLimited) return l10n.commonRateLimited;
      if (error.isNetworkFailure && !online) return l10n.commonOfflineBanner;
      if (error.isDuplicateSku) return l10n.prodSkuDuplicate;
      return error.display;
    }
    if (error is StorageFailure) return error.message;
    return '$error';
  }

  /// 写操作统一入口：离线直接挡掉，不回排队列。
  Future<T> guardWrite<T>(Future<T> Function() action) async {
    if (!canWrite) {
      throw ApiException(
        status: 0,
        code: 'OFFLINE',
        serverMessage: l10n.setWriteBlockedOffline,
      );
    }
    return action();
  }

  String formatMoney(num amount) => Fmt.money(amount, symbol: profile.currencySymbol);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    api.online.removeListener(_onConnectivityChanged);
    session.dispose();
    api.dispose();
    super.dispose();
  }
}
