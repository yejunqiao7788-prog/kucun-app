import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../tokens.dart';

/// 全屏模态：从底部推上来、带大号标题和「取消 / 保存」，符合单手操作。
Future<T?> pushSheet<T>(
  BuildContext context, {
  required Widget child,
  bool fullScreen = true,
}) {
  return Navigator.of(context).push<T>(
    CupertinoPageRoute<T>(
      builder: (BuildContext context) => child,
      fullscreenDialog: fullScreen,
    ),
  );
}

/// 底部抽屉：矮内容用（筛选、选择），带拖拽把手。
Future<T?> showDrawer<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  double maxHeightFactor = 0.78,
  Color? accent,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final bool dark = Theme.of(sheetContext).brightness == Brightness.dark;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ClipRRect(
          borderRadius: Radii.sheet_,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * maxHeightFactor,
              ),
              color: dark ? AppInk.darkSurface : AppInk.surface,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppInk.tint(AppInk.textTertiary, alpha: 0.5),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: AppType.heavy,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(child: builder(sheetContext)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 破坏性动作一律二次确认，并原样说明服务端会做什么。
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final L10n l10n = L10n.of(Localizations.localeOf(context));
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel ?? l10n.actCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppInk.danger : AppInk.dashboard,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel ?? l10n.actConfirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showToast(BuildContext context, String message, {bool danger = false}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger ? AppInk.danger : AppInk.onDark,
        duration: Duration(seconds: danger ? 4 : 2),
      ),
    );
}

