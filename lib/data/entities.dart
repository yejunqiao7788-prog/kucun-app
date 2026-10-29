import 'json_map.dart';

export 'json_map.dart';

/// 库存三档阈值（契约 §6.3）。表达式是在客户端算的纯函数，但阈值定义不能改。
enum StockTier {
  out, // quantity == 0
  low, // 0 < quantity <= min_stock
  overflow, // quantity >= max_stock * 0.95
  normal;

  static StockTier of(num quantity, num minStock, num maxStock) {
    if (quantity <= 0) return StockTier.out;
    if (quantity <= minStock) return StockTier.low;
    if (quantity >= maxStock * 0.95) return StockTier.overflow;
    return StockTier.normal;
  }
}

class Product extends JsonMap {
  const Product(super.json);

  String get id => asStringOr('id', '');
  String get tenantId => asStringOr('tenant_id', '');
  String get sku => asStringOr('sku', '');
  String get name => asStringOr('name', '');
  String? get categoryId => asString('category_id');
  String? get categoryName => asString('category_name');

  double get price => asDoubleOr('price', 0);
  double get cost => asDoubleOr('cost', 0);
  String get unit => asStringOr('unit', '件');

  /// NULL = 该商品不做整箱销售。
  int? get unitsPerBox => asInt('units_per_box');
  double? get boxPrice => asDouble('box_price');
  bool get sellsByBox => (unitsPerBox ?? 0) > 1;

  String? get description => asString('description');

  /// 有序画廊，第 1 张是封面；`image_url` 是它的派生镜像。
  List<String> get imageUrls => asStringList('image_urls');
  String? get imageUrl => asString('image_url') ?? (imageUrls.isEmpty ? null : imageUrls.first);

  int get quantity => asIntOr('quantity', 0);
  int get minStock => asIntOr('min_stock', 0);
  int get maxStock => asIntOr('max_stock', 1000);
  String? get location => asString('location');

  DateTime? get createdAt => asDate('created_at');
  DateTime? get updatedAt => asDate('updated_at');
  DateTime? get deletedAt => asDate('deleted_at');

  StockTier get tier => StockTier.of(quantity, minStock, maxStock);

  /// 展示层换算：松散数 = 总量 − 整箱占用。库存真相始终是 `quantity`。
  int get looseQuantity {
    final int? perBox = unitsPerBox;
    if (perBox == null || perBox <= 1) return quantity;
    final int boxes = quantity ~/ perBox;
    return quantity - boxes * perBox;
  }

  int get boxCount {
    final int? perBox = unitsPerBox;
    if (perBox == null || perBox <= 1) return 0;
    return quantity ~/ perBox;
  }
}

/// `GET /products/inventory` 的行（库存视角的商品投影）。
class InventoryRow extends JsonMap {
  const InventoryRow(super.json);

  String get productId => asStringOr('product_id', asStringOr('id', ''));
  String get sku => asStringOr('sku', '');
  String get name => asStringOr('name', '');
  int get quantity => asIntOr('quantity', 0);
  int get minStock => asIntOr('min_stock', 0);
  int get maxStock => asIntOr('max_stock', 1000);
  String? get location => asString('location');
  String? get categoryId => asString('category_id');
  String? get categoryName => asString('category_name');
  String get unit => asStringOr('unit', '件');
  String? get imageUrl => asString('image_url');

  StockTier get tier => StockTier.of(quantity, minStock, maxStock);

  /// 空库位回空串，「未分配」这个词属于文案层，不进数据层。
  String get locationGroup => (location == null) ? '' : location!.trim();
}

class Category extends JsonMap {
  const Category(super.json);

  String get id => asStringOr('id', '');
  String get name => asStringOr('name', '');
  int get productCount => asIntOr('product_count', asIntOr('count', 0));
  String? get parentId => asString('parent_id');
}

class Customer extends JsonMap {
  const Customer(super.json);

  String get id => asStringOr('id', '');
  String get name => asStringOr('name', '');
  String? get phone => asString('phone');
  String? get email => asString('email');
  String? get address => asString('address');
  String? get notes => asString('notes');
  DateTime? get createdAt => asDate('created_at');
}

enum OrderType {
  inbound,
  outbound;

  static OrderType parse(String? raw) =>
      raw == 'inbound' ? OrderType.inbound : OrderType.outbound;
}

enum OrderStatus {
  pending,
  completed;

  static OrderStatus parse(String? raw) =>
      raw == 'completed' ? OrderStatus.completed : OrderStatus.pending;
}

enum PaymentStatus {
  unpaid,
  partial,
  paid;

  static PaymentStatus parse(String? raw) {
    switch (raw) {
      case 'paid':
        return PaymentStatus.paid;
      case 'partial':
        return PaymentStatus.partial;
      default:
        return PaymentStatus.unpaid;
    }
  }
}

class Order extends JsonMap {
  const Order(super.json);

  String get id => asStringOr('id', '');
  String get orderNumber => asStringOr('order_number', '—');
  OrderType get type => OrderType.parse(asString('type'));
  OrderStatus get status => OrderStatus.parse(asString('status'));
  String? get orderDate => asString('order_date');
  String? get notes => asString('notes');
  bool get isPreparing => asBool('is_preparing');
  bool get showInPickingList => asBool('show_in_picking_list');
  String? get createdBy => asString('created_by');
  DateTime? get completedAt => asDate('completed_at');
  DateTime? get createdAt => asDate('created_at');

  String? get customerId => asString('customer_id');
  String get customerName => asStringOr('customer_name', '未指定客户');

  /// 仅 `created_by == 'marketplace'` 时服务端才给手机号。
  String? get customerPhone => asString('customer_phone');

  int get totalQuantity => asIntOr('total_quantity', 0);
  double get totalAmount => asDoubleOr('total_amount', 0);
  double get payableAmount => asDoubleOr('payable_amount', 0);
  double get paidAmount => asDoubleOr('paid_amount', 0);
  PaymentStatus get paymentStatus => PaymentStatus.parse(asString('payment_status'));

  double get outstandingAmount {
    final double due = payableAmount - paidAmount;
    return due < 0 ? 0 : due;
  }

  List<OrderItem> get items =>
      asRawList('items').map(OrderItem.new).toList(growable: false);
  int get itemCount => items.length;
}

class OrderItem extends JsonMap {
  const OrderItem(super.json);

  String? get id => asString('id');
  String get productId => asStringOr('product_id', '');
  String get productName => asStringOr('product_name', '');
  String get productSku => asStringOr('product_sku', '');
  int get quantity => asIntOr('quantity', 0);
  double get unitPrice => asDoubleOr('unit_price', 0);
  double get subtotal => asDoubleOr('subtotal', 0);
  int get boxCount => asIntOr('box_count', 0);
  int? get unitsPerBox => asInt('units_per_box');
  String? get categoryName => asString('category_name');
  String? get imageUrl => asString('image_url');
  List<String> get imageUrls => asStringList('image_urls');

  Map<String, Object?> toDraftPayload() => <String, Object?>{
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName,
        'product_sku': productSku,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'box_count': boxCount,
        'units_per_box': unitsPerBox,
      };
}

/// `/orders/product-history` 给的是**按商品行展开**的流水，不是 Order：
/// 服务端只回单号、单据类型、日期、这一支的数量、客户与备注，
/// 没有订单 id 也带不出金额，所以这里不能复用 [Order]（会读出一堆 0 与空 id）。
class ProductHistoryEntry extends JsonMap {
  const ProductHistoryEntry(super.json);

  String get orderNumber => asStringOr('order_number', '—');
  OrderType get type => OrderType.parse(asString('type'));
  DateTime? get orderDate => asDate('order_date');
  int get quantity => asIntOr('quantity', 0);
  String get customerName => asStringOr('customer_name', '');
  String? get notes => asString('notes');
}

/// `POST /invitations/lookup` → `data.invitation`。
///
/// 注册前预览：服务端只给团队名、入职角色与有效期，不给成员名单。
class InvitationPreview extends JsonMap {
  const InvitationPreview(super.json);

  factory InvitationPreview.fromData(Object? envelopeData) =>
      InvitationPreview(JsonMap.from(envelopeData).asMap('invitation').json);

  String get tenantName => asStringOr('tenant_name', '');
  String get role => asStringOr('role', 'tenant_user');
  DateTime? get expiresAt => asDate('expires_at');
}

