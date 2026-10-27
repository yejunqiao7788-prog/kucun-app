import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../tokens.dart';
import 'surfaces.dart';

/// 主按钮：整宽、54dp、唯一强调色。一屏最多出现一个。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.color,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? color;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Color accent = color ?? AppInk.dashboard;
    final Widget button = icon == null
        ? FilledButton(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(label),
          )
        : FilledButton.icon(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Widget child = icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return SizedBox(width: double.infinity, child: child);
  }
}

class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, this.onPressed, this.color});

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: color == null
            ? null
            : TextButton.styleFrom(foregroundColor: color),
        child: Text(label),
      );
}

/// 圆形图标按钮，热区仍保持 48dp。
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.tooltip,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color accent = color ?? Theme.of(context).textTheme.bodyMedium?.color ?? AppInk.textSecondary;
    final Widget button = Material(
      color: AppInk.tint(accent, alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 20, color: accent),
        ),
      ),
    );
    return tooltip == null
        ? ConstrainedBox(constraints: const BoxConstraints(minWidth: Hit.min, minHeight: Hit.min), child: button)
        : Tooltip(message: tooltip!, child: button);
  }
}

/// 顶栏内联搜索框：不弹新页，拇指一划就改条件。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
        isDense: true,
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.suffix,
    this.maxLines = 1,
    this.obscure = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.initialValue,
    this.textInputAction,
    this.inputFormatters,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final int maxLines;
  final bool obscure;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final String? initialValue;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.foot,
              fontWeight: AppType.semi,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          autofocus: autofocus,
          focusNode: focusNode,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: obscure ? 1 : maxLines,
          obscureText: obscure,
          enabled: enabled,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
        ),
      ],
    );
  }
}

/// 金额/数量输入：只允许一个小数点，负号交给方向开关。
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.controller,
    this.allowNegative = false,
    this.allowDecimal = true,
    this.suffix,
    this.onChanged,
    this.hint,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final bool allowNegative;
  final bool allowDecimal;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      hint: hint,
      autofocus: autofocus,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(
        decimal: allowDecimal,
        signed: allowNegative,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          RegExp(allowDecimal ? r'^-?\d*\.?\d*$' : r'^-?\d*$'),
        ),
      ],
      suffix: suffix == null ? null : Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(child: Text(suffix!, style: const TextStyle(fontSize: AppType.foot))),
      ),
    );
  }
}

/// 横向胶囊筛选：单选，选中项铺模块色。
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.accent,
    this.scrollable = true,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final Color? accent;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ?? AppInk.dashboard;
    final Widget row = Row(
      children: values
          .map(
            (T value) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                label: labelOf(value),
                selected: value == selected,
                accent: color,
                onTap: () => onChanged(value),
              ),
            ),
          )
          .toList(growable: false),
    );
    return SizedBox(
      height: 40,
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: row,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: row,
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : (Theme.of(context).brightness == Brightness.dark
          ? AppInk.darkSurfaceDim
          : AppInk.surfaceDim),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.foot,
              fontWeight: AppType.semi,
              color: selected ? Colors.white : AppInk.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 出库/入库方向开关：一个控件同时表达方向和数量增减。
class DirectionSwitch extends StatelessWidget {
  const DirectionSwitch({
    super.key,
    required this.inbound,
    required this.onChanged,
    required this.inboundLabel,
    required this.outboundLabel,
  });

  final bool inbound;
  final ValueChanged<bool> onChanged;
  final String inboundLabel;
  final String outboundLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _HalfSelector(
            label: inboundLabel,
            active: inbound,
            color: AppInk.finance,
            icon: Icons.arrow_downward_rounded,
            onTap: () => onChanged(true),
          ),
        ),
        const HGap(10),
        Expanded(
          child: _HalfSelector(
            label: outboundLabel,
            active: !inbound,
            color: AppInk.products,
            icon: Icons.arrow_upward_rounded,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _HalfSelector extends StatelessWidget {
  const _HalfSelector({
    required this.label,
    required this.active,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppInk.tint(color, alpha: 0.16) : Colors.transparent,
      borderRadius: Radii.control_,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.control_,
        child: Container(
          height: Hit.min,
          decoration: BoxDecoration(
            borderRadius: Radii.control_,
            border: Border.all(color: active ? color : Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: active ? color : AppInk.textTertiary),
              const HGap(6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppType.foot,
                  fontWeight: AppType.semi,
                  color: active ? color : AppInk.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// +/- 步进器：受控组件，值由父级持有（库存/数量输入共用一颗）。
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999999,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RoundIconButton(
          icon: Icons.remove_rounded,
          onPressed: value <= min ? null : () => onChanged((value - 1).clamp(min, max)),
        ),
        const HGap(8),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        const HGap(8),
        RoundIconButton(
          icon: Icons.add_rounded,
          onPressed: value >= max ? null : () => onChanged((value + 1).clamp(min, max)),
        ),
      ],
    );
  }
}

/// 图片行：封面在前，删除即整表替换前先把剩余项读回来。
class ImageStrip extends StatelessWidget {
  const ImageStrip({
    super.key,
    required this.urls,
    required this.onAdd,
    required this.onRemove,
    this.maxCount = 5,
    this.busy = false,
  });

  final List<String> urls;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int maxCount;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (int index = 0; index < urls.length; index++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: Radii.chip_,
                    child: Image.network(
                      urls[index],
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 84,
                        height: 84,
                        color: AppInk.surfaceDim,
                        child: const Icon(Icons.broken_image_outlined, size: 20),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => onRemove(index),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppInk.onDark,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppInk.tint(AppInk.products, alpha: 0.9),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(L10n.of(Localizations.localeOf(context)).prodCover,
                            style: const TextStyle(fontSize: AppType.micro, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          if (urls.length < maxCount)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: busy
                  ? const SizedBox(
                      width: 84,
                      height: 84,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : InkWell(
                      onTap: onAdd,
                      borderRadius: Radii.chip_,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: Radii.chip_,
                          border: Border.all(color: AppInk.hairline),
                          color: AppInk.surfaceDim,
                        ),
                        child: const Icon(Icons.add_photo_alternate_outlined, size: 24),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// 只读信息行（详情抽屉里大量复用）。
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: text.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: text.titleMedium?.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
