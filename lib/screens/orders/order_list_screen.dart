import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';
import 'order_create_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);
    final profile = auth.currentProfile;
    final currency = profile?.currencySymbol ?? '₴';
    final tenantId = profile?.tenantId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('订单管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '出库单(销售)'),
            Tab(text: '入库单(进货)'),
          ],
        ),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: '状态筛选',
            onSelected: (val) => setState(() => _statusFilter = val),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: null, child: Text('全部状态')),
              const PopupMenuItem(value: 'pending', child: Text('仅草稿')),
              const PopupMenuItem(value: 'completed', child: Text('仅已定稿')),
            ],
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: 'orders'),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(firestore, tenantId, null, currency, auth.currentUser!.uid),
          _buildOrdersList(firestore, tenantId, 'outbound', currency, auth.currentUser!.uid),
          _buildOrdersList(firestore, tenantId, 'inbound', currency, auth.currentUser!.uid),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('开立新单'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrderCreateScreen()),
          );
        },
      ),
    );
  }

  Widget _buildOrdersList(
    FirestoreService firestore,
    String tenantId,
    String? type,
    String currency,
    String userId,
  ) {
    return StreamBuilder<List<OrderModel>>(
      stream: firestore.watchOrders(tenantId, type: type, status: _statusFilter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('暂无相关订单', style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final order = list[index];
            final isInbound = order.type == 'inbound';
            final isCompleted = order.status == 'completed';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Order Number + Type + Status Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isInbound ? Colors.purple.shade50 : Colors.deepOrange.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isInbound ? '入库' : '出库',
                                style: TextStyle(
                                  color: isInbound ? Colors.purple : Colors.deepOrange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              order.orderNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCompleted ? Colors.green.shade50 : Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isCompleted ? '已定稿' : '草稿中',
                            style: TextStyle(
                              color: isCompleted ? Colors.green.shade800 : Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // Order Info
                    Text("客户/供应商: ${order.customerName ?? '未指定散客'}"),
                    const SizedBox(height: 4),
                    Text("开单日期: ${order.orderDate} · 商品种类: ${order.items.length} 种"),
                    const SizedBox(height: 6),

                    // Items snippet
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: order.items.take(3).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "${item.productName} (SKU: ${item.productSku})",
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  "x${item.quantity} · $currency${item.subtotal.toStringAsFixed(2)}",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (order.items.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "... 还有 ${order.items.length - 3} 件明细",
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        ),
                      ),

                    const SizedBox(height: 10),
                    // Summary amount + Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "共 ${order.totalQuantity} 件",
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                            Text(
                              "合计: $currency${order.totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (!isCompleted) ...[
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () async {
                                  await firestore.deleteOrderDraft(order.id);
                                },
                                child: const Text('删除草稿'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  _showFinalizeConfirmDialog(
                                    context,
                                    firestore,
                                    order,
                                    tenantId,
                                    userId,
                                  );
                                },
                                child: const Text('确认定稿'),
                              ),
                            ] else ...[
                              IconButton(
                                icon: Icon(
                                  order.showInPickingList ? Icons.checklist_rtl : Icons.checklist,
                                  color: order.showInPickingList ? Colors.blue : Colors.grey,
                                ),
                                tooltip: '切换备货清单',
                                onPressed: () async {
                                  await firestore.togglePickingList(
                                    order.id,
                                    !order.showInPickingList,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFinalizeConfirmDialog(
    BuildContext context,
    FirestoreService firestore,
    OrderModel order,
    String tenantId,
    String userId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('定稿确认'),
          content: Text(
            '定稿是不可逆的关键动作！\n\n'
            '单号：${order.orderNumber}\n'
            '明细：共 ${order.items.length} 个商品 / ${order.totalQuantity} 件\n'
            '金额：${order.totalAmount.toStringAsFixed(2)}\n\n'
            '定稿后将立即执行真实库存变动并写入变动账本。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await firestore.finalizeOrder(
                    orderId: order.id,
                    tenantId: tenantId,
                    userId: userId,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('订单定稿成功，库存已同步更新')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 8),
                            Text('定稿失败'),
                          ],
                        ),
                        content: Text(e.toString().replaceAll('Exception: ', '')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('我知道了'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text('确认定稿'),
            ),
          ],
        );
      },
    );
  }
}
