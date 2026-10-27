import 'package:flutter/material.dart';

/// 多彩扁平色板。
///
/// 规则只有两条：表面不投影、颜色只用来表达"这是哪件事"。
/// 每个模块一把专属色，底部导航、统计卡、状态徽章共用同一把，
/// 用户在 App 里看到颜色就知道自己在哪一格。
class AppInk {
  const AppInk._();

  // 中性层
  static const Color canvas = Color(0xFFF5F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFFEFF1F7);
  static const Color hairline = Color(0xFFE3E6EF);
  static const Color textPrimary = Color(0xFF121726);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textTertiary = Color(0xFF98A2B3);
  static const Color onDark = Color(0xFF0B1020);

  // 模块专属色
  static const Color dashboard = Color(0xFF4C6FFF);
  static const Color products = Color(0xFFFF7A45);
  static const Color inventory = Color(0xFF0FB5A6);
  static const Color orders = Color(0xFF7C5CFF);
  static const Color showroom = Color(0xFFFFB020);
  static const Color marketplace = Color(0xFFFF3D9A);
  static const Color finance = Color(0xFF12B76A);
  static const Color ai = Color(0xFF00B8E6);
  static const Color settings = Color(0xFF6B7280);

  // 语义色
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFF5A524);
  static const Color success = Color(0xFF12B76A);
  static const Color info = Color(0xFF4C6FFF);

  /// 深色模式下表面层换掉，模块色提亮一档保持可读。
  static const Color darkCanvas = Color(0xFF0B1020);
  static const Color darkSurface = Color(0xFF151B2E);
  static const Color darkSurfaceDim = Color(0xFF1D2438);
  static const Color darkHairline = Color(0xFF2A3350);
  static const Color darkTextPrimary = Color(0xFFF2F4FA);
  static const Color darkTextSecondary = Color(0xFFA5AFC8);

  /// 用模块色铺一层很淡的底，代替阴影来区分卡片。
  static Color tint(Color color, {double alpha = 0.10}) =>
      color.withValues(alpha: alpha);
}

/// Apple 标准的减速曲线：起步快、收尾长，接近物理感。
class Motion {
  const Motion._();

  static const Curve standard = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Curve decelerate = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration sheet = Duration(milliseconds: 340);
}

class Radii {
  const Radii._();

  static const double chip = 12;
  static const double control = 16;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;

  static const BorderRadius control_ = BorderRadius.all(Radius.circular(control));
  static const BorderRadius card_ = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheet_ = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius chip_ = BorderRadius.all(Radius.circular(chip));
}

class Space {
  const Space._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double gutter = 16;

  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: gutter);
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// 字号阶梯：只保留六档，避免"到处都是小字"。
class AppType {
  const AppType._();

  static const double huge = 30; // 大标题
  static const double title = 22;
  static const double head = 17;
  static const double body = 15;
  static const double foot = 13;
  static const double micro = 11;

  static const FontWeight heavy = FontWeight.w700;
  static const FontWeight semi = FontWeight.w600;
  static const FontWeight regular = FontWeight.w400;
}

/// 触控热区下限（Apple HIG 44pt / Material 48dp，取更宽的 48）。
class Hit {
  const Hit._();

  static const double min = 48;
  static const double primaryButton = 54;
  static const double fab = 62;
}
