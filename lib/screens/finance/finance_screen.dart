import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// 财务：概览 / 流水 / 欠款 / 钱包与订阅。
///
/// 三条服务端事实决定了界面怎么摆：
/// 1. 汇总走 `GET /finance/stats`，命中扫描上限时 `truncated=true`，界面必须如实说「可能少报」；
/// 2. 欠款面 `GET /finance/debts` 按客户分组且没有分页，还款是 `POST /finance/debts/:customer_id`，
///    服务端从最老的未结清单往下抵，超出部分回成找零而不是余额；
/// 3. 订阅与钱包充值都只在服务端托管收银台扣款，客户端拿到的是一张带 `page_url` 的票据，
///    App 只负责打开它并轮询状态，任何客户端金额都不参与。
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late final AppState _app = context.read<AppState>();
  int _tab = 0;

  late final ValueLoader<FinanceSummary> _stats = ValueLoader<FinanceSummary>(
    () => _app.repos.finance.stats(dateFrom: _from, dateTo: _to),
  );
  late final ValueLoader<JsonMap> _debts =
      ValueLoader<JsonMap>(() => _app.repos.finance.debts());
  late final ListController<PaymentRecord> _records = ListController<PaymentRecord>(
    fetch: (int page) async {
      final Paged<PaymentRecord> res = await _app.repos.finance.records(
        page: page,
        pageSize: 20,
        method: _method,
        type: _type,
      );
      return FetchResult<PaymentRecord>(rows: res.rows, hasMore: res.hasMore);
    },
  );

  String? _method;
  String? _type;
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    unawaited(_stats.load());
    unawaited(_debts.load());
    unawaited(_records.load());
  }

  @override
  void dispose() {
    _stats.dispose();
    _debts.dispose();
    _records.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final DateTime today = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      initialDateRange: _from == null
          ? null
          : DateTimeRange(
              start: DateTime.parse(_from!),
              end: DateTime.parse(_to ?? _from!),
            ),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = Fmt.isoDate(range.start);
      _to = Fmt.isoDate(range.end);
    });
    await _stats.refresh();
  }

  void _clearRange() {
    setState(() {
      _from = null;
      _to = null;
    });
    unawaited(_stats.refresh());
  }

  Future<void> _editCurrency() async {
    final L10n l10n = _app.l10n;
    final TextEditingController controller =
        TextEditingController(text: _app.profile.currencySymbol);
    final String? symbol = await showDrawer<String>(
      context,
      title: l10n.finCurrency,
      accent: AppInk.finance,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppTextField(
            label: l10n.finCurrency,
            controller: controller,
            autofocus: true,
            hint: '₴ / \$ / ¥',
          ),
          const VGap(6),
          Text(
            l10n.finCurrencyNote,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            color: AppInk.finance,
            onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    if (symbol == null || symbol.isEmpty || !_app.canWrite) return;
    try {
      await _app.guardWrite<void>(() => _app.repos.finance.setCurrencySymbol(symbol));
      if (!mounted) return;
      await _app.refreshProfileQuietly();
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 10),
              child: Row(
                children: <Widget>[
                  const RoundBackButton(accent: AppInk.finance),
                  const HGap(10),
                  Expanded(
                    child: Text(
                      l10n.moduleFinance,
                      style: const TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.heavy,
                        color: AppInk.finance,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (app.isAdmin)
                    RoundIconButton(
                      icon: Icons.attach_money_rounded,
                      size: 38,
                      color: AppInk.finance,
                      tooltip: l10n.finCurrency,
                      onPressed: app.canWrite ? _editCurrency : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: PillTabs<int>(
                values: const <int>[0, 1, 2, 3],
                selected: _tab,
                accent: AppInk.finance,
                scrollable: false,
                labelOf: (int value) => switch (value) {
                  1 => l10n.finRecords,
                  2 => l10n.finDebts,
                  3 => l10n.finWallet,
                  _ => l10n.finOverview,
                },
                onChanged: (int value) => setState(() => _tab = value),
              ),
            ),
            const VGap(12),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _OverviewTab(
                    stats: _stats,
                    currency: app.profile.currencySymbol,
                    hasRange: _from != null,
                    onPickRange: _pickRange,
                    onClearRange: _clearRange,
                    onOpenTab: (int index) => setState(() => _tab = index),
                  ),
                  _RecordsTab(
                    controller: _records,
                    currency: app.profile.currencySymbol,
                    method: _method,
                    type: _type,
                    onMethod: (String? value) {
                      setState(() => _method = value);
                      unawaited(_records.load());
                    },
                    onType: (String? value) {
                      setState(() => _type = value);
                      unawaited(_records.load());
                    },
                  ),
                  _DebtsTab(debts: _debts, currency: app.profile.currencySymbol),
                  const _WalletTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ———————————————————————————————— 概览

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.stats,
    required this.currency,
    required this.hasRange,
    required this.onPickRange,
    required this.onClearRange,
    required this.onOpenTab,
  });

  final ValueLoader<FinanceSummary> stats;
  final String currency;
  final bool hasRange;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final ValueChanged<int> onOpenTab;

  String _money(double value) => Fmt.money(value, symbol: currency, compact: true);

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    final FinanceSummary? data = stats.value;

    if (stats.loading && data == null) {
      return const SafeArea(child: SkeletonList(count: 5, itemHeight: 92));
    }
    if (data == null) {
      return SafeArea(
        child: AppErrorView(
          message: stats.errorText ?? l10n.commonErrorTitle,
          onRetry: stats.load,
        ),
      );
    }

    final List<Widget> banners = <Widget>[
      if (stats.stale)
        NoticeBanner(
          text: l10n.commonStaleBanner,
          color: AppInk.info,
          icon: Icons.history_rounded,
        ),
      if (data.truncated)
        NoticeBanner(
          text: l10n.finTruncated,
          color: AppInk.warning,
          icon: Icons.data_thresholding_rounded,
        ),
    ];

    return RefreshIndicator(
      onRefresh: stats.refresh,
      color: AppInk.finance,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
        children: <Widget>[
          ...banners,
          AppCard(
            accent: AppInk.finance,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: <Widget>[
                TileRow(
                  icon: Icons.date_range_rounded,
                  title: l10n.finRange,
                  subtitle: hasRange ? '${data.dateFrom} → ${data.dateTo}' : l10n.finRangeDefault,
                  accent: AppInk.finance,
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
                  onTap: onPickRange,
                ),
                if (hasRange)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextAction(label: l10n.finRangeReset, onPressed: onClearRange),
                  ),
              ],
            ),
          ),
          const VGap(14),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: l10n.finTodayReceived,
                  value: _money(data.todayNet),
                  accent: AppInk.finance,
                  icon: Icons.today_rounded,
                  footnote: '${l10n.finRecords} ${Fmt.count(data.todayCount)}',
                ),
              ),
              const HGap(10),
              Expanded(
                child: StatTile(
                  label: l10n.finReceived,
                  value: _money(data.periodNet),
                  accent: AppInk.inventory,
                  icon: Icons.payments_rounded,
                ),
              ),
            ],
          ),
          const VGap(10),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: l10n.finRevenue,
                  value: _money(data.revenue),
                  accent: AppInk.products,
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const HGap(10),
              Expanded(
                child: StatTile(
                  label: l10n.finProfit,
                  value: _money(data.profit),
                  accent: data.profit >= 0 ? AppInk.success : AppInk.danger,
                  icon: Icons.savings_rounded,
                  footnote: '${l10n.finOrders} ${Fmt.count(data.orderCount)}',
                ),
              ),
            ],
          ),
          const VGap(14),
          AppCard(
            accent: AppInk.orders,
            onTap: () => onOpenTab(1),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.finRecords, style: Theme.of(context).textTheme.titleMedium),
                      const VGap(4),
                      Text(
                        _methodSplit(data, l10n, _money),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
              ],
            ),
          ),
          const VGap(14),
          AppCard(
            accent: data.totalOutstanding > 0 ? AppInk.danger : AppInk.settings,
            onTap: () => onOpenTab(2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.finDebts, style: Theme.of(context).textTheme.titleMedium),
                      const VGap(4),
                      Text(
                        '${_money(data.totalOutstanding)} · ${Fmt.count(data.debtCustomerCount)} ${l10n.finDebtCustomers}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
              ],
            ),
          ),
          if (data.trend.isNotEmpty) ...<Widget>[
            const VGap(14),
            SectionHeader(title: l10n.finTrend, accent: AppInk.finance),
            AppCard(
              child: _TrendBars(trend: data.trend, currency: currency),
            ),
          ],
        ],
      ),
    );
  }

  static String _methodSplit(FinanceSummary data, L10n l10n, String Function(double) money) {
    final JsonMap totals = data.methodTotals;
    final double cash = totals.asDoubleOr('cash', 0);
    final double transfer = totals.asDoubleOr('transfer', 0);
    return '${l10n.ordCash} ${money(cash)} · ${l10n.ordTransfer} ${money(transfer)}';
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.trend, required this.currency});

  final List<JsonMap> trend;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final List<JsonMap> rows = trend.length > 14 ? trend.sublist(trend.length - 14) : trend;
    double maxNet = 0;
    for (final JsonMap row in rows) {
      final double net = row.asDoubleOr('net', 0).abs();
      if (net > maxNet) maxNet = net;
    }
    final double floor = maxNet <= 0 ? 1 : maxNet;

    return SizedBox(
      height: 108,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final JsonMap row in rows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      Fmt.money(row.asDoubleOr('net', 0), symbol: currency, compact: true),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(fontSize: 8, color: AppInk.textTertiary),
                    ),
                    const VGap(2),
                    AnimatedContainer(
                      duration: Motion.base,
                      curve: Motion.standard,
                      height: (28 + 56 * (row.asDoubleOr('net', 0).abs() / floor)).clamp(4.0, 84.0),
                      decoration: BoxDecoration(
                        color: row.asDoubleOr('net', 0) >= 0 ? AppInk.finance : AppInk.danger,
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                    ),
                    const VGap(4),
                    Text(
                      (row.asStringOr('date', '')).split('-').length == 3
                          ? row.asStringOr('date', '').split('-')[1]
                          : '',
                      style: const TextStyle(fontSize: 8, color: AppInk.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ———————————————————————————————— 流水

class _RecordsTab extends StatelessWidget {
  const _RecordsTab({
    required this.controller,
    required this.currency,
    required this.method,
    required this.type,
    required this.onMethod,
    required this.onType,
  });

  final ListController<PaymentRecord> controller;
  final String currency;
  final String? method;
  final String? type;
  final ValueChanged<String?> onMethod;
  final ValueChanged<String?> onType;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 10),
          child: PillTabs<String?>(
            values: const <String?>[null, 'payment', 'refund', 'debt_settle'],
            selected: type,
            accent: AppInk.finance,
            scrollable: false,
            labelOf: (String? value) => switch (value) {
              'payment' => l10n.finTypePayment,
              'refund' => l10n.finTypeRefund,
              'debt_settle' => l10n.finTypeSettle,
              _ => l10n.commonAll,
            },
            onChanged: onType,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 10),
          child: PillTabs<String?>(
            values: const <String?>[null, 'cash', 'transfer'],
            selected: method,
            accent: AppInk.inventory,
            scrollable: false,
            labelOf: (String? value) => switch (value) {
              'cash' => l10n.ordCash,
              'transfer' => l10n.ordTransfer,
              _ => l10n.finAllMethods,
            },
            onChanged: onMethod,
          ),
        ),
        Expanded(
          child: PagedView<PaymentRecord>(
            controller: controller,
            accent: AppInk.finance,
            emptyTitle: l10n.commonEmptyTitle,
            emptyHint: l10n.finNoRecords,
            emptyIcon: Icons.receipt_long_rounded,
            itemBuilder: (BuildContext context, PaymentRecord record, int index) =>
                _RecordRow(
                  record: record,
                  currency: currency,
                  onChanged: () => unawaited(controller.refresh()),
                ),
          ),
        ),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.currency, required this.onChanged});

  final PaymentRecord record;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final double signed = record.isRefund ? -record.applied : record.applied;

    return AppCard(
      accent: record.isRefund ? AppInk.danger : AppInk.finance,
      padding: const EdgeInsets.all(12),
      onTap: app.canWrite ? () => _voidRecord(context, app) : null,      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.orderNumber,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const VGap(2),
                Text(
                  '${record.customerName} · ${Fmt.dateTime(record.paidAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const VGap(6),
                Row(
                  children: <Widget>[
                    StatusPill(
                      label: record.method == 'transfer' ? l10n.ordTransfer : l10n.ordCash,
                      color: record.method == 'transfer' ? AppInk.inventory : AppInk.textSecondary,
                      dense: true,
                    ),
                    const HGap(6),
                    if (record.isRefund)
                      StatusPill(label: l10n.finTypeRefund, color: AppInk.danger, dense: true)
                    else if (record.isDebtSettle)
                      StatusPill(label: l10n.finTypeSettle, color: AppInk.showroom, dense: true),
                  ],
                ),
              ],
            ),
          ),
          const HGap(8),
          Text(
            Fmt.signedMoney(signed, symbol: currency),
            style: TextStyle(
              fontSize: AppType.head,
              fontWeight: AppType.heavy,
              color: signed >= 0 ? AppInk.finance : AppInk.danger,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _voidRecord(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    final bool sure = await confirmAction(
      context,
      title: l10n.finVoid,
      message: l10n.finVoidConfirm,
      confirmLabel: l10n.actConfirm,
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    try {
      await app.guardWrite<void>(
        () => app.repos.finance.voidRecord(record.id, reason: 'app'),
      );
      if (!context.mounted) return;
      showToast(context, l10n.commonDeleted);
      onChanged();
    } on Object catch (error) {
      if (!context.mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }
}

// ———————————————————————————————— 欠款

class _DebtsTab extends StatelessWidget {
  const _DebtsTab({required this.debts, required this.currency});

  final ValueLoader<JsonMap> debts;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final JsonMap? data = debts.value;
    final List<DebtRow> rows =
        data == null ? const <DebtRow>[] : data.asEntities('customers', DebtRow.new);

    if (debts.loading && data == null) {
      return const SafeArea(child: SkeletonList(count: 4, itemHeight: 88));
    }
    if (data == null) {
      return SafeArea(
        child: AppErrorView(message: debts.errorText ?? l10n.commonErrorTitle, onRetry: debts.load),
      );
    }

    return RefreshIndicator(
      onRefresh: debts.refresh,
      color: AppInk.finance,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
        children: <Widget>[
          if (data.asBool('truncated'))
            NoticeBanner(
              text: l10n.finTruncated,
              color: AppInk.warning,
              icon: Icons.data_thresholding_rounded,
            ),
          AppCard(
            accent: AppInk.danger,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        Fmt.money(data.asDoubleOr('total_outstanding', 0),
                            symbol: currency, compact: true),
                        style: const TextStyle(
                          fontSize: AppType.huge,
                          fontWeight: AppType.heavy,
                          color: AppInk.danger,
                        ),
                      ),
                      const VGap(4),
                      Text(
                        '${Fmt.count(data.asIntOr('customer_count', rows.length))} ${l10n.finDebtCustomers}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VGap(14),
          if (rows.isEmpty)
            AppEmpty(
              title: l10n.finAllSettled,
              hint: l10n.finNoDebtsHint,
              icon: Icons.task_alt_rounded,
              accent: AppInk.success,
            )
          else
            for (final DebtRow row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DebtRowCard(
                row: row,
                currency: currency,
                onChanged: () => unawaited(debts.refresh()),
              ),
              ),
        ],
      ),
    );
  }
}

class _DebtRowCard extends StatelessWidget {
  const _DebtRowCard({
    required this.row,
    required this.currency,
    required this.onChanged,
  });

  final DebtRow row;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;

    return AppCard(
      accent: AppInk.danger,
      padding: const EdgeInsets.all(12),
      onTap: app.canWrite && !row.isAnonymous
          ? () => _settle(context, app)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(row.customerName, style: Theme.of(context).textTheme.titleMedium),
                    if (row.customerPhone != null) ...<Widget>[
                      const VGap(2),
                      Text(row.customerPhone!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const HGap(8),
              Text(
                Fmt.money(row.totalOutstanding, symbol: currency),
                style: const TextStyle(
                  fontSize: AppType.head,
                  fontWeight: AppType.heavy,
                  color: AppInk.danger,
                ),
              ),
            ],
          ),
          const VGap(8),
          Text(
            row.isAnonymous ? l10n.finAnonDebtNote : '${Fmt.count(row.orderCount)} ${l10n.navOrders}',
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          for (final JsonMap order in row.orders.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      order.asStringOr('order_number', '—'),
                      style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
                    ),
                  ),
                  Text(
                    Fmt.money(order.asDoubleOr('outstanding', 0), symbol: currency),
                    style: const TextStyle(fontSize: AppType.foot, color: AppInk.danger),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _settle(BuildContext context, AppState app) async {
    final L10n l10n = app.l10n;
    final TextEditingController amount =
        TextEditingController(text: row.totalOutstanding.toStringAsFixed(2));
    String method = 'cash';

    final Object? result = await showDrawer<Object?>(
      context,
      title: '${l10n.finSettle} · ${row.customerName}',
      accent: AppInk.finance,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter refresh) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            NumberField(
              label: l10n.finSettleAmount,
              controller: amount,
              suffix: app.profile.currencySymbol,
              autofocus: true,
            ),
            const VGap(14),
            PillTabs<String>(
              values: const <String>['cash', 'transfer'],
              selected: method,
              accent: AppInk.finance,
              scrollable: false,
              labelOf: (String value) => value == 'cash' ? l10n.ordCash : l10n.ordTransfer,
              onChanged: (String value) {
                refresh(() => method = value);
              },            ),
            const VGap(12),
            Text(
              l10n.finSettleHint,
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
            const VGap(18),
            PrimaryButton(
              label: l10n.finSettle,
              color: AppInk.finance,
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(sheetContext).pop(<String, Object?>{
                'amount': double.tryParse(amount.text.trim()) ?? 0,
                'method': method,
              }),
            ),
          ],
        ),
      ),
    );

    if (result is! Map || !context.mounted) return;
    final double paid = (result['amount'] as num).toDouble();
    if (paid <= 0) return;
    try {
      final DebtSettlement receipt = await app.guardWrite<DebtSettlement>(
        () => app.repos.finance
            .settle(row.customerId!, amount: paid, method: result['method'] as String),
      );
      if (!context.mounted) return;
      showToast(
        context,
        receipt.change > 0
            ? '${l10n.finSettleDone} · ${l10n.finChange} ${Fmt.money(receipt.change, symbol: currency)}'
            : l10n.finSettleDone,
      );
      onChanged();
    } on Object catch (error) {
      if (!context.mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }
}

// ———————————————————————————————— 钱包与订阅

class _WalletTab extends StatefulWidget {
  const _WalletTab();

  @override
  State<_WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<_WalletTab> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<WalletAccount> _wallet =
      ValueLoader<WalletAccount>(() => _app.repos.settings.wallet());
  late final ValueLoader<WalletTopupBoard> _topup =
      ValueLoader<WalletTopupBoard>(() => _app.repos.settings.walletTopupPlans());
  late final ValueLoader<PlanBoard> _plans =
      ValueLoader<PlanBoard>(() => _app.repos.settings.plans());
  late final ValueLoader<List<JsonMap>> _history = ValueLoader<List<JsonMap>>(
    () async => _app.repos.settings.payments(),
  );

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_wallet.load());
    unawaited(_topup.load());
    unawaited(_plans.load());
    unawaited(_history.load());
  }

  @override
  void dispose() {
    _wallet.dispose();
    _topup.dispose();
    _plans.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait<void>(<Future<void>>[
        _wallet.refresh(),
        _topup.refresh(),
        _plans.refresh(),
        _history.refresh(),
      ]);

  /// 建单 → 打开托管收银台 → 轮询状态。付款发生在浏览器，App 只报最终结果。
  Future<void> _pay(Future<PaymentTicket> Function() create) async {
    if (!_app.canWrite) {
      showToast(context, _app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final PaymentTicket ticket = await _app.guardWrite<PaymentTicket>(create);
      final String? url = ticket.pageUrl;
      if (url != null && url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      showToast(context, _app.l10n.finPendingPayment);
      final PaymentTicket settled = await _poll(ticket);
      if (!mounted) return;
      showToast(
        context,
        settled.succeeded ? _app.l10n.finPaidOk : '${_app.l10n.finStatus} ${settled.status}',
        danger: !settled.succeeded,
      );
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PaymentTicket> _poll(PaymentTicket ticket) async {
    PaymentTicket latest = ticket;
    for (int attempt = 0; attempt < 6 && !latest.terminal; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        latest = await _app.repos.settings.paymentStatus(
          latest.id,
          channel: latest.provider.isEmpty ? null : latest.provider,
        );
      } on Object {
        break;
      }
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_wallet, _topup, _plans, _history]),
      builder: (BuildContext context, Widget? _) => RefreshIndicator(
        onRefresh: _refresh,
        color: AppInk.finance,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 40),
          children: <Widget>[
            _loaderCard<WalletAccount>(
              loader: _wallet,
              accent: AppInk.ai,
              title: l10n.finWallet,
              builder: (BuildContext context, WalletAccount wallet) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    wallet.exists
                        ? Fmt.money(wallet.balance, symbol: '${wallet.currency} ')
                        : l10n.finWalletNone,
                    style: const TextStyle(
                      fontSize: AppType.huge,
                      fontWeight: AppType.heavy,
                      color: AppInk.ai,
                    ),
                  ),
                  if (wallet.updatedAt != null) ...<Widget>[
                    const VGap(4),
                    Text(
                      l10n.commonUpdatedAt(l10n.elapsed(wallet.updatedAt!)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const VGap(14),
                  ...(_topup.value?.tiers ?? const <JsonMap>[]).map((JsonMap tier) {
                    final String key = tier.asStringOr('tier', '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TileRow(
                        icon: Icons.add_circle_outline_rounded,
                        title: _tierLabel(key, l10n),
                        subtitle: '${l10n.finTopup} ${Fmt.money(tier.asDoubleOr('uahMajor', 0), symbol: '₴')}',
                        accent: AppInk.ai,
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppInk.textTertiary),
                        onTap: _busy || !_topup.value!.payable
                            ? null
                            : () => _pay(() => app.repos.settings.topUpWallet(key)),
                      ),
                    );
                  }),
                  if (_topup.value != null && !_topup.value!.enabled)
                    Text(l10n.finTopupClosed,
                        style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary)),
                ],
              ),
            ),
            const VGap(14),
            _loaderCard<PlanBoard>(
              loader: _plans,
              accent: AppInk.finance,
              title: l10n.finPlans,
              builder: (BuildContext context, PlanBoard board) {
                final List<PlanChannel> channels = board.channels
                    .where((PlanChannel channel) => channel.payable)
                    .toList(growable: false);
                if (channels.isEmpty) {
                  return Text(
                    l10n.finNoPayableChannel,
                    style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final PlanChannel channel in channels) ...<Widget>[
                      Text(
                        channel.name,
                        style: const TextStyle(
                            fontSize: AppType.foot,
                            fontWeight: AppType.semi,
                            color: AppInk.finance),
                      ),
                      const VGap(6),
                      for (final PlanRow plan in channel.plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TileRow(
                            icon: Icons.workspace_premium_outlined,
                            title: _planLabel(plan.planType, l10n),
                            subtitle: '${Fmt.count(plan.days)} ${l10n.finDays}',
                            accent: AppInk.finance,
                            trailing: Text(
                              Fmt.money(plan.amount, symbol: '${plan.currency} '),
                              style: const TextStyle(
                                  fontSize: AppType.foot, fontWeight: AppType.semi),
                            ),
                            onTap: _busy
                                ? null
                                : () => _pay(
                                      () => app.repos.settings.createPayment(
                                        planType: plan.planType,
                                        channel: channel.name,
                                      ),
                                    ),
                          ),
                        ),
                    ],
                    const VGap(8),
                    Text(l10n.finPayOpen,
                        style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary)),
                  ],
                );
              },
            ),
            const VGap(14),
            if ((_history.value ?? const <JsonMap>[]).isNotEmpty) ...<Widget>[
              SectionHeader(title: l10n.finPayHistory, accent: AppInk.settings),
              for (final JsonMap row in (_history.value ?? const <JsonMap>[]).take(8))
                AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _planLabel(row.asStringOr('plan_type', ''), l10n),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const VGap(2),
                            Text(
                              '${row.asStringOr('provider', '')} · ${Fmt.dateTime(row.asDate('created_at'))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      HGap(8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            Fmt.money(row.asIntOr('amount_cents', 0) / 100.0,
                                symbol: '${row.asStringOr('currency', '')} '),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          StatusPill(
                            label: row.asStringOr('status', ''),
                            color: row.asStringOr('status', '') == 'succeeded'
                                ? AppInk.success
                                : AppInk.textTertiary,
                            dense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loaderCard<T>({
    required ValueLoader<T> loader,
    required Color accent,
    required String title,
    required Widget Function(BuildContext, T) builder,
  }) {
    final L10n l10n = AppState.of(context).l10n;
    if (loader.loading && loader.value == null) {
      return const AppCard(child: SkeletonList(count: 1, itemHeight: 60));
    }
    if (loader.value == null) {
      return AppCard(
        accent: accent,
        onTap: loader.load,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(loader.errorText ?? l10n.commonErrorTitle,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            const Icon(Icons.refresh_rounded, size: 20),
          ],
        ),
      );
    }
    return AppCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title, accent: accent),
          builder(context, loader.value as T),
        ],
      ),
    );
  }

  static String _tierLabel(String tier, L10n l10n) => switch (tier) {
        'small' => l10n.finTierSmall,
        'medium' => l10n.finTierMedium,
        'large' => l10n.finTierLarge,
        _ => tier,
      };

  /// 服务端价目表只有月/年两档可买，trial 是注册时发的，不会出现在这里。
  static String _planLabel(String planType, L10n l10n) => switch (planType) {
        'monthly' => l10n.finPlanMonthly,
        'yearly' => l10n.finPlanYearly,
        'trial' => l10n.setSubTrial,
        _ => planType,
      };
}