/// 工作台八个指标：单个 RPC 出数，客户端不得二次汇总。
class DashboardStats extends JsonMap {
  const DashboardStats(super.json);

  int get totalProducts => asIntOr('totalProducts', 0);
  int get totalStock => asIntOr('totalStock', 0);
  int get lowStock => asIntOr('lowStock', 0);
  int get inboundToday => asIntOr('inboundToday', 0);
  int get outboundToday => asIntOr('outboundToday', 0);
  int get inboundQtyToday => asIntOr('inboundQtyToday', 0);
  int get outboundQtyToday => asIntOr('outboundQtyToday', 0);
  double get totalValue => asDoubleOr('totalValue', 0);
}

class OperationLog extends JsonMap {
  const OperationLog(super.json);

  String get id => asStringOr('id', '');

  /// 日志出参历史上见到两套键名：业务侧的 `action`/`detail`/`username`，和网页端类型里的
  /// `operation_type`/`details{…}`/`user_name`。只认一套时另一套会整行读成空白，键名在这里取并集。
  String get action => asStringOr('action', asStringOr('operation_type', ''));

  String get actor => asStringOr(
        'username',
        asStringOr('user_name', asStringOr('actor', asStringOr('created_by', ''))),
      );

  String get tableName => asStringOr('table_name', '');

  JsonMap get _details => asMap('details');

  String get productName => asStringOr('name', _details.asStringOr('name', ''));

  String get productSku => asStringOr('sku', _details.asStringOr('sku', ''));

  String get detail {
    final String direct = asStringOr('detail', asStringOr('message', ''));
    return direct.isNotEmpty ? direct : _changeSummary;
  }

  /// `quantity: 12 → 8 · location: A → B`，网页端是逐字段小块，这里收成一行文本。
  String get _changeSummary {
    final Map<String, Object?> changes = _details.asMap('changes').json;
    return changes.entries
        .map((MapEntry<String, Object?> entry) {
          final JsonMap pair = JsonMap.from(entry.value);
          return '${entry.key}: ${pair.raw('from') ?? '—'} → ${pair.raw('to') ?? '—'}';
        })
        .join(' · ');
  }

