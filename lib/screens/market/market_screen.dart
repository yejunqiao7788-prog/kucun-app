import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/list_controller.dart';
import '../../state/value_loader.dart';

/// 集市：把库存挂到平台公域，接留资、回会话、开投放、看表现。
///
/// 服务端事实决定了这里的形状：
/// 1. `GET /marketplace/listings` 是**选品视图**（商品 + 它的申请单），未申请的商品也在里面；
/// 2. 提审要带 `terms_version`，`pending_review`/`in_review` 两态锁编辑（409 LISTING_LOCKED）；
/// 3. 已上架内容一改就退回草稿并重审，公域投影当场摘掉；
/// 4. 投放只支持 CPL，金额都是最小货币单位；花费读不到时服务端回 null，界面不能塌成 0。
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  late final AppState _app = context.read<AppState>();
  int _tab = 0;

  late final ValueLoader<JsonMap> _config =
      ValueLoader<JsonMap>(() => _app.repos.market.config());

  static const List<int> _tabKeys = <int>[0, 1, 2, 3, 4, 5];

  /// 集市首页直接读 `_config.value`（聊天开关、店铺页），这一层没有 AnimatedBuilder，
  /// 得自己挂监听，否则配置回来后停在首帧的默认值上。
  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _config.addListener(_repaint);
    unawaited(_config.load());
  }

  @override
  void dispose() {
    _config.removeListener(_repaint);
    _config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 10),
              child: Row(
                children: <Widget>[
                  const RoundBackButton(accent: AppInk.marketplace),
                  const HGap(10),
                  Expanded(
                    child: Text(
                      l10n.moduleMarketplace,
                      style: const TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.heavy,
                        color: AppInk.marketplace,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (app.renewalPending)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: NoticeBanner(
                  text: l10n.commonExpiredBanner,
                  color: AppInk.danger,
                  icon: Icons.lock_outline_rounded,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: PillTabs<int>(
                values: _tabKeys,
                selected: _tab,
                accent: AppInk.marketplace,
                labelOf: (int value) => switch (value) {
                  1 => l10n.mpLeads,
                  2 => l10n.mpChats,
                  3 => l10n.mpCampaigns,
                  4 => l10n.mpAnalytics,
                  5 => l10n.mpStore,
                  _ => l10n.mpSupply,
                },
                onChanged: (int value) => setState(() => _tab = value),
              ),
            ),
            const VGap(12),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _SupplyTab(onOpenTab: (int index) => setState(() => _tab = index)),
                  _LeadsTab(),
                  _ChatsTab(chatEnabled: _config.value?.asBool('chat_enabled', fallback: true) ?? true),
                  const _CampaignsTab(),
                  const _AnalyticsTab(),
                  _StoreTab(config: _config),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ———————————————————————————————— 选品 / 供给

class _SupplyTab extends StatefulWidget {
  const _SupplyTab({required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<_SupplyTab> createState() => _SupplyTabState();
}

class _SupplyTabState extends State<_SupplyTab> {
  late final AppState _app = context.read<AppState>();
  late final ListController<MpCandidate> _list = ListController<MpCandidate>(
    fetch: (int page) async {
      final MpCandidatePage res = await _app.repos.market.candidates(
        status: _status,
        keyword: _keyword.isEmpty ? null : _keyword,
        inStockOnly: _inStockOnly,
        page: page,
        pageSize: 24,
      );
      return FetchResult<MpCandidate>(
        rows: res.items,
        hasMore: res.hasMore,
        summary: res,
      );
    },
  );

  final TextEditingController _search = TextEditingController();
  String? _status;
  String _keyword = '';
  bool _inStockOnly = false;

  static const List<String?> _statuses = <String?>[
    null,
    'none',
    'draft',
    'pending_review',
    'published',
    'rejected',
    'paused',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_list.load());
  }

  @override
  void dispose() {
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  MpCandidatePage? get _page => _list.summary is MpCandidatePage ? _list.summary as MpCandidatePage : null;

  Future<void> _openEditor(MpCandidate candidate) async {
    final bool? saved = await pushSheet<bool>(
      context,
      child: ListingEditorScreen(candidate: candidate),
    );
    if (saved == true) await _list.refresh();
  }

  Future<void> _openDetail(MpListing listing) async {
    await pushSheet<void>(context, child: ListingDetailScreen(listingId: listing.id));
    if (!mounted) return;
    await _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final MpCandidatePage? page = _page;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 10),
          child: SearchField(
            controller: _search,
            hintText: l10n.mpSearchHint,
            onChanged: (String value) {
              _keyword = value;
              unawaited(_list.load());
            },
            onSubmitted: (String value) {
              _keyword = value;
              unawaited(_list.load());
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PillTabs<String?>(
                    values: _statuses,
                    selected: _status,
                    accent: AppInk.marketplace,
                    labelOf: (String? value) => switch (value) {
                      'none' => '${l10n.mpNotApplied} ${page?.noneCount ?? ''}'.trim(),
                      'draft' => l10n.mpDraft,
                      'pending_review' => l10n.mpSubmitted,
                      'published' => l10n.mpPublished,
                      'rejected' => l10n.mpRejected,
                      'paused' => l10n.mpPaused,
                      _ => l10n.commonAll,
                    },
                    onChanged: (String? value) {
                      setState(() => _status = value);
                      unawaited(_list.load());
                    },
                  ),
                ),
              ),
              const HGap(8),
              RoundIconButton(
                icon: _inStockOnly ? Icons.inventory_rounded : Icons.inventory_2_outlined,
                size: 38,
                color: _inStockOnly ? AppInk.inventory : AppInk.textTertiary,
                tooltip: l10n.mpInStockOnly,
                onPressed: () {
                  setState(() => _inStockOnly = !_inStockOnly);
                  unawaited(_list.load());
                },
              ),
            ],
          ),
        ),
        if (page != null && page.scanTruncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 10, Space.gutter, 0),
            child: NoticeBanner(
              text: l10n.mpScanTruncated,
              color: AppInk.warning,
              icon: Icons.data_thresholding_rounded,
            ),
          ),
        if (page != null && page.outOfStockCount > 0 && !_inStockOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${l10n.mpOutOfStock} ${Fmt.count(page.outOfStockCount)}',
                    style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
                  ),
                ),
                TextAction(label: l10n.mpInStockOnly, onPressed: () {
                  setState(() => _inStockOnly = true);
                  unawaited(_list.load());
                }),
              ],
            ),
          ),
        Expanded(
          child: PagedView<MpCandidate>(
            controller: _list,
            accent: AppInk.marketplace,
            emptyTitle: l10n.commonEmptyTitle,
            emptyHint: l10n.mpSupplyHint,
            emptyIcon: Icons.storefront_rounded,
            itemBuilder: (BuildContext context, MpCandidate row, int index) {
              final MpListing? listing = row.listing;
              return AppCard(
                accent: AppInk.marketplace,
                padding: const EdgeInsets.all(12),
                onTap: () => listing == null ? _openEditor(row) : _openDetail(listing),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            row.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const VGap(4),
                          Text(
                            _candidateNote(row, l10n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const HGap(8),
                    if (listing == null)
                      StatusPill(label: l10n.mpNewListing, color: AppInk.marketplace, dense: true)
                    else
                      StatusPill(
                        label: _statusLabel(listing.status, l10n),
                        color: _statusColor(listing.status),
                        dense: true,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _candidateNote(MpCandidate row, L10n l10n) {
    final Product? product = row.product;
    final MpListing? listing = row.listing;
    final List<String> parts = <String>[
      if (product != null) product.sku,
      if (product != null) '${Fmt.count(product.quantity)} ${product.unit}',
      if (listing != null) Fmt.money(listing.price, symbol: '${listing.currency} '),
      if (listing == null && row.qualityMax > 0)
        '${l10n.mpQuality} ${row.qualityScore}/${row.qualityMax}',
      if (listing?.categoryRequiresDocument ?? false) l10n.mpNeedsDoc,
    ].where((String part) => part.isNotEmpty).toList();
    return parts.join(' · ');
  }

  static String _statusLabel(ListingStatus status, L10n l10n) => switch (status) {
        ListingStatus.draft => l10n.mpDraft,
        ListingStatus.pendingReview => l10n.mpSubmitted,
        ListingStatus.inReview => l10n.mpInReview,
        ListingStatus.approved => l10n.mpApproved,
        ListingStatus.published => l10n.mpPublished,
        ListingStatus.rejected => l10n.mpRejected,
        ListingStatus.paused => l10n.mpPaused,
        ListingStatus.delisted => l10n.mpDelisted,
        ListingStatus.archived => l10n.mpArchived,
      };

  static Color _statusColor(ListingStatus status) => switch (status) {
        ListingStatus.published => AppInk.success,
        ListingStatus.rejected => AppInk.danger,
        ListingStatus.paused => AppInk.warning,
        ListingStatus.pendingReview || ListingStatus.inReview => AppInk.showroom,
        ListingStatus.approved => AppInk.inventory,
        _ => AppInk.textTertiary,
      };
}

/// 申请单编辑：新建走 `POST /marketplace/listings`（按 product_id upsert）。
class ListingEditorScreen extends StatefulWidget {
  const ListingEditorScreen({super.key, this.candidate, this.listing});

  final MpCandidate? candidate;
  final MpListing? listing;

  @override
  State<ListingEditorScreen> createState() => _ListingEditorScreenState();
}

class _ListingEditorScreenState extends State<ListingEditorScreen> {
  late final AppState _app = context.read<AppState>();

  late final Product? _product = widget.candidate?.product;
  late final MpListing? _origin = widget.candidate?.listing ?? widget.listing;

  late final TextEditingController _titleUk = TextEditingController(text: _origin?.titleUk ?? '');
  late final TextEditingController _titleEn =
      TextEditingController(text: _origin?.titleEn ?? _product?.name ?? '');
  late final TextEditingController _descUk = TextEditingController(text: _origin?.descUk ?? '');
  late final TextEditingController _descEn =
      TextEditingController(text: _origin?.descEn ?? _product?.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: (_origin?.price ?? 0) > 0
        ? _origin!.price.toStringAsFixed(2)
        : (_product != null ? _product.price.toStringAsFixed(2) : ''),
  );
  late final TextEditingController _minQty =
      TextEditingController(text: '${_origin?.minOrderQty ?? 1}');
  late final TextEditingController _leadTime =
      TextEditingController(text: _origin?.leadTimeDays == null ? '' : '${_origin!.leadTimeDays}');

  late bool _onlinePay = _origin?.supportsOnlinePay ?? false;
  late bool _supportUk = _origin?.supportUk ?? false;
  late String? _mpCategoryId = _origin?.mpCategoryId;

  List<JsonMap> _categories = const <JsonMap>[];
  bool _saving = false;
  bool _agreedTerms = false;
  String? _termsVersion;
  String _termsBody = '';

  bool get _isNew => _origin == null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeta());
  }

  Future<void> _loadMeta() async {
    try {
      final List<JsonMap> categories = await _app.repos.market.categories();
      final JsonMap terms = await _app.repos.market.terms();
      final JsonMap current = terms.asMap('current');
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _termsVersion = current.asString('version');
        _termsBody = current.asString('body_zh') ?? current.asString('body_en') ?? '';
        _agreedTerms = _origin?.termsVersion != null;
      });
    } on Object {
      // 类目与条款拉不到时仍可存草稿，提审那一步再挡。
    }
  }

  @override
  void dispose() {
    _titleUk.dispose();
    _titleEn.dispose();
    _descUk.dispose();
    _descEn.dispose();
    _price.dispose();
    _minQty.dispose();
    _leadTime.dispose();
    super.dispose();
  }

  Future<String> _saveDraft() async {
    final String price = _price.text.trim();
    final Map<String, Object?> payload = <String, Object?>{
      'product_id': _product!.id,
      'mp_category_id': _mpCategoryId,
      'title_uk': _titleUk.text.trim().isEmpty ? null : _titleUk.text.trim(),
      'title_en': _titleEn.text.trim().isEmpty ? null : _titleEn.text.trim(),
      'desc_uk': _descUk.text.trim().isEmpty ? null : _descUk.text.trim(),
      'desc_en': _descEn.text.trim().isEmpty ? null : _descEn.text.trim(),
      'price_ukr': double.tryParse(price) ?? 0,
      'min_order_qty': int.tryParse(_minQty.text.trim()) ?? 1,
      'lead_time_days': int.tryParse(_leadTime.text.trim()),
      'supports_online_pay': _onlinePay,
      'support_uk': _supportUk,
      // 图集缺省 = 从商品库继承；显式清空才传空数组。
      if (_termsVersion != null && _agreedTerms) 'terms_version': _termsVersion,
    };
    final JsonMap saved =
        JsonMap.from(await _app.repos.market.saveListing(payload));
    return saved.asStringOr('id', _origin?.id ?? '');
  }

  Future<void> _submit() async {
    if (!_app.canWrite) {
      showToast(context, _app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    if (!_agreedTerms || _termsVersion == null) {
      showToast(context, _app.l10n.mpTermsRequired, danger: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final String id = await _app.guardWrite<String>(_saveDraft);
      if (id.isEmpty) throw StateError(_app.l10n.commonErrorTitle);
      await _app.guardWrite<Object?>(
        () => _app.repos.market.submitListing(id, termsVersion: _termsVersion),
      );
      if (!mounted) return;
      showToast(context, _app.l10n.mpSubmitQueued);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _saveOnly() async {
    if (!_app.canWrite) {
      showToast(context, _app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    final L10n l10n = _app.l10n;
    if (_titleUk.text.trim().isEmpty && _titleEn.text.trim().isEmpty) {
      showToast(context, l10n.mpTitleRequired, danger: true);
      return;
    }
    if ((double.tryParse(_price.text.trim()) ?? 0) <= 0) {
      showToast(context, l10n.mpPriceRequired, danger: true);
      return;
    }
    if (_mpCategoryId == null) {
      showToast(context, l10n.mpCategoryRequired, danger: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _app.guardWrite<String>(_saveDraft);
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final bool locked = _origin?.status.locked ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? l10n.mpNewListing : l10n.actEdit)),
      body: locked
          ? AppErrorView(
              message: l10n.mpLockedEdit,
              icon: Icons.lock_outline_rounded,
              title: l10n.mpSubmitted,
              onRetry: () => Navigator.of(context).pop(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
              children: <Widget>[
                if (_product != null)
                  AppCard(
                    accent: AppInk.products,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(_product.name,
                                  style: Theme.of(context).textTheme.titleMedium),
                              const VGap(2),
                              Text(
                                '${_product.sku} · ${Fmt.count(_product.quantity)} ${_product.unit}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: _product.quantity > 0 ? l10n.mpInStock : l10n.mpOutOfStock,
                          color: _product.quantity > 0 ? AppInk.success : AppInk.warning,
                          dense: true,
                        ),
                      ],
                    ),
                  )
                else if (_origin != null)
                  AppCard(
                    accent: AppInk.products,
                    child: KeyValueRow(
                      label: l10n.mpLinkedProduct,
                      value: _origin.productName ?? _origin.productSku ?? '—',
                      accent: AppInk.products,
                    ),
                  ),
                const VGap(14),
                AppCard(
                  accent: AppInk.marketplace,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: l10n.mpListingTitle, accent: AppInk.marketplace),
                      AppTextField(
                        label: l10n.mpTitleUk,
                        controller: _titleUk,
                        hint: l10n.mpTitleUkHint,
                      ),
                      const VGap(12),
                      AppTextField(label: l10n.mpTitleEn, controller: _titleEn),
                      const VGap(12),
                      AppTextField(
                        label: l10n.mpDescUk,
                        controller: _descUk,
                        maxLines: 3,
                        hint: l10n.mpDescHint,
                      ),
                      const VGap(12),
                      AppTextField(
                        label: l10n.mpDescEn,
                        controller: _descEn,
                        maxLines: 3,
                        hint: l10n.mpDescHint,
                      ),
                    ],
                  ),
                ),
                const VGap(14),
                AppCard(
                  accent: AppInk.finance,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: l10n.mpTradeTerms, accent: AppInk.finance),
                      NumberField(
                        label: l10n.mpPrice,
                        controller: _price,
                        suffix: _origin?.currency ?? 'UAH',
                      ),
                      const VGap(12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: NumberField(
                              label: l10n.mpMinQty,
                              controller: _minQty,
                              allowDecimal: false,
                            ),
                          ),
                          const HGap(10),
                          Expanded(
                            child: NumberField(
                              label: l10n.mpLeadTime,
                              controller: _leadTime,
                              allowDecimal: false,
                              hint: l10n.commonNone,
                            ),
                          ),
                        ],
                      ),
                      const VGap(12),
                      _ToggleTile(
                        label: l10n.mpOnlinePay,
                        value: _onlinePay,
                        onChanged: (bool v) => setState(() => _onlinePay = v),
                      ),
                      _ToggleTile(
                        label: l10n.mpSupportUk,
                        value: _supportUk,
                        onChanged: (bool v) => setState(() => _supportUk = v),
                      ),
                    ],
                  ),
                ),
                const VGap(14),
                AppCard(
                  accent: AppInk.orders,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: l10n.mpPlatformCategory,
                        accent: AppInk.orders,
                        subtitle: l10n.mpCategoryHint,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final JsonMap category in _categories)
                            _CategoryPill(
                              label: category.asStringOr('name_zh',
                                  category.asStringOr('name_en', category.asStringOr('slug', ''))),
                              risky: category.asString('risk_tier') == 'high' ||
                                  category.asBool('requires_document'),
                              selected: _mpCategoryId == category.asString('id'),
                              onTap: () =>
                                  setState(() => _mpCategoryId = category.asString('id')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const VGap(14),
                AppCard(
                  accent: AppInk.settings,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: l10n.mpTerms, accent: AppInk.settings),
                      if (_termsBody.isEmpty)
                        Text(
                          l10n.mpTermsLoading,
                          style: const TextStyle(
                              fontSize: AppType.foot, color: AppInk.textTertiary),
                        )
                      else
                        Text(
                          _termsBody,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppType.foot),
                        ),
                      const VGap(8),
                      InkWell(
                        onTap: () => setState(() => _agreedTerms = !_agreedTerms),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _agreedTerms
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: _agreedTerms ? AppInk.marketplace : AppInk.textTertiary,
                            ),
                            const HGap(8),
                            Expanded(child: Text(l10n.mpTermsAgree)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_origin?.wasPublished ?? false) ...<Widget>[
                  const VGap(14),
                  NoticeBanner(
                    text: l10n.mpReeditNote,
                    color: AppInk.warning,
                    icon: Icons.info_outline_rounded,
                  ),
                ],
                const VGap(20),
                PrimaryButton(
                  label: l10n.mpSubmit,
                  icon: Icons.send_rounded,
                  color: AppInk.marketplace,
                  loading: _saving,
                  onPressed: app.canWrite && _agreedTerms ? _submit : null,
                ),
                const VGap(12),
                GhostButton(
                  label: l10n.mpSaveDraft,
                  icon: Icons.save_outlined,
                  color: AppInk.marketplace,
                  onPressed: app.canWrite && !_saving ? _saveOnly : null,
                ),
              ],
            ),
    );
  }
}

