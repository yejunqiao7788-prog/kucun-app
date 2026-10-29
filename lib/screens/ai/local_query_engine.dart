import 'dart:math';

import '../../core/formatters.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';

/// 速查的本地意图引擎 —— 复刻原项目 `api/ai_local.ts`：正则认意图，
/// 数据全部走已有的业务接口现取现算，不经过任何模型，也不需要模型密钥。
/// 与 `/assist/query` 的区别只有一条：这条通道永远在线。
class LocalQuery {
  const LocalQuery(this.text, {this.only});

  /// 真正参与意图匹配的字：数据类意图是写死的中文原文，正则才认。
  final String text;

  /// 按日期拿到的是当天全部单据，这一位说明只想要哪一类。
  final OrderType? only;
}

enum LocalKind { stats, low, orders, products, logs, hint }

class LocalResult {
  const LocalResult({
    required this.kind,
    this.title = '',
    this.note = '',
    this.count = 0,
    this.products = const <InventoryRow>[],
    this.orders = const <Order>[],
    this.logs = const <OperationLog>[],
    this.stats = const <String, String>{},
  });

  final LocalKind kind;
  final String title;

  /// 副标题：日期区间、关键词这类上下文。
  final String note;
  final int count;
  final List<InventoryRow> products;
  final List<Order> orders;
  final List<OperationLog> logs;
  final Map<String, String> stats;
}

class LocalQueryEngine {
  const LocalQueryEngine(this._repos);

  final Repos _repos;

  static final RegExp _logIntent =
      RegExp('操作记录|操作日志|修改记录|变更记录|改动记录|谁改|改过什么|删除过什么|operation ?logs?|audit ?log', caseSensitive: false);
  static final RegExp _valueIntent = RegExp('库存统计|库存价值|货值|总价值|value', caseSensitive: false);
  static final RegExp _lowIntent = RegExp('库存预警|预警|低库存|补货|warning|low', caseSensitive: false);
  static final RegExp _outTodayIntent = RegExp('今日出货|今日出库|today.*ship|today.*out', caseSensitive: false);
  static final RegExp _inTodayIntent = RegExp('今日入库|today.*in', caseSensitive: false);
  static final RegExp _historyIntent =
      RegExp(r'(?:历史订单|历史|orders?(?: on)?)[：:\s]*(\d{4}-\d{2}-\d{2})', caseSensitive: false);
  static final RegExp _todayIntent = RegExp('今日订单|今日|today', caseSensitive: false);
  static final RegExp _yesterdayIntent = RegExp('昨天|昨日|yesterday', caseSensitive: false);

  /// 日志意图先判：「谁改了库存」不该落到库存统计上。
  static bool isLogQuery(String text) => _logIntent.hasMatch(text);

  Future<LocalResult> run(LocalQuery query, {required DateTime today}) async {
    final String s = query.text.trim();
    if (s.isEmpty) return const LocalResult(kind: LocalKind.hint);

    if (isLogQuery(s)) {
      return _logs(_logKeyword(s));
    }
    if (_valueIntent.hasMatch(s)) {
      return _stats();
    }
    if (_lowIntent.hasMatch(s)) {
      return _low();
    }
    if (_outTodayIntent.hasMatch(s)) {
      return _ordersOn(Fmt.isoDate(today), Fmt.isoDate(today), OrderType.outbound);
    }
    if (_inTodayIntent.hasMatch(s)) {
      return _ordersOn(Fmt.isoDate(today), Fmt.isoDate(today), OrderType.inbound);
    }
    final RegExpMatch? history = _historyIntent.firstMatch(s);
    if (history != null) {
      final String date = history.group(1)!;
      return _ordersOn(date, date, OrderType.outbound);
    }
    if (_yesterdayIntent.hasMatch(s)) {
      final String day = Fmt.isoDate(today.subtract(const Duration(days: 1)));
      return _ordersOn(day, day, null);
    }
    if (_todayIntent.hasMatch(s)) {
      return _ordersOn(Fmt.isoDate(today), Fmt.isoDate(today), null);
    }
    final LocalResult? sku = await _bySku(s);
    if (sku != null) return sku;
    return const LocalResult(kind: LocalKind.hint);
  }

