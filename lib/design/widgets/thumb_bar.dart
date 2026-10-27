import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

class ThumbSlot {
  const ThumbSlot({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color accent;
}

/// 五位底部导航：中间是凸起的「开单」动作键，不是页面而是动作。
/// 选中项用模块色铺一颗胶囊，拇指落点始终在屏幕下 1/3。
class ThumbBar extends StatelessWidget {
  const ThumbBar({
    super.key,
    required this.slots,
    required this.selectedIndex,
    required this.onSelect,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.add_rounded,
    this.actionAccent,
    this.badges = const <int, String>{},
  });

  final List<ThumbSlot> slots;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData actionIcon;
  final Color? actionAccent;
  final Map<int, String> badges;

  static const double _barHeight = 66;
  static const double _notch = 30;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color surface = dark ? AppInk.darkSurface : AppInk.surface;
    final Color accent = actionAccent ?? AppInk.orders;

    // slots 长度 4 时动作键插在索引 2（即第 3 位）。
    final int actionIndex = math.min(2, slots.length);
    final List<Widget> children = <Widget>[];
    for (int index = 0; index < slots.length; index++) {
      if (index == actionIndex) {
        children.add(_ActionKey(
          label: actionLabel,
          icon: actionIcon,
          color: accent,
          onTap: onAction,
        ));
      }
      children.add(Expanded(
        child: _TabButton(
          slot: slots[index],
          selected: index == selectedIndex,
          badge: badges[index],
          onTap: () => onSelect(index),
        ),
      ));
    }
    if (actionIndex >= slots.length) {
      children.add(_ActionKey(
        label: actionLabel,
        icon: actionIcon,
        color: accent,
        onTap: onAction,
      ));
    }

    return SizedBox(
      height: _barHeight + _notch + MediaQuery.of(context).padding.bottom,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            child: CustomPaint(
              painter: _NotchPainter(surface: surface, dark: dark),
              child: const SizedBox(height: _barHeight + _notch, width: double.infinity),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 4,
            child: SafeArea(
              top: false,
              child: Row(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.slot,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final ThumbSlot slot;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? slot.accent : AppInk.textTertiary;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: ThumbBar._barHeight - 8,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
          AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.standard,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 16 : 12,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: selected ? AppInk.tint(slot.accent, alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Badge(
              isLabelVisible: badge != null && badge!.isNotEmpty,
              label: Text(badge ?? ''),
              backgroundColor: slot.accent,
              child: Icon(selected ? slot.activeIcon : slot.icon, size: 22, color: color),
            ),
          ),
            const SizedBox(height: 2),
            Text(
              slot.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.micro,
                fontWeight: selected ? AppType.semi : AppType.regular,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Center(
        child: Column(
          children: <Widget>[
            TweenAnimationBuilder<double>(
              duration: Motion.quick,
              tween: Tween<double>(begin: 0, end: 1),
              builder: (BuildContext context, double value, Widget? child) =>
                  Transform.scale(scale: 0.9 + 0.1 * value, child: child),
              child: Material(
                color: color,
                shape: const CircleBorder(),
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: Hit.fab,
                    height: Hit.fab,
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.micro,
                fontWeight: AppType.semi,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中间挖一个圆凹槽，动作键坐进去，视觉上和导航条一体。
class _NotchPainter extends CustomPainter {
  _NotchPainter({required this.surface, required this.dark});

  final Color surface;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final double notchCenterX = size.width / 2;
    final double barTop = _notchDepth;
    final double radius = 30;

    final Path path = Path()
      ..moveTo(0, barTop)
      ..lineTo(notchCenterX - radius - 14, barTop)
      ..cubicTo(
        notchCenterX - radius + 2,
        barTop,
        notchCenterX - radius + 6,
        barTop + radius * 0.9,
        notchCenterX,
        barTop + radius * 0.9,
      )
      ..cubicTo(
        notchCenterX + radius - 6,
        barTop + radius * 0.9,
        notchCenterX + radius - 2,
        barTop,
        notchCenterX + radius + 14,
        barTop,
      )
      ..lineTo(size.width, barTop)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black, dark ? 6 : 3, false);
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = dark ? AppInk.darkHairline : AppInk.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  static const double _notchDepth = 30;

  @override
  bool shouldRepaint(_NotchPainter oldDelegate) => oldDelegate.surface != surface;
}
