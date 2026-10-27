import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 只读离线缓存。
///
/// 契约只允许"读"降级到缓存：断网时写操作一律禁用并提示，不排队、不补发。
/// 换账号 / 换租户必须整目录清空（同一台设备可能登录不同租户）。
class OfflineCache {
  OfflineCache._();

  static final OfflineCache instance = OfflineCache._();

  Directory? _root;
  String? _tenantScope;

  Future<void> useTenant(String? tenantId) async {
    final String scope = tenantId == null || tenantId.isEmpty ? 'anonymous' : tenantId;
    if (_tenantScope == scope && _root != null) return;
    _tenantScope = scope;
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/kucun_cache/$scope');
    await dir.create(recursive: true);
    _root = dir;
  }

  File _fileFor(String key) {
    final String name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${_root!.path}/$name.json');
  }

  bool get ready => _root != null;

  Future<void> write(String key, Object payload) async {
    if (_root == null) return;
    try {
      await _fileFor(key).writeAsString(jsonEncode(payload), flush: true);
    } on Object {
      // 缓存写失败不影响主流程。
    }
  }

  Future<Map<String, Object?>> read(String key) async {
    if (_root == null) return <String, Object?>{};
    try {
      final File file = _fileFor(key);
      if (!await file.exists()) return <String, Object?>{};
      final Object? decoded = jsonDecode(await file.readAsString());
      final DateTime stamp = file.statSync().modified;
      if (decoded is Map<String, Object?>) {
        return <String, Object?>{'payload': decoded, 'stamp': stamp.toIso8601String()};
      }
      return <String, Object?>{'payload': decoded, 'stamp': stamp.toIso8601String()};
    } on Object {
      return <String, Object?>{};
    }
  }

  /// 跨租户残留的清理入口。
  Future<void> dropAll() async {
    if (_root == null) return;
    try {
      await _root!.delete(recursive: true);
    } on Object {
      // 已被删除或不可写都视为已清理。
    }
    _root = null;
    _tenantScope = null;
  }
}