  /// 一行可读摘要：谁 · 做了什么 · 哪件货（带变更）。缺哪段跳哪段，不留空行。
  String get summary {
    final String target = productName.isNotEmpty ? productName : productSku;
    final List<String> parts = <String>[
      if (actor.isNotEmpty) actor,
      if (action.isNotEmpty) action,
      if (target.isNotEmpty) target,
      if (detail.isNotEmpty) detail,
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  DateTime? get createdAt => asDate('created_at');
}

class Showroom extends JsonMap {
  const Showroom(super.json);

  String get id => asStringOr('id', '');

  /// 服务端字段叫 `title`，历史数据里才有 `name`。
  String get name => asStringOr('title', asStringOr('name', ''));
  String? get brandName => asString('brand_name');
  String get mode => asStringOr('mode', 'selected');

  /// 历史数据可能带 `[theme:xxx]` 前缀：读出剥离，写入不再添加。
  String? get description {
    final String? rawValue = asString('description');
    if (rawValue == null) return null;
    return rawValue.replaceFirst(RegExp(r'^\s*\[theme:[^\]]*\]\s*'), '');
  }

  /// 公开地址是 `/s/<share_token>`，token 由数据库生成，客户端不能自造。
  String? get shareToken => asString('share_token') ?? asString('token');
  String? get publicUrl => asString('public_url');
  String get status => asStringOr('status', 'active');
  bool get isActive => status == 'active';
  DateTime? get expiresAt => asDate('expires_at');

  bool get showPrice => asBool('show_price', fallback: true);
  bool get showStock => asBool('show_stock');
  bool get requirePhone => asBool('require_phone', fallback: true);
  bool get allowOrder => asBool('allow_order', fallback: true);
  bool get showName => asBool('show_name', fallback: true);
  bool get showCategory => asBool('show_category', fallback: true);
  String? get categoryId => asString('category_id');
  String? get categoryName => asString('category_name');
  String? get customerId => asString('customer_id');

  /// 列表行给的是服务端算好的 `item_count`（按 mode 口径），详情行才带 `items` 数组。
  int get itemCount => asInt('item_count') ?? asList('items').length;
  int get visitCount => asIntOr('visit_count', 0);
  int get orderCount => asIntOr('order_count', 0);
  List<JsonMap> get items => asList('items');
  DateTime? get createdAt => asDate('created_at');
}

/// 备忘录是按「当前用户」隔离的（服务端用 `user_id` 过滤，别人看不到你的）。
class Memo extends JsonMap {
  const Memo(super.json);

  String get id => asStringOr('id', '');
  String get content => asStringOr('content', '');
  bool get completed => asBool('is_completed');

  /// 只有 `high` / `normal` 两档，服务端把其它值一律折成 normal。
  String get priority => asStringOr('priority', 'normal');
  bool get isHigh => priority == 'high';
  DateTime? get createdAt => asDate('created_at');
}

/// 备货勾选：主键是 `(order_id, item_index)`，没有独立 id，也没有商品名快照。
/// `picked_count` 是绝对值，服务端幂等 upsert；传 0 等于删除这一行的标记。
class PickingMark extends JsonMap {
  const PickingMark(super.json);

  String get orderId => asStringOr('order_id', '');
  int get itemIndex => asIntOr('item_index', -1);
  int get pickedCount => asIntOr('picked_count', 0);
  int get maxQuantity => asIntOr('max_quantity', 0);
  DateTime? get updatedAt => asDate('updated_at');

  bool get done => maxQuantity > 0 && pickedCount >= maxQuantity;
}

class MemberRow extends JsonMap {
  const MemberRow(super.json);

  String get id => asStringOr('id', '');
  String get email => asStringOr('email', '');

  /// 出参里 `username` 可能为 null，服务端自己也用邮箱兜底。
  String get username => (asString('username')?.isNotEmpty ?? false) ? asString('username')! : email;
  String get role => asStringOr('role', 'user');
  String get status => asStringOr('status', 'pending');
  bool get isActive => status == 'active';

  /// 权限位是服务端 `normalizePermissions()` 出来的固定键集，缺键按 false。
  Map<String, bool> get permissions => asBoolMap('permissions');
  String? get avatarUrl => asString('avatar_url');
  DateTime? get createdAt => asDate('created_at');
  DateTime? get updatedAt => asDate('updated_at');
}

/// 邀请码是一串可反复出示的凭证，没有邮箱归属：`{id,code,role,permissions,status,used_by,used_at,expires_at,...}`。
class Invitation extends JsonMap {
  const Invitation(super.json);

  String get id => asStringOr('id', '');
  String get code => asStringOr('code', '');
  String get role => asStringOr('role', 'user');
  Map<String, bool> get permissions => asBoolMap('permissions');
  String get status => asStringOr('status', 'pending');
  bool get isPending => status == 'pending';
  bool get isUsed => status == 'used';
  String? get usedBy => asString('used_by');
  DateTime? get usedAt => asDate('used_at');
  DateTime? get expiresAt => asDate('expires_at');
  DateTime? get createdAt => asDate('created_at');

  /// 「已过期」服务端不写状态位（status 仍是 pending），到期判断只能由 `expires_at` 现算。
  bool get isExpired {
    final DateTime? at = expiresAt;
    return at != null && at.isBefore(DateTime.now());
  }

  /// 用过或过期都只剩一个删除动作，不能再被拿去注册。
  bool get consumable => isPending && !isExpired;
}

/// 租户反馈线程：`{id,category,content,page_url,status,reply,replied_at,created_at,updated_at,mine}`。
class FeedbackThread extends JsonMap {
  const FeedbackThread(super.json);

  String get id => asStringOr('id', '');

  /// `bug` / `billing` / `marketplace` / `suggestion` / `other`。
  String get category => asStringOr('category', 'other');
  String get content => asStringOr('content', '');
  String? get pageUrl => asString('page_url');
  String get status => asStringOr('status', 'open');
  bool get answered => (asString('reply')?.isNotEmpty ?? false);
  String get reply => asStringOr('reply', '');
  DateTime? get repliedAt => asDate('replied_at');
  DateTime? get createdAt => asDate('created_at');
  DateTime? get updatedAt => asDate('updated_at');

  /// `mine` 由服务端按当前查看者算：只有自己能看见自己那条的正文之外的信息。
  bool get mine => asBool('mine');
}

class PaymentRecord extends JsonMap {
  const PaymentRecord(super.json);

  String get id => asStringOr('id', '');
  String? get orderId => asString('order_id');
  String? get customerId => asString('customer_id');
  String get orderNumber => asStringOr('order_number', '—');
  String get customerName => asStringOr('customer_name', '散客/未关联');

  /// `payment` / `refund` / `debt_settle` 三种流水，退款与还款的净额符号不同。
  String get type => asStringOr('type', 'payment');
  bool get isRefund => type == 'refund';
  bool get isDebtSettle => type == 'debt_settle';

  /// `cash` / `transfer`。
  String get method => asStringOr('method', 'cash');
  double get received => asDoubleOr('received_amount', 0);
  double get change => asDoubleOr('change_amount', 0);

  /// 真正入账的数：汇总、趋势、方法分布都读这一列，不读 `received`。
  double get applied => asDoubleOr('applied_amount', 0);
  DateTime? get paidAt => asDate('paid_at');
  String? get notes => asString('notes');
  String? get createdBy => asString('created_by');
}

/// `GET /finance/debts` 按客户分组（不是按单），一行 = 一个欠款客户 + 他的未结清单。
class DebtRow extends JsonMap {
  const DebtRow(super.json);

  String? get customerId => asString('customer_id');

  /// 没有 customer_id 的那一组服务端固定写作「散客/未关联」，还款要落到具体客户才行。
  String get customerName => asStringOr('customer_name', '散客/未关联');
  String? get customerPhone => asString('customer_phone');
  double get totalOutstanding => asDoubleOr('total_outstanding', 0);
  int get orderCount => asIntOr('order_count', orders.length);

  /// 组内按订单展开：`{order_id, order_number, order_date, payable_amount, paid_amount, outstanding, payment_status}`。
  List<JsonMap> get orders => asList('orders');
  bool get isAnonymous => customerId == null;
}

/// 一次客户还款的回执：`{settled[], total_applied, change}`。
class DebtSettlement extends JsonMap {
  const DebtSettlement(super.json);

  List<JsonMap> get settled => asList('settled');
  int get settledCount => settled.length;
  double get totalApplied => asDoubleOr('total_applied', 0);

  /// 还超了就是找零，不是余额；界面要分开说。
  double get change => asDoubleOr('change', 0);
}

/// 财务汇总。注意 `truncated`：现网扫描有行数上限，命中即为"可能少报"。
class FinanceSummary extends JsonMap {
  const FinanceSummary(super.json);

  String? get dateFrom => asMap('range').asString('dateFrom');
  String? get dateTo => asMap('range').asString('dateTo');

  JsonMap get today => asMap('today');
  double get todayNet => today.asDoubleOr('net', 0);
  double get todayReceived => today.asDoubleOr('received', 0);
  double get todayChange => today.asDoubleOr('change', 0);
  double get todayCash => today.asDoubleOr('cash', 0);
  double get todayTransfer => today.asDoubleOr('transfer', 0);
  int get todayCount => today.asIntOr('count', 0);

  JsonMap get period => asMap('period');
  double get periodNet => period.asDoubleOr('net_received', 0);
  double get revenue => period.asDoubleOr('revenue', 0);
  double get profit => period.asDoubleOr('profit', 0);
  int get orderCount => period.asIntOr('order_count', 0);
  JsonMap get methodTotals => period.asMap('method_totals');

  JsonMap get debts => asMap('debts');
  double get totalOutstanding => debts.asDoubleOr('total_outstanding', 0);
  int get debtCustomerCount => debts.asIntOr('customer_count', 0);

  List<JsonMap> get trend => asList('trend');
  bool get truncated => asBool('truncated');
}

/// `GET /wallet/account`：集市投放钱包。出参没有 `spent`，也没有「读失败折成 0」——
/// 服务端把「没账户行」如实回成 `exists: false`。
class WalletAccount extends JsonMap {
  const WalletAccount(super.json);

  bool get exists => asBool('exists');
  int get balanceMinor => asIntOr('balance_minor', 0);
  double get balance => asDoubleOr('balance_major', balanceMinor / 100.0);
  String get currency => asStringOr('currency', 'UAH');
  DateTime? get updatedAt => asDate('updated_at');
}

/// 订阅价目表：`{default_channel, channels:{monobank:{...plans[]}, paddle:{...plans[]}}}`。
/// `channels` 是对象不是数组，逐通道摊平成行给界面用。
/// 通道这一层不能省：`/wallet/plans` 是扁平的，套它的读法会永远读不到档位。
class PlanBoard extends JsonMap {
  const PlanBoard(super.json);

  String? get defaultChannel => asString('default_channel');

  JsonMap get _channels => asMap('channels');

  PlanChannel _row(String name) {
    final JsonMap raw = _channels.asMap(name);
    // 别名要在判空之后才补：先补进 map 就再没有「服务端没发这条」的形状了。
    return raw.json.isEmpty
        ? const PlanChannel(<String, Object?>{})
        : PlanChannel(<String, Object?>{...raw.json, 'channel': name});
  }

  List<PlanChannel> get channels => <String>['monobank', 'paddle']
      .map(_row)
      .where((PlanChannel row) => row.json.isNotEmpty)
      .toList(growable: false);

  PlanChannel channel(String name) => _row(name);

  /// 服务端算好的那一条：没有它就不该出现默认选中的通道。
  PlanChannel? get payableDefault {
    final String? name = defaultChannel;
    if (name == null) return null;
    final PlanChannel row = channel(name);
    return row.payable ? row : null;
  }

  bool get anyPayable => channels.any((PlanChannel row) => row.payable);
}

class PlanChannel extends JsonMap {
  const PlanChannel(super.json);

  /// `provider` 是服务端的键，`channel` 是这里补的别名，两者同值。
  String get name => asStringOr('channel', asStringOr('provider', ''));
  String get currency => asStringOr('currency', name == 'paddle' ? 'USD' : 'UAH');

  /// monobank 有 `enabled` 开关，paddle 没有这一路 —— 缺键时按「可付即可用」处理。
  bool get enabled => json.containsKey('enabled') ? asBool('enabled') : payable;
  bool get configured => asBool('configured');
  bool get payable => asBool('payable');
  bool get tokenizationEnabled => asBool('tokenization_enabled');
  String? get environment => asString('environment');

  List<PlanRow> get plans =>
      asEntities('plans', PlanRow.new);

  PlanRow plan(String planType) => PlanRow(<String, Object?>{
        ...plans.firstWhere(
              (PlanRow row) => row.planType == planType,
              orElse: () => const PlanRow(<String, Object?>{}),
            ).json,
        'currency': currency,
        'channel': name,
        'payable': payable,
      });
}

class PlanRow extends JsonMap {
  const PlanRow(super.json);

  /// 通道行的键是驼峰 `planType`。
  String get planType => asStringOr('planType', asStringOr('plan_type', ''));
  int get days => asIntOr('days', 0);
  int get priceMinor => asIntOr('priceMinor', asIntOr('price_minor', 0));
  String get currency => asStringOr('currency', '');
  String get channel => asStringOr('channel', '');
  bool get payable => asBool('payable');

  /// 分单位换回元：Monobank 用 kopeck，Paddle 用 cent。
  double get amount => priceMinor / 100.0;

  bool get hasPrice => priceMinor > 0;
}

/// 建单/轮询的回执：`{payment:{id,invoice_id,plan_type,amount_cents,ccy,status,page_url,...}, reused?}`。
/// 金额与档位都来自服务端价目表，客户端传进去的任何金额都不参与。
class PaymentTicket extends JsonMap {
  const PaymentTicket(super.json);

  JsonMap get payment => asMap('payment');
  String get id => payment.asStringOr('id', '');
  String? get invoiceId => payment.asString('invoice_id');

  /// 托管收银台地址：App 里唯一能把它交给用户的通道是 `url_launcher`（内嵌 webview 拿不到银行页）。
  String? get pageUrl => payment.asString('page_url');
  String get planType => payment.asStringOr('plan_type', '');
  String get provider => payment.asStringOr('provider', '');
  String get currency => payment.asStringOr('ccy', '');
  int get amountCents => payment.asIntOr('amount_cents', 0);
  double get amount => amountCents / 100.0;

  /// `created` / `processing` / `succeeded` / `failed` / `expired` / `canceled`。
  String get status => payment.asStringOr('status', 'created');
  bool get succeeded => status == 'succeeded';
  bool get terminal => const <String>{'succeeded', 'failed', 'expired', 'canceled'}.contains(status);
  String? get failureReason => payment.asString('failure_reason');
  String? get maskedPan => payment.asString('masked_pan');
  DateTime? get paidAt => payment.asDate('paid_at');

  /// 复用了此前未终态的同档账单（同一张票，不是又扣一次）。
  bool get reused => asBool('reused');
}

/// `GET /wallet/plans`：充值档位（`{currency, enabled, configured, payable, tiers[]}`）。
class WalletTopupBoard extends JsonMap {
  const WalletTopupBoard(super.json);

  String get currency => asStringOr('currency', 'UAH');
  bool get enabled => asBool('enabled');
  bool get configured => asBool('configured');
  bool get payable => asBool('payable');

  /// 档位行是 `{tier:'small'|'medium'|'large', uahMajor, priceMinor}`。
  List<JsonMap> get tiers => asList('tiers');
  List<String> get tierKeys =>
      tiers.map((JsonMap row) => row.asStringOr('tier', '')).where((String k) => k.isNotEmpty).toList();
}

/// 批量导入的回包：服务端给计数加失败样例，两个键名在不同入口里不一致，都得吃。
class ImportOutcome extends JsonMap {
  const ImportOutcome(super.json);

  int get successCount => asIntOr('success_count', 0);
  int get failedCount => asIntOr('failed_count', 0);

  /// 只有外部数据源导入才会带：图片下载失败不影响商品写入。
  int get imageFailedCount => asIntOr('image_failed_count', 0);

  List<JsonMap> get failures {
    final List<JsonMap> primary = asList('failures');
    return primary.isEmpty ? asList('failed_examples') : primary;
  }
}

/// 批量改价的回执同样是逐行统计，不是整批成败：一部分商品可能因为成本为空、
/// 价格越界而单独失败，`failed_examples` 只回前若干条。
class BatchPriceResult extends JsonMap {
  const BatchPriceResult(super.json);

  int get updatedCount => asIntOr('updated_count', 0);
  int get unchangedCount => asIntOr('unchanged_count', 0);
  int get failedCount => asIntOr('failed_count', 0);

  List<String> get failureHints => asList('failed_examples')
      .map((JsonMap row) {
        final String sku = row.asStringOr('sku', '');
        final String message = row.asStringOr('message', '');
        if (message.isEmpty) return sku;
        return sku.isEmpty ? message : '$sku $message';
      })
      .where((String text) => text.isNotEmpty)
      .toList(growable: false);
}

/// `/data/external-preview` 把外部 YML / XML 商品源解析成整店统计加待写行，
/// `items` 原样透传给导入与同步，客户端不参与字段拼装。
class ExternalPreview extends JsonMap {
  const ExternalPreview(super.json);

  String get shopName => asStringOr('shop_name', '');
  int get total => asIntOr('total', 0);
  int get withImageCount => asIntOr('with_image_count', 0);
  int get withBoxCount => asIntOr('with_box_count', 0);
  int get categoriesCount => asIntOr('categories_count', 0);
  List<JsonMap> get items => asList('items');
}

/// `/data/external-sync`：只动已有商品，认不出的行回在 `new_items` 里等导入。
class ExternalSyncOutcome extends JsonMap {
  const ExternalSyncOutcome(super.json);

  int get updatedCount => asIntOr('updated_count', 0);
  int get unchangedCount => asIntOr('unchanged_count', 0);
  int get skippedCount => asIntOr('skipped_count', 0);
  int get failedCount => asIntOr('failed_count', 0);
  List<JsonMap> get failures => asList('failed_examples');
  List<JsonMap> get newItems => asList('new_items');
}

/// 保留策略的报告（预览与执行同形）：条数、两档窗口、两枚 cutoff，外加样本。
class RetentionReport extends JsonMap {
  const RetentionReport(super.json);

  int get softDeletedCount => asIntOr('soft_deleted_count', 0);
  int get hardDeletedCount => asIntOr('hard_deleted_count', 0);
  int get total => softDeletedCount + hardDeletedCount;
  bool get hasWork => total > 0;

  List<JsonMap> get softDeletedProducts => asList('soft_deleted_products');
  List<JsonMap> get hardDeletedProducts => asList('hard_deleted_products');

  /// 生效窗口由服务端折出来（非法值回落到默认），界面读回显而不是自己那份输入。
  int get zeroStockDays => asIntOr('zero_stock_days', 0);
  int get softDeleteDays => asIntOr('soft_delete_days', 0);
  int get daysMin => asIntOr('days_min', 1);
  int get daysMax => asIntOr('days_max', 3650);

  DateTime? get zeroStockCutoff => asDate('zero_stock_cutoff');
  DateTime? get softDeleteCutoff => asDate('soft_delete_cutoff');
}

/// 外部 API Key：`{id,tenant_id,name,key_prefix,scopes,status,last_used_at,expires_at,...}`。
/// 完整明文只在创建那一次回带来，列表里永远只有 `key_prefix`。
class ApiKey extends JsonMap {
  const ApiKey(super.json);

  String get id => asStringOr('id', '');
  String get name => asStringOr('name', '');
  String get keyPrefix => asStringOr('key_prefix', '');
  List<String> get scopes => asStringList('scopes');

  /// `active` / `revoked`（服务端另有过期判定）。
  String get status => asStringOr('status', 'active');
  bool get active => status == 'active';
  DateTime? get lastUsedAt => asDate('last_used_at');
  DateTime? get expiresAt => asDate('expires_at');
  DateTime? get createdAt => asDate('created_at');
  DateTime? get revokedAt => asDate('revoked_at');

  bool get isExpired {
    final DateTime? at = expiresAt;
    return at != null && at.isBefore(DateTime.now());
  }

  String get display => '$keyPrefix••••';
}

/// 创建回执：`{key, plaintext}`。`plaintext` 只显示这一次，关掉就再也拿不回来。
class ApiKeyCreated extends JsonMap {
  const ApiKeyCreated(super.json);

  ApiKey get key => ApiKey(asMap('key').json);
  String get plaintext => asStringOr('plaintext', '');
}

class AiConfig extends JsonMap {
  const AiConfig(super.json);

  /// 两枚开关分开看：`enabled` 是租户侧总开关，`configured` 才说明超管挂了密钥。
  bool get enabled => asBool('enabled');
  bool get configured => asBool('configured');

  /// 服务端把模型放在驼峰的 `modelChat`，没有 `model` / `model_name`。
  String get model => asStringOr('modelChat', 'deepseek-chat');
  String get baseUrl => asStringOr('baseUrl', '');
  double get temperature => asDoubleOr('temperature', 0.7);
  int get maxTokens => asIntOr('maxTokens', 2000);
  int get contextWindow => asIntOr('contextWindow', 10);

  /// `quick_prompts` 存的是 JSON 数组，元素可能是纯字符串或 `{text}` 对象。
  List<String> get quickPrompts {
    final Object? raw = json['quickPrompts'] ?? json['quick_prompts'];
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? item in raw) {
      final String text = item is String
          ? item
          : (normalize(item)['text'] ?? normalize(item)['label'] ?? '').toString();
      if (text.isNotEmpty) out.add(text);
    }
    return out;
  }

  String? get error => asString('error');

  /// 密钥不在租户手里，未配置时页面只解释「为什么不能聊」，不提供输入框。
  bool get usable => enabled && configured;
}

enum LeadStatus {
  new_,
  contacted,
  confirmed,
  converted,
  declined,
  spam,
  expired;

