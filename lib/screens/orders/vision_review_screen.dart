import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/vision_review_model.dart';
import 'order_create_screen.dart' show pickProductForOrder;

/// 拍照识别 → 整表复核。逐条抄网页端 `hud/modules/orders/VisionOrderDialog.tsx`。
///
/// 为什么不再"一行一个弹窗"：一次识别最多回 40 行，串行弹窗在手机上是十几次点击，
/// 中途关掉一个就把整批结果丢了（原来的实现连没匹配上的行都不吭声）。这里把结果留在页上，
/// 只自动勾选"库里唯一确定"的行，歧义与无匹配必须卖家自己点，收单前还能改数量。
///
/// 单价、库存、客户归属始终来自数据库，识别只负责提出候选：网页端把这条写在副标题上，
/// 这里也照抄，不让卖家以为确认了就锁了价。
class VisionReviewScreen extends StatefulWidget {
  const VisionReviewScreen({
    super.key,
    required this.imageDataUrl,
    required this.inbound,
  });

  final String imageDataUrl;
  final bool inbound;

  @override
  State<VisionReviewScreen> createState() => _VisionReviewScreenState();
}

class _VisionReviewScreenState extends State<VisionReviewScreen> {
  final TextEditingController _hint = TextEditingController();
  final TextEditingController _term = TextEditingController();

  VisionReviewModel? _model;
  bool _running = false;
  String? _error;

  VisionFilter _filter = VisionFilter.all;
  String _query = '';

