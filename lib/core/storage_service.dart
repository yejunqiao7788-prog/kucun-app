import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'session.dart';

/// 图片与附件上传。
///
/// 契约硬约束：商品图只能落在公开桶 `product-images`，路径第一级必须是租户 id；
/// 集市资质文件落私有桶 `mp-assets`，只回签名 URL。业务 API 只收 URL 字符串，
/// 客户端不能自造桶名，也不能把 base64 直接塞进 `image_urls`。
class StorageService {
  StorageService(this.session);

  final SessionManager session;

  SupabaseStorageClient get _storage => Supabase.instance.client.storage;

  /// 同一张图重复上传会各占一份，用内容指纹 + 时间戳避免覆盖与撞名。
  String buildImagePath({
    required String tenantId,
    required String fileName,
    int? sequence,
  }) {
    final String ext = _extensionOf(fileName);
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final String suffix = session.accessToken
        .toString()
        .codeUnits
        .fold<int>(stamp, (int acc, int unit) => acc * 31 + unit)
        .toRadixString(36);
    final String tag = sequence == null ? '' : '-$sequence';
    return '$tenantId/img-$stamp$tag-$suffix.$ext';
  }

  Future<String> uploadProductImage({
    required String tenantId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/jpeg',
    int? sequence,
  }) async {
    if (tenantId.isEmpty) {
      throw const StorageFailure('缺少租户，无法上传图片');
    }
    final String path = buildImagePath(tenantId: tenantId, fileName: fileName, sequence: sequence);
    final StorageFileApi bucket = _storage.from(Env.publicImagesBucket);
    await bucket.upload(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return bucket.getPublicUrl(path);
  }

  /// 集市资质文件：落私有桶，返回**对象路径**。
  /// 服务端 `registerDocument` 只认 `<tenant_id>/...` 这一种形态，完整 URL 会被拒。
  Future<String> uploadPrivateAsset({
    required String tenantId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'application/pdf',
  }) async {
    final String ext = _extensionOf(fileName);
    final String path =
        '$tenantId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final StorageFileApi bucket = _storage.from(Env.privateAssetsBucket);
    await bucket.upload(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return path;
  }

  String _extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'jpg';
    final String ext = fileName.substring(dot + 1).toLowerCase();
    return ext.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

class StorageFailure implements Exception {
  const StorageFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
