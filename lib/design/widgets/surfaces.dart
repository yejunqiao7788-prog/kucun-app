import 'package:flutter/material.dart';

import '../tokens.dart';

/// 扁平卡片：不投影，靠发丝描边 + 模块色淡底区分层级。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: margin,
      child: Material(
        color: dark ? AppInk.darkSurface : AppInk.surface,
        borderRadius: Radii.card_,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.card_,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: Radii.card_,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              gradient: accent == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        AppInk.tint(accent!, alpha: dark ? 0.18 : 0.10),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, 0.55],
                    ),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 分区标题：左对齐小字，右侧可挂一个动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accent ?? AppInk.dashboard,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 设置类页面的一行：彩色图标块 + 主副标题 + 尾部。
class TileRow extends StatelessWidget {
  const TileRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = danger ? AppInk.danger : (accent ?? AppInk.dashboard);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.control_,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppInk.tint(tint, alpha: 0.14),
                  borderRadius: Radii.chip_,
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: danger
                          ? text.titleMedium?.copyWith(color: AppInk.danger)
                          : text.titleMedium,
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: text.bodySmall),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else if (!danger)
                Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).textTheme.bodySmall?.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工作台的大数字块：整块铺模块色淡底，一眼看出归属。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    this.footnote,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final String? footnote;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: accent, fontWeight: AppType.semi),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: text.displaySmall?.copyWith(color: accent)),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(footnote!, style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// 状态徽章：只用色，不用阴影。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.dense = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool dense;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: AppInk.tint(color, alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? AppType.micro : AppType.foot,
              fontWeight: AppType.semi,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面纵向留白统一出口。
class VGap extends StatelessWidget {
  const VGap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

class HGap extends StatelessWidget {
  const HGap(this.width, {super.key});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(width: width);
}