  @override
  void dispose() {
    _hint.dispose();
    _term.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 动作

  Future<void> _run() async {
    final AppState app = AppState.of(context);
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final VisionDraft draft = await app.repos.orders.visionDraft(
        dataUrl: widget.imageDataUrl,
        hint: _hint.text,
      );
      if (!mounted) return;
      setState(() {
        _model = VisionReviewModel(draft)..autoCheck();
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = app.describeError(error));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _accept() {
    Navigator.of(context).pop(_model?.commit() ?? const <VisionPick>[]);
  }

  Future<void> _pickManually(int index) async {
    final VisionLine line = _model!.draft.items[index];
    // 带上模型这一行读到的码/名：同码几十行只列前几行时，卖家不该从零再打一遍。
    final String seed = line.skuHint.isNotEmpty ? line.skuHint : line.nameHint;
    final Product? picked = await pickProductForOrder(
      context,
      inbound: widget.inbound,
      initialKeyword: seed,
    );
    if (picked != null) setState(() => _model!.choose(index, picked));
  }

  void _zoom() {
    final double tall = MediaQuery.sizeOf(context).height - 140;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: _Photo(
            dataUrl: widget.imageDataUrl,
            maxHeight: tall,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    final bool hasResult = _model != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.visSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: hasResult ? _reviewBody(l10n) : _prepareBody(l10n),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 10),
          child: hasResult
              ? Row(
                  children: <Widget>[
                    Expanded(
                      child: GhostButton(
                        label: l10n.actCancel,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const HGap(10),
                    Expanded(
                      child: PrimaryButton(
                        label: l10n.visAddSelected(_model?.checkedCount ?? 0),
                        color: AppInk.ai,
                        onPressed: (_model?.checkedCount ?? 0) == 0 ? null : _accept,
                      ),
                    ),
                  ],
                )
              : PrimaryButton(
                  label: _running ? l10n.visWorking : l10n.visRun,
                  icon: Icons.document_scanner_outlined,
                  color: AppInk.ai,
                  loading: _running,
                  onPressed: _running ? null : _run,
                ),
        ),
      ),
    );
  }

  Widget _prepareBody(L10n l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 24),
      children: <Widget>[
        ClipRRect(
          borderRadius: Radii.card_,
          // 整张照片都要看得见：识别靠的就是那几个字，裁掉一半就没法核对。
          child: _Photo(
            dataUrl: widget.imageDataUrl,
            maxHeight: 260,
            fit: BoxFit.contain,
          ),
        ),
        const VGap(14),
        AppTextField(
          label: l10n.visHintLabel,
          controller: _hint,
          hint: l10n.visHintPlaceholder,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(200),
          ],
        ),
        if (_error != null) ...<Widget>[
          const VGap(10),
          NoticeBanner(text: _error!, color: AppInk.danger),
        ],
      ],
    );
  }

  String _filterLabel(L10n l10n, VisionFilter value) => switch (value) {
        VisionFilter.all => l10n.visFilterAll,
        VisionFilter.needsPick => l10n.visFilterNeedsPick,
        VisionFilter.unmatched => l10n.visFilterUnmatched,
      };

  Widget _reviewBody(L10n l10n) {
    final VisionReviewModel model = _model!;
    final VisionCounts counts = model.counts;
    final List<int> visible = model.visible(_filter, _query);

    return Column(
      children: <Widget>[
        // 结果最多 40 行，控制条吸顶：摘要、过滤、全选不该要靠滚回上面才找得到。
        Container(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 8),
          decoration: const BoxDecoration(
            color: AppInk.surface,
            border: Border(bottom: BorderSide(color: AppInk.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    button: true,
                    label: l10n.visZoomPhoto,
                    child: GestureDetector(
                      onTap: _zoom,
                      child: ClipRRect(
                        borderRadius: Radii.chip_,
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: _Photo(dataUrl: widget.imageDataUrl),
                        ),
                      ),
                    ),
                  ),
                  const HGap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.visSummary(counts.ready, counts.needsPick, counts.all),
                          style: const TextStyle(
                              fontSize: AppType.foot, fontWeight: AppType.semi),
                        ),
                        if (model.draft.customerHint.isNotEmpty)
                          Text(
                            '${l10n.visCustomerHint}：${model.draft.customerHint}',
                            style: const TextStyle(fontSize: AppType.foot),
                          ),
                        if (counts.ready > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: TextAction(
                              label: model.isEveryReadyChecked
                                  ? l10n.visClearAll
                                  : l10n.visSelectAll,
                              color: AppInk.ai,
                              onPressed: () => setState(model.toggleAllReady),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const VGap(6),
              PillTabs<VisionFilter>(
                values: VisionFilter.values,
                selected: _filter,
                accent: AppInk.ai,
                labelOf: (VisionFilter value) =>
                    '${_filterLabel(l10n, value)} ${counts.byFilter(value)}',
                onChanged: (VisionFilter value) => setState(() => _filter = value),
              ),
              SearchField(
                controller: _term,
                hintText: l10n.visSearchPlaceholder,
                onChanged: (String value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
        if (counts.unmatched != 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 10, Space.gutter, 0),
            child: NoticeBanner(
              text: l10n.visUnmatchedGuide,
              color: AppInk.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? AppEmpty(
                  title: l10n.visFilterEmpty,
                  icon: Icons.filter_alt_off_rounded,
                  accent: AppInk.ai,
                  action: GhostButton(
                    label: l10n.visFilterReset,
                    icon: Icons.refresh_rounded,
                    onPressed: () => setState(() {
                      _filter = VisionFilter.all;
                      _term.clear();
                      _query = '';
                    }),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 10, Space.gutter, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const VGap(10),
                  itemBuilder: (BuildContext context, int slot) {
                    final int index = visible[slot];
                    return VisionRowCard(
                      key: ValueKey<int>(index),
                      line: model.draft.items[index],
                      status: model.statusOf(index),
                      resolved: model.resolvedOf(index),
                      checked: model.isChecked(index),
                      qty: model.qtyOf(index),
                      currency: AppState.of(context).profile.currencySymbol,
                      l10n: l10n,
                      onToggle: () => setState(() => model.toggle(index)),
                      onChoose: (Product product) =>
                          setState(() => model.choose(index, product)),
                      onReselect: () => setState(() => model.reselect(index)),
                      onManual: () => _pickManually(index),
                      onQty: (int value) => setState(() => model.setQty(index, value)),
                    );
                  },
                ),
        ),
        // 网页端把这条写在列表下面：确认候选不等于锁价，单价始终以库里的数为准。
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.visPriceNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// 结果里的行本身不带图片，缩略图只有一个：卖家拍的那张原图。
/// 尺寸一律由调用方给死（宽填满、高固定）：图本身的 intrinsic 尺寸是相机原图，
/// 交给布局去猜就会在对话框里溢出。
class _Photo extends StatelessWidget {
  const _Photo({
    required this.dataUrl,
    this.maxHeight,
    this.fit = BoxFit.cover,
  });

  final String dataUrl;
  final double? maxHeight;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final int comma = dataUrl.indexOf(',');
    final Uint8List bytes =
        base64Decode(comma < 0 ? dataUrl : dataUrl.substring(comma + 1));
    return SizedBox(
      width: double.infinity,
      height: maxHeight ?? 46,
      child: Image.memory(
        bytes,
        fit: fit,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            const Icon(Icons.broken_image_outlined, color: AppInk.textTertiary),
      ),
    );
  }
}

/// 复核列表的一行。公开只为让布局能在测试里被真正摆一遍：
/// 行内排版出错在 release 包里就是一块灰，analyze 抓不到。
class VisionRowCard extends StatelessWidget {
  const VisionRowCard({
    super.key,
    required this.line,
    required this.status,
    required this.resolved,
    required this.checked,
    required this.qty,
    required this.currency,
    required this.l10n,
    required this.onToggle,
    required this.onChoose,
    required this.onReselect,
    required this.onManual,
    required this.onQty,
  });

  final VisionLine line;
  final VisionRowStatus status;
  final Product? resolved;
  final bool checked;
  final int qty;
  final String currency;
  final L10n l10n;
  final VoidCallback onToggle;
  final ValueChanged<Product> onChoose;
  final VoidCallback onReselect;
  final VoidCallback onManual;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final bool ready = status == VisionRowStatus.ready;
    return AppCard(
      accent: ready ? AppInk.ai : AppInk.warning,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 40,
            height: 34,
            child: Checkbox(
              value: checked,
              onChanged: ready ? (bool? _) => onToggle() : null,
              activeColor: AppInk.ai,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(child: _details(ready)),
          // 移动端只给"已确定"的行留数量列：一个不能用的控件不算信息，
          // 却要吃掉候选行最需要的宽度。（网页端同一条注释，照它做。）
          if (ready)
            SizedBox(
              width: 92,
              child: _QtyField(
                label: l10n.visQtyLabel,
                value: qty,
                onChanged: onQty,
              ),
            ),
        ],
      ),
    );
  }

  /// 「模型读到什么」这一排是卖家判断这一行的唯一依据。
  ///
  /// 网页端用 `flex flex-wrap` + `min-w-0`，Flutter 里对应的容器是 `Wrap`，而 `Wrap`
  /// 不接受 `Flexible`/`Expanded`（那是 `Row`/`Column` 的 ParentData）——放进去 release 包
  /// 会把整棵子树画成一块灰。所以这里一律用普通 `Text`：`Wrap` 已经把子项宽度上限给到
  /// 自己的可用宽，长文本自然折行，两行封顶后截断。
  Widget _details(bool ready) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            StatusPill(
              label: '${l10n.visConfidence} ${(line.confidence * 100).round()}%',
              color: AppInk.textTertiary,
              dense: true,
            ),
            Text(
              <String>[
                '${l10n.visHintWas}：${line.hintWas}',
                if (line.categoryHint.isNotEmpty) line.categoryHint,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppType.foot),
            ),
            if (line.note.isNotEmpty)
              Text(
                '${l10n.visNoteLabel}：${line.note}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: AppType.foot, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        const VGap(8),
        if (ready && resolved != null)
          _ResolvedBlock(
            product: resolved!,
            currency: currency,
            l10n: l10n,
            onTap: onToggle,
            onReselect: onReselect,
          )
        else ...<Widget>[
          Text(
            line.candidates.isEmpty
                ? l10n.visNoMatch
                : (line.truncated
                    ? l10n.visTruncatedHint(line.groupSize, line.candidates.length)
                    : l10n.visChooseTitle(line.groupSize)),
            style: TextStyle(
              fontSize: AppType.foot,
              color: line.candidates.isEmpty ? AppInk.warning : AppInk.textSecondary,
            ),
          ),
          const VGap(6),
          for (final VisionCandidate candidate in line.candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _CandidateTile(
                candidate: candidate,
                picked: resolved?.id == candidate.id,
                currency: currency,
                l10n: l10n,
                onTap: () => onChoose(candidate.product),
              ),
            ),
          GhostButton(
            label: l10n.visManual,
            icon: Icons.search_rounded,
            onPressed: onManual,
          ),
        ],
      ],
    );
  }
}

class _ResolvedBlock extends StatelessWidget {
  const _ResolvedBlock({
    required this.product,
    required this.currency,
    required this.l10n,
    required this.onTap,
    required this.onReselect,
  });

  final Product product;
  final String currency;
  final L10n l10n;
  final VoidCallback onTap;
  final VoidCallback onReselect;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SkuName(sku: product.sku, name: product.name),
                const VGap(4),
                _chips(context, product, currency, l10n),
              ],
            ),
          ),
        ),
        RoundIconButton(
          icon: Icons.swap_horiz_rounded,
          color: AppInk.ai,
          size: 36,
          tooltip: l10n.visReselect,
          onPressed: onReselect,
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.picked,
    required this.currency,
    required this.l10n,
    required this.onTap,
  });

  final VisionCandidate candidate;
  final bool picked;
  final String currency;
  final L10n l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Product product = candidate.product;
    return AppCard(
      accent: picked ? AppInk.ai : null,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: picked ? AppInk.ai : AppInk.textTertiary,
          ),
          const HGap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SkuName(sku: candidate.sku, name: candidate.name),
                const VGap(4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _KindPill(kind: candidate.matchKind, l10n: l10n),
                    ..._metaChips(context, product, currency, l10n),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind, required this.l10n});

  final MatchKind kind;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: kind == MatchKind.none
          ? l10n.visNoMatch
          : l10n.raw('vis_kind_${kind.wire}'),
      color: AppInk.textTertiary,
      dense: true,
    );
  }
}

