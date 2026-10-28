import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kucun_app/core/vision_image.dart';

/// 拍照录单的上传图：这一层出错就是整次识别白跑，所以阶梯和上限要能离线验。
void main() {
  Uint8List jpegOf(int side, {int quality = 82}) {
    final img.Image image = img.Image(width: side, height: side);
    img.fill(image, color: img.ColorRgb8(120, 90, 60));
    return img.encodeJpg(image, quality: quality);
  }

  group('data URL 上限', () {
    test('字符数估算永远不低估真实 base64', () {
      for (final int size in <int>[0, 1, 2, 3, 100, 4096, 99999]) {
        final Uint8List bytes = Uint8List(size);
        final int real = 'data:image/jpeg;base64,'.length +
            base64Encode(bytes).length;
        expect(visionDataUrlChars(size), greaterThanOrEqualTo(real),
            reason: '低估就会把超限请求发出去');
      }
    });

    test('上限卡在 3.5 MB 字符，留出服务端 4 MB 的余量', () {
      expect(fitsVisionDataUrl(2700000), isTrue);
      expect(fitsVisionDataUrl(2800000), isFalse);
      expect(kVisionDataUrlMaxChars, lessThan(4 * 1024 * 1024));
    });
  });

  group('compressImageForVision', () {
    test('已经压进上限的 JPEG 原样发出，不再解一遍', () async {
      final Uint8List bytes = jpegOf(64);
      final String dataUrl = await compressImageForVision(bytes);
      expect(dataUrl, startsWith('data:image/jpeg;base64,'));
      expect(dataUrl.length, lessThanOrEqualTo(kVisionDataUrlMaxChars));
      expect(base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
          equals(bytes));
    });

    test('PNG 走阶梯重编成 JPEG', () async {
      final img.Image image = img.Image(width: 900, height: 900);
      img.fill(image, color: img.ColorRgb8(30, 200, 120));
      final Uint8List png = img.encodePng(image);
      final String dataUrl = await compressImageForVision(png);
      expect(dataUrl, startsWith('data:image/jpeg;base64,'));
      expect(dataUrl.length, lessThanOrEqualTo(kVisionDataUrlMaxChars));
    });

    test('头像是 PNG 但内容解不开：报"读不出图片"，不是"太大"', () async {
      final Uint8List fake = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        ...List<int>.filled(64, 0),
      ]);
      await expectLater(
        compressImageForVision(fake),
        throwsA(predicate((Object? e) =>
            e is VisionImageException &&
            e.problem == VisionImageProblem.decodeFailed)),
      );
    });

    test('根本不是图片就直接拒，不发请求', () async {
      final Uint8List junk = Uint8List.fromList(
          'this is not an image at all, not even close'.codeUnits);
      await expectLater(
        compressImageForVision(junk),
        throwsA(predicate((Object? e) =>
            e is VisionImageException &&
            e.problem == VisionImageProblem.decodeFailed)),
      );
    });
  });
}
