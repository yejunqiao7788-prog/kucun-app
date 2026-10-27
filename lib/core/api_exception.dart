/// 服务端信封 `error.code` 是唯一分支依据；`message` 只是中文展示文案。
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.serverMessage,
    this.details,
    this.requestId,
  });

  final int status;
  final String code;
  final String serverMessage;
  final Object? details;
  final String? requestId;

  /// 订阅到期（402）：除 设置/反馈/续费/看余额 之外都应跳续费引导。
  bool get isSubscriptionExpired =>
      status == 402 || code == 'SUBSCRIPTION_EXPIRED';

  /// 会话失效（401）：刷新一次再重试，刷新失败即清会话。
  bool get isUnauthorized => status == 401 || code == 'UNAUTHORIZED';

  /// 权限缺口：以服务端结果为准，不在 App 里按角色字符串推断。
  bool get isPermissionDenied => const {
        'FORBIDDEN',
        'TENANT_FORBIDDEN',
        'ADMIN_FORBIDDEN',
      }.contains(code);

  bool get isRateLimited => status == 429 || code == 'RATE_LIMITED';
  bool get isNotFound => status == 404 || code == 'NOT_FOUND';
  bool get isUpstreamFailure => const {
        'DB_ERROR',
        'FETCH_ERROR',
        'CREATE_ERROR',
        'DELETE_ERROR',
      }.contains(code);
  bool get isDuplicateSku => code == 'DUPLICATE_SKU';
  bool get isNetworkFailure =>
      code == 'NETWORK' || code == 'TIMEOUT' || code == 'CANCELLED';

  /// GET 幂等可退避重试；写操作默认不重试（502 可能已写成功）。
  bool get retryable =>
      isNetworkFailure || isRateLimited || isUpstreamFailure || status >= 500;

  /// 直接原样展示的错误（含「库存不足：名称 / SKU（需要 N，现有 M）」这类四要素文案）。
  String get display => serverMessage;

  @override
  String toString() => 'ApiException($status $code): $serverMessage';
}