/// 申请单详情：状态、准入门、资质文件与状态机动作。
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<MpListing> _listing =
      ValueLoader<MpListing>(() => _app.repos.market.listing(widget.listingId));
  late final ValueLoader<List<MpDocument>> _docs = ValueLoader<List<MpDocument>>(
    () => _app.repos.market.listingDocuments(widget.listingId),
  );
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_listing.load());
    unawaited(_docs.load());
  }

  @override
  void dispose() {
    _listing.dispose();
    _docs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _listing.refresh();
    await _docs.refresh();
  }

  Future<void> _action(String action) async {
    final L10n l10n = _app.l10n;
    try {
      await _app.guardWrite<void>(() async {
        if (action == 'submit') {
          await _app.repos.market.submitListing(widget.listingId);
        } else if (action == 'boost') {
          await _app.repos.market.boostListing(widget.listingId);
        } else {
          await _app.repos.market.listingAction(widget.listingId, action);
        }
      });
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _edit() async {
    final MpListing? data = _listing.value;
    if (data == null) return;
    final bool? saved = await pushSheet<bool>(
      context,
      child: ListingEditorScreen(listing: data),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _uploadDoc() async {
    final L10n l10n = _app.l10n;
    final String? docType = await showDrawer<String>(
      context,
      title: l10n.mpDocuments,
      accent: AppInk.marketplace,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String key in kDocTypes)
            TileRow(
              icon: Icons.description_outlined,
              title: _docTypeLabel(key, l10n),
              accent: AppInk.marketplace,
              onTap: () => Navigator.of(sheetContext).pop(key),
            ),
        ],
      ),
    );
    if (docType == null || !mounted) return;

    final ImageSource? source = await showDrawer<ImageSource>(
      context,
      title: _docTypeLabel(docType, l10n),
      accent: AppInk.marketplace,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TileRow(
            icon: Icons.photo_camera_rounded,
            title: l10n.prodShootCamera,
            accent: AppInk.marketplace,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          TileRow(
            icon: Icons.photo_library_rounded,
            title: l10n.prodShootAlbum,
            accent: AppInk.marketplace,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (file == null) return;
      final String name = file.name.isEmpty ? '$docType.jpg' : file.name;
      final String path = await _app.storage.uploadPrivateAsset(
        tenantId: _app.profile.tenantId,
        bytes: await file.readAsBytes(),
        fileName: name,
        contentType: 'image/jpeg',
      );
      if (!mounted) return;
      await _app.guardWrite<Object?>(
        () => _app.repos.market.registerDocument(
          listingId: widget.listingId,
          docType: docType,
          storagePath: path,
          originalName: name,
        ),
      );
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final MpListing? data = _listing.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(data?.title.isNotEmpty ?? false ? data!.title : l10n.mpListings),
        actions: <Widget>[
          if (data != null && data.status.editable && app.canWrite)
            IconButton(
              tooltip: l10n.actEdit,
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_listing, _docs]),
        builder: (BuildContext context, Widget? _) {
          if (_listing.loading && data == null) {
            return const SafeArea(child: SkeletonList(count: 4, itemHeight: 80));
          }
          if (data == null) {
            return SafeArea(
              child: AppErrorView(
                message: _listing.errorText ?? l10n.commonErrorTitle,
                onRetry: _listing.load,
              ),
            );
          }
          final List<MpDocument> docs = _docs.value ?? const <MpDocument>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppInk.marketplace,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
              children: <Widget>[
                AppCard(
                  accent: _SupplyTabState._statusColor(data.status),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              data.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          StatusPill(
                            label: _SupplyTabState._statusLabel(data.status, l10n),
                            color: _SupplyTabState._statusColor(data.status),
                          ),
                        ],
                      ),
                      const VGap(12),
                      KeyValueRow(
                        label: l10n.mpPlatformCategory,
                        value: data.mpCategoryName.isEmpty ? '—' : data.mpCategoryName,
                        accent: AppInk.orders,
                      ),
                      KeyValueRow(
                        label: l10n.mpPrice,
                        value: '${Fmt.money(data.price, symbol: '${data.currency} ')} / ${data.minOrderQty} ${data.unit}',
                        accent: AppInk.finance,
                      ),
                      KeyValueRow(
                        label: l10n.mpQuality,
                        value: '${data.quality}/${data.qualityMax}',
                        accent: AppInk.ai,
                      ),
                      KeyValueRow(
                        label: l10n.mpStockQty,
                        value: '${Fmt.count(data.inventoryQty)} ${data.unit}',
                        accent: AppInk.inventory,
                      ),
                      if (data.publicSlug != null)
                        KeyValueRow(
                          label: l10n.mpPublicUrl,
                          value: '${Env.siteBase}/market/p/${data.publicSlug}',
                          accent: AppInk.marketplace,
                        ),
                    ],
                  ),
                ),
                if (data.qualityReasons.isNotEmpty) ...<Widget>[
                  const VGap(14),
                  AppCard(
                    accent: AppInk.showroom,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionHeader(title: l10n.mpQualityTips, accent: AppInk.showroom),
                        for (final JsonMap reason in data.qualityReasons)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Padding(
                                  padding: EdgeInsets.only(right: 8, top: 2),
                                  child: Icon(Icons.circle, size: 6, color: AppInk.showroom),
                                ),
                                Expanded(
                                  child: Text(
                                    reason.asStringOr('message',
                                        reason.asStringOr('code', reason.toString())),
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.rejectReason != null || data.rejectGates.isNotEmpty) ...<Widget>[
                  const VGap(14),
                  NoticeBanner(
                    text: data.rejectReason ?? data.rejectGates.join('、'),
                    color: AppInk.danger,
                    icon: Icons.gpp_maybe_rounded,
                  ),
                ],
                const VGap(18),
                SectionHeader(title: l10n.mpActions, accent: AppInk.marketplace),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (data.status.editable && !data.status.locked)
                      _ActionChip(
                        label: l10n.mpSubmit,
                        icon: Icons.send_rounded,
                        enabled: app.canWrite && _agreedForSubmit(data),
                        onTap: () => _action('submit'),
                      ),
                    _ActionChip(
                      label: l10n.mpBoost,
                      icon: Icons.bolt_rounded,
                      enabled: app.canWrite && data.status == ListingStatus.published,
                      onTap: () => _action('boost'),
                    ),
                    if (data.status.canPause)
                      _ActionChip(
                        label: l10n.mpPause,
                        icon: Icons.pause_circle_outline_rounded,
                        enabled: app.canWrite,
                        onTap: () => _action('pause'),
                      ),
                    if (data.status.canResume)
                      _ActionChip(
                        label: l10n.mpResume,
                        icon: Icons.play_circle_outline_rounded,
                        enabled: app.canWrite,
                        onTap: () => _action('resume'),
                      ),
                    if (data.status.canWithdraw)
                      _ActionChip(
                        label: l10n.mpWithdraw,
                        icon: Icons.undo_rounded,
                        enabled: app.canWrite,
                        onTap: () => _action('withdraw'),
                      ),
                  ],
                ),
                const VGap(20),
                AppCard(
                  accent: AppInk.settings,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: l10n.mpDocuments,
                        accent: AppInk.settings,
                        subtitle: data.categoryRequiresDocument ? l10n.mpNeedsDoc : null,
                        trailing: app.canWrite
                            ? TextAction(
                                label: l10n.actAdd,
                                onPressed: _uploading ? null : _uploadDoc,
                              )
                            : null,
                      ),
                      if (_uploading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: AppSpinner(color: AppInk.marketplace),
                        )
                      else if (docs.isEmpty)
                        Text(
                          l10n.commonEmptyTitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        for (final MpDocument doc in docs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  doc.verified
                                      ? Icons.verified_rounded
                                      : Icons.hourglass_bottom_rounded,
                                  size: 16,
                                  color: doc.verified ? AppInk.success : AppInk.warning,
                                ),
                                const HGap(8),
                                Expanded(
                                  child: Text(
                                    '${doc.fileName} · ${_docTypeLabel(doc.kind, l10n)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                if (app.canWrite)
                                  RoundIconButton(
                                    icon: Icons.delete_outline_rounded,
                                    size: 30,
                                    color: AppInk.danger,
                                    onPressed: () async {
                                      final bool sure = await confirmAction(
                                        context,
                                        title: l10n.mpDocuments,
                                        message: doc.fileName,
                                        confirmLabel: l10n.actDelete,
                                        destructive: true,
                                      );
                                      if (!sure || !context.mounted) return;
                                      try {
                                        await app.guardWrite<void>(
                                          () => app.repos.market.removeDocument(doc.id),
                                        );
                                        if (!context.mounted) return;
                                        showToast(context, l10n.commonDeleted);
                                        await _refresh();
                                      } on Object catch (error) {
                                        if (!context.mounted) return;
                                        showToast(context, app.describeError(error), danger: true);
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static bool _agreedForSubmit(MpListing data) => data.termsVersion != null;
}

/// 线上集市只认这三种 `doc_type`（原项目上传控件里就这三个值），
/// 自造的类型名服务端不一定收。
const List<String> kDocTypes = <String>[
  'business_license',
  'brand_authorization',
  'conformity_certificate',
];

String _docTypeLabel(String kind, L10n l10n) => switch (kind) {
      'business_license' || 'license' => l10n.mpDocLicense,
      'brand_authorization' => l10n.mpDocBrand,
      'conformity_certificate' => l10n.mpDocConformity,
      'quality' => l10n.mpDocQuality,
      'test_report' => l10n.mpDocTestReport,
      _ => l10n.mpDocOther,
    };

// ———————————————————————————————— 留资

class _LeadsTab extends StatefulWidget {
  @override
  State<_LeadsTab> createState() => _LeadsTabState();
}

class _LeadsTabState extends State<_LeadsTab> {
  late final AppState _app = context.read<AppState>();
  late final ListController<MpLead> _list = ListController<MpLead>(
    fetch: (int page) async {
      final Paged<MpLead> res =
          await _app.repos.market.leads(status: _status, page: page, pageSize: 20);
      return FetchResult<MpLead>(rows: res.rows, hasMore: res.hasMore);
    },
  );
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_list.load());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _setStatus(MpLead lead, String status) async {
    try {
      await _app.guardWrite<void>(() => _app.repos.market.setLeadStatus(lead.id, status));
      if (!mounted) return;
      showToast(context, _app.l10n.commonSaved);
      await _list.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _pickStatus(MpLead lead) async {
    final L10n l10n = _app.l10n;
    final String? picked = await showDrawer<String>(
      context,
      title: l10n.mpLeadStatus,
      accent: AppInk.marketplace,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String value in LeadStatus.sellerSettable)
            TileRow(
              icon: Icons.label_outlined,
              title: _leadStatusLabel(value, l10n),
              accent: AppInk.marketplace,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    );
    if (picked != null) await _setStatus(lead, picked);
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: PillTabs<String?>(
            values: const <String?>[null, 'new', 'contacted', 'converted'],
            selected: _status,
            accent: AppInk.marketplace,
            scrollable: false,
            labelOf: (String? value) => switch (value) {
              'new' => l10n.mpLeadNew,
              'contacted' => l10n.mpLeadContacted,
              'converted' => l10n.mpLeadConverted,
              _ => l10n.commonAll,
            },
            onChanged: (String? value) {
              setState(() => _status = value);
              unawaited(_list.load());
            },
          ),
        ),
        const VGap(12),
        NoticeBanner(
          text: l10n.mpContactMasked,
          color: AppInk.info,
          icon: Icons.privacy_tip_outlined,
        ),
        Expanded(
          child: PagedView<MpLead>(
            controller: _list,
            accent: AppInk.marketplace,
            emptyTitle: l10n.commonEmptyTitle,
            emptyHint: l10n.mpNoLeadsHint,
            emptyIcon: Icons.people_alt_outlined,
            itemBuilder: (BuildContext context, MpLead lead, int index) => AppCard(
              accent: AppInk.marketplace,
              padding: const EdgeInsets.all(12),
              onTap: () => _pickStatus(lead),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          lead.contactName ?? lead.contactMasked,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const HGap(8),
                      StatusPill(
                        label: _leadStatusLabel(lead.status.wire, l10n),
                        color: lead.status == LeadStatus.converted
                            ? AppInk.success
                            : lead.status == LeadStatus.new_
                                ? AppInk.marketplace
                                : AppInk.textSecondary,
                        dense: true,
                      ),
                    ],
                  ),
                  const VGap(6),
                  Text(
                    lead.demandNote ?? lead.listingTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const VGap(6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${lead.quantity} ${lead.listingTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        l10n.elapsed(lead.createdAt),
                        style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _leadStatusLabel(String wire, L10n l10n) => switch (wire) {
        'contacted' => l10n.mpLeadContacted,
        'confirmed' => l10n.mpLeadConfirmed,
        'converted' => l10n.mpLeadConverted,
        'declined' => l10n.mpLeadDeclined,
        'spam' => l10n.mpLeadSpam,
        'expired' => l10n.mpLeadExpired,
        _ => l10n.mpLeadNew,
      };
}

// ———————————————————————————————— 会话

class _ChatsTab extends StatefulWidget {
  const _ChatsTab({required this.chatEnabled});

  final bool chatEnabled;

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  late final AppState _app = context.read<AppState>();
  late final ListController<MpConversation> _list = ListController<MpConversation>(
    fetch: (int page) async {
      final Paged<MpConversation> res =
          await _app.repos.market.conversations(filter: _filter, page: page, pageSize: 20);
      return FetchResult<MpConversation>(rows: res.rows, hasMore: res.hasMore);
    },
  );
  String? _filter;

  @override
  void initState() {
    super.initState();
    unawaited(_list.load());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _open(MpConversation conversation) async {
    await pushSheet<void>(
      context,
      child: ConversationScreen(conversationId: conversation.id, chatEnabled: widget.chatEnabled),
    );
    if (!mounted) return;
    await _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: PillTabs<String?>(
            values: const <String?>[null, 'open', 'unread'],
            selected: _filter,
            accent: AppInk.marketplace,
            scrollable: false,
            labelOf: (String? value) => switch (value) {
              'open' => l10n.mpChatOpen,
              'unread' => l10n.mpChatUnread,
              _ => l10n.commonAll,
            },
            onChanged: (String? value) {
              setState(() => _filter = value);
              unawaited(_list.load());
            },
          ),
        ),
        const VGap(12),
        if (!widget.chatEnabled)
          NoticeBanner(
            text: l10n.mpChatClosed,
            color: AppInk.warning,
            icon: Icons.chat_bubble_outline_rounded,
          ),
        Expanded(
          child: PagedView<MpConversation>(
            controller: _list,
            accent: AppInk.marketplace,
            emptyTitle: l10n.commonEmptyTitle,
            emptyHint: l10n.mpNoChatsHint,
            emptyIcon: Icons.forum_outlined,
            itemBuilder: (BuildContext context, MpConversation row, int index) => AppCard(
              accent: AppInk.marketplace,
              padding: const EdgeInsets.all(12),
              onTap: () => _open(row),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          row.buyerName ?? row.buyerPhoneMasked,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const VGap(2),
                        Text(
                          row.listingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const VGap(4),
                        Text(
                          row.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const HGap(8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        l10n.elapsed(row.lastMessageAt),
                        style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
                      ),
                      if (row.sellerUnread > 0) ...<Widget>[
                        const VGap(4),
                        StatusPill(label: '${row.sellerUnread}', color: AppInk.danger, dense: true),
                      ],
                      if (row.status != 'open') ...<Widget>[
                        const VGap(4),
                        StatusPill(label: row.status, color: AppInk.textTertiary, dense: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.chatEnabled,
  });

  final String conversationId;
  final bool chatEnabled;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<MpConversation> _thread = ValueLoader<MpConversation>(
    () => _app.repos.market.conversation(widget.conversationId),
  );
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_thread.load());
  }

  @override
  void dispose() {
    _thread.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _app.guardWrite<void>(() => _app.repos.market.reply(widget.conversationId, body));
      _input.clear();
      await _thread.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _inviteLead() async {
    try {
      await _app.guardWrite<JsonMap>(
        () => _app.repos.market.inviteLead(widget.conversationId),
      );
      if (!mounted) return;
      showToast(context, _app.l10n.mpLeadInvited);
      await _thread.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await _app.guardWrite<void>(
        () => _app.repos.market.setConversationStatus(widget.conversationId, status),
      );
      if (!mounted) return;
      showToast(context, _app.l10n.commonSaved);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(_thread.value?.listingTitle ?? l10n.mpChats),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.mpChatClose,
            onPressed: app.canWrite ? () => _setStatus('closed') : null,
            icon: const Icon(Icons.link_off_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _thread,
        builder: (BuildContext context, Widget? _) {
          if (_thread.loading && _thread.value == null) {
            return const SafeArea(child: SkeletonList(count: 5, itemHeight: 56));
          }
          final MpConversation? data = _thread.value;
          if (data == null) {
            return SafeArea(
              child: AppErrorView(message: _thread.errorText ?? l10n.commonErrorTitle, onRetry: _thread.load),
            );
          }
          return Column(
            children: <Widget>[
              if (data.listingSlugStatus != null && data.listingSlugStatus != 'active')
                NoticeBanner(
                  text: l10n.mpListingHidden,
                  color: AppInk.warning,
                  icon: Icons.visibility_off_outlined,
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 8),
                  reverse: true,
                  children: <Widget>[
                    TextAction(
                      label: l10n.mpInviteLead,
                      color: AppInk.marketplace,
                      onPressed: app.canWrite ? _inviteLead : null,
                    ),
                    const VGap(10),
                    for (final MpMessage message in data.messages.reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: message.sender == 'seller'
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: AppCard(
                            accent: message.sender == 'seller' ? AppInk.marketplace : null,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 0),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(message.body, style: Theme.of(context).textTheme.bodyMedium),
                                  const VGap(2),
                                  Text(
                                    l10n.elapsed(message.createdAt),
                                    style: const TextStyle(
                                        fontSize: AppType.micro, color: AppInk.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (data.messages.isEmpty)
                      AppEmpty(title: l10n.commonEmptyTitle, hint: l10n.mpNoChatsHint),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: AppTextField(
                          label: l10n.mpReply,
                          controller: _input,
                          hint: l10n.mpReplyHint,
                          enabled: widget.chatEnabled && app.canWrite,
                          onSubmitted: (String _) => _send(),
                        ),
                      ),
                      const HGap(8),
                      RoundIconButton(
                        icon: Icons.send_rounded,
                        color: AppInk.marketplace,
                        onPressed: widget.chatEnabled && app.canWrite && !_sending ? _send : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ———————————————————————————————— 投放

class _CampaignsTab extends StatefulWidget {
  const _CampaignsTab();

  @override
  State<_CampaignsTab> createState() => _CampaignsTabState();
}

class _CampaignsTabState extends State<_CampaignsTab> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<MpCampaignPage> _page =
      ValueLoader<MpCampaignPage>(() => _app.repos.market.campaigns());

  @override
  void initState() {
    super.initState();
    unawaited(_page.load());
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final MpCampaignPage? board = _page.value;
    if (board == null) return;
    final MpCandidatePage supply =
        await _app.repos.market.candidates(status: 'published', pageSize: 50);
    if (!mounted) return;
    final List<MpListing> published = supply.items
        .map((MpCandidate row) => row.listing)
        .whereType<MpListing>()
        .toList(growable: false);
    if (published.isEmpty) {
      showToast(context, _app.l10n.mpNoPublishedListing, danger: true);
      return;
    }
    final bool? created = await pushSheet<bool>(
      context,
      child: CampaignEditorScreen(listings: published, currency: board.currency),
    );
    if (created == true) await _page.refresh();
  }

  Future<void> _patch(MpCampaign campaign, Map<String, Object?> changes) async {
    try {
      await _app.guardWrite<void>(
        () => _app.repos.market.patchCampaign(
          campaign.id,
          status: changes['status'] as String?,
          dailyCapMinor: changes['daily_cap_minor'] as int?,
          totalBudgetMinor: changes['total_budget_minor'] as int?,
          clearBudget: changes['clear_budget'] == true,
          endedAt: changes['ended_at'] as String?,
          clearEndedAt: changes['clear_ended_at'] == true,
        ),
      );
      if (!mounted) return;
      showToast(context, _app.l10n.commonSaved);
      await _page.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _manage(MpCampaign campaign) async {
    final L10n l10n = _app.l10n;
    final String currency = _page.value?.currency ?? 'UAH';
    final TextEditingController cap =
        TextEditingController(text: campaign.dailyCap.toStringAsFixed(2));
    final TextEditingController budget = TextEditingController(
      text: campaign.budget == null ? '' : campaign.budget!.toStringAsFixed(2),
    );

    final Object? result = await showDrawer<Object?>(
      context,
      title: campaign.listingTitle,
      accent: AppInk.marketplace,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NumberField(
            label: l10n.mpDailyCap,
            controller: cap,
            suffix: currency,
          ),
          const VGap(12),
          NumberField(
            label: l10n.mpBudget,
            controller: budget,
            suffix: currency,
            hint: l10n.mpBudgetNone,
          ),
          const VGap(14),
          PrimaryButton(
            label: l10n.actSave,
            color: AppInk.marketplace,
            onPressed: () => Navigator.of(sheetContext).pop(<String, Object?>{
              'daily_cap_minor': ((double.tryParse(cap.text.trim()) ?? 0) * 100).round(),
              'total_budget_minor': ((double.tryParse(budget.text.trim()) ?? 0) * 100).round(),
              'clear_budget': budget.text.trim().isEmpty,
            }),
          ),
        ],
      ),
    );
    if (result is! Map || !mounted) return;
    await _patch(campaign, Map<String, Object?>.from(result));
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final MpCampaignPage? board = _page.value;

    return AnimatedBuilder(
      animation: _page,
      builder: (BuildContext context, Widget? _) {
        if (_page.loading && board == null) {
          return const SafeArea(child: SkeletonList(count: 3, itemHeight: 120));
        }
        if (board == null) {
          return SafeArea(
            child: AppErrorView(message: _page.errorText ?? l10n.commonErrorTitle, onRetry: _page.load),
          );
        }
        if (_page.adEnabledBlocked) {
          return SafeArea(
            child: AppEmpty(
              title: l10n.mpAdsClosed,
              hint: l10n.mpAdsClosedHint,
              icon: Icons.campaign_rounded,
              accent: AppInk.textTertiary,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _page.refresh,
          color: AppInk.marketplace,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
            children: <Widget>[
              if (board.adEnabledReadFailed)
                NoticeBanner(
                  text: l10n.mpAdStateUnknown,
                  color: AppInk.warning,
                  icon: Icons.help_outline_rounded,
                ),
              if (board.warningText != null)
                NoticeBanner(
                  text: board.warningText!,
                  color: AppInk.info,
                  icon: Icons.info_outline_rounded,
                ),
              AppCard(
                accent: AppInk.marketplace,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${Fmt.count(board.activeCount)} / ${Fmt.count(board.total)}',
                            style: const TextStyle(
                              fontSize: AppType.title,
                              fontWeight: AppType.heavy,
                              color: AppInk.marketplace,
                            ),
                          ),
                          const VGap(4),
                          Text(
                            board.priced
                                ? '${l10n.mpCpl} ${Fmt.money((board.baseLeadMinor ?? 0) / 100.0, symbol: '${board.currency} ')}'
                                : l10n.mpNotPriced,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (board.adSlotCap > 0)
                            Text(
                              '${l10n.mpSlotCap} ${Fmt.count(board.adSlotCap)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (app.canWrite && board.priced)
                      RoundIconButton(
                        icon: Icons.add_rounded,
                        color: AppInk.marketplace,
                        tooltip: l10n.mpNewCampaign,
                        onPressed: _create,
                      ),
                  ],
                ),
              ),
              const VGap(14),
              if (board.items.isEmpty)
                AppEmpty(
                  title: l10n.commonEmptyTitle,
                  hint: l10n.mpNoCampaignHint,
                  icon: Icons.trending_up_rounded,
                  accent: AppInk.marketplace,
                )
              else
                for (final MpCampaign campaign in board.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CampaignCard(
                      campaign: campaign,
                      currency: board.currency,
                      canWrite: app.canWrite,
                      onManage: () => _manage(campaign),
                      onStatus: (String status) =>
                          _patch(campaign, <String, Object?>{'status': status}),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

extension on ValueLoader<MpCampaignPage> {
  /// 未开放且不是「读不到」才拦 —— 读失败时让页面自己报警，不静默变成「未开放」。
  bool get adEnabledBlocked => value != null && !value!.adEnabled && !value!.adEnabledReadFailed;
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.currency,
    required this.canWrite,
    required this.onManage,
    required this.onStatus,
  });

  final MpCampaign campaign;
  final String currency;
  final bool canWrite;
  final VoidCallback onManage;
  final ValueChanged<String> onStatus;

  String _minor(double? value) =>
      value == null ? '—' : Fmt.money(value, symbol: '$currency ');

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    final double? ratio = campaign.spentRatio;

    return AppCard(
      accent: campaign.isActive ? AppInk.marketplace : AppInk.textTertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  campaign.listingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const HGap(8),
              StatusPill(
                label: _campaignStatusLabel(campaign.status, l10n),
                color: campaign.isActive
                    ? AppInk.success
                    : campaign.isExhausted
                        ? AppInk.warning
                        : AppInk.textTertiary,
                dense: true,
              ),
            ],
          ),
          const VGap(10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: <Widget>[
              _Fact(label: l10n.mpDailyCap, value: _minor(campaign.dailyCap)),
              _Fact(label: l10n.mpBudget, value: campaign.budget == null ? l10n.mpBudgetNone : _minor(campaign.budget)),
              _Fact(
                label: l10n.mpSpent,
                value: campaign.spendReadFailed
                    ? l10n.mpSpendUnknown
                    : _minor(campaign.spent),
              ),
              _Fact(label: l10n.mpCpl, value: campaign.estCpl == null ? '—' : _minor(campaign.estCpl)),
            ],
          ),
          if (ratio != null) ...<Widget>[
            const VGap(10),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.chip),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppInk.surfaceDim,
                valueColor: AlwaysStoppedAnimation<Color>(
                  ratio >= 1 ? AppInk.danger : AppInk.marketplace,
                ),
              ),
            ),
          ],
          if (campaign.dailyCapReached) ...<Widget>[
            const VGap(8),
            Text(
              l10n.mpDailyCapHit,
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.warning),
            ),
          ],
          if (campaign.slotGrantedNow == false) ...<Widget>[
            const VGap(8),
            Text(
              l10n.mpNoSlot,
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
          ],
          if (!campaign.qualityPass) ...<Widget>[
            const VGap(8),
            Text(
              l10n.mpQualityFail,
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.danger),
            ),
          ],
          const VGap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ActionChip(
                label: l10n.actEdit,
                icon: Icons.tune_rounded,
                enabled: canWrite && campaign.status != 'canceled',
                onTap: onManage,
              ),
              if (campaign.isActive)
                _ActionChip(
                  label: l10n.mpPause,
                  icon: Icons.pause_circle_outline_rounded,
                  enabled: canWrite,
                  onTap: () => onStatus('paused'),
                ),
              if (campaign.status == 'paused')
                _ActionChip(
                  label: l10n.mpResume,
                  icon: Icons.play_circle_outline_rounded,
                  enabled: canWrite,
                  onTap: () => onStatus('active'),
                ),
              if (campaign.isExhausted && campaign.restartAvailable == true)
                _ActionChip(
                  label: l10n.mpRestart,
                  icon: Icons.restart_alt_rounded,
                  enabled: canWrite,
                  onTap: () => onStatus('active'),
                ),
              if (campaign.status != 'canceled' && campaign.status != 'completed')
                _ActionChip(
                  label: l10n.mpCancelCampaign,
                  icon: Icons.stop_circle_outlined,
                  enabled: canWrite,
                  danger: true,
                  onTap: () => onStatus('canceled'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _campaignStatusLabel(String status, L10n l10n) => switch (status) {
        'active' => l10n.mpCampaignActive,
        'paused' => l10n.mpPaused,
        'exhausted' => l10n.mpCampaignExhausted,
        'completed' => l10n.mpCampaignCompleted,
        'canceled' => l10n.mpCampaignCanceled,
        _ => l10n.mpCampaignDraft,
      };
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(fontSize: AppType.body, fontWeight: AppType.semi),
        ),
        Text(label,
            style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary)),
      ],
    );
  }
}

class CampaignEditorScreen extends StatefulWidget {
  const CampaignEditorScreen({
    super.key,
    required this.listings,
    required this.currency,
  });

  final List<MpListing> listings;
  final String currency;

  @override
  State<CampaignEditorScreen> createState() => _CampaignEditorScreenState();
}

class _CampaignEditorScreenState extends State<CampaignEditorScreen> {
  late final AppState _app = context.read<AppState>();
  late MpListing _chosen = widget.listings.first;
  final TextEditingController _cap = TextEditingController(text: '200');
  final TextEditingController _budget = TextEditingController(text: '');
  bool _saving = false;

  @override
  void dispose() {
    _cap.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final L10n l10n = _app.l10n;
    final int capMinor = ((double.tryParse(_cap.text.trim()) ?? 0) * 100).round();
    if (capMinor <= 0) {
      showToast(context, l10n.mpDailyCapRequired, danger: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _app.guardWrite<void>(
        () => _app.repos.market.createCampaign(
          listingId: _chosen.id,
          dailyCapMinor: capMinor,
          totalBudgetMinor: ((double.tryParse(_budget.text.trim()) ?? 0) * 100).round() == 0
              ? null
              : ((double.tryParse(_budget.text.trim()) ?? 0) * 100).round(),
        ),
      );
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mpNewCampaign)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
        children: <Widget>[
          SectionHeader(title: l10n.mpListings, accent: AppInk.marketplace),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final MpListing listing in widget.listings)
                _CategoryPill(
                  label: listing.title,
                  selected: _chosen.id == listing.id,
                  accentOverride: AppInk.marketplace,
                  onTap: () => setState(() => _chosen = listing),
                ),
            ],
          ),
          const VGap(18),
          NumberField(
            label: l10n.mpDailyCap,
            controller: _cap,
            suffix: widget.currency,
          ),
          const VGap(12),
          NumberField(
            label: l10n.mpBudget,
            controller: _budget,
            suffix: widget.currency,
            hint: l10n.mpBudgetNone,
          ),
          const VGap(8),
          Text(
            l10n.mpStartDateNote,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          const VGap(20),
          PrimaryButton(
            label: _saving ? l10n.commonSaving : l10n.mpNewCampaign,
            icon: Icons.bolt_rounded,
            color: AppInk.marketplace,
            loading: _saving,
            onPressed: app.canWrite ? _save : null,
          ),
        ],
      ),
    );
  }
}

// ———————————————————————————————— 表现

class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab();

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<MpAnalytics> _data =
      ValueLoader<MpAnalytics>(() => _app.repos.market.analytics(days: _days));
  int _days = 7;

  @override
  void initState() {
    super.initState();
    unawaited(_data.load());
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _boost(MpAnalyticsRow row) async {
    if (row.slug == null) return;
    try {
      await _app.guardWrite<void>(() async {
        final MpCandidatePage page =
            await _app.repos.market.candidates(status: 'published', keyword: row.title, pageSize: 50);
        final MpListing? listing = page.items
            .map((MpCandidate candidate) => candidate.listing)
            .whereType<MpListing>()
            .where((MpListing item) => item.publicSlug == row.slug)
            .firstOrNull;
        if (listing == null) throw StateError(_app.l10n.mpNotFound);
        await _app.repos.market.boostListing(listing.id);
      });
      if (!mounted) return;
      showToast(context, _app.l10n.mpBoostQueued);
      await _data.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final MpAnalytics? data = _data.value;

    return AnimatedBuilder(
      animation: _data,
      builder: (BuildContext context, Widget? _) {
        if (_data.loading && data == null) {
          return const SafeArea(child: SkeletonList(count: 4, itemHeight: 110));
        }
        if (data == null) {
          return SafeArea(
            child: AppErrorView(message: _data.errorText ?? l10n.commonErrorTitle, onRetry: _data.load),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
          children: <Widget>[
            PillTabs<int>(
              values: const <int>[7, 14, 30],
              selected: _days,
              accent: AppInk.marketplace,
              scrollable: false,
              labelOf: (int value) => '$value${l10n.mpDaysSuffix}',
              onChanged: (int value) {
                setState(() => _days = value);
                unawaited(_data.refresh());
              },
            ),
            const VGap(12),
            if (data.truncated)
              NoticeBanner(
                text: l10n.finTruncated,
                color: AppInk.warning,
                icon: Icons.data_thresholding_rounded,
              ),
            if (data.warningText != null)
              NoticeBanner(
                text: data.warningText!,
                color: AppInk.info,
                icon: Icons.info_outline_rounded,
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: l10n.mpImpressions,
                    value: Fmt.count(data.impressions),
                    accent: AppInk.marketplace,
                    icon: Icons.visibility_rounded,
                  ),
                ),
                const HGap(10),
                Expanded(
                  child: StatTile(
                    label: l10n.mpClicks,
                    value: '${Fmt.count(data.clicks)}${data.ctr == null ? '' : ' · ${Fmt.percent(data.ctr!)}'}',
                    accent: AppInk.ai,
                    icon: Icons.ads_click_rounded,
                  ),
                ),
              ],
            ),
            const VGap(10),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: l10n.mpLeads,
                    value: '${Fmt.count(data.leads)} · ${Fmt.count(data.leadsPending)} ${l10n.mpLeadNew}',
                    accent: AppInk.orders,
                    icon: Icons.people_alt_rounded,
                    footnote: data.leadRate == null ? null : '${l10n.mpLeadRate} ${Fmt.percent(data.leadRate!)}',
                  ),
                ),
                const HGap(10),
                Expanded(
                  child: StatTile(
                    label: l10n.mpViews,
                    value: Fmt.count(data.productViews),
                    accent: AppInk.products,
                    icon: Icons.category_rounded,
                    footnote: '${l10n.mpChats} ${Fmt.count(data.chats)}',
                  ),
                ),
              ],
            ),
            const VGap(18),
            SectionHeader(
              title: l10n.mpListingBoard,
              accent: AppInk.marketplace,
              subtitle: '${l10n.mpPublicNow} ${Fmt.count(data.publicNowCount)} · ${l10n.mpMuted} ${Fmt.count(data.mutedCount)}',
            ),
            if (data.rows.isEmpty)
              AppEmpty(title: l10n.commonEmptyTitle, hint: l10n.mpNoRowsHint)
            else
              for (final MpAnalyticsRow row in data.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PerfRow(
                    row: row,
                    l10n: l10n,
                    canWrite: app.canWrite,
                    onBoost: () => _boost(row),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PerfRow extends StatelessWidget {
  const _PerfRow({
    required this.row,
    required this.l10n,
    required this.canWrite,
    required this.onBoost,
  });

  final MpAnalyticsRow row;
  final L10n l10n;
  final bool canWrite;
  final VoidCallback onBoost;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: row.isMuted ? AppInk.textTertiary : AppInk.marketplace,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const HGap(8),
              if (row.isMuted)
                StatusPill(label: l10n.mpMuted, color: AppInk.danger, dense: true)
              else if (row.publicNow)
                StatusPill(label: l10n.mpPublicNow, color: AppInk.success, dense: true),
            ],
          ),
          const VGap(10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: <Widget>[
              _Fact(label: l10n.mpImpressions, value: Fmt.count(row.impressions)),
              _Fact(
                label: l10n.mpClicks,
                value: row.ctr == null
                    ? Fmt.count(row.clicks)
                    : '${Fmt.count(row.clicks)} · ${Fmt.percent(row.ctr!)}',
              ),
              _Fact(label: l10n.mpLeads, value: Fmt.count(row.leads)),
              _Fact(
                label: l10n.mpTtfr,
                value: row.ttfrHours == null ? '—' : '${row.ttfrHours!.toStringAsFixed(1)}h',
              ),
              _Fact(
                label: l10n.mpQuality,
                value: '${row.qualityScore}/${row.qualityMax}',
              ),
            ],
          ),
          if (row.rankReasons.isNotEmpty) ...<Widget>[
            const VGap(8),
            Text(
              row.rankReasons
                  .map((JsonMap reason) =>
                      reason.asStringOr('message', reason.asStringOr('code', '')))
                  .where((String text) => text.isNotEmpty)
                  .join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
          ],
          const VGap(12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.scoreStale ? l10n.mpScoreStale : '',
                  style: const TextStyle(fontSize: AppType.foot, color: AppInk.warning),
                ),
              ),
              _ActionChip(
                label: l10n.mpBoost,
                icon: Icons.bolt_rounded,
                enabled: canWrite && !row.boostCoolingDown && row.publicNow,
                hint: row.boostCoolingDown && row.boostAvailableAt != null
                    ? l10n.elapsed(row.boostAvailableAt)
                    : null,
                onTap: onBoost,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ———————————————————————————————— 店铺

class _StoreTab extends StatefulWidget {
  const _StoreTab({required this.config});

  final ValueLoader<JsonMap> config;

  @override
  State<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<_StoreTab> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<MpSeller> _seller =
      ValueLoader<MpSeller>(() => _app.repos.market.seller());
  late final ValueLoader<TelegramBinding> _telegram =
      ValueLoader<TelegramBinding>(() => _app.repos.market.telegram());
  late final ValueLoader<List<JsonMap>> _mappings =
      ValueLoader<List<JsonMap>>(() => _app.repos.market.mappings());

  @override
  void initState() {
    super.initState();
    unawaited(_seller.load());
    unawaited(_telegram.load());
    unawaited(_mappings.load());
  }

  @override
  void dispose() {
    _seller.dispose();
    _telegram.dispose();
    _mappings.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final L10n l10n = _app.l10n;
    final TextEditingController controller =
        TextEditingController(text: _seller.value?.rawSellerName ?? '');
    final String? name = await showDrawer<String>(
      context,
      title: l10n.mpSellerProfile,
      accent: AppInk.marketplace,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppTextField(label: l10n.mpStoreName, controller: controller, autofocus: true),
          const VGap(6),
          Text(
            l10n.mpStoreNameNote,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            color: AppInk.marketplace,
            onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !_app.canWrite) return;
    try {
      await _app.guardWrite<void>(() => _app.repos.market.renameSeller(name));
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      await _seller.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  /// 映射只有「新建」这一支写操作：服务端没有解绑接口，改映射等于覆盖同一本店类目。
  Future<void> _addMapping() async {
    final L10n l10n = _app.l10n;
    final List<String> mapped = (_mappings.value ?? const <JsonMap>[])
        .map((JsonMap row) => row.asStringOr('tenant_category_id', ''))
        .toList(growable: false);
    final List<Category> tenantCategories;
    final List<JsonMap> mpCategories;
    try {
      tenantCategories = await _app.repos.products.categories();
      mpCategories = await _app.repos.market.categories();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
      return;
    }
    final List<Category> free =
        tenantCategories.where((Category c) => !mapped.contains(c.id)).toList();
    if (!mounted) return;
    if (free.isEmpty) {
      showToast(context, l10n.mpMappingAllDone);
      return;
    }
    if (mpCategories.isEmpty) {
      showToast(context, l10n.mpCategoryRequired, danger: true);
      return;
    }
    final Category? tenant = await _pickSheet<Category>(
      title: l10n.mpMappingPickTenant,
      items: free,
      labelOf: (Category c) => c.name,
      detailOf: (Category c) => '${Fmt.count(c.productCount)} ${l10n.unitPiece}',
    );
    if (tenant == null || !mounted) return;
    final JsonMap? mp = await _pickSheet<JsonMap>(
      title: l10n.mpMappingPickMp,
      items: mpCategories,
      labelOf: (JsonMap c) => c.asStringOr(
          'name_zh', c.asStringOr('name_en', c.asStringOr('slug', '—'))),
      detailOf: (JsonMap c) => c.asStringOr('slug', ''),
    );
    final String mpId = mp?.asStringOr('id', '') ?? '';
    if (mpId.isEmpty || !_app.canWrite) return;
    try {
      await _app.guardWrite<void>(
        () => _app.repos.market.saveMapping(tenant.id, mpId),
      );
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      await _mappings.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<T?> _pickSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T item) labelOf,
    required String Function(T item) detailOf,
  }) {
    return showDrawer<T>(
      context,
      title: title,
      accent: AppInk.orders,
      maxHeightFactor: 0.62,
      builder: (BuildContext sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final T item in items)
              TileRow(
                icon: Icons.label_outline_rounded,
                accent: AppInk.orders,
                title: labelOf(item),
                subtitle: detailOf(item).isEmpty ? null : detailOf(item),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _bindTelegram() async {
    final L10n l10n = _app.l10n;
    final TextEditingController token = TextEditingController();
    final TextEditingController chatId = TextEditingController();

    final Object? result = await showDrawer<Object?>(
      context,
      title: l10n.mpTelegram,
      accent: AppInk.marketplace,
      maxHeightFactor: 0.86,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppTextField(
            label: l10n.mpTgToken,
            controller: token,
            obscure: true,
            hint: l10n.mpTgTokenHint,
          ),
          const VGap(12),
          AppTextField(
            label: l10n.mpTgChatId,
            controller: chatId,
            hint: l10n.mpTgChatIdHint,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            ],
          ),
          const VGap(8),
          Text(
            l10n.mpTgNote,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.mpTelegramBind,
            color: AppInk.marketplace,
            onPressed: () => Navigator.of(sheetContext).pop(<String, Object?>{
              'token': token.text.trim(),
              'chat': chatId.text.trim(),
            }),
          ),
        ],
      ),
    );
    if (result is! Map || !_app.canWrite) return;
    final String tokenValue = result['token'] as String? ?? '';
    if (tokenValue.isEmpty) return;
    try {
      final TelegramBinding bound = await _app.guardWrite<TelegramBinding>(
        () => _app.repos.market.bindTelegram(
          botToken: tokenValue,
          chatId: result['chat'] as String?,
        ),
      );
      if (!mounted) return;
      showToast(
        context,
        bound.testDelivered == false ? l10n.mpTgNotDelivered : l10n.commonSaved,
        danger: bound.testDelivered == false,
      );
      await _telegram.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _toggleNotify(bool enabled) async {
    try {
      await _app.guardWrite<void>(() => _app.repos.market.setTelegramNotify(enabled));
      await _telegram.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _copyStoreLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showToast(context, _app.l10n.commonCopied);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final MpSeller? seller = _seller.value;
    final TelegramBinding? tg = _telegram.value;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_seller, _telegram, _mappings]),
      builder: (BuildContext context, Widget? _) => RefreshIndicator(
        onRefresh: () => Future.wait<void>(<Future<void>>[
          _seller.refresh(),
          _telegram.refresh(),
          _mappings.refresh(),
        ]),
        color: AppInk.marketplace,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
          children: <Widget>[
            if (_seller.loading && seller == null)
              const SkeletonList(count: 3, itemHeight: 100)
            else if (seller != null)
              AppCard(
                accent: AppInk.marketplace,
                onTap: app.canWrite ? _rename : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            seller.sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (app.canWrite)
                          const Icon(Icons.edit_outlined, size: 18, color: AppInk.textTertiary),
                      ],
                    ),
                    const VGap(6),
                    KeyValueRow(label: l10n.setTenant, value: seller.tenantName),
                    KeyValueRow(
                      label: l10n.mpPublicListings,
                      value: '${Fmt.count(seller.publicListings)} · ${l10n.mpProjected} ${Fmt.count(seller.projectedListings)}',
                      accent: AppInk.products,
                    ),
                    if (seller.hasStore) ...<Widget>[
                      const VGap(10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${Env.siteBase}${seller.storePath}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: AppType.foot, color: AppInk.marketplace),
                            ),
                          ),
                          RoundIconButton(
                            icon: Icons.copy_rounded,
                            size: 34,
                            color: AppInk.marketplace,
                            tooltip: l10n.actCopy,
                            onPressed: () =>
                                _copyStoreLink('${Env.siteBase}${seller.storePath}'),
                          ),
                          const HGap(6),
                          RoundIconButton(
                            icon: Icons.open_in_new_rounded,
                            size: 34,
                            color: AppInk.marketplace,
                            tooltip: l10n.actOpen,
                            onPressed: () => launchUrl(
                              Uri.parse('${Env.siteBase}${seller.storePath}'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                      ),
                    ] else if (seller.isHiddenStore)
                      Text(
                        l10n.mpStoreHidden,
                        style: const TextStyle(fontSize: AppType.foot, color: AppInk.warning),
                      ),
                  ],
                ),
              ),
            const VGap(14),
            AppCard(
              accent: AppInk.ai,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    title: l10n.mpTelegram,
                    accent: AppInk.ai,
                    trailing: app.canWrite
                        ? TextAction(
                            label: (tg?.bound ?? false) ? l10n.actEdit : l10n.mpTelegramBind,
                            color: AppInk.ai,
                            onPressed: _bindTelegram,
                          )
                        : null,
                  ),
                  if (tg == null)
                    Text(
                      _telegram.errorText ?? l10n.commonLoading,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else if (!tg.bound)
                    Text(
                      l10n.mpTgUnbound,
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else ...<Widget>[
                    KeyValueRow(
                      label: l10n.mpTgBot,
                      value: tg.botUsername == null ? '—' : '@${tg.botUsername}',
                      accent: AppInk.ai,
                    ),
                    KeyValueRow(label: l10n.mpTgChat, value: tg.chatMasked, accent: AppInk.ai),
                    const VGap(6),
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(l10n.mpTgNotify)),
                        Switch.adaptive(
                          value: tg.notifyEnabled,
                          activeThumbColor: AppInk.ai,
                          onChanged: app.canWrite ? _toggleNotify : null,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _ActionChip(
                          label: l10n.mpTgTest,
                          icon: Icons.send_rounded,
                          enabled: app.canWrite,
                          onTap: () async {
                            try {
                              final TelegramBinding reply =
                                  await app.repos.market.testTelegram();
                              if (!context.mounted) return;
                              showToast(
                                context,
                                reply.delivered
                                    ? l10n.mpTgTestOk
                                    : '${l10n.mpTgTestFailed}${reply.deliveryError ?? ''}',
                                danger: !reply.delivered,
                              );
                            } on Object catch (error) {
                              if (!context.mounted) return;
                              showToast(context, app.describeError(error), danger: true);
                            }
                          },
                        ),
                        _ActionChip(
                          label: l10n.mpTgUnbind,
                          icon: Icons.link_off_rounded,
                          enabled: app.canWrite,
                          danger: true,
                          onTap: () async {
                            final bool sure = await confirmAction(
                              context,
                              title: l10n.mpTgUnbind,
                              message: l10n.mpTgUnbindConfirm,
                              confirmLabel: l10n.actDelete,
                              destructive: true,
                            );
                            if (!sure || !context.mounted) return;
                            try {
                              await app.guardWrite<void>(
                                () => app.repos.market.unbindTelegram(),
                              );
                              if (!context.mounted) return;
                              showToast(context, l10n.commonDeleted);
                              await _telegram.refresh();
                            } on Object catch (error) {
                              if (!context.mounted) return;
                              showToast(context, app.describeError(error), danger: true);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const VGap(14),
            AppCard(
              accent: AppInk.orders,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    title: l10n.mpCategoryMapping,
                    accent: AppInk.orders,
                    subtitle: l10n.mpMappingHint,
                    trailing: RoundIconButton(
                      icon: Icons.add_rounded,
                      size: 30,
                      color: AppInk.orders,
                      tooltip: l10n.mpMappingAdd,
                      onPressed: app.canWrite ? _addMapping : null,
                    ),
                  ),
                  ...(_mappings.value ?? const <JsonMap>[]).map(
                    (JsonMap row) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: KeyValueRow(
                        label: row.asStringOr('tenant_category_name',
                            row.asStringOr('tenant_category_id', '—')),
                        value: row.asMap('mp_categories').asStringOr(
                            'name_zh',
                            row.asStringOr('mp_category_id', '—')),
                        accent: AppInk.orders,
                      ),
                    ),
                  ),
                  if ((_mappings.value ?? const <JsonMap>[]).isEmpty)
                    Text(
                      l10n.commonEmptyTitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ———————————————————————————————— 小部件

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.hint,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? hint;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppInk.danger : AppInk.marketplace;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppInk.tint(color, alpha: 0.12),
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: AppInk.tint(color, alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const HGap(6),
              Text(
                hint == null ? label : '$label · $hint',
                style: TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.risky = false,
    this.accentOverride,
  });

  final String label;
  final bool selected;
  final bool risky;
  final Color? accentOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = accentOverride ?? AppInk.orders;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : AppInk.surfaceDim,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: !selected && risky ? AppInk.warning : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (risky && !selected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.warning_amber_rounded, size: 14, color: AppInk.warning),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.foot,
                fontWeight: AppType.semi,
                color: selected ? Colors.white : AppInk.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Switch.adaptive(
              value: value,
              activeThumbColor: AppInk.marketplace,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