  static const List<String> sellerSettable = <String>[
    'contacted',
    'confirmed',
    'converted',
    'declined',
    'spam',
  ];

  static LeadStatus parse(String? raw) => LeadStatus.values.firstWhere(
        (LeadStatus value) => value.wire == raw,
        orElse: () => LeadStatus.new_,
      );

  String get wire => this == LeadStatus.new_ ? 'new' : name;
}

enum BuyerIdentity {
  verified,
  anonymous,
  closed,
  unknown;

  static BuyerIdentity parse(String? raw) => BuyerIdentity.values.firstWhere(
        (BuyerIdentity value) => value.name == raw,
        orElse: () => BuyerIdentity.unknown,
      );
}

class MpLead extends JsonMap {
  const MpLead(super.json);

  String get id => asStringOr('id', '');
  LeadStatus get status => LeadStatus.parse(asString('status'));

  /// 服务端下发的是 `contact_phone_masked`，明文手机号不进 App。
  String get contactMasked =>
      asStringOr('contact_phone_masked', asStringOr('contact_masked', '—'));
  String? get contactName => asString('contact_name');

  /// 买家的需求原文 + 数量/整箱快照，都是留资时填的。
  String? get demandNote => asString('demand_note');
  int get quantity => asIntOr('quantity', 0);
  double get quotedAmount => asDoubleOr('quoted_amount', 0);

