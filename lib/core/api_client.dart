import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'env.dart';
import 'offline_cache.dart';
import 'session.dart';

/// 一次读请求的结果。`stale` 为真表示这份数据来自离线缓存，界面必须挂"可能不是最新"横幅。
class ApiResponse<T> {
  ApiResponse({
    required this.data,
    this.stale = false,
    this.cachedAt,
    this.requestId,
  });

  final T data;
  final bool stale;
  final DateTime? cachedAt;
  final String? requestId;
}

/// `/api/business/*` 的唯一出口。
///
/// 守住的契约：只读 `error.code` 分支；GET 幂等才退避重试；写操作不自动重试；
/// 401 刷新一次并重放原请求；并发 401 共用同一次刷新。
class ApiClient {
  ApiClient({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  final SessionManager session;
  final http.Client _client;
  final Random _random = Random();

  /// 由请求结果反推网络状态，省掉一个 connectivity 插件的原生配置面。
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  static const int _maxGetAttempts = 3;

  String _newRequestId() {
    final int seed = DateTime.now().microsecondsSinceEpoch;
    final String suffix =
        _random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return '${seed.toRadixString(16)}-$suffix';
  }

  Uri _uri(String path, Map<String, Object?>? query) {
    final Map<String, String> normalized = <String, String>{};
    query?.forEach((String key, Object? value) {
      if (value == null) return;
      if (value is bool) {
        normalized[key] = value ? 'true' : 'false';
      } else if (value is List) {
        normalized[key] = value.join(',');
      } else {
        normalized[key] = '$value';
      }
    });
    return Uri.parse('${Env.apiBase}$path')
        .replace(queryParameters: normalized.isEmpty ? null : normalized);
  }

  Future<ApiResponse<Object?>> get(
    String path, {
    Map<String, Object?>? query,
    String? tenantId,
    bool heavy = false,
    bool cache = true,
  }) async {
    final Map<String, Object?> withTenant = <String, Object?>{
      if (query != null) ...query,
      if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
    };
    final Uri uri = _uri(path, withTenant);
    final String cacheKey = 'GET ${uri.toString()}';

    ApiException? lastError;
    for (int attempt = 0; attempt < _maxGetAttempts; attempt++) {
      try {
        final Object? data = await _send(
          'GET',
          uri,
          timeout: heavy ? Env.heavyTimeout : Env.normalTimeout,
        );
        online.value = true;
        if (cache) {
          unawaited(OfflineCache.instance.write(
            cacheKey,
            <String, Object?>{'data': data},
          ));
        }
        return ApiResponse<Object?>(data: data);
      } on ApiException catch (error) {
        lastError = error;
        if (!error.retryable) break;
        if (error.isNetworkFailure) online.value = false;
        if (attempt < _maxGetAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (1 << attempt)),
          );
        }
      }
    }

    if (lastError != null && lastError.isNetworkFailure && cache) {
      online.value = false;
      final Map<String, Object?> hit =
          await OfflineCache.instance.read(cacheKey);
      final Object? wrapped = hit['payload'];
      if (wrapped is Map<String, Object?> && wrapped.containsKey('data')) {
        return ApiResponse<Object?>(
          data: wrapped['data'],
          stale: true,
          cachedAt: DateTime.tryParse('${hit['stamp']}'),
        );
      }
    }
    throw lastError ??
        ApiException(
          status: 500,
          code: 'FETCH_ERROR',
          serverMessage: '未知错误',
        );
  }

