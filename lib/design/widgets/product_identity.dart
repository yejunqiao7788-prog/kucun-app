import 'package:flutter/material.dart';

import '../tokens.dart';

/// 商品标识（SKU + 名称）的唯一实现 —— 字号只在这里定义一次。
///
/// 规则：**SKU 恒 ≥ 名称**。SKU 是这一库里的唯一标识（名称是库位名，一个名称几百行），
/// 拣货的人照着码找货，所以它不该被降成灰色小字；名称降为副行，租户可以在
/// 设置 → 打印与显示 里整档关掉（`print_settings.show_product_name`）。
///
/// 两档对应网页端 `src/ui/ProductIdentity.tsx` 的 SIZE（md 14/13、sm 13/12）；
/// App 的字号阶梯只有六档（见 [AppType]），所以落在 body/foot 与 foot/micro 上，
/// 不变量「SKU ≥ 名称」两档都成立。
///
/// 打印单据（`core/print_sheet.dart`）出的是 PDF，用不了这个组件，那一侧的字号与墨色
/// 手工与这里对账 —— 改这里的档位必须同时改那张单据。
enum IdentitySize { md, sm }

class IdentityType {
  const IdentityType._();

  static double sku(IdentitySize size) =>
      size == IdentitySize.md ? AppType.body : AppType.foot;

  static double name(IdentitySize size) =>
      size == IdentitySize.md ? AppType.foot : AppType.micro;
}

/// 单行站点的 SKU（集市选品 / 展厅选品 / 动态 chip 那一类「名称 + 码 + 状态」一行排开的
/// 布局）。它们不该被改成两行，但字号必须与两行面出自同一处。
class SkuText extends StatelessWidget {
  const SkuText({
    super.key,
    required this.sku,
    this.size = IdentitySize.md,
    this.struck = false,
    this.maxLines = 1,
  });

  final String? sku;
  final IdentitySize size;

  /// 已拣货：划线 + 降为淡墨，与名称同待遇。
  final bool struck;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String value = (sku ?? '').trim();
    return Text(
      value.isEmpty ? '—' : value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: IdentityType.sku(size),
        fontWeight: AppType.semi,
        fontFamily: 'monospace',
        letterSpacing: 0.3,
        color: struck ? text.bodySmall?.color : text.bodyLarge?.color,
        decoration: struck ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

/// 两行面：SKU 主行（可跟一个柜名/类目徽章），名称副行（可再跟库存、箱规这一截）。
///
/// 分隔符由组件插入：名称被关掉时不留孤立的「·」，而 [secondary] 那一截仍然显示 ——
/// 库存与箱规不跟着名称一起消失。
class ProductIdentity extends StatelessWidget {
  const ProductIdentity({
    super.key,
    required this.sku,
    this.name,
    this.size = IdentitySize.md,
    this.badge,
    this.secondary,
    this.struck = false,
    this.showName = true,
  });

  final String? sku;
  final String? name;
  final IdentitySize size;
  final Widget? badge;

  /// 名称之后追加的同一行内容（库存、箱规…），传字符串即可。
  final String? secondary;
  final bool struck;

  /// 租户偏好。买家可见面（展厅公页）传它自己那份 `show_name`，不读租户内部口径。
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String shownName = (showName ? name : null)?.trim() ?? '';
    final String tail = secondary?.trim() ?? '';
    final String secondLine = shownName.isEmpty
        ? tail
        : (tail.isEmpty ? shownName : '$shownName · $tail');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(child: SkuText(sku: sku, size: size, struck: struck)),
            if (badge != null) ...<Widget>[const SizedBox(width: 6), badge!],
          ],
        ),
        if (secondLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              secondLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: IdentityType.name(size),
                fontWeight: FontWeight.w500,
                color: struck ? text.bodySmall?.color : text.bodyMedium?.color,
                decoration: struck ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
      ],
    );
  }
}