  /// `currency` 这一格服务端回的是符号（不是三字码），直接当符号用。
  String get currencySymbol => asStringOr('currency', '');
  String? get orderId => asString('order_id');

  /// 关联的申请单行叫 `mp_listings`，历史形状才叫 `listing`。
  JsonMap get listing => asMap('mp_listings').json.isEmpty ? asMap('listing') : asMap('mp_listings');
  String get listingTitle {
    final JsonMap value = listing;
    if (value.asStringOr('title_uk', '').isNotEmpty) return value.asStringOr('title_uk', '');
    if (value.asStringOr('title_en', '').isNotEmpty) return value.asStringOr('title_en', '');
    return value.asStringOr('title', '—');
  }

  String? get listingSlug => asMap('mp_listing_public').asString('slug');
  DateTime? get createdAt => asDate('created_at');
}

class MpConversation extends JsonMap {
  const MpConversation(super.json);

  String get id => asStringOr('id', '');

  /// 服务端只有三种：open / closed / blocked。
  String get status => asStringOr('status', 'open');
  BuyerIdentity get buyerIdentity => BuyerIdentity.parse(asString('buyer_identity'));
  String? get buyerName => asString('buyer_name');
  String get buyerPhoneMasked => asStringOr('buyer_phone_masked', '');

  /// 列表行把商品名拍平成 `listing_title` + `slug`，没有嵌套对象。
  String get listingTitle => asStringOr('listing_title', asMap('listing').asStringOr('title', '—'));
  String? get listingSlug => asString('slug');
  String get sellerName => asStringOr('seller_name', '');

  /// `last_message` 是一个对象（sender/body/created_at），不是字符串。
  JsonMap get lastMessageRow => asMap('last_message');
  String get lastMessage => lastMessageRow.asStringOr('body', '');
  String get lastSender => lastMessageRow.asStringOr('sender', '');
  DateTime? get lastMessageAt {
    final DateTime? fromRow = lastMessageRow.asDate('created_at');
    return fromRow ?? asDate('last_buyer_at') ?? asDate('last_seller_at');
  }

  DateTime? get lastBuyerAt => asDate('last_buyer_at');
  DateTime? get lastSellerAt => asDate('last_seller_at');
  int get sellerUnread => asIntOr('seller_unread', 0);
  String get lang => asStringOr('lang', 'en');

  /// 详情行才带 `messages`（列表行没有）：`{id, sender, body, created_at}`。
  List<MpMessage> get messages =>
      asEntities('messages', MpMessage.new);
  bool get hasThread => raw('messages') != null;

  /// 商品页当前在公域的状态（`tenant_state`），用来解释「会话还在，商品页已经下架」。
  String? get listingSlugStatus => asString('listing_slug_status');
}

class MpMessage extends JsonMap {
  const MpMessage(super.json);

  String get id => asStringOr('id', '');
  String get body => asStringOr('body', asStringOr('content', ''));
  String get sender => asStringOr('sender', asStringOr('from', 'buyer'));
  DateTime? get createdAt => asDate('created_at');
}

enum ListingStatus {
  draft,
  pendingReview,
  inReview,
  approved,
  published,
  rejected,
  paused,
  delisted,

  /// `withdraw` 才会落到这一态；分栏角标不数它，所以它不在 `LISTING_STATUSES` 里。
  archived;

  static ListingStatus parse(String? raw) => ListingStatus.values.firstWhere(
        (ListingStatus value) => value.wire == raw,
        orElse: () => ListingStatus.draft,
      );

  String get wire {
    switch (this) {
      case ListingStatus.pendingReview:
        return 'pending_review';
      case ListingStatus.inReview:
        return 'in_review';
      default:
        return name;
    }
  }

  /// 服务端在这三个状态下拒绝编辑（409 LISTING_LOCKED）。
  bool get locked => this == ListingStatus.pendingReview || this == ListingStatus.inReview;

  /// 只有这几个状态允许存草稿（EDITABLE_STATUSES）。
  bool get editable =>
      !locked &&
      const <ListingStatus>{
        ListingStatus.draft,
        ListingStatus.rejected,
        ListingStatus.paused,
        ListingStatus.approved,
        ListingStatus.published,
        ListingStatus.delisted,
      }.contains(this);

  /// 服务端 STATE_ACTIONS 只认这几组转移，按钮必须严格按它来，
  /// 否则点了就是 409 —— 界面给出一个必然失败的按钮比少给一个按钮更糟。
  bool get canPause =>
      this == ListingStatus.published || this == ListingStatus.approved;

  /// resume 只从 paused 回到 pending_review（重新排队审核），delisted 不在其列。
  bool get canResume => this == ListingStatus.paused;

  bool get canWithdraw => const <ListingStatus>{
        ListingStatus.draft,
        ListingStatus.pendingReview,
        ListingStatus.inReview,
        ListingStatus.rejected,
        ListingStatus.approved,
        ListingStatus.paused,
      }.contains(this);
}

class MpListing extends JsonMap {
  const MpListing(super.json);

  String get id => asStringOr('id', '');

  /// 集市是乌克兰市场：标题分 `title_uk`/`title_en` 两列，展示优先乌克兰语。
  String get titleUk => asStringOr('title_uk', '');
  String get titleEn => asStringOr('title_en', '');
  String get title {
    if (titleUk.isNotEmpty) return titleUk;
    if (titleEn.isNotEmpty) return titleEn;
    return asStringOr('title', '未命名');
  }

  String get descUk => asStringOr('desc_uk', '');
  String get descEn => asStringOr('desc_en', '');

  ListingStatus get status => ListingStatus.parse(asString('status'));

  /// 公域地址来自 `public_slug`（shapeListing 已拍平）。
  String? get publicSlug => asString('public_slug') ?? asString('slug');
  String get currency => asStringOr('currency', 'UAH');

  /// 定价列叫 `price_ukr`（格里夫纳），不是 `price`。
  double get price => asDoubleOr('price_ukr', asDoubleOr('price', 0));
  int get minOrderQty => asIntOr('min_order_qty', 1);
  int? get leadTimeDays => asInt('lead_time_days');
  bool get supportsOnlinePay => asBool('supports_online_pay');
  bool get supportUk => asBool('support_uk');
  String? get termsVersion => asString('terms_version');
  int get reviewRound => asIntOr('review_round', 0);

  JsonMap get product => asMap('product');
  String? get productId => asString('product_id') ?? product.asString('id');
  String? get productName => product.asString('name');
  String? get productSku => product.asString('sku');
  int get inventoryQty => product.asIntOr('inventory_qty', 0);
  String get unit => product.asStringOr('unit', '件');

  String? get mpCategoryId => asString('mp_category_id');

  /// 平台类目行：详情行键名是复数的 `mp_categories`，候选行里的单数 `mp_category`。
  JsonMap get mpCategory {
    final JsonMap plural = asMap('mp_categories');
    return plural.json.isEmpty ? asMap('mp_category') : plural;
  }

  String get mpCategoryName {
    final JsonMap value = mpCategory;
    if (value.asStringOr('name_zh', '').isNotEmpty) return value.asStringOr('name_zh', '');
    return value.asStringOr('name_en', value.asStringOr('slug', ''));
  }

  bool get categoryRequiresDocument => mpCategory.asBool('requires_document');