  Future<Object?> post(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    String? tenantId,
    bool heavy = false,
  }) =>
      _write('POST', path, body, query, tenantId, heavy);

  Future<Object?> patch(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    String? tenantId,
    bool heavy = false,
  }) =>
      _write('PATCH', path, body, query, tenantId, heavy);

  Future<Object?> delete(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    String? tenantId,
  }) =>
      _write('DELETE', path, body, query, tenantId, false);

  Future<Object?> _write(
    String method,
    String path,
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    String? tenantId,
    bool heavy,
  ) async {
    final bool hasTenantInBody = body?.containsKey('tenant_id') ?? false;
    final Map<String, Object?> payload = <String, Object?>{
      if (body != null) ...body,
      if (!hasTenantInBody && tenantId != null && tenantId.isNotEmpty)
        'tenant_id': tenantId,
    };
    final Uri uri = _uri(path, query);
    try {
      final Object? data = await _send(
        method,
        uri,
        body: payload,
        timeout: heavy ? Env.heavyTimeout : Env.normalTimeout,
      );
      online.value = true;
      return data;
    } on ApiException catch (error) {
      if (error.isNetworkFailure) online.value = false;
      rethrow;
    }
  }

  /// 发一次请求，必要时在 401 后刷新会话并重放一次。
  Future<Object?> _send(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    required Duration timeout,
    bool allowRetryOn401 = true,
  }) async {
    final String? token = await session.ensureSession();
    if (token == null) {
      throw ApiException(
        status: 401,
        code: 'UNAUTHORIZED',
        serverMessage: '会话已失效，请重新登录',
      );
    }

    late http.Response response;
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(<String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Request-Id': _newRequestId(),
        });
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        status: 0,
        code: 'TIMEOUT',
        serverMessage: '请求超时，服务可能正在冷启动',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        status: 0,
        code: 'NETWORK',
        serverMessage: '网络不可用：$error',
      );
    } on Object {
      throw ApiException(
        status: 0,
        code: 'NETWORK',
        serverMessage: '网络不可用',
      );
    }

    final Map<String, Object?> envelope = _decodeEnvelope(response);

    if (response.statusCode == 401 && allowRetryOn401) {
      // 刷新一次再重放原请求；SessionManager 内部已做并发去重。
      final String? refreshed = await session.ensureSession(force: true);
      if (refreshed != null) {
        return _send(
          method,
          uri,
          body: body,
          timeout: timeout,
          allowRetryOn401: false,
        );
      }
      throw ApiException(
        status: 401,
        code: 'UNAUTHORIZED',
        serverMessage: '会话已失效，请重新登录',
      );
    }

    final bool okFlag = envelope['ok'] == true;
    if (!okFlag) {
      final Object? errorPart = envelope['error'];
      final Map<String, Object?> errorMap = _asStringMap(errorPart);
      final Object? meta = envelope['meta'];
      throw ApiException(
        status: response.statusCode,
        code: '${errorMap['code'] ?? 'HTTP_${response.statusCode}'}',
        serverMessage: '${errorMap['message'] ?? response.body}',
        details: errorMap['details'],
        requestId: meta is Map ? meta['requestId'] as String? : null,
      );
    }

    final Object? meta = envelope['meta'];
    final String? requestId =
        meta is Map ? meta['requestId'] as String? : null;
    final Object? data = envelope['data'];
    if (requestId != null && kDebugMode) {
      debugPrint('[api] $method $uri → ${response.statusCode} req=$requestId');
    }
    return data;
  }

  Map<String, Object?> _decodeEnvelope(http.Response response) {
    final String raw = utf8.decode(response.bodyBytes);
    if (raw.trimLeft().startsWith('<')) {
      // 代理/网关直接回 HTML：不是业务信封，按上游故障处理。
      throw ApiException(
        status: response.statusCode,
        code: response.statusCode == 401 ? 'UNAUTHORIZED' : 'FETCH_ERROR',
        serverMessage: '网关返回了非预期响应（HTTP ${response.statusCode}）',
      );
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _asStringMap(decoded);
      }
      return <String, Object?>{'ok': true, 'data': decoded};
    } on Object {
      throw ApiException(
        status: response.statusCode,
        code: 'FETCH_ERROR',
        serverMessage: '响应解析失败（HTTP ${response.statusCode}）',
      );
    }
  }

  static Map<String, Object?> _asStringMap(Object? source) {
    if (source is Map) {
      return source.map(
        (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
      );
    }
    return <String, Object?>{};
  }

  void dispose() {
    _client.close();
    online.dispose();
  }
}
