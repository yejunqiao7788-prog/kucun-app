import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 拍照录单的上传图：对应网页端 `api/orders.ts` 的 `compressImageForVision`。
///
/// 3.5 MB 是 data URL 的字符数上限，卡在两道硬顶之前：服务端对 `image` 收 4 MB，
/// 函数计算对请求体收 4.5 MB。留出这一档余量，就不会出现"本地以为没事、服务端整请求拒收"。
const int kVisionDataUrlMaxChars = 3670016; // (3.5 * 1024 * 1024)

/// 与网页端同一把阶梯：最长边与质量一起降，先落进上限的那一档就用。
/// 阶梯走完还超限就报错，不回退原图——原图发出去只会被服务端判 `VISION_IMAGE_INVALID`。
const List<(int, int)> kVisionLadder = <(int, int)>[
  (1280, 82),
  (1024, 72),
  (800, 62),
  (600, 50),
];

enum VisionImageProblem { decodeFailed, tooLarge }

class VisionImageException implements Exception {
  const VisionImageException(this.problem);

  final VisionImageProblem problem;
}

/// data URL 比原字节长 4/3，再加 `data:image/jpeg;base64,` 这 23 个字符的前缀。
int visionDataUrlChars(int byteLength) =>
    24 + ((byteLength + 2) ~/ 3) * 4;

bool fitsVisionDataUrl(int byteLength) =>
    visionDataUrlChars(byteLength) <= kVisionDataUrlMaxChars;

String jpegDataUrl(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

bool _isJpeg(Uint8List b) =>
    b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

/// `image` 这个包能解的格式。识别不了就直接报"读不出图片"，不必再花钱去试解码。
bool _isDecodable(Uint8List b) {
  if (b.length < 12) return false;
  if (_isJpeg(b)) return true;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true; // PNG
  if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
  if ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
      (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A)) {
    return true; // TIFF
  }
  final bool riff = b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46;
  return riff && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // WEBP
}

/// 首档一般由 `image_picker` 的原生降采样直接达成（maxWidth/maxHeight 1280、quality 82），
/// 这里只在它没能压进上限、或回来的根本不是 JPEG 时才重编，省得把一张正常照片解两遍。
Future<String> compressImageForVision(Uint8List bytes) async {
  if (_isJpeg(bytes) && fitsVisionDataUrl(bytes.length)) return jpegDataUrl(bytes);
  if (!_isDecodable(bytes)) {
    throw const VisionImageException(VisionImageProblem.decodeFailed);
  }
  final (Uint8List? encoded, VisionImageProblem? failure) =
      await compute(_encodeWithinLadder, bytes);
  if (encoded == null) {
    // 解不开和压不小是两回事：把"这张读不出来"报成"太大"，卖家会一直重拍同一张坏图。
    throw VisionImageException(failure ?? VisionImageProblem.tooLarge);
  }
  return jpegDataUrl(encoded);
}

/// 在 isolate 里走完阶梯：解码一次，逐档缩放重编，第一档落进上限就返回。
(Uint8List?, VisionImageProblem?) _encodeWithinLadder(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // 半截 JPEG 会让解码器直接抛 RangeError，而不是回 null。
    return (null, VisionImageProblem.decodeFailed);
  }
  if (decoded == null) return (null, VisionImageProblem.decodeFailed);
  final int longest =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longest <= 0) return (null, VisionImageProblem.decodeFailed);
  for (final (int maxSide, int quality) in kVisionLadder) {
    final double scale = maxSide / longest;
    final img.Image sized = scale >= 1
        ? decoded
        : img.copyResize(
            decoded,
            width: (decoded.width * scale).round().clamp(1, decoded.width),
            height: (decoded.height * scale).round().clamp(1, decoded.height),
          );
    final Uint8List out = img.encodeJpg(sized, quality: quality);
    if (fitsVisionDataUrl(out.length)) return (out, null);
  }
  return (null, VisionImageProblem.tooLarge);
}