  /// 准入分是服务端读时算的纯函数结果：`{score, max, reasons[]}`，客户端不再复算。
  JsonMap get qualityRow => asMap('quality');
  int get quality => qualityRow.asIntOr('score', 0);
  int get qualityMax => qualityRow.asIntOr('max', 100);
  List<JsonMap> get qualityReasons => qualityRow.asList('reasons');

  DateTime? get createdAt => asDate('created_at');
  DateTime? get updatedAt => asDate('updated_at');
  DateTime? get submittedAt => asDate('submitted_at');
  DateTime? get publishedAt => asDate('published_at');
  DateTime? get delistedAt => asDate('delisted_at');
  String? get rejectReason => asString('reject_note');
  List<String> get rejectGates => asStringList('reject_gates');

  /// 出参里没有 `was_published`，「曾经上过公域」只能由 `published_at` 推。
  bool get wasPublished => publishedAt != null || status == ListingStatus.published;

  /// 图集提交的是私有桶对象引用（`image_asset_ids`），展示仍用商品库的 URL。
  List<String> get imageAssetIds => asStringList('image_asset_ids');

  /// 图片优先取 listing 自己的，回落到关联商品的画廊首图。
  String? get imageUrl {
    final List<String> own = asStringList('image_urls');
    if (own.isNotEmpty) return own.first;
    final String? direct = asString('image_url');
    if (direct != null && direct.isNotEmpty) return direct;
    final List<String> fromProduct = product.asStringList('image_urls');
    if (fromProduct.isNotEmpty) return fromProduct.first;
    return product.asString('image_url');
  }
}

/// `GET /marketplace/listings` 回的是「商品 + 它的申请单」，不是申请单列表：
/// 未申请的商品也在里面（`listing == null`），卖家从这一面直接发起第一份申请。
class MpCandidate extends JsonMap {
  const MpCandidate(super.json);

  JsonMap get productRow => asMap('product');

  /// 候选行把库存拍平成 `inventory_qty`，`Product` 读的是 `quantity`，这里补一次映射。
  Product? get product {
    if (productRow.json.isEmpty) return null;
    return Product(<String, Object?>{
      ...productRow.json,
      'quantity': productRow.asIntOr('inventory_qty', 0),
    });
  }

  MpListing? get listing =>
      raw('listing') == null ? null : MpListing(asMap('listing').json);

  bool get hasListing => listing != null;

  /// 未申请的商品没有申请单，也就没有状态；分栏角标用 `'none'` 这一栏计数。
  ListingStatus? get listingStatus => listing?.status;
  String? get listingId => listing?.id;
  int get qualityScore => asMap('quality').asIntOr('score', 0);
  int get qualityMax => asMap('quality').asIntOr('max', 100);
  List<JsonMap> get qualityReasons => asMap('quality').asList('reasons');
  String? get suggestedMpCategoryId => asString('suggested_mp_category_id');

  /// 候选行的标题优先商品名（申请单那几列在选品视图里是精简过的）。
  String get displayTitle {
    final String? name = productRow.asString('name');
    if (name != null && name.isNotEmpty) return name;
    return listing?.title ?? '—';
  }
}

/// 选品视图的整页出参：`{items, counts, total, page, page_size, total_pages, scan_truncated, out_of_stock_count}`。
class MpCandidatePage extends JsonMap {
  const MpCandidatePage(super.json);

  List<MpCandidate> get items =>
      asEntities('items', MpCandidate.new);

  JsonMap get counts => asMap('counts');

  /// 键是 ListingStatus 的 wire 值，外加 `'none'`（未申请）。
  int countFor(String key) => counts.asIntOr(key, 0);
  int get noneCount => counts.asIntOr('none', 0);

  int get total => asIntOr('total', items.length);
  int get page => asIntOr('page', 1);
  int get pageSize => asIntOr('page_size', 24);
  int get totalPages => asIntOr('total_pages', 1);

  /// 「未申请」栏可能没扫完，这时 total 是角标数而不是真实条数，界面要如实说。
  bool get scanTruncated => asBool('scan_truncated');
  int get outOfStockCount => asIntOr('out_of_stock_count', 0);

  bool get hasMore => page < totalPages;
}

/// `GET /marketplace/campaigns` 的单行：计划本体 + 花费 + 公域/付费位实时结论。
///
/// 出参里没有 `name`，也没有 `leads_count` —— 卖家认档只靠商品标题和 slug。
/// 预算与花费都是最小货币单位（COPECK）整数，展示前除以 100；带 null 的三枚
/// 是服务端「这一轮没读到」的降级，不能塌成 0 或 false。
class MpCampaign extends JsonMap {
  const MpCampaign(super.json);

  String get id => asStringOr('id', '');
  String get listingId => asStringOr('listing_id', '');
  String? get slug => asString('slug');

  /// 计划跟着商品走，标题取乌克兰语那一列（公域展示用的就是它）。
  String get listingTitle => asStringOr('title_uk', '—');

  /// 目前服务端只支持 `cpl`，其它值直接 400 KIND_NOT_SUPPORTED。
  String get kind => asStringOr('kind', 'cpl');
  String get status => asStringOr('status', 'draft');

  bool get isActive => status == 'active';
  bool get isExhausted => status == 'exhausted';

  double get dailyCap => asIntOr('daily_cap_minor', 0) / 100.0;

  /// null = 不设总预算上限。
  double? get budget =>
      asInt('total_budget_minor') == null ? null : asInt('total_budget_minor')! / 100.0;

  double? get spent => asInt('spent') == null ? null : asInt('spent')! / 100.0;
  double? get spentToday =>
      asInt('spent_today') == null ? null : asInt('spent_today')! / 100.0;

  /// 花费读的降级：读挂了或部分窗口被截断，界面要分别说「没查到」而不是报个数。
  bool get spendReadFailed => asBool('spend_read_failed');
  bool get spendTruncated => asBool('spend_truncated');

  /// 下一轮真会扣的那条留资单价估算。
  double? get estCpl => asInt('est_cpl_minor') == null ? null : asInt('est_cpl_minor')! / 100.0;

  int get qualityScore => asIntOr('quality_score', 0);
  bool get qualityPass => asBool('quality_pass');

  /// 在公域 ≠ 占到首屏那一格付费位。
  bool get publicNow => asBool('public_now');

  /// null = 这一轮巡检没给出结论（未知），不能当「位没了」渲染。
  bool? get slotGrantedNow => json['slot_granted_now'] == null ? null : asBool('slot_granted_now');

  /// 仅当已触顶时服务端才判定；null 同样是「未知，不是不行」。
  bool? get restartAvailable =>
      json['restart_available'] == null ? null : asBool('restart_available');

  DateTime? get startedAt => asDate('started_at');
  DateTime? get endedAt => asDate('ended_at');
  DateTime? get settledThroughAt => asDate('settled_through_at');
  DateTime? get createdAt => asDate('created_at');

