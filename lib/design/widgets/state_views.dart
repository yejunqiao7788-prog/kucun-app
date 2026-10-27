import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../tokens.dart';
import 'surfaces.dart';

/// 首屏骨架：不做闪烁动画，用固定灰块占位，滚动不卡。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.itemHeight = 84});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color base = dark ? AppInk.darkSurfaceDim : AppInk.surfaceDim;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 96),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const VGap(10),
      itemBuilder: (BuildContext context, int index) => Container(
        height: itemHeight,
        decoration: BoxDecoration(
          color: base,
          borderRadius: Radii.card_,
        ),
      ),
    );
  }
}

class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(color: color ?? AppInk.dashboard));
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(Localizations.localeOf(context));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppSpinner(),
          if (label != null) ...<Widget>[
            const VGap(12),
            Text(label ?? l10n.commonLoading,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.inbox_rounded,
    this.accent,
    this.action,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final Color? accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ?? AppInk.textTertiary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppInk.tint(color, alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const VGap(16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (hint != null) ...<Widget>[
              const VGap(6),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (action != null) ...<Widget>[const VGap(18), action!],
          ],
        ),
      ),
    );
  }
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title,
    this.icon = Icons.cloud_off_rounded,
  });

  final String message;
  final VoidCallback onRetry;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(Localizations.localeOf(context));
    return AppEmpty(
      title: title ?? l10n.commonErrorTitle,
      hint: message,
      icon: icon,
      accent: AppInk.danger,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(l10n.actRetry),
        style: FilledButton.styleFrom(
          minimumSize: const Size(140, Hit.min),
        ),
      ),
    );
  }
}

/// 顶部横条：离线 / 缓存 / 到期三选一，同一时间只出现一条。
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.action,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppInk.tint(color, alpha: 0.12),
        borderRadius: Radii.chip_,
        border: Border.all(color: AppInk.tint(color, alpha: 0.32)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon ?? Icons.info_outline_rounded, size: 18, color: color),
          const HGap(8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.foot,
                fontWeight: AppType.semi,
                color: color,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// 把 banner + 内容叠在一起的常用外壳：banner 固定不跟随滚动。
class BannerStack extends StatelessWidget {
  const BannerStack({super.key, required this.banners, required this.child});

  final List<Widget> banners;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (banners.isEmpty) return child;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 0),
          child: Column(children: banners),
        ),
        Expanded(child: child),
      ],
    );
  }
}
