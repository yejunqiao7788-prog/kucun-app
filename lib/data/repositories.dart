import 'dart:convert' show base64Encode;

import '../core/api_client.dart';
import '../data/entities.dart';

/// 仓储层：一个端点一个方法，只做路径拼装与出参定型，不含业务判断。
/// 租户 id 用闭包取，换账号后不需要重建仓储对象。
typedef TenantProvider = String Function();

class Repos {
  Repos(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  late final DashboardRepo dashboard = DashboardRepo(api, tenant);
  late final ProductRepo products = ProductRepo(api, tenant);
  late final OrderRepo orders = OrderRepo(api, tenant);
  late final ShowroomRepo showrooms = ShowroomRepo(api, tenant);
  late final MarketRepo market = MarketRepo(api, tenant);
  late final FinanceRepo finance = FinanceRepo(api, tenant);
  late final AiRepo ai = AiRepo(api, tenant);
  late final SettingsRepo settings = SettingsRepo(api, tenant);
}

Future<Object?> _get(
  ApiClient api,
  String path, {
  Map<String, Object?>? query,
  required TenantProvider tenant,
  bool heavy = false,
  bool cache = false,
}) =>
    api
        .get(
          path,
          query: query,
          tenantId: tenant(),
          heavy: heavy,
          cache: cache,
        )
        .then((ApiResponse<Object?> r) => r.data);

class DashboardRepo {
  const DashboardRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<ApiResponse<DashboardStats>> stats() async {
    final ApiResponse<Object?> res =
        await api.get('/dashboard/stats', tenantId: tenant(), cache: true);
    final JsonMap map = JsonMap.from(res.data);
    return ApiResponse<DashboardStats>(
      // RPC 出参既可能直接摊平，也可能包在 `stats` 里。
      data: DashboardStats(map.raw('stats') == null ? map.json : map.asMap('stats').json),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<ApiResponse<DashboardOrders>> orders() async {
    final ApiResponse<Object?> res =
        await api.get('/dashboard/orders', tenantId: tenant(), cache: true);
    return ApiResponse<DashboardOrders>(
      data: DashboardOrders(JsonMap.from(res.data)),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<Paged<OperationLog>> logs({int page = 1, int pageSize = 20}) async {
    final Object? data = await _get(
      api,
      '/dashboard/logs',
      query: <String, Object?>{'page': page, 'pageSize': pageSize},
      tenant: tenant,
    );
    return Paged.of<OperationLog>(data, OperationLog.new);
  }
}

/// `dashboard/orders` 的 `{ recent, picking }`。
class DashboardOrders {
  const DashboardOrders(this.json);

  final JsonMap json;

  List<Order> get picking =>
      JsonMap.rawListOf(json.raw('picking'), <String>[]).map(Order.new).toList();

  /// 契约要求客户端复现这条收窄规则：非管理员的今日订单只保留备货中的单。
  List<Order> recent({required bool privileged}) {
    final List<Order> rows =
        JsonMap.rawListOf(json.raw('recent'), <String>[]).map(Order.new).toList();
    return privileged ? rows : rows.where((Order o) => o.isPreparing).toList();
  }
}

class ProductRepo {
  const ProductRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<ApiResponse<Paged<Product>>> list({
    int page = 1,
    int pageSize = 24,
    String? search,
    String? categoryId,
    bool lowStockOnly = false,
    bool hideZeroStock = false,
    String orderBy = 'updated_at',
    bool ascending = false,
  }) async {
    final ApiResponse<Object?> res = await api.get(
      '/products',
      query: <String, Object?>{
        'page': page,
        'pageSize': pageSize,
        'search': search,
        'categoryId': categoryId,
        'lowStockOnly': lowStockOnly ? true : null,
        'hideZeroStock': hideZeroStock ? true : null,
        'orderBy': orderBy,
        'ascending': ascending,
      },
      tenantId: tenant(),
      cache: true,
    );
    return ApiResponse<Paged<Product>>(
      data: Paged.of<Product>(res.data, Product.new),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<List<Product>> search(String keyword, {int limit = 12}) async {
    final Object? data = await _get(
      api,
      '/products/search',
      query: <String, Object?>{'search': keyword, 'q': keyword, 'limit': limit},
      tenant: tenant,
    );
    return _products(data);
  }

  /// 订单创建用的全量索引（60 s 超时）。
  Future<List<Product>> searchIndex() async {
    final Object? data = await _get(
      api,
      '/products/search-index',
      tenant: tenant,
      heavy: true,
    );
    return _products(data);
  }

  /// 全量库存（60 s 超时）。
  Future<ApiResponse<List<InventoryRow>>> inventory() async {
    final ApiResponse<Object?> res = await api.get(
      '/products/inventory',
      tenantId: tenant(),
      heavy: true,
      cache: true,
    );
    final List<Map<String, Object?>> rows = JsonMap.rawListOf(res.data, <String>['products', 'data']);
    return ApiResponse<List<InventoryRow>>(
      data: rows.map(InventoryRow.new).toList(),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<Object?> create(Map<String, Object?> payload) =>
      api.post('/products', body: payload, tenantId: tenant());

  /// 库存快调要写回整行（PATCH 是整体替换），但 `/products/inventory` 的投影里没有
  /// `description` 与图片，直接拿它回写会抹掉这两项，所以先按 SKU 取回完整行。
  Future<Product?> fullRow({required String id, required String sku}) async {
    final ApiResponse<Paged<Product>> res = await list(pageSize: 50, search: sku);
    for (final Product row in res.data.rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// 库存调整也走这里：`sku` 与 `name` 必须一并提交，否则被判缺必填字段。
  Future<Object?> update(String id, Map<String, Object?> payload) => api.patch(
        '/products/$id',
        body: <String, Object?>{...payload, 'id': id},
        tenantId: tenant(),
      );

  Future<Object?> remove(String id) => api.delete('/products/$id', tenantId: tenant());

  Future<Object?> batchDelete(List<String> ids) => api.post(
        '/products/batch-delete',
        body: <String, Object?>{'product_ids': ids},
        tenantId: tenant(),
      );

  /// 模式只有四种：`set`（定价）、`markup_cost`（按成本加成）、`percent`（按比例）、
  /// `amount`（按绝对额）。单次上限 500 件，键名是 `product_ids`。
  Future<Object?> batchPrice({
    required List<String> ids,
    required String mode,
    required double value,
  }) =>
      api.post(
        '/products/batch-price',
        body: <String, Object?>{'product_ids': ids, 'mode': mode, 'value': value},
        tenantId: tenant(),
      );

  /// 表格导入：解析在客户端做，服务端只认这一套字段名（`sku/name/category/price/cost/`
  /// `units_per_box/box_price/quantity/min_stock/max_stock/location` + `tenant_id`）。
  /// 一次 50 行是原项目的节流值，重复 SKU 与坏值都从 `failures` 里回，不是整批失败。
  Future<ImportOutcome> importRows(List<Map<String, Object?>> items) async => ImportOutcome(
        JsonMap.from(
          await api.post(
            '/products/import',
            body: <String, Object?>{'items': items},
            tenantId: tenant(),
            heavy: true,
          ),
        ).json,
      );

  /// 只修库存：形状同上，但走 `/import-corrections`，不碰价格与名称。
  Future<ImportOutcome> importCorrections(List<Map<String, Object?>> items) async => ImportOutcome(
        JsonMap.from(
          await api.post(
            '/products/import-corrections',
            body: <String, Object?>{'items': items},
            tenantId: tenant(),
            heavy: true,
          ),
        ).json,
      );

  /// 保留策略预览：服务端把 `dry_run` 钉死在 SQL 包装函数里，这一刀无论传什么都不可能写库。
  /// 窗口留空即用服务端默认值，出参会回显生效的 `zero_stock_days/soft_delete_days` 与两枚 cutoff。
  Future<RetentionReport> retentionPreview({int? zeroStockDays, int? softDeleteDays}) async =>
      RetentionReport(JsonMap.from(await api.post(
        '/products/retention-preview',
        body: <String, Object?>{
          if (zeroStockDays != null) 'zero_stock_days': zeroStockDays,
          if (softDeleteDays != null) 'soft_delete_days': softDeleteDays,
        },
        tenantId: tenant(),
      )).json);

  /// 执行没有任何确认口令 —— `retention-cleanup` 一调就真删。
  /// 所以界面上必须先拿到同参数的 `retentionPreview`，把条数摊给用户看再由他点确认。
  Future<RetentionReport> retentionCleanup({int? zeroStockDays, int? softDeleteDays}) async =>
      RetentionReport(JsonMap.from(await api.post(
        '/products/retention-cleanup',
        body: <String, Object?>{
          if (zeroStockDays != null) 'zero_stock_days': zeroStockDays,
          if (softDeleteDays != null) 'soft_delete_days': softDeleteDays,
        },
        tenantId: tenant(),
      )).json);

  Future<Object?> resetTenantData() => api.post(
        '/products/reset-tenant-data',
        body: <String, Object?>{'confirm': 'RESET_TENANT_DATA'},
        tenantId: tenant(),
      );

  Future<List<Category>> categories() async {
    final Object? data =
        await _get(api, '/categories', tenant: tenant, cache: true);
    return JsonMap.rawListOf(data, <String>['categories', 'data'])
        .map(Category.new)
        .toList();
  }

  Future<Object?> createCategory(String name) =>
      api.post('/categories', body: <String, Object?>{'name': name}, tenantId: tenant());

  Future<Object?> renameCategory(String id, String name) =>
      api.patch('/categories/$id', body: <String, Object?>{'name': name}, tenantId: tenant());

  Future<Object?> removeCategory(String id) => api.delete('/categories/$id', tenantId: tenant());

  static List<Product> _products(Object? data) =>
      JsonMap.rawListOf(data, <String>['products', 'data']).map(Product.new).toList();
}

class OrderRepo {
  const OrderRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<ApiResponse<Paged<Order>>> list({
    int page = 1,
    int pageSize = 20,
    String? type,
    String? status,
    String? search,
    String? customerId,
    String? paymentStatus,
    String? dateFrom,
    String? dateTo,
  }) async {
    final ApiResponse<Object?> res = await api.get(
      '/orders',
      query: <String, Object?>{
        'page': page,
        'pageSize': pageSize,
        'type': type,
        'status': status,
        'search': search,
        'customerId': customerId,
        'paymentStatus': paymentStatus,
        'dateFrom': dateFrom,
        'dateTo': dateTo,
      },
      tenantId: tenant(),
      cache: true,
    );
    return ApiResponse<Paged<Order>>(
      data: Paged.of<Order>(res.data, Order.new),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  /// 订单详情（60 s 超时）。
  Future<ApiResponse<Order>> detail(String id) async {
    final ApiResponse<Object?> res =
        await api.get('/orders/$id', tenantId: tenant(), heavy: true, cache: true);
    return ApiResponse<Order>(
      data: Order(JsonMap.mergeFrom(res.data, 'order', 'items').json),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  /// 建单必须一次带上 `order_data` + 非空 `items_data`，服务端没有「空草稿」接口。
  /// `is_preparing: true` 让 RPC 跳过扣库存（草稿）；`false` 则服务端当场改库存并把
  /// `status` 落成 `completed`，此时**不要**再调 [finalize]，那支只给备货单转正式用。
  Future<String> createDraft({
    required Map<String, Object?> orderData,
    required List<Map<String, Object?>> items,
    bool showInPickingList = false,
  }) async {
    final Object? data = await api.post(
      '/orders',
      body: <String, Object?>{'order_data': orderData, 'items_data': items},
      tenantId: tenant(),
    );
    final String id = JsonMap.from(data).asStringOr('order_id', '');
    if (id.isEmpty) return id;
    if (showInPickingList) {
      // RPC 不落这个开关，成功后单独补写一次；失败不影响已建成的单。
      try {
        await setPickingList(id, true);
      } on Object {
        // 单已经落成，开关没写上不能反过来报建单失败（否则用户会重复建单）。
      }
    }
    return id;
  }

  /// 定稿整单原子：任一商品不足即全单回滚，服务端把「名称 / SKU（需要 N，现有 M）」
  /// 直接写在 `error.message` 里，客户端原样展示，不自行拼装。
  Future<Object?> finalize(String id) =>
      api.post('/orders/$id/finalize', body: <String, Object?>{}, tenantId: tenant());

  Future<Object?> remove(String id) => api.delete('/orders/$id', tenantId: tenant());

  Future<Object?> setPickingList(String id, bool visible) => api.patch(
        '/orders/$id/picking-list',
        body: <String, Object?>{'show_in_picking_list': visible},
        tenantId: tenant(),
      );

  /// 加行：同商品已存在则服务端合并数量，不是整表替换。
  Future<Object?> addItem(String orderId, Map<String, Object?> payload) =>
      api.post('/orders/$orderId/items', body: payload, tenantId: tenant());

  Future<Object?> updateItem(String itemId, Map<String, Object?> payload) =>
      api.patch('/order-items/$itemId', body: payload, tenantId: tenant());

  Future<Object?> removeItem(String itemId) =>
      api.delete('/order-items/$itemId', tenantId: tenant());

  /// 收款：服务端只吃 `received_amount`(>0) + `method`(cash|transfer) + `paid_at`/`notes`；
  /// 实收找零与冲抵哪张单都由服务端算，客户端不传 `change_amount`/`applied_amount`。
  Future<Object?> recordPayment(String orderId, Map<String, Object?> payload) =>
      api.post('/orders/$orderId/payments', body: payload, tenantId: tenant());

  Future<List<PaymentRecord>> payments(String orderId) async {
    final Object? data = await _get(api, '/orders/$orderId/payments', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['payments', 'data', 'records'])
        .map(PaymentRecord.new)
        .toList();
  }

  Future<List<ProductHistoryEntry>> productHistory(String productId, {int limit = 20}) async {
    final Object? data = await _get(
      api,
      '/orders/product-history',
      query: <String, Object?>{'productId': productId, 'limit': limit},
      tenant: tenant,
    );
    return JsonMap.rawListOf(data, <String>['orders', 'data'])
        .map(ProductHistoryEntry.new)
        .toList();
  }

  Future<List<VisionLine>> visionDraft({
    required String dataUrl,
    String? hint,
  }) async {
    final Object? data = await api.post(
      '/orders/vision-draft',
      body: <String, Object?>{'image': dataUrl, 'hint': hint},
      tenantId: tenant(),
      heavy: true,
    );
    return JsonMap.rawListOf(data, <String>['items']).map(VisionLine.new).toList();
  }

  Future<List<PickingMark>> pickingMarks({String? orderId}) async {
    final Object? data = await _get(
      api,
      '/picking-marks',
      // 服务端只认 `order_id` / `order_ids` 两个查询键。
      query: <String, Object?>{'order_id': orderId},
      tenant: tenant,
    );
    return JsonMap.rawListOf(data, <String>['marks', 'data'])
        .map(PickingMark.new)
        .toList();
  }

  /// 一次写一行：`{order_id, item_index, picked_count, max_quantity}`。
  /// `picked_count` 是绝对值且被服务端夹到 `max_quantity`，传 0 即清除该行标记。
  Future<Object?> savePickingMark({
    required String orderId,
    required int itemIndex,
    required int pickedCount,
    required int maxQuantity,
  }) =>
      api.post(
        '/picking-marks',
        body: <String, Object?>{
          'order_id': orderId,
          'item_index': itemIndex,
          'picked_count': pickedCount,
          'max_quantity': maxQuantity,
        },
        tenantId: tenant(),
      );

  Future<Object?> clearPickingMark(String orderId, int itemIndex) =>
      api.delete('/picking-marks/$orderId/$itemIndex', tenantId: tenant());

  Future<Object?> clearPickingMarksForOrder(String orderId) =>
      api.delete('/picking-marks/order/$orderId', tenantId: tenant());
}

class ShowroomRepo {
  const ShowroomRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<ApiResponse<List<Showroom>>> list() async {
    final ApiResponse<Object?> res =
        await api.get('/showrooms', tenantId: tenant(), cache: true);
    return ApiResponse<List<Showroom>>(
      data: JsonMap.rawListOf(res.data, const <String>['showrooms', 'data'])
          .map(Showroom.new)
          .toList(),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<Showroom> detail(String id) async {
    final Object? data = await _get(api, '/showrooms/$id', tenant: tenant);
    return Showroom(JsonMap.mergeFrom(data, 'showroom', 'items').json);
  }

  Future<Object?> create(Map<String, Object?> payload) =>
      api.post('/showrooms', body: payload, tenantId: tenant());

  Future<Object?> update(String id, Map<String, Object?> payload) =>
      api.patch('/showrooms/$id', body: payload, tenantId: tenant());

  Future<Object?> remove(String id) => api.delete('/showrooms/$id', tenantId: tenant());

  /// 整表替换展厅商品：`{items:[{product_id, sort_order, custom_price, is_visible}]}`，
  /// 先读后写，最多 500 行。
  Future<Object?> replaceItems(String id, List<Map<String, Object?>> items) => api.post(
        '/showrooms/$id/items',
        body: <String, Object?>{'items': items},
        tenantId: tenant(),
      );
}

class MarketRepo {
  const MarketRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<JsonMap> config() async =>
      JsonMap.from(await _get(api, '/marketplace/config', tenant: tenant));

  Future<List<JsonMap>> categories() async {
    final Object? data = await _get(api, '/marketplace/categories', tenant: tenant);
    final JsonMap map = JsonMap.from(data);
    final List<JsonMap> flat = JsonMap.listOf(map.raw('flat'), <String>[]);
    return flat.isNotEmpty ? flat : JsonMap.listOf(map.raw('categories'), <String>[]);
  }

  Future<JsonMap> terms() async =>
      JsonMap.from(await _get(api, '/marketplace/terms', tenant: tenant));

  Future<MpSeller> seller() async =>
      MpSeller(JsonMap.from(await _get(api, '/marketplace/seller', tenant: tenant)).json);

  /// 改店招不动 slug（公开地址是冻结的）。服务端只认 `name` 这一枚键。
  Future<Object?> renameSeller(String displayName) => api.patch(
        '/marketplace/seller',
        body: <String, Object?>{'name': displayName},
        tenantId: tenant(),
      );

  Future<List<JsonMap>> mappings() async => JsonMap.listOf(
        await _get(api, '/marketplace/mappings', tenant: tenant),
        <String>['mappings', 'data'],
      );

  Future<Object?> saveMapping(String tenantCategoryId, String mpCategoryId) => api.post(
        '/marketplace/mappings',
        body: <String, Object?>{
          'tenant_category_id': tenantCategoryId,
          'mp_category_id': mpCategoryId,
        },
        tenantId: tenant(),
      );

  /// `GET /marketplace/listings` 回的是**选品视图**（商品 + 它当前的申请单），不是申请单列表。
  /// `status` 传 `'none'` 取「未申请」那一栏；角标读 `counts`，无货件数读 `out_of_stock_count`。
  Future<MpCandidatePage> candidates({
    String? status,
    String? keyword,
    String? categoryId,
    bool inStockOnly = false,
    int page = 1,
    int pageSize = 24,
  }) async {
    final Object? data = await _get(
      api,
      '/marketplace/listings',
      query: <String, Object?>{
        'status': status,
        'keyword': keyword,
        'category_id': categoryId,
        if (inStockOnly) 'in_stock': 'true',
        'page': page,
        'page_size': pageSize,
      },
      tenant: tenant,
    );
    return MpCandidatePage(JsonMap.from(data).json);
  }

  Future<MpListing> listing(String id) async {
    final Object? data = await _get(api, '/marketplace/listings/$id', tenant: tenant);
    // 详情行是 shapeListing 拍平后 + 一个 documents 数组，没有外层 `listing` 包装。
    return MpListing(JsonMap.from(data).json);
  }

  Future<List<MpDocument>> listingDocuments(String id) async {
    final Object? data = await _get(api, '/marketplace/listings/$id', tenant: tenant);
    return JsonMap.from(data).asEntities('documents', MpDocument.new);
  }

  Future<Object?> saveListing(Map<String, Object?> payload) =>
      api.post('/marketplace/listings', body: payload, tenantId: tenant());

  /// 提交要带条款版本号，服务端存过才允许省略。
  Future<Object?> submitListing(String id, {String? termsVersion}) => api.post(
        '/marketplace/listings/$id/submit',
        body: <String, Object?>{'terms_version': termsVersion},
        tenantId: tenant(),
      );

  Future<Object?> boostListing(String id) => api.post(
        '/marketplace/listings/$id/boost',
        body: <String, Object?>{},
        tenantId: tenant(),
      );

  /// 状态机动作而非目标状态：`pause` / `resume` / `withdraw`，源状态不对回 409。
  Future<Object?> listingAction(String id, String action) => api.patch(
        '/marketplace/listings/$id',
        body: <String, Object?>{'action': action},
        tenantId: tenant(),
      );

  /// 文件本体先上传到私有桶，这里只登记对象路径。
  /// 服务端校验路径必须以 `<tenant_id>/` 开头，且不收完整 URL。
  Future<Object?> registerDocument({
    required String listingId,
    required String docType,
    required String storagePath,
    String? originalName,
    String? expiresAt,
  }) =>
      api.post(
        '/marketplace/documents',
        body: <String, Object?>{
          'listing_id': listingId,
          'doc_type': docType,
          'storage_path': storagePath,
          'original_name': originalName,
          'expires_at': expiresAt,
        },
        tenantId: tenant(),
      );

  Future<Object?> removeDocument(String id) =>
      api.delete('/marketplace/documents/$id', tenantId: tenant());

  Future<Paged<MpLead>> leads({String? status, int page = 1, int pageSize = 20}) async {
    final Object? data = await _get(
      api,
      '/marketplace/leads',
      query: <String, Object?>{'status': status, 'page': page, 'page_size': pageSize},
      tenant: tenant,
    );
    return Paged.of<MpLead>(data, MpLead.new);
  }

  Future<Object?> setLeadStatus(String id, String status) => api.patch(
        '/marketplace/leads/$id',
        body: <String, Object?>{'status': status},
        tenantId: tenant(),
      );

  Future<TelegramBinding> telegram() async => TelegramBinding(
      JsonMap.from(await _get(api, '/marketplace/telegram', tenant: tenant)).json);

  /// `bot_token` 必填（服务端先 getMe 验证），`chat_id` 留空走自动探测。
  /// token 只进不出：这一枚写完就再也读不回来，客户端也不落本地。
  Future<TelegramBinding> bindTelegram({
    required String botToken,
    String? chatId,
    bool notifyEnabled = true,
    String? lang,
  }) async {
    final Object? data = await api.post(
      '/marketplace/telegram',
      body: <String, Object?>{
        'bot_token': botToken,
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        'notify_enabled': notifyEnabled,
        if (lang != null) 'lang': lang,
      },
      tenantId: tenant(),
    );
    return TelegramBinding(JsonMap.from(data).json);
  }

  Future<TelegramBinding> testTelegram() async {
    final Object? data = await api.post(
      '/marketplace/telegram/test',
      body: <String, Object?>{},
      tenantId: tenant(),
    );
    return TelegramBinding(JsonMap.from(data).json);
  }

  /// 服务端认的是 `notify_enabled`，不是 `enabled`。
  Future<Object?> setTelegramNotify(bool enabled) => api.post(
        '/marketplace/telegram/notify',
        body: <String, Object?>{'notify_enabled': enabled},
        tenantId: tenant(),
      );

  Future<Object?> unbindTelegram() => api.delete('/marketplace/telegram', tenantId: tenant());

  /// `filter` 只有 `'open'` 与 `'unread'` 两档被服务端识别，其余值等于不过滤。
  Future<Paged<MpConversation>> conversations({
    String? filter,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? data = await _get(
      api,
      '/marketplace/conversations',
      query: <String, Object?>{'status': filter, 'page': page, 'page_size': pageSize},
      tenant: tenant,
    );
    return Paged.of<MpConversation>(data, MpConversation.new);
  }

  /// 详情行 = 会话头部 + 整页消息；打开会话时顺带把未读清零（服务端做的）。
  Future<MpConversation> conversation(String conversationId, {int? after}) async {
    final Object? data = await _get(
      api,
      '/marketplace/conversations/$conversationId/messages',
      query: <String, Object?>{'after': after},
      tenant: tenant,
    );
    return MpConversation(JsonMap.from(data).json);
  }

  Future<Object?> reply(String conversationId, String body) => api.post(
        '/marketplace/conversations/$conversationId/reply',
        body: <String, Object?>{'body': body},
        tenantId: tenant(),
      );

  /// 引导留资只吃路径参数：服务端按会话语言插一条 system 消息，重复调用回 `already_invited`。
  Future<JsonMap> inviteLead(String conversationId) async => JsonMap.from(
      await api.post(
        '/marketplace/conversations/$conversationId/invite-lead',
        body: <String, Object?>{},
        tenantId: tenant(),
      ));

  Future<Object?> setConversationStatus(String id, String status) => api.patch(
        '/marketplace/conversations/$id',
        body: <String, Object?>{'status': status},
        tenantId: tenant(),
      );

  Future<MpAnalytics> analytics({int days = 7}) async => MpAnalytics(
      JsonMap.from(await _get(
        api,
        '/marketplace/analytics',
        query: <String, Object?>{'days': days},
        tenant: tenant,
      )).json);

  /// 顶层是 `{items, total, ad, priced, base_lead_minor, currency, warnings}`，不是裸数组。
  Future<MpCampaignPage> campaigns() async => MpCampaignPage(
      JsonMap.from(await _get(api, '/marketplace/campaigns', tenant: tenant)).json);

  /// 只支持 `kind: "cpl"`；两枚金额都是最小货币单位整数（₴ 的分位）：
  /// `daily_cap_minor` 必填、`total_budget_minor` 留空即「不设上限」，
  /// `started_at` 不能早于现在（否则会把过去的自然留资按 CPL 补扣）。
  Future<MpCampaignWrite> createCampaign({
    required String listingId,
    required int dailyCapMinor,
    int? totalBudgetMinor,
    String? startedAt,
    String? endedAt,
  }) async {
    final Object? data = await api.post(
      '/marketplace/campaigns',
      body: <String, Object?>{
        'listing_id': listingId,
        'kind': 'cpl',
        'daily_cap_minor': dailyCapMinor,
        'total_budget_minor': totalBudgetMinor,
        'started_at': startedAt,
        'ended_at': endedAt,
      },
      tenantId: tenant(),
    );
    return MpCampaignWrite(JsonMap.from(data).json);
  }

  /// 卖家能改的状态只有三档；`canceled` 是终态，重新开始要建新的一档。
  /// `exhausted → active` 只有把总预算抬到已花费之上、或清空预算这两条路。
  /// 传 `clearBudget: true` 表示「把总预算改成不设上限」（`null` = 清空，缺省 = 不改）。
  Future<MpCampaignWrite> patchCampaign(
    String id, {
    String? status,
    int? dailyCapMinor,
    int? totalBudgetMinor,
    bool clearBudget = false,
    String? startedAt,
    String? endedAt,
    bool clearEndedAt = false,
  }) async {
    final Object? data = await api.patch(
      '/marketplace/campaigns/$id',
      body: <String, Object?>{
        if (status != null) 'status': status,
        if (dailyCapMinor != null) 'daily_cap_minor': dailyCapMinor,
        if (clearBudget) 'total_budget_minor': null,
        if (totalBudgetMinor != null) 'total_budget_minor': totalBudgetMinor,
        if (startedAt != null) 'started_at': startedAt,
        if (clearEndedAt) 'ended_at': null,
        if (endedAt != null) 'ended_at': endedAt,
      },
      tenantId: tenant(),
    );
    return MpCampaignWrite(JsonMap.from(data).json);
  }
}

class FinanceRepo {
  const FinanceRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<ApiResponse<FinanceSummary>> stats({
    String? dateFrom,
    String? dateTo,
  }) async {
    final ApiResponse<Object?> res = await api.get(
      '/finance/stats',
      query: <String, Object?>{'dateFrom': dateFrom, 'dateTo': dateTo},
      tenantId: tenant(),
      cache: true,
    );
    // stale 必须跟着数据一起出去：离线兜底读到的是缓存，界面得知道这串数字可能不是最新。
    return ApiResponse<FinanceSummary>(
      data: FinanceSummary(JsonMap.from(res.data).json),
      stale: res.stale,
      cachedAt: res.cachedAt,
    );
  }

  Future<Paged<PaymentRecord>> records({
    String? dateFrom,
    String? dateTo,
    String? method,
    String? type,
    String? customerId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Object? data = await _get(
      api,
      '/finance/records',
      query: <String, Object?>{
        'dateFrom': dateFrom,
        'dateTo': dateTo,
        'method': method,
        'type': type,
        'customer_id': customerId,
        'page': page,
        'pageSize': pageSize,
      },
      tenant: tenant,
    );
    return Paged.of<PaymentRecord>(data, PaymentRecord.new);
  }

  /// 冲销一条流水（`DELETE /finance/records/:record_id`），服务端会把订单金额重算回去。
  Future<Object?> voidRecord(String recordId, {String? reason}) => api.delete(
        '/finance/records/$recordId',
        body: <String, Object?>{'reason': reason},
        tenantId: tenant(),
      );

  /// 欠款面按客户分组、一次给全（服务端没有分页也没有筛选），`truncated` 如实报扫描上限。
  Future<JsonMap> debts() async {
    final Object? data = await _get(api, '/finance/debts', tenant: tenant);
    return JsonMap.from(data);
  }

  /// 路径就是客户 UUID，动作没有额外一段：`POST /finance/debts/:customer_id`。
  /// 服务端从该客户最老的未结清单开始抵扣，超出欠款的部分回成 `change`（找零，不是余额）。
  Future<DebtSettlement> settle(String customerId, {
    required double amount,
    required String method,
    String? notes,
  }) async {
    final Object? data = await api.post(
      '/finance/debts/$customerId',
      body: <String, Object?>{'amount': amount, 'method': method, 'notes': notes},
      tenantId: tenant(),
    );
    return DebtSettlement(JsonMap.from(data).json);
  }

  /// 金额展示用的符号是租户级设置，只有管理员能改（服务端截到 8 个字符）。
  Future<Object?> setCurrencySymbol(String symbol) => api.patch(
        '/finance/currency',
        body: <String, Object?>{'currency_symbol': symbol},
        tenantId: tenant(),
      );
}

class AiRepo {
  const AiRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<AiConfig> config() async =>
      AiConfig(JsonMap.from(await _get(api, '/ai/config', tenant: tenant)).json);

  Future<String> chat(List<Map<String, Object?>> messages, {String? page}) async {
    final Object? data = await api.post(
      '/ai/chat',
      body: <String, Object?>{'messages': messages, 'page': page},
      tenantId: tenant(),
      heavy: true,
    );
    final JsonMap map = JsonMap.from(data);
    return map.asStringOr('reply', map.asStringOr('content', map.asStringOr('answer', '')));
  }

  Future<String> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/webm',
    String? language,
  }) =>
      api
          .post(
            '/speech/transcribe',
            body: <String, Object?>{
              'audio': base64Encode(audioBytes),
              'mimeType': mimeType,
              'language': language,
            },
            tenantId: tenant(),
            heavy: true,
          )
          .then((Object? data) => JsonMap.from(data).asStringOr('text', ''));

  /// 自然语言查订单/商品/日志：键名是 `query`，出参按 `intent` 分支。
  Future<JsonMap> assistQuery(String utterance) async => JsonMap.from(await api.post(
        '/assist/query',
        body: <String, Object?>{'query': utterance},
        tenantId: tenant(),
      ));
}

class SettingsRepo {
  const SettingsRepo(this.api, this.tenant);

  final ApiClient api;
  final TenantProvider tenant;

  Future<List<MemberRow>> users() async {
    final Object? data = await _get(api, '/users', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['users', 'data']).map(MemberRow.new).toList();
  }

  /// `role` 留空即保持原角色（服务端按 `payload.role || 现角色` 取）。
  /// 注意 admin / tenant_admin 会被服务端强制写成全开的权限位，勾出来的子集不算数。
  Future<Object?> setPermissions(String userId, Map<String, bool> permissions, {String? role}) =>
      api.patch(
        '/users/$userId/permissions',
        body: <String, Object?>{
          'permissions': permissions,
          if (role != null) 'role': role,
        },
        tenantId: tenant(),
      );

  Future<Object?> removeMember(String userId) => api.delete('/users/$userId', tenantId: tenant());

  Future<List<Invitation>> invitations() async {
    final Object? data = await _get(api, '/invitations', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['invitations', 'data']).map(Invitation.new).toList();
  }

  /// 邀请码由服务端生成（4-10 位大写字母数字），不接收邮箱。
  Future<Object?> invite({
    String? code,
    required String role,
    int expiresHours = 168,
    Map<String, bool>? permissions,
  }) =>
      api.post(
        '/invitations',
        body: <String, Object?>{
          if (code != null && code.isNotEmpty) 'code': code,
          'role': role,
          'expires_hours': expiresHours,
          if (permissions != null) 'permissions': permissions,
        },
        tenantId: tenant(),
      );

  Future<Object?> revokeInvitation(String id) =>
      api.delete('/invitations/$id', tenantId: tenant());

  Future<List<Customer>> customers() async {
    final Object? data = await _get(api, '/customers', tenant: tenant, cache: true);
    return JsonMap.rawListOf(data, <String>['customers', 'data']).map(Customer.new).toList();
  }

  Future<Object?> createCustomer(Map<String, Object?> payload) =>
      api.post('/customers', body: payload, tenantId: tenant());

  Future<Object?> updateCustomer(String id, Map<String, Object?> payload) =>
      api.patch('/customers/$id', body: payload, tenantId: tenant());

  Future<Object?> removeCustomer(String id) => api.delete('/customers/$id', tenantId: tenant());

  Future<List<Memo>> memos() async {
    final Object? data = await _get(api, '/memos', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['memos', 'data']).map(Memo.new).toList();
  }

  Future<Object?> createMemo(String content, {String priority = 'normal'}) => api.post(
        '/memos',
        body: <String, Object?>{'content': content, 'priority': priority},
        tenantId: tenant(),
      );

  /// PATCH 是按字段增量改：`content` / `is_completed` / `priority` 都可以只传一个。
  Future<Object?> updateMemo(
    String id, {
    String? content,
    bool? completed,
    String? priority,
  }) =>
      api.patch(
        '/memos/$id',
        body: <String, Object?>{
          if (content != null) 'content': content,
          if (completed != null) 'is_completed': completed,
          if (priority != null) 'priority': priority,
        },
        tenantId: tenant(),
      );

  Future<Object?> removeMemo(String id) => api.delete('/memos/$id', tenantId: tenant());

  Future<List<FeedbackThread>> feedback() async {
    final Object? data = await _get(api, '/feedback', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['items', 'threads', 'feedback', 'data'])
        .map(FeedbackThread.new)
        .toList();
  }

  /// 正文 5–2000 字（服务端 trim 后按同一把尺量），`page_url` 可空。
  Future<Object?> submitFeedback({
    required String category,
    required String content,
    String? pageUrl,
  }) =>
      api.post(
        '/feedback',
        body: <String, Object?>{
          'category': category,
          'content': content,
          if (pageUrl != null) 'page_url': pageUrl,
        },
        tenantId: tenant(),
      );

  Future<PlanBoard> plans() async =>
      PlanBoard(JsonMap.from(await _get(api, '/payments/plans', tenant: tenant)).json);

  Future<List<JsonMap>> payments() async => JsonMap.listOf(
        await _get(api, '/payments', tenant: tenant),
        <String>['payments', 'data'],
      );

  /// 轮询回执同样是 `{payment}`：`{channel}` 查询参数缺省时服务端自己判通道。
  Future<PaymentTicket> paymentStatus(String id, {String? channel}) async => PaymentTicket(
      JsonMap.from(await _get(
        api,
        '/payments/$id/status',
        query: <String, Object?>{'channel': channel},
        tenant: tenant,
      )).json);

  Future<WalletAccount> wallet() async =>
      WalletAccount(JsonMap.from(await _get(api, '/wallet/account', tenant: tenant)).json);

  Future<WalletTopupBoard> walletTopupPlans() async => WalletTopupBoard(
      JsonMap.from(await _get(api, '/wallet/plans', tenant: tenant)).json);

  /// 订阅开单：`plan_type` 三档，`channel` 缺省即用业主设的默认通道。
  /// 金额一律来自服务端价目表，客户端传 `amount`/`success_url` 会被忽略。
  Future<PaymentTicket> createPayment({required String planType, String? channel}) async =>
      PaymentTicket(JsonMap.from(await api.post(
        '/payments',
        body: <String, Object?>{'plan_type': planType, if (channel != null) 'channel': channel},
        tenantId: tenant(),
      )).json);

  /// 钱包充值只认档位（`small|medium|large`），且只走 Monobank。
  Future<PaymentTicket> topUpWallet(String tier) async => PaymentTicket(JsonMap.from(
      await api.post(
        '/wallet/topup',
        body: <String, Object?>{'tier': tier},
        tenantId: tenant(),
      )).json);

  Future<JsonMap> fullExport() async => JsonMap.from(
      await _get(api, '/data/full-export', tenant: tenant, heavy: true));

  // ———— 外部商品源（YML / XML）————
  //
  // 单次请求 60 s 封顶，而一整店的外部行动辄上千，所以导入与同步都由调用方按块喂，
  // 这里只保证「一块一次请求」。

  Future<ExternalPreview> externalPreview(String url) async => ExternalPreview(
        JsonMap.from(await api.post(
          '/data/external-preview',
          body: <String, Object?>{'url': url},
          tenantId: tenant(),
          heavy: true,
        )).json,
      );

  Future<ImportOutcome> externalImportChunk(
    List<JsonMap> items, {
    required bool downloadImages,
    required bool priceAsCost,
    int? markupPercent,
  }) async =>
      ImportOutcome(JsonMap.from(await api.post(
        '/data/external-import',
        body: <String, Object?>{
          'items': items.map((JsonMap row) => row.json).toList(growable: false),
          'download_images': downloadImages,
          'price_as_cost': priceAsCost,
          'markup_percent': markupPercent,
        },
        tenantId: tenant(),
        heavy: true,
      )).json);

  Future<ExternalSyncOutcome> externalSyncChunk(
    List<JsonMap> items, {
    required bool updatePrice,
    required bool updateStock,
    required String priceTarget,
    int? markupPercent,
    required String source,
  }) async =>
      ExternalSyncOutcome(JsonMap.from(await api.post(
        '/data/external-sync',
        body: <String, Object?>{
          'items': items.map((JsonMap row) => row.json).toList(growable: false),
          'update_price': updatePrice,
          'update_stock': updateStock,
          'price_target': priceTarget,
          'markup_percent': markupPercent,
          'source': source,
        },
        tenantId: tenant(),
        heavy: true,
      )).json);

  /// 出参是 `{settings:{...}}` 单对象（服务端永远兜一份默认值回来，不会有 null）。
  Future<PrintSettings> printSettings() async =>
      PrintSettings(JsonMap.from(await _get(api, '/print-settings', tenant: tenant)).asMap('settings').json);

  Future<PrintSettings> savePrintSettings(PrintSettings values) async => PrintSettings(
      JsonMap.from(await api.post(
        '/print-settings',
        body: values.toPayload(),
        tenantId: tenant(),
      )).asMap('settings').json);

  // ———— 外部 API Key（仅租户管理员；明文只在创建那一次返回） ————

  Future<List<ApiKey>> apiKeys() async {
    final Object? data = await _get(api, '/api-keys', tenant: tenant);
    return JsonMap.rawListOf(data, <String>['keys', 'data'])
        .map(ApiKey.new)
        .toList(growable: false);
  }

  /// `scopes` 不能为空，且只能取服务端 `TENANT_SCOPES` 那 16 项；有效 key 上限 10 枚。
  Future<ApiKeyCreated> createApiKey({
    required String name,
    required List<String> scopes,
    String? expiresAt,
  }) async {
    final Object? data = await api.post(
      '/api-keys',
      body: <String, Object?>{'name': name, 'scopes': scopes, 'expires_at': expiresAt},
      tenantId: tenant(),
    );
    return ApiKeyCreated(JsonMap.from(data).json);
  }

  Future<Object?> removeApiKey(String id) => api.delete('/api-keys/$id', tenantId: tenant());
}
