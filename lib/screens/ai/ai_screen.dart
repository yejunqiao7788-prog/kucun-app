import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/access.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';
import '../orders/order_detail_screen.dart';

/// AI 模块只做两件事，且两套真相不混用。
///
/// 「问答」把最近若干轮对话交给服务端 `/ai/chat`；模型、密钥、温度都握在超管手里，
/// App 没有任何输入密钥的入口，配置读不到就只解释原因、不给输入框。
/// 「速查」走 `/assist/query`，返回的是系统里的真实订单/商品/日志行，不是模型写的字，
/// 所以它和问答分开两个签，避免把「AI 说」当成「系统有」。
///
/// 输入框上方常驻一排快捷发送：问答那边是服务端 `quick_prompts`（没配就用本地兜底的用法
/// 问题，绝不放需要家底数据的问题，模型手里没有），速查这边是今日出库/今日入库/昨天的订单，
/// 发出去的都是正则兜底认得的中文原文。
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  late final Repos _repos = context.read<AppState>().repos;
  late final ValueLoader<AiConfig> _config =
      ValueLoader<AiConfig>(() => _repos.ai.config());

  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  final List<_Turn> _turns = <_Turn>[];
  bool _sending = false;

  JsonMap? _lookup;
  bool _looking = false;
  String? _lookupError;

  /// 服务端按日期返回全部单据，不替用户区分出入库；这一位记住「这次问的是哪一类」，
  /// 行数据和条数都按它来筛，界面上就不会把入库算进出库。
  OrderType? _typeFilter;

  final SpeechToText _stt = SpeechToText();
  bool _sttInitialised = false;
  bool _listening = false;

  int _tab = 0;

  /// build 直接读 `_config.value/errorText`，没有 AnimatedBuilder 接手，得自己挂监听，
  /// 否则配置回来后页面停在骨架屏。
  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _config.addListener(_repaint);
    _config.load();
  }

  @override
  void dispose() {
    _config.removeListener(_repaint);
    _config.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    if (_sttInitialised && _stt.isListening) {
      _stt.stop();
    }
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.quick,
        curve: Motion.standard,
      );
    });
  }

  Future<void> _ask(String question) async {
    final String text = question.trim();
    if (text.isEmpty || _sending) return;
    final L10n l10n = AppState.of(context).l10n;
    _input.clear();
    setState(() {
      _turns.add(_Turn.ask(text));
      _sending = true;
    });
    _scrollToEnd();

    final int window = _config.value?.contextWindow ?? 10;
    final int from = (_turns.length - 1 - window).clamp(0, _turns.length);
    final List<Map<String, Object?>> payload = _turns
        .skip(from)
        .map((_Turn turn) => <String, Object?>{'role': turn.role, 'content': turn.text})
        .toList(growable: false);

    String? failure;
    String reply = '';
    final AppState state = AppState.of(context);
    try {
      reply = await _repos.ai.chat(payload);
    } on Object catch (error) {
      failure = state.describeError(error);
    }
    if (!mounted) return;
    setState(() {
      _turns.add(failure != null ? _Turn.failed(failure) : _Turn.answer(reply.isEmpty ? l10n.aiAnswerEmpty : reply));
      _sending = false;
    });
    _scrollToEnd();
  }

  Future<void> _lookupNow(String utterance, {OrderType? only}) async {
    final String text = utterance.trim();
    if (text.isEmpty || _looking) return;
    _input.clear();
    setState(() {
      _looking = true;
      _lookupError = null;
      _typeFilter = only ?? _typeIn(text);
    });
    String? failure;
    JsonMap? result;
    final AppState state = AppState.of(context);
    try {
      result = await _repos.ai.assistQuery(text);
    } on Object catch (error) {
      failure = state.describeError(error);
    }
    if (!mounted) return;
    setState(() {
      _lookup = result;
      _lookupError = failure;
      _looking = false;
    });
  }

  /// 意图解析的正则兜底只认中文，所以快捷发送发的是写死的中文原文，界面只展示本地化标签。
  /// 问答那边交给模型的是用法问题，不是家底问题 —— `/ai/chat` 手里没有租户数据。
  List<_Shortcut> _shortcuts(L10n l10n) {
    if (_tab == 0) {
      final List<String> server = _config.value?.quickPrompts ?? const <String>[];
      if (server.isNotEmpty) {
        return server.map((String prompt) => _Shortcut(prompt, prompt)).toList(growable: false);
      }
      return <_Shortcut>[
        _Shortcut(l10n.aiQCanDo, l10n.aiQCanDo),
        _Shortcut(l10n.aiQOrderStates, l10n.aiQOrderStates),
        _Shortcut(l10n.aiQHowExport, l10n.aiQHowExport),
      ];
    }
    return <_Shortcut>[
      _Shortcut(l10n.dashOutToday, '今日出库', only: OrderType.outbound),
      _Shortcut(l10n.dashInToday, '今日入库', only: OrderType.inbound),
      _Shortcut(l10n.aiQYesterday, '昨天的订单'),
    ];
  }

  void _applyShortcut(_Shortcut shortcut) {
    if (_tab == 0) {
      _ask(shortcut.text);
    } else {
      _lookupNow(shortcut.text, only: shortcut.only);
    }
  }

  /// 手打和语音没有按钮那份现成的意图，只能从原文认关键词。
  OrderType? _typeIn(String text) {
    if (text.contains('出库') || text.contains('出货') || text.contains('发货') || text.contains('outbound')) {
      return OrderType.outbound;
    }
    if (text.contains('入库') || text.contains('到货') || text.contains('inbound')) {
      return OrderType.inbound;
    }
    return null;
  }

  List<JsonMap> _keepType(List<JsonMap> rows) {
    final OrderType? want = _typeFilter;
    if (want == null) return rows;
    return rows.where((JsonMap row) => Order(row.json).type == want).toList(growable: false);
  }

  String _countNote(L10n l10n, JsonMap result, List<JsonMap> rows) =>
      l10n.aiCountOrders(_typeFilter == null ? result.asIntOr('count', 0) : rows.length);

  /// 底部那条空白原本是「快捷问句只来自服务端」留下的：超管没配 quick_prompts，
  /// 列表里就一颗按钮都没有。快捷发送因此改挂在输入框上方，本地兜底一组按钮。
  /// 只在当前签真能用时才出现 —— 给一排点不动的按钮比不给更糟。
  Widget? _stripIfUsable(AiConfig? config) {
    if (config == null || _config.loading || !config.enabled) return null;
    if (_tab == 0 && !config.usable) return null;
    return _shortcutStrip();
  }

  Widget _shortcutStrip() {
    final L10n l10n = AppState.of(context).l10n;
    final List<_Shortcut> items = _shortcuts(l10n);
    final bool busy = _tab == 0 ? _sending : _looking;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (BuildContext context, int index) => const HGap(8),
        itemBuilder: (BuildContext context, int index) => _PromptChip(
          label: items[index].label,
          onTap: busy ? null : () => _applyShortcut(items[index]),
        ),
      ),
    );
  }

  Future<void> _toggleMic() async {
    final AppState app = AppState.of(context);
    if (_listening) {
      await _stt.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    if (!_sttInitialised) {
      _sttInitialised = await _stt.initialize(
        onError: (SpeechRecognitionError error) {
          if (!mounted) return;
          setState(() => _listening = false);
          showToast(context, '${app.l10n.aiSttFailed}: ${error.errorMsg}', danger: true);
        },
      );
      if (!mounted) return;
      if (!_sttInitialised) {
        showToast(context, app.l10n.aiMicUnavailable, danger: true);
        return;
      }
    }
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        final String words = result.recognizedWords;
        _input.text = words;
        _input.selection = TextSelection.collapsed(offset: words.length);
        if (!result.finalResult) return;
        if (!mounted) return;
        setState(() => _listening = false);
        if (_tab == 1) {
          _lookupNow(words);
        } else {
          _ask(words);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    if (!mounted) return;
    setState(() => _listening = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final AiConfig? config = _config.value;

    return Scaffold(
      body: Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 10),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      RoundBackButton(accent: AppInk.ai),
                      const HGap(10),
                      Expanded(
                        child: Text(
                          l10n.moduleAi,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppType.title,
                            fontWeight: AppType.heavy,
                            color: AppInk.ai,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      RoundIconButton(
                        icon: Icons.refresh_rounded,
                        color: AppInk.ai,
                        tooltip: l10n.actRefresh,
                        onPressed: _config.refresh,
                      ),
                    ],
                  ),
                  const VGap(12),
                  PillTabs<int>(
                    values: const <int>[0, 1],
                    selected: _tab,
                    accent: AppInk.ai,
                    labelOf: (int value) => value == 0 ? l10n.aiTabChat : l10n.aiTabLookup,
                    onChanged: (int value) => setState(() => _tab = value),
                  ),
                ],
              ),
            ),
          ),
          if (_config.loading && config == null)
            const Expanded(child: SkeletonList(count: 3, itemHeight: 70))
          else if (_config.errorText != null && config == null)
            Expanded(child: AppErrorView(message: _config.errorText!, onRetry: _config.load))
          else if (config != null && !config.enabled)
            Expanded(child: _NotConfigured(config: config, l10n: l10n))
          else if (config != null && !config.usable && _tab == 0)
            // 缺的是模型密钥，不是速查：问答锁掉，速查照常走真实记录。
            Expanded(
              child: _NotConfigured(
                config: config,
                l10n: l10n,
                onLookup: () => setState(() => _tab = 1),
              ),
            )
          else if (config == null)
            const Expanded(child: SkeletonList(count: 3, itemHeight: 70))
          else
            Expanded(child: _tab == 0 ? _buildChat(l10n) : _buildLookup(l10n)),
          _Composer(
            controller: _input,
            focusNode: _focus,
            busy: _tab == 0 ? _sending : _looking,
            listening: _listening,
            hint: l10n.aiPlaceholder,
            listeningHint: l10n.aiListening,
            sendLabel: l10n.aiSend,
            voiceTooltip: l10n.aiVoice,
            shortcuts: _stripIfUsable(config),
            onSend: () => _tab == 0 ? _ask(_input.text) : _lookupNow(_input.text),
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }

  Widget _buildChat(L10n l10n) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 16),
      children: <Widget>[
        if (_turns.isEmpty)
          AppEmpty(
            title: l10n.aiEmptyTitle,
            hint: l10n.aiEmptyHint,
            icon: Icons.auto_awesome_rounded,
            accent: AppInk.ai,
          ),
        for (final _Turn turn in _turns) _Bubble(turn: turn),
        if (_sending) const _ThinkingRow(),
        const VGap(14),
        Text(
          l10n.aiDisclaimer,
          style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
        ),
      ],
    );
  }

  Widget _buildLookup(L10n l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 16),
      children: <Widget>[
        Text(
          l10n.aiLookupHint,
          style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
        ),
        const VGap(12),
        if (_lookupError != null)
          NoticeBanner(text: _lookupError!, color: AppInk.danger, icon: Icons.error_outline_rounded),
        if (_looking)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: AppSpinner(color: AppInk.ai)),
        if (!_looking && _lookup == null && _lookupError == null)
          AppEmpty(
            title: l10n.aiEmptyTitle,
            hint: l10n.aiLookupExample,
            icon: Icons.search_rounded,
            accent: AppInk.ai,
          ),
        if (!_looking && _lookup != null) ..._renderLookup(_lookup!, l10n),
      ],
    );
  }

  List<Widget> _renderLookup(JsonMap result, L10n l10n) {
    switch (result.asStringOr('intent', '')) {
      case 'date_orders':
        final List<JsonMap> rows =
            _keepType(JsonMap.listOf(result.raw('orders'), const <String>[]));
        return _orderRows(
          l10n,
          title: '${result.asStringOr('dateFrom', '—')} → ${result.asStringOr('dateTo', '—')}',
          note: _countNote(l10n, result, rows),
          orders: rows,
        );
      case 'customer_orders':
        final List<JsonMap> orders = JsonMap.listOf(result.raw('orders'), const <String>[]);
        final JsonMap matched = result.asMap('matched');
        final List<JsonMap> customers = JsonMap.listOf(result.raw('customers'), const <String>[]);
        final String who =
            matched.asStringOr('name', customers.isEmpty ? '' : customers.first.asStringOr('name', ''));
        if (orders.isEmpty) {
          final List<JsonMap> products = JsonMap.listOf(result.raw('fallbackProducts'), const <String>[]);
          if (products.isEmpty) return <Widget>[_notFound(l10n, who)];
          return _productRows(l10n, note: who, products: products);
        }
        final List<JsonMap> rows = _keepType(orders);
        return _orderRows(
          l10n,
          title: who,
          note: _countNote(l10n, result, rows),
          orders: rows,
        );
      case 'notes_search':
        final List<JsonMap> rows =
            _keepType(JsonMap.listOf(result.raw('orders'), const <String>[]));
        return _orderRows(
          l10n,
          title: result.asStringOr('keyword', ''),
          note: _countNote(l10n, result, rows),
          orders: rows,
        );
      case 'product_search':
        return _productRows(
          l10n,
          note: result.asStringOr('keyword', ''),
          products: JsonMap.listOf(result.raw('products'), const <String>[]),
        );
      case 'logs_search':
        final List<JsonMap> logs = JsonMap.listOf(result.raw('logs'), const <String>[]);
        if (logs.isEmpty) return <Widget>[_notFound(l10n, result.asStringOr('keyword', ''))];
        return <Widget>[
          SectionHeader(title: l10n.dashActivity, subtitle: result.asString('keyword'), accent: AppInk.ai),
          AppCard(
            accent: AppInk.ai,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: logs
                  .take(15)
                  .map((JsonMap row) => KeyValueRow(
                        label: Fmt.dateTime(row.asDate('created_at')),
                        value: '${row.asStringOr('action', '')} ${row.asStringOr('detail', '')}'.trim(),
                      ))
                  .toList(growable: false),
            ),
          ),
        ];
      default:
        final String answer = result.asStringOr('answer', '');
        if (answer.isEmpty) return <Widget>[_notFound(l10n, '')];
        return <Widget>[const VGap(6), _Bubble(turn: _Turn.answer(answer))];
    }
  }

  Widget _notFound(L10n l10n, String keyword) => AppEmpty(
        title: l10n.aiNotFound,
        hint: keyword.isEmpty ? null : '“$keyword”',
        icon: Icons.search_off_rounded,
        accent: AppInk.textTertiary,
      );

  List<Widget> _orderRows(
    L10n l10n, {
    required String title,
    required String note,
    required List<JsonMap> orders,
  }) {
    if (orders.isEmpty) {
      return <Widget>[SectionHeader(title: title, subtitle: note, accent: AppInk.orders), _notFound(l10n, '')];
    }
    final AppState app = AppState.of(context);
    return <Widget>[
      SectionHeader(title: title, subtitle: note, accent: AppInk.orders),
      AppCard(
        accent: AppInk.orders,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: orders
              .take(20)
              .map((JsonMap row) {
                final Order order = Order(row.json);
                final bool inbound = order.type == OrderType.inbound;
                return TileRow(
                  icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                  accent: AppInk.orders,
                  title: '${order.orderNumber} · ${order.customerName}',
                  // 单据类型写在行上：速查一次给的是当天全部单据，不标出来就会把入库读成出库。
                  subtitle: '${inbound ? l10n.ordInbound : l10n.ordOutbound} · '
                      '${Fmt.date(Fmt.parseIsoDate(order.orderDate))} · '
                      '${Fmt.count(order.totalQuantity)}',
                  trailing: Text(
                    Fmt.money(order.totalAmount, symbol: app.profile.currencySymbol),
                    style: const TextStyle(fontWeight: AppType.semi, color: AppInk.orders),
                  ),
                  onTap: () => pushSheet<void>(context, child: OrderDetailScreen(orderId: order.id)),
                );
              })
              .toList(growable: false),
        ),
      ),
    ];
  }

  List<Widget> _productRows(L10n l10n, {required String note, required List<JsonMap> products}) {
    if (products.isEmpty) return <Widget>[_notFound(l10n, note)];
    final AppState app = AppState.of(context);
    return <Widget>[
      SectionHeader(title: l10n.aiProducts, subtitle: note, accent: AppInk.products),
      AppCard(
        accent: AppInk.products,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: products
              .take(20)
              .map((JsonMap row) {
                final Product product = Product(row.json);
                return TileRow(
                  icon: Icons.inventory_2_rounded,
                  accent: AppInk.products,
                  title: product.name,
                  subtitle: '${product.sku} · ${Fmt.count(product.quantity)}',
                  trailing: Text(
                    Fmt.money(product.price, symbol: app.profile.currencySymbol),
                    style: const TextStyle(fontWeight: AppType.semi),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    ];
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.text, {this.only});

  /// 按钮上给用户看的字，走本地化。
  final String label;

  /// 真正发出去的字：数据类问句必须是中文原文，正则兜底才认。
  final String text;

  /// 速查按日期拿到的是当天全部单据，这一位说明只想要哪一类。
  final OrderType? only;
}

class _Turn {
  _Turn._(this.role, this.text, this.failed);

  factory _Turn.ask(String text) => _Turn._('user', text, false);
  factory _Turn.answer(String text) => _Turn._('assistant', text, false);
  factory _Turn.failed(String text) => _Turn._('assistant', text, true);

  final String role;
  final String text;
  final bool failed;

  bool get fromUser => role == 'user';
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    if (turn.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: const BoxDecoration(color: AppInk.ai, borderRadius: Radii.card_),
          child: Text(
            turn.text,
            style: const TextStyle(color: Colors.white, fontSize: AppType.body, height: 1.35),
          ),
        ),
      );
    }
    final Color accent = turn.failed ? AppInk.danger : AppInk.ai;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: AppInk.surface,
          borderRadius: Radii.card_,
          border: Border.all(color: AppInk.tint(accent, alpha: 0.28)),
        ),
        child: Text(
          turn.text,
          style: TextStyle(
            fontSize: AppType.body,
            height: 1.4,
            color: turn.failed ? AppInk.danger : AppInk.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: <Widget>[
          const AppSpinner(color: AppInk.ai),
          const HGap(10),
          Text(
            AppState.of(context).l10n.aiThinking,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppInk.tint(AppInk.ai, alpha: 0.12),
      borderRadius: Radii.chip_,
      child: InkWell(
        borderRadius: Radii.chip_,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi, color: AppInk.ai),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.listening,
    required this.hint,
    required this.listeningHint,
    required this.sendLabel,
    required this.voiceTooltip,
    required this.shortcuts,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool listening;
  final String hint;
  final String listeningHint;
  final String sendLabel;
  final String voiceTooltip;
  final Widget? shortcuts;
  final VoidCallback onSend;
  final Future<void> Function() onMic;

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        RoundIconButton(
          icon: listening ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: listening ? AppInk.danger : AppInk.ai,
          tooltip: voiceTooltip,
          onPressed: busy ? null : onMic,
        ),
        const HGap(8),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: Hit.min, maxHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(color: AppInk.surfaceDim, borderRadius: Radii.control_),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: listening ? listeningHint : hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
        const HGap(8),
        PrimaryButton(
          label: sendLabel,
          icon: Icons.arrow_upward_rounded,
          color: AppInk.ai,
          loading: busy,
          expanded: false,
          onPressed: busy ? null : onSend,
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 10),
        decoration: const BoxDecoration(
          color: AppInk.surface,
          border: Border(top: BorderSide(color: AppInk.hairline)),
        ),
        child: shortcuts == null
            ? row
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  shortcuts!,
                  const VGap(8),
                  row,
                ],
              ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.config, required this.l10n, this.onLookup});

  final AiConfig config;
  final L10n l10n;

  /// 只有「模块开着、缺模型密钥」时能给：速查不依赖密钥，可以直接切过去。
  final VoidCallback? onLookup;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 24),
      children: <Widget>[
        AppEmpty(
          title: l10n.aiNotConfigured,
          hint: config.enabled ? l10n.aiKeyMissing : l10n.aiModuleOff,
          icon: config.enabled ? Icons.key_off_rounded : Icons.help_outline_rounded,
          accent: AppInk.ai,
        ),
        const VGap(12),
        if (config.model.isNotEmpty)
          AppCard(
            accent: AppInk.ai,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: <Widget>[
                KeyValueRow(label: l10n.aiModel, value: config.model),
                KeyValueRow(label: l10n.aiContextTurns, value: '${config.contextWindow}'),
              ],
            ),
          ),
        const VGap(16),
        if (onLookup != null)
          PrimaryButton(
            label: l10n.aiGoLookup,
            icon: Icons.search_rounded,
            color: AppInk.ai,
            onPressed: onLookup,
          ),
        const VGap(10),
        GhostButton(
          label: l10n.setFeedback,
          icon: Icons.forum_rounded,
          color: AppInk.ai,
          onPressed: () => ModuleKey.settings.jumpTo(context),
        ),
      ],
    );
  }
}
