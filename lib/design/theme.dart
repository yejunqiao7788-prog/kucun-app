import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 主题：零投影、发丝描边、模块色铺淡底；页面转场统一用 iOS 右滑返回，
/// 这样 Android 上也能用拇指往右一划就退回去。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: AppInk.dashboard,
      onPrimary: Colors.white,
      secondary: AppInk.marketplace,
      onSecondary: Colors.white,
      error: AppInk.danger,
      onError: Colors.white,
      surface: isDark ? AppInk.darkSurface : AppInk.surface,
      onSurface: isDark ? AppInk.darkTextPrimary : AppInk.textPrimary,
      surfaceContainerHighest: isDark ? AppInk.darkSurfaceDim : AppInk.surfaceDim,
      outline: isDark ? AppInk.darkHairline : AppInk.hairline,
    );

    final Color canvas = isDark ? AppInk.darkCanvas : AppInk.canvas;
    final Color bodyText = isDark ? AppInk.darkTextPrimary : AppInk.textPrimary;
    final Color muted = isDark ? AppInk.darkTextSecondary : AppInk.textSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      // iOS 式右滑返回：这是"借鉴苹果操作理念"里最实在的一条。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: _textTheme(bodyText, muted),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: bodyText,
        titleTextStyle: TextStyle(
          fontSize: AppType.head,
          fontWeight: AppType.semi,
          color: bodyText,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? AppInk.darkSurface : AppInk.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card_,
          side: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontSize: AppType.head,
          fontWeight: AppType.semi,
          color: bodyText,
        ),
        subtitleTextStyle: TextStyle(fontSize: AppType.foot, color: muted),
        shape: const RoundedRectangleBorder(borderRadius: Radii.control_),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md),
        minLeadingWidth: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Hit.primaryButton),
          textStyle: const TextStyle(
            fontSize: AppType.head,
            fontWeight: AppType.semi,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.control_),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(Hit.primaryButton),
          side: BorderSide(color: scheme.outline, width: 1.5),
          foregroundColor: bodyText,
          textStyle: const TextStyle(
            fontSize: AppType.head,
            fontWeight: AppType.semi,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.control_),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Hit.min, Hit.min),
          textStyle: const TextStyle(fontSize: AppType.body, fontWeight: AppType.semi),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            const RoundedRectangleBorder(borderRadius: Radii.chip_),
          ),
          side: WidgetStatePropertyAll<BorderSide?>(BorderSide(color: scheme.outline)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppInk.darkSurfaceDim : AppInk.surfaceDim,
        selectedColor: AppInk.dashboard,
        side: BorderSide(color: scheme.outline),
        labelStyle: TextStyle(fontSize: AppType.foot, color: bodyText),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chip_),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppInk.darkSurfaceDim : AppInk.surfaceDim,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        hintStyle: TextStyle(color: muted, fontSize: AppType.body),
        labelStyle: TextStyle(color: muted, fontSize: AppType.foot),
        border: OutlineInputBorder(
          borderRadius: Radii.control_,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.control_,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.control_,
          borderSide: const BorderSide(color: AppInk.dashboard, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.control_,
          borderSide: const BorderSide(color: AppInk.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.control_,
          borderSide: const BorderSide(color: AppInk.danger, width: 1.6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppInk.darkSurface : AppInk.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet_),
        showDragHandle: true,
        dragHandleColor: muted.withValues(alpha: 0.4),
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppInk.darkSurface : AppInk.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card_),
        titleTextStyle: TextStyle(
          fontSize: AppType.title,
          fontWeight: AppType.heavy,
          color: bodyText,
        ),
        contentTextStyle: TextStyle(fontSize: AppType.body, color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppInk.darkSurfaceDim : AppInk.onDark,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: AppType.body),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chip_),
        insetPadding: const EdgeInsets.all(Space.gutter),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppInk.dashboard,
        linearMinHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          isDark ? AppInk.darkTextPrimary : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? AppInk.success : scheme.outline,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: bodyText,
        unselectedLabelColor: muted,
        labelStyle: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
        unselectedLabelStyle: const TextStyle(fontSize: AppType.foot),
        dividerColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppInk.dashboard,
        selectionColor: AppInk.tint(AppInk.dashboard, alpha: 0.28),
        selectionHandleColor: AppInk.dashboard,
      ),
    );
  }

  static TextTheme _textTheme(Color body, Color muted) => TextTheme(
        displaySmall: TextStyle(
          fontSize: AppType.huge,
          fontWeight: AppType.heavy,
          color: body,
          height: 1.15,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          fontSize: AppType.title,
          fontWeight: AppType.heavy,
          color: body,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: AppType.head,
          fontWeight: AppType.semi,
          color: body,
        ),
        bodyLarge: TextStyle(fontSize: AppType.body, color: body, height: 1.35),
        bodyMedium: TextStyle(fontSize: AppType.foot, color: muted, height: 1.35),
        bodySmall: TextStyle(fontSize: AppType.micro, color: muted, height: 1.3),
        labelLarge: TextStyle(
          fontSize: AppType.foot,
          fontWeight: AppType.semi,
          color: body,
          letterSpacing: 0.2,
        ),
      );
}
