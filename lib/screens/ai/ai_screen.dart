import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/access.dart';
import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/log_labels.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/product_identity.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';
import '../orders/order_detail_screen.dart';
import 'local_query_engine.dart';

/// AI 模块只做两件事，且两套真相不混用。
///
/// 「问答」把最近若干轮对话交给服务端 `/ai/chat`；模型、密钥、温度都握在超管手里，
/// App 没有任何输入密钥的入口，配置读不到就只解释原因、不给输入框。
/// 「速查」走本地引擎（`local_query_engine.dart`，复刻原项目 ai_local.ts）：
/// 正则认意图，数据从库存/订单/日志接口现取现算，返回的都是系统里的真实行，
/// 不经过模型、也不需要模型密钥 —— 问答被锁时它照常工作。
///
/// 输入框上方常驻一排快捷发送：问答那边是服务端 `quick_prompts`（没配就用本地兜底的用法
/// 问题，绝不放需要家底数据的问题，模型手里没有），速查这边是库存统计/库存预警/
/// 今日出库/今日入库/操作记录/历史订单（最后一项先选日期），
/// 发出去的都是引擎认得的中文原文。
///
/// 语音有两条通道：系统听写（`speech_to_text`，边说边出字）和服务端录音转写
/// （录一段 m4a 交给 `/speech/transcribe`）。后者是原项目就给 Web Speech 不可用设备留的
/// 回落，在国产 ROM 上往往是唯一能用的一条；系统听写起不来时自动走它。
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

  late final LocalQueryEngine _engine = LocalQueryEngine(_repos);
  LocalQuery? _lastQuery;
  LocalResult? _lookup;
  bool _looking = false;
  String? _lookupError;

  final SpeechToText _stt = SpeechToText();
  bool _sttInitialised = false;
  bool _listening = false;

  final AudioRecorder _rec = AudioRecorder();
  Timer? _tick;
  bool _recording = false;
  bool _transcribing = false;
  int _recordSeconds = 0;

  /// 上游 25 秒硬超时，60 秒的音频已经贴着天花板；再长就让它到点自己停。
  static const int _recordCapSeconds = 60;

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
    _tick?.cancel();
    if (_sttInitialised && _stt.isListening) {
      _stt.stop();
    }
    _rec.dispose();
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

  Future<void> _runLocal(LocalQuery query) async {
    if (query.text.trim().isEmpty || _looking) return;
    _input.clear();
    setState(() {
      _looking = true;
      _lookupError = null;
      _lastQuery = query;
    });
    LocalResult? result;
    String? failure;
    final AppState state = AppState.of(context);
    try {
      result = await _engine.run(query, today: DateTime.now());
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

  /// 「历史订单」按钮先落日期再发，发出去的仍是引擎认得的 `历史订单:YYYY-MM-DD`。
  Future<void> _pickHistoryDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    await _runLocal(LocalQuery('历史订单:${Fmt.isoDate(picked)}', only: OrderType.outbound));
  }

  /// 意图解析的正则只认中文，所以快捷发送发的是写死的中文原文，界面只展示本地化标签。
  /// 问答那边交给模型的是用法问题，不是家底问题 —— `/ai/chat` 手里没有租户数据。
  List<_Shortcut> _shortcuts(L10n l10n) {
    if (_tab == 0) {
      final List<String> server = _config.value?.quickPrompts ?? const <String>[];
      if (server.isNotEmpty) {
        return server
            .map((String prompt) => _Shortcut(prompt, LocalQuery(prompt)))
            .toList(growable: false);
      }
      return <_Shortcut>[
        _Shortcut(l10n.aiQCanDo, LocalQuery(l10n.aiQCanDo)),
        _Shortcut(l10n.aiQOrderStates, LocalQuery(l10n.aiQOrderStates)),
        _Shortcut(l10n.aiQHowExport, LocalQuery(l10n.aiQHowExport)),
      ];
    }
    return <_Shortcut>[
      _Shortcut(l10n.aiValueTitle, const LocalQuery('库存统计')),
      _Shortcut(l10n.aiLowStockTitle, const LocalQuery('库存预警')),
      _Shortcut(l10n.dashOutToday, const LocalQuery('今日出库', only: OrderType.outbound)),
      _Shortcut(l10n.dashInToday, const LocalQuery('今日入库', only: OrderType.inbound)),
      _Shortcut(l10n.aiLogsTitle, const LocalQuery('操作记录')),
      _Shortcut(l10n.aiHistoryShort, const LocalQuery('历史订单'), history: true),
    ];
  }

  void _applyShortcut(_Shortcut shortcut) {
    if (_tab == 0) {
      _ask(shortcut.query.text);
    } else if (shortcut.history) {
      _pickHistoryDate();
    } else {
      _runLocal(shortcut.query);
    }
  }

  /// 底部那条空白原本是「快捷问句只来自服务端」留下的：超管没配 quick_prompts，
  /// 列表里就一颗按钮都没有。快捷发送因此改挂在输入框上方，本地兜底一组按钮。
  /// 速查走本地引擎，不依赖配置 —— 只有问答在模块被关或缺密钥时才锁。
  Widget? _stripIfUsable(AiConfig? config) {
    if (config != null && !config.enabled) return null;
    if (_tab == 0 && config != null && !config.usable) return null;
    return _shortcutStrip();
  }

  Widget _shortcutStrip() {
    final L10n l10n = AppState.of(context).l10n;
    final List<_Shortcut> items = _shortcuts(l10n);
    final bool busy = _tab == 0 ? _sending : _looking;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          // 录音转写排在最前面：它不依赖系统语音识别，是唯一保证能用的口述入口。
          _PromptChip(label: l10n.aiRecord, onTap: busy || _transcribing ? null : _startRecording),
          for (final _Shortcut item in items) ...<Widget>[
            const HGap(8),
            _PromptChip(
              label: item.label,
              onTap: busy ? null : () => _applyShortcut(item),
            ),
          ],
        ],
      ),
    );
  }

  /// 录音时快捷发送整排让位给这一条：此刻用户要的只有「停」和「算了」。
  Widget _recordingStrip(L10n l10n) {
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          const Icon(Icons.mic_rounded, size: 16, color: AppInk.danger),
          const HGap(8),
          Expanded(
            child: Text(
              l10n.aiRecordCap,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
            ),
          ),
          TextAction(label: l10n.aiRecordCancel, color: AppInk.textSecondary, onPressed: _cancelRecording),
        ],
      ),
    );
  }

  Future<void> _toggleMic() async {
    final AppState app = AppState.of(context);
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (_transcribing) return;
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
        // 系统识别装不上（国产 ROM 上很常见）——直接改用服务端转写，别把人退回打字。
        await _startRecording();
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
          _runLocal(LocalQuery(words));
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

  /// 录一段交给 `/speech/transcribe`：这是原项目给 Web Speech 不可用的设备留的回落通道。
  /// 16 kHz 单声道够 Whisper 认字，文件也小；到 60 秒自己停，不靠用户记得收。
  Future<void> _startRecording() async {
    if (_recording || _transcribing) return;
    final AppState app = AppState.of(context);
    // 系统听写还开着就先把麦克风交出来：安卓上两个录音源只会一起失败。
    if (_listening) {
      await _stt.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    final bool allowed = await _rec.hasPermission();
    if (!mounted) return;
    if (!allowed) {
      showToast(context, app.l10n.aiRecordDenied, danger: true);
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    final String path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordSeconds = 0;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _recordSeconds += 1);
      if (_recordSeconds >= _recordCapSeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _tick?.cancel();
    _tick = null;
    final AppState app = AppState.of(context);
    String? path;
    try {
      path = await _rec.stop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _recording = false);
      showToast(context, app.describeError(error), danger: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
      _transcribing = true;
    });

    String text = '';
    String? failure;
    try {
      if (path == null) throw const FileSystemException('录音没落盘');
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();
      try {
        if (bytes.isEmpty) throw const FileSystemException('录音是空的');
        text = await _repos.ai.transcribe(bytes, mimeType: 'audio/mp4');
      } finally {
        // 转写失败也要清掉临时录音，不然每次说不清都留一个 m4a 在缓存里。
        try {
          await file.delete();
        } on Object catch (_) {}
      }
    } on Object catch (error) {
      failure = error is ApiException ? app.describeError(error) : app.l10n.aiRecordFailed;
    }
    if (!mounted) return;
    setState(() => _transcribing = false);
    final String words = text.trim();
    if (failure != null || words.isEmpty) {
      showToast(context, failure ?? app.l10n.aiRecordFailed, danger: true);
      return;
    }
    _input.text = words;
    _input.selection = TextSelection.collapsed(offset: words.length);
    if (_tab == 1) {
      _runLocal(LocalQuery(words));
    } else {
      _ask(words);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _tick?.cancel();
    _tick = null;
    await _rec.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
    });
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
          if (config != null && !config.enabled)
            // 超管把模块整个关了：没有数据可查，也没有模型可问，只剩解释和反馈。
            Expanded(child: _NotConfigured(config: config, l10n: l10n))
          else if (_tab == 1)
            // 速查走本地引擎：配置在途或拉不到都不挡路，它只要业务接口活着。
            Expanded(child: _buildLookup(l10n))
          else if (_config.loading && config == null)
            const Expanded(child: SkeletonList(count: 3, itemHeight: 70))
          else if (config == null)
            Expanded(
              child: AppErrorView(message: _config.errorText ?? l10n.commonErrorTitle, onRetry: _config.load),
            )
          else if (!config.usable)
            // 缺的是模型密钥，不是速查：问答锁掉，速查照常走真实记录。
            Expanded(
              child: _NotConfigured(
                config: config,
                l10n: l10n,
                onLookup: () => setState(() => _tab = 1),
              ),
            )
          else
            Expanded(child: _buildChat(l10n)),
          _Composer(
            controller: _input,
            focusNode: _focus,
            busy: _sending || _looking || _transcribing,
            listening: _listening || _recording,
            hint: l10n.aiPlaceholder,
            listeningHint: _recording ? l10n.aiRecording(_recordSeconds) : l10n.aiListening,
            sendLabel: l10n.aiSend,
            voiceTooltip: _recording ? l10n.actDone : l10n.aiVoice,
            shortcuts: _recording ? _recordingStrip(l10n) : _stripIfUsable(config),
            onSend: () => _tab == 0 ? _ask(_input.text) : _runLocal(LocalQuery(_input.text)),
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
        if (!_looking && _lookup != null) ..._renderResult(_lookup!, l10n),
      ],
    );
  }

  List<Widget> _renderResult(LocalResult result, L10n l10n) {
    final AppState app = AppState.of(context);
    switch (result.kind) {
      case LocalKind.stats:
        return <Widget>[
          SectionHeader(title: l10n.aiValueTitle, accent: AppInk.inventory),
          AppCard(
            accent: AppInk.inventory,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: <Widget>[
                KeyValueRow(label: l10n.dashProducts, value: result.stats['products'] ?? '0'),
                KeyValueRow(label: l10n.dashStockQty, value: result.stats['qty'] ?? '0'),
                KeyValueRow(
                  label: l10n.dashStockValue,
                  value: Fmt.money(
                    double.tryParse(result.stats['value'] ?? '') ?? 0,
                    symbol: app.profile.currencySymbol,
                  ),
                ),
              ],
            ),
          ),
        ];
      case LocalKind.low:
        if (result.products.isEmpty) {
          return <Widget>[
            SectionHeader(title: l10n.aiLowStockTitle, accent: AppInk.showroom),
            AppEmpty(
              title: l10n.commonEmptyTitle,
              hint: l10n.aiLookupHint,
              icon: Icons.inventory_2_rounded,
              accent: AppInk.success,
            ),
          ];
        }
        return <Widget>[
          SectionHeader(
            title: l10n.aiLowStockTitle,
            subtitle: l10n.aiCountOrders(result.count),
            accent: AppInk.showroom,
          ),
          AppCard(
            accent: AppInk.showroom,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: result.products
                  .map(
                    (InventoryRow row) => TileRow(
                      icon: Icons.inventory_2_rounded,
                      accent: AppInk.showroom,
                      identity: ProductIdentity(
                        sku: row.sku,
                        name: row.name,
                        showName: AppState.of(context).productNameVisible,
                        secondary: '${Fmt.count(row.quantity)} / ${l10n.prodMinStock} ${Fmt.count(row.minStock)}'
                            '${row.location == null ? '' : ' · ${row.location}'}',
                      ),
                      trailing: StatusPill(
                        label: row.quantity <= 0 ? l10n.invOutOf : l10n.invLow,
                        color: row.quantity <= 0 ? AppInk.danger : AppInk.showroom,
                        dense: true,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ];
      case LocalKind.orders:
        // 快捷按钮之外还认手打的「出库/入库」字样：类型筛选落在展示层，引擎给的是当天全部单据。
        final OrderType? want = _lastQuery?.only;
        final List<Order> rows = want == null
            ? result.orders
            : result.orders.where((Order o) => o.type == want).toList(growable: false);
        return _orderRows(
          l10n,
          title: result.title,
          note: l10n.aiCountOrders(want == null ? result.count : rows.length),
          orders: rows,
        );
      case LocalKind.products:
        return _productRows(l10n, note: result.note, rows: result.products);
      case LocalKind.logs:
        if (result.logs.isEmpty) return <Widget>[_notFound(l10n, result.note)];
        return <Widget>[
          SectionHeader(
            title: l10n.aiLogsTitle,
            subtitle: result.note.isEmpty ? null : result.note,
            accent: AppInk.ai,
          ),
          AppCard(
            accent: AppInk.ai,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: result.logs
                  .take(15)
                  .map((OperationLog log) => KeyValueRow(
                        label: Fmt.dateTime(log.createdAt),
                        value: logLine(l10n, log,
                            showName: AppState.of(context).productNameVisible),
                      ))
                  .toList(growable: false),
            ),
          ),
        ];
      case LocalKind.hint:
        return <Widget>[
          const VGap(6),
          _Bubble(turn: _Turn.answer(l10n.aiLocalHint)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final _Shortcut item in _shortcuts(l10n).skip(1))
                _PromptChip(label: item.label, onTap: () => _applyShortcut(item)),
            ],
          ),
        ];
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
    required List<Order> orders,
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
              .map((Order order) {
                final bool inbound = order.type == OrderType.inbound;
                return TileRow(
                  icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                  accent: AppInk.orders,
                  title: '${order.orderNumber} · ${order.customerName}',
                  // 单据类型写在行上：按日期查的一次给的是当天全部单据，不标出来就会把入库读成出库。
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

  List<Widget> _productRows(L10n l10n, {required String note, required List<InventoryRow> rows}) {
    if (rows.isEmpty) return <Widget>[_notFound(l10n, note)];
    return <Widget>[
      SectionHeader(title: l10n.aiProducts, subtitle: note, accent: AppInk.products),
      AppCard(
        accent: AppInk.products,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: rows
              .map(
                (InventoryRow row) => TileRow(
                  icon: Icons.inventory_2_rounded,
                  accent: AppInk.products,
                  identity: ProductIdentity(
                    sku: row.sku,
                    name: row.name,
                    showName: AppState.of(context).productNameVisible,
                    secondary: '${Fmt.count(row.quantity)} ${row.unit}'
                        '${row.location == null || row.location!.isEmpty ? '' : ' · ${row.location}'}',
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    ];
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.query, {this.history = false});

  /// 按钮上给用户看的字，走本地化。
  final String label;

  /// 真正发出去的问题：数据类问句必须是中文原文，引擎的正则才认。
  final LocalQuery query;

  /// 「历史订单」先落日期，再拼成 `历史订单:YYYY-MM-DD` 发给引擎。
  final bool history;
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