  /// 预算进度条：没有总预算时返回 null，界面改成显示「不限总额」。
  double? get spentRatio {
    final double? total = budget;
    final double? used = spent;
    if (total == null || used == null || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  /// 日限额今天是否已经贴到顶。花费读不到时不下结论。
  bool get dailyCapReached {
    final double? today = spentToday;
    if (today == null || dailyCap <= 0) return false;
    return today >= dailyCap;
  }
}

/// `GET /marketplace/campaigns` 的整页出参。
///
/// `ad.enabled` 决定「投放」这一签能不能用；`readAdSurface` 读失败时服务端会带
/// `enabled_read_failed`，此时既不能说「未开放」也不能说「已开放」，只能如实报「确认不了」。
class MpCampaignPage extends JsonMap {
  const MpCampaignPage(super.json);

  List<MpCampaign> get items =>
      asEntities('items', MpCampaign.new);

  int get total => asIntOr('total', items.length);
  bool get scanTruncated => asBool('scan_truncated');

  JsonMap get ad => asMap('ad');
  bool get adEnabled => ad.asBool('enabled');
  bool get adEnabledReadFailed => ad.asBool('enabled_read_failed');
  int get adSlotCap => ad.asIntOr('slot_cap', 0);
  bool get adSlotCapFellBack => ad.asBool('slot_cap_fell_back');

  /// `priced: false` 时平台还没定 CPL 单价，这一档只能看不能开。
  bool get priced => asBool('priced');
  int? get baseLeadMinor => asInt('base_lead_minor');
  String get currency => asStringOr('currency', 'UAH');

  List<JsonMap> get warnings => asList('warnings');
  String? get warningText => warnings.isEmpty ? null : warnings.first.asString('message');

  int get activeCount => items.where((MpCampaign c) => c.isActive).length;
}

/// 创建/修改的回执：`{item, changed, ad_slot_cap?, warnings}`。
/// `item` 是裸库表行，没有花费与坑位那些派生列 —— 所以写完必须重读列表。
class MpCampaignWrite extends JsonMap {
  const MpCampaignWrite(super.json);

  MpCampaign get campaign => MpCampaign(asMap('item').json);
  String get id => campaign.id;
  List<String> get changed => asStringList('changed');
  bool get unchanged => asBool('unchanged');
  List<JsonMap> get warnings => asList('warnings');
  String? get warningText => warnings.isEmpty ? null : warnings.first.asString('message');
}

/// `GET /marketplace/seller`：店招是「买家页那一句 由 X 直供」的唯一可写位。
/// 没有任何投影行时三枚身份字段都是 null（服务端不兜底成空串）。
class MpSeller extends JsonMap {
  const MpSeller(super.json);

  String get tenantName => asStringOr('tenant_name', '');
  String? get rawSellerName => asString('seller_name');
  String get sellerName => rawSellerName ?? '平台卖家';
  String? get sellerSlug => asString('seller_slug');

  /// 公域店招相对路径，形如 `/market/s/<seller_slug>`；还没上架时是 null。
  String? get storePath => asString('store_path');
  int get publicListings => asIntOr('public_listings', 0);
  int get projectedListings => asIntOr('projected_listings', 0);

  bool get hasStore => (sellerSlug?.isNotEmpty ?? false) && storePath != null;

  /// 只有「已生成地址但当前不展示」这一档值得对卖家单独说一句。
  bool get isHiddenStore => !hasStore && projectedListings > 0;

  /// PATCH 的回执：投影同步失败是可重试缺口，服务端如实带回错误文本。
  bool get projectionSyncFailed => asBool('projection_sync_failed');
  String? get projectionSyncError => asString('projection_sync_error');
  int get projectedUpdated => asIntOr('projected_updated', 0);
  bool get changed => asBool('changed');
}

/// `GET /marketplace/analytics`：顶层不是计数器，而是 `{days, totals, rows, warnings}`。
/// 所有比值分母为 0 时服务端回 null（「没曝光」≠「有曝光没点击」），客户端保持 null。
class MpAnalytics extends JsonMap {
  const MpAnalytics(super.json);

  int get days => asIntOr('days', 7);
  int get rankingWindowDays => asIntOr('ranking_window_days', 7);
  int get rankingStaleHours => asIntOr('ranking_stale_hours', 6);

  /// 三块补充维度各自可降级：读不到就少一列并报警，整面仍然可用。
  bool get engagementAvailable => asBool('engagement_available', fallback: true);
  bool get leadsAvailable => asBool('leads_available', fallback: true);
  bool get chatsAvailable => asBool('chats_available', fallback: true);

  JsonMap get scanTruncated => asMap('scan_truncated');
  bool get truncated =>
      scanTruncated.asBool('projection') ||
      scanTruncated.asBool('leads') ||
      scanTruncated.asBool('chats');

  JsonMap get totals => asMap('totals');
  List<MpAnalyticsRow> get rows =>
      asEntities('rows', MpAnalyticsRow.new);

  List<JsonMap> get warnings => asList('warnings');
  String? get warningText {
    final List<JsonMap> list = warnings;
    if (list.isEmpty) return null;
    return list.first.asString('message');
  }

  int get listingCount => totals.asIntOr('listings', rows.length);
  int get publicNowCount => totals.asIntOr('public_now', 0);
  int get mutedCount => totals.asIntOr('muted', 0);
  int get trialBoostCount => totals.asIntOr('trial_boost', 0);
  int get scoreStaleCount => totals.asIntOr('score_stale', 0);
  int get impressions => totals.asIntOr('impressions', 0);
  int get clicks => totals.asIntOr('clicks', 0);
  int get productViews => totals.asIntOr('product_views', 0);
  int get leads => totals.asIntOr('leads', 0);
  int get leadsResponded => totals.asIntOr('leads_responded', 0);
  int get leadsPending => totals.asIntOr('leads_pending', 0);
  int get leadsOrdered => totals.asIntOr('leads_ordered', 0);
  int get chats => totals.asIntOr('chats', 0);
  double? get ctr => totals.asDouble('ctr');
  double? get leadRate => totals.asDouble('lead_rate');
}

/// 一行 = 一条已投影到公域的申请单。排序键（pool / 原因）由服务端按当前窗口现算。
class MpAnalyticsRow extends JsonMap {
  const MpAnalyticsRow(super.json);

  String get listingId => asStringOr('listing_id', '');
  String? get slug => asString('slug');
  String get title => asStringOr('title_uk', '—');

  /// `status` 可能为 null（投影行有了但申请单读不到）。
  String? get rawStatus => asString('status');
  ListingStatus get status => ListingStatus.parse(rawStatus);
  bool get publicNow => asBool('public_now');
  double get price => asDoubleOr('price_ukr', 0);
  int get stockQty => asIntOr('stock_qty', 0);

  JsonMap get metrics => asMap('metrics');
  int get impressions => metrics.asIntOr('impressions', 0);
  int get clicks => metrics.asIntOr('clicks', 0);
  int get leads => metrics.asIntOr('leads', 0);
  int get leadsPending => metrics.asIntOr('leads_pending', 0);
  int get leadsOrdered => metrics.asIntOr('leads_ordered', 0);
  int get chats => metrics.asIntOr('chats', 0);
  double? get ctr => metrics.asDouble('ctr');
  double? get leadRate => metrics.asDouble('lead_rate');

  /// 首响中位小时数：null = 窗口内没有已回复的留资。
  double? get ttfrHours => metrics.asDouble('ttfr_hours');

  JsonMap get ranking => asMap('ranking');
  String get pool => ranking.asStringOr('pool', 'default');
  bool get isMuted => pool == 'muted';
  bool get scoreStale => ranking.asBool('score_stale');
  List<JsonMap> get rankReasons => ranking.asList('reasons');

  JsonMap get boostRow => asMap('boost');
  bool get boostCounting => boostRow.asBool('counting');
  DateTime? get boostAvailableAt => boostRow.asDate('available_at');

  /// 「刷新曝光」按钮的可用性服务端已经算好：兑现中或倒计时未到就禁用。
  bool get boostCoolingDown =>
      boostCounting ||
      (boostAvailableAt != null && boostAvailableAt!.isAfter(DateTime.now()));

  JsonMap get quality => asMap('quality');
  int get qualityScore => quality.asIntOr('score', 0);
  int get qualityMax => quality.asIntOr('max', 100);
}

class MpDocument extends JsonMap {
  const MpDocument(super.json);

  String get id => asStringOr('id', '');

  /// 服务端存的是 `original_name`，不是 `file_name`。
  String get fileName => asStringOr('original_name', asStringOr('file_name', ''));
  String get kind => asStringOr('doc_type', asStringOr('kind', ''));
  DateTime? get createdAt => asDate('created_at');

  /// 资质文件只有「验没验过」两态，没有中间状态列。
  bool get verified => asBool('verified');
  String? get note => asString('note');
  String? get listingId => asString('listing_id');
}

/// `GET /marketplace/telegram` → `maskChannel()` + `chat_enabled`：
/// `{bound, bot_username, chat_masked, notify_enabled, verified_at, chat_enabled}`。
/// 掩码形状（`123****45`）是服务端拼的，客户端不再重新截一遍。
class TelegramBinding extends JsonMap {
  const TelegramBinding(super.json);

  bool get bound => asBool('bound');
  String? get botUsername => asString('bot_username');
  String get chatMasked => asStringOr('chat_masked', '');
  bool get notifyEnabled => asBool('notify_enabled', fallback: true);

  /// 双向消息开关（买家在公域发起会话时才会用到），与「新留资推送」是两件事。
  bool get chatEnabled => asBool('chat_enabled');
  DateTime? get verifiedAt => asDate('verified_at');

  /// 绑定回执多带一枚 `test_delivered`：机器人没能把确认消息发出去时不能报「已绑定」。
  bool? get testDelivered =>
      json['test_delivered'] == null ? null : asBool('test_delivered');

  /// `POST /marketplace/telegram/test` 的回执：`{delivered, error}`。
  bool get delivered => asBool('delivered');
  String? get deliveryError => asString('error');
}

enum MatchKind {
  skuExact,
  skuFolded,
  skuPartial,
  skuContains,
  nameExact,
  namePartial,
  nameInHint,
  none;

  static MatchKind parse(String? raw) => MatchKind.values.firstWhere(
        (MatchKind value) => value.wire == raw,
        orElse: () => MatchKind.none,
      );

  String get wire {
    switch (this) {
      case MatchKind.skuExact:
        return 'sku_exact';
      case MatchKind.skuFolded:
        return 'sku_folded';
      case MatchKind.skuPartial:
        return 'sku_partial';
      case MatchKind.skuContains:
        return 'sku_contains';
      case MatchKind.nameExact:
        return 'name_exact';
      case MatchKind.namePartial:
        return 'name_partial';
      case MatchKind.nameInHint:
        return 'name_in_hint';
      case MatchKind.none:
        return 'none';
    }
  }

  bool get isSkuBased => index <= MatchKind.skuContains.index;
}

/// 识别回执里的库位行（`product` 与 `candidates[]` 同一个形状）：价格写作 `unit_price`、
/// 库存写作 `stock`。归一是必须的，不是美化 —— 直接读 `price` 永远是 0，
/// 拍照识别出来的行会以 ¥0 进单（旧实现正是这样）。
Product _visionProduct(JsonMap row) => Product(<String, Object?>{
      ...row.json,
      'price': row.asDoubleOr('unit_price', row.asDoubleOr('price', 0)),
      'quantity': row.asIntOr('stock', row.asIntOr('quantity', 0)),
    });

class VisionCandidate extends JsonMap {
  const VisionCandidate(super.json);

  String get id => asStringOr('id', '');
  String get sku => asStringOr('sku', '');
  String get name => asStringOr('name', '');

  Product get product => _visionProduct(this);

  double get score => asDoubleOr('score', 0);
  MatchKind get matchKind => MatchKind.parse(asString('match_kind'));
  List<String> get reasons => asStringList('reasons');
}

class VisionLine extends JsonMap {
  const VisionLine(super.json);

  bool get matched => asBool('matched');

  /// 同码写法变体或在不同柜位：服务端刻意不猜 top-1，`product` 留空，必须由卖家点选。
  bool get ambiguous => asBool('ambiguous');

  /// 模型对这一行读数自己的把握，服务端夹在 0–1、非数时兜 0.5。只用来排序和显示，
  /// 没有任何"低于多少就丢弃"的阈值——网页端也没有，丢弃识别结果比标个低置信更糟。
  double get confidence => (asDoubleOr('confidence', 0.5)).clamp(0.0, 1.0);

  Product? get product =>
      raw('product') == null ? null : _visionProduct(asMap('product'));
  List<VisionCandidate> get candidates =>
      asRawList('candidates').map(VisionCandidate.new).toList(growable: false);
  int get groupSize => asIntOr('group_size', candidates.length);

  /// 候选被服务端截断（同码 55 行只列 8 行），界面要另给一句提示，别让人以为这就是全部。
  bool get truncated => asBool('truncated');

  JsonMap get hint => asMap('hint');

  /// 数量在 `hint.qty` 里：服务端没有顶层 `qty`，读错就等于每行都按 1 加进单。
  int get qty => hint.asIntOr('qty', 0);
  String get skuHint => hint.asStringOr('sku_hint', '');
  String get nameHint => hint.asStringOr('name_hint', '');
  String get categoryHint => hint.asStringOr('category_hint', '');
  String get note => hint.asStringOr('note', '');

  /// 「模型看到」那一行：码优先，没有码才退到名，都没有就一个破折号。
  String get hintWas =>
      skuHint.isNotEmpty ? skuHint : (nameHint.isNotEmpty ? nameHint : '—');

  Product? get resolvedProduct => matched ? product : null;
}

/// `POST /orders/vision-draft` 的整包回执。
class VisionDraft extends JsonMap {
  const VisionDraft(super.json);

  List<VisionLine> get items =>
      asRawList('items').map(VisionLine.new).toList(growable: false);

  /// 模型猜的客户名。只显示、不自动落到单上：认错了客户比认错了 SKU 更难发现。
  String get customerHint => asStringOr('customer_hint', '');

  /// `type_hint`（进/出库方向）界面刻意不读：方向在开单页就定死了，网页端同样把这支当死载荷。
}

/// 列表分页响应：行在 `data`，`page` 必须采用服务端回显值（越界会回落第 1 页）。
class Paged<T> {
  const Paged({
    required this.rows,
    required this.count,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    this.summary = JsonMap.empty,
  });

  final List<T> rows;
  final int count;
  final int page;
  final int pageSize;
  final int totalPages;
  final JsonMap summary;

  bool get hasMore => page < totalPages;

  static Paged<R> of<R>(Object? envelopeData, R Function(Map<String, Object?> row) convert) {
    final JsonMap map = JsonMap.from(envelopeData);
    // 分页出参有两套命名：业务侧用 `data/count/pageSize/totalPages`，集市用 `items/total/page_size`，
    // 分析类还有裸数组。键名在这里一次性收口，不让每个仓库各猜一遍。
    final List<Map<String, Object?>> rows =
        JsonMap.rawListOf(map.json, <String>['data', 'items', 'rows']);
    final int count = map.asInt('count') ?? map.asIntOr('total', rows.length);
    final int pageSize = map.asInt('pageSize') ?? map.asIntOr('page_size', rows.length);
    final int totalPages =
        map.asInt('totalPages') ?? map.asIntOr('total_pages', pageSize <= 0 ? 1 : (count / pageSize).ceil());
    return Paged<R>(
      rows: rows.map(convert).toList(growable: false),
      count: count,
      page: map.asIntOr('page', 1),
      pageSize: pageSize,
      totalPages: totalPages < 1 ? 1 : totalPages,
      summary: map.asMap('summary'),
    );
  }

  static const Paged<JsonMap> empty = Paged<JsonMap>(
    rows: <JsonMap>[],
    count: 0,
    page: 1,
    pageSize: 24,
    totalPages: 1,
  );
}

/// 打印模板设置：三枚开关 + 四段文案，`show_image` 的默认值是 false。
class PrintSettings extends JsonMap {
  const PrintSettings(super.json);

  static const PrintSettings defaults = PrintSettings(<String, Object?>{
    'template_id': 'standard',
    'show_price': true,
    'show_sku': true,
    'show_image': false,
  });

  String get templateId => asStringOr('template_id', 'standard');
  String get companyName => asStringOr('company_name', '');
  String get logoUrl => asStringOr('logo_url', '');
  String get contactInfo => asStringOr('contact_info', '');
  String get footerText => asStringOr('footer_text', '');
  bool get showPrice => asBool('show_price', fallback: true);
  bool get showSku => asBool('show_sku', fallback: true);
  bool get showImage => asBool('show_image');

  /// 服务端只认这八列，整行原样贴回去会多带 tenant_id / updated_at 等无关键。
  Map<String, Object?> toPayload() => <String, Object?>{
        'template_id': templateId,
        'company_name': companyName,
        'logo_url': logoUrl,
        'contact_info': contactInfo,
        'footer_text': footerText,
        'show_price': showPrice,
        'show_sku': showSku,
        'show_image': showImage,
      };

  PrintSettings copyWith({
    String? templateId,
    String? companyName,
    String? logoUrl,
    String? contactInfo,
    String? footerText,
    bool? showPrice,
    bool? showSku,
    bool? showImage,
  }) =>
      PrintSettings(<String, Object?>{
        ...json,
        'template_id': templateId ?? this.templateId,
        'company_name': companyName ?? this.companyName,
        'logo_url': logoUrl ?? this.logoUrl,
        'contact_info': contactInfo ?? this.contactInfo,
        'footer_text': footerText ?? this.footerText,
        'show_price': showPrice ?? this.showPrice,
        'show_sku': showSku ?? this.showSku,
        'show_image': showImage ?? this.showImage,
      });
}
