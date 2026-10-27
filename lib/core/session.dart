import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// 会话韧性层。
///
/// 现网踩过的坑：移动端切后台会挂起定时器，GoTrue 自带的自动刷新因此失效。
/// 所以这里自己掌握三件事 —— 回前台立刻校验、前台期间心跳校验、并发 401 只刷新一次。
class SessionManager {
  SessionManager();

  final List<void Function()> _listeners = <void Function()>[];
  Completer<Session?>? _refreshInFlight;
  Timer? _heartbeat;
  DateTime _lastEnsureAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _refreshSkew = Duration(minutes: 5);
  static const Duration _heartbeatInterval = Duration(minutes: 5);
  static const Duration _ensureCooldown = Duration(seconds: 20);

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Session? get session => _auth.currentSession;
  String? get accessToken => _auth.currentSession?.accessToken;
  bool get isSignedIn => _auth.currentSession != null;

  void addListener(void Function() callback) => _listeners.add(callback);

  void removeListener(void Function() callback) => _listeners.remove(callback);

  void _notify() {
    for (final void Function() listener in _listeners) {
      listener();
    }
  }

  /// 前台心跳；后台时挂起，避免和系统节流抢跑。
  void startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(ensureSession(force: true));
    });
  }

  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void onResumed() {
    unawaited(ensureSession(force: true));
  }

  Future<Session?> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    startHeartbeat();
    _notify();
    return response.session;
  }

  Future<void> signOut() async {
    stopHeartbeat();
    await _auth.signOut();
    _notify();
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim());

  /// 取一个"确定还活着"的 token。临近过期就刷新，多个调用者共享同一次刷新。
  Future<String?> ensureSession({bool force = false}) async {
    final Session? current = _auth.currentSession;
    if (current == null) return null;

    final int? expiresAt = current.expiresAt; // unix 秒
    final bool healthy = expiresAt != null &&
        DateTime.now()
            .add(_refreshSkew)
            .isBefore(DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000));
    if (healthy && !force) {
      return current.accessToken;
    }
    if (!force &&
        DateTime.now().difference(_lastEnsureAt) < _ensureCooldown &&
        _refreshInFlight == null) {
      // 冷却期内重复触发不硬刷，交给 401 兜底重试。
      return _auth.currentSession?.accessToken;
    }

    if (_refreshInFlight != null) {
      return (await _refreshInFlight!.future)?.accessToken;
    }

    final Completer<Session?> flight = Completer<Session?>();
    _refreshInFlight = flight;
    _lastEnsureAt = DateTime.now();
    try {
      final AuthResponse response = await _auth.refreshSession();
      final Session? refreshed = response.session ?? _auth.currentSession;
      flight.complete(refreshed);
      _notify();
      return refreshed?.accessToken;
    } on Object {
      // 刷新失败即清会话，绝不静默重登（可能已经换人使用设备）。
      flight.complete(null);
      stopHeartbeat();
      unawaited(_auth.signOut());
      _notify();
      return null;
    } finally {
      _refreshInFlight = null;
    }
  }

  void dispose() {
    stopHeartbeat();
    _listeners.clear();
  }
}