  Future<LocalResult> _stats() async {
    final List<InventoryRow> rows = (await _repos.products.inventory()).data;
    int qty = 0;
    double value = 0;
    for (final InventoryRow row in rows) {
      qty += row.quantity;
      final Object? price = row.raw('price');
      if (price is num) value += price.toDouble() * row.quantity;
    }
    return LocalResult(
      kind: LocalKind.stats,
      count: rows.length,
      stats: <String, String>{
        'products': Fmt.count(rows.length),
        'qty': Fmt.count(qty),
        'value': value.toStringAsFixed(2),
      },
    );
  }

  Future<LocalResult> _low() async {
    final List<InventoryRow> rows = (await _repos.products.inventory()).data;
    final List<InventoryRow> low =
        rows.where((InventoryRow row) => row.quantity <= row.minStock).toList()
          ..sort((InventoryRow a, InventoryRow b) =>
              (a.quantity - a.minStock).compareTo(b.quantity - b.minStock));
    return LocalResult(
      kind: LocalKind.low,
      count: low.length,
      products: low.take(30).toList(growable: false),
    );
  }

  Future<LocalResult> _ordersOn(String from, String to, OrderType? type) async {
    final Paged<Order> page = (await _repos.orders.list(
      page: 1,
      pageSize: 50,
      type: type?.name,
      status: 'all',
      dateFrom: from,
      dateTo: to,
    )).data;
    return LocalResult(
      kind: LocalKind.orders,
      title: from == to ? from : '$from → $to',
      note: type?.name ?? '',
      count: page.count,
      orders: page.rows,
    );
  }

  Future<LocalResult> _logs(String keyword) async {
    final List<OperationLog> rows =
        await _repos.dashboard.logs(limit: 30, search: keyword.isEmpty ? null : keyword);
    return LocalResult(
      kind: LocalKind.logs,
      note: keyword,
      count: rows.length,
      logs: rows,
    );
  }

  /// SKU/商品名查询：拿全量库存做本地打分，原样照搬 ai_local 的排序权重。
  Future<LocalResult?> _bySku(String input) async {
    final String keyword = input.toLowerCase();
    final List<InventoryRow> rows = (await _repos.products.inventory()).data;
    final List<InventoryRow> hit = rows.where((InventoryRow row) {
      final String sku = row.sku.toLowerCase();
      final String name = row.name.toLowerCase();
      return sku.contains(keyword) || name.contains(keyword);
    }).toList()
      ..sort((InventoryRow a, InventoryRow b) =>
          _score(b, keyword).compareTo(_score(a, keyword)));
    if (hit.isEmpty) return null;
    return LocalResult(
      kind: LocalKind.products,
      note: input,
      count: hit.length,
      products: hit.take(20).toList(growable: false),
    );
  }

  static int _score(InventoryRow row, String q) {
    final String sku = row.sku.trim().toLowerCase();
    final String name = row.name.trim().toLowerCase();
    int score = 0;
    if (sku == q) {
      score += 1000;
    } else if (name == q) {
      score += 900;
    } else if (sku.startsWith('${q}_')) {
      score += 700;
    } else if (sku.startsWith(q)) {
      score += 600;
    } else if (sku.contains(q)) {
      score += 500;
    } else if (name.contains(q)) {
      score += 300;
    }
    if (row.quantity > 0) score += 20;
    return score;
  }

  /// 从「最近谁改了商品A01库存吗」这类句子里剥掉意图词和助词，剩下的才是关键词。
  static String _logKeyword(String text) {
    final String stripped = text.replaceAll(
      RegExp(
        '操作记录|操作日志|修改记录|变更记录|改动记录|谁改了|改过什么|删除过什么|operation ?logs?|audit ?log|最近|查一下|看一下|查询|商品|库存|的|吗|？|\\?',
        caseSensitive: false,
      ),
      '',
    ).trim();
    return stripped.isEmpty ? stripped : stripped.substring(0, min(stripped.length, 40));
  }
}
