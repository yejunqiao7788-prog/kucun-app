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

  final SpeechToText _stt = SpeechToText();
  bool _sttInitialised = false;
  bool _listening = false;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _config.load();
  }

  @override
  void dispose() {
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

  Future<void> _lookupNow(String utterance) async {
    final String text = utterance.trim();
    if (text.isEmpty || _looking) return;
    _input.clear();
    setState(() {
      _looking = true;
      _lookupError = null;
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
          else if (config != null && !config.usable)
            Expanded(child: _NotConfigured(config: config, l10n: l10n))
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
            onSend: () => _tab == 0 ? _ask(_input.text) : _lookupNow(_input.text),
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }

  Widget _buildChat(L10n l10n) {
    final List<String> prompts = _config.value?.quickPrompts ?? const <String>[];
    final List<String> chips = _turns.isEmpty ? prompts : prompts.take(3).toList();
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
        if (chips.isNotEmpty) ...<Widget>[
          const VGap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map((String prompt) => _PromptChip(label: prompt, onTap: _sending ? null : () => _ask(prompt)))
                .toList(growable: false),
          ),
        ],
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
        return _orderRows(
          l10n,
          title: '${result.asStringOr('dateFrom', '—')} → ${result.asStringOr('dateTo', '—')}',
          note: l10n.aiCountOrders(result.asIntOr('count', 0)),
          orders: JsonMap.listOf(result.raw('orders'), const <String>[]),
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
        return _orderRows(
          l10n,
          title: who,
          note: l10n.aiCountOrders(result.asIntOr('count', 0)),
          orders: orders,
        );
      case 'notes_search':
        return _orderRows(
          l10n,
          title: result.asStringOr('keyword', ''),
          note: l10n.aiCountOrders(result.asIntOr('count', 0)),
          orders: JsonMap.listOf(result.raw('orders'), const <String>[]),
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
                return TileRow(
                  icon: Icons.receipt_long_rounded,
                  accent: AppInk.orders,
                  title: '${order.orderNumber} · ${order.customerName}',
                  subtitle:
                      '${Fmt.date(Fmt.parseIsoDate(order.orderDate))} · ${Fmt.count(order.totalQuantity)}',
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
  final VoidCallback onSend;
  final Future<void> Function() onMic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 10),
        decoration: const BoxDecoration(
          color: AppInk.surface,
          border: Border(top: BorderSide(color: AppInk.hairline)),
        ),
        child: Row(
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
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.config, required this.l10n});

  final AiConfig config;
  final L10n l10n;

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