class _SkuName extends StatelessWidget {
  const _SkuName({required this.sku, required this.name});

  final String sku;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(sku,
            style: const TextStyle(
                fontSize: AppType.body,
                fontWeight: AppType.heavy,
                fontFamily: 'monospace')),
        // 与网页端 `min-w-0`（移动端不 truncate）一致：库位名跟着码排在同一行，
        // 放不下就自己折行，最多两行后截断。Wrap 里不能放 Flexible。
        Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppType.foot)),
      ],
    );
  }
}

/// 柜名 / 库存 / 单价 / 箱规这一排小字，已确定行与候选行共用（网页端也是同构的）。
Widget _chips(BuildContext context, Product product, String currency, L10n l10n) =>
    Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _metaChips(context, product, currency, l10n),
    );

List<Widget> _metaChips(
  BuildContext context,
  Product product,
  String currency,
  L10n l10n,
) {
  final TextStyle foot = const TextStyle(fontSize: AppType.foot);
  return <Widget>[
    Text(
      product.categoryName?.isNotEmpty == true
          ? product.categoryName!
          : l10n.visCategoryNone,
      style: foot,
    ),
    Text(
      '${l10n.visStockHint} ${Fmt.count(product.quantity)}',
      style: foot.copyWith(
        color: product.quantity > 0 ? AppInk.textSecondary : AppInk.warning,
      ),
    ),
    Text(Fmt.money(product.price, symbol: currency), style: foot),
    if ((product.unitsPerBox ?? 0) > 1)
      Text(
        '/${product.unitsPerBox}'
        '${product.boxPrice != null && product.boxPrice! > 0 ? ' · ${Fmt.money(product.boxPrice!, symbol: currency)}' : ''}',
        style: foot,
      ),
  ];
}

/// 数量：识别出来的是草稿数，卖家在这里改定的才是最终进单的那个数。
class _QtyField extends StatefulWidget {
  const _QtyField({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(_QtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 行会被回收复用（筛选切换），控制器得跟上新行的数，否则显示的是上一行的数量。
    if (_controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'^\d*$')),
      ],
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: AppType.body),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
      ),
      onChanged: (String raw) {
        widget.onChanged((int.tryParse(raw.trim()) ?? 0).clamp(0, 999999));
      },
    );
  }
}
