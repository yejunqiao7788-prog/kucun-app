import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';
import '../orders/order_create_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DashboardStats _stats = DashboardStats.empty();
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    final tenantId = auth.currentProfile?.tenantId ?? '';

    if (tenantId.isNotEmpty) {
      final stats = await firestore.getDashboardStats(tenantId);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);
    final profile = auth.currentProfile;
    final currency = profile?.currencySymbol ?? '₴';
    final tenantId = profile?.tenantId ?? '';
    final isManager = ['admin', 'tenant_admin', 'super_admin'].contains(profile?.role);

    return Scaffold(
      appBar: AppBar(
        title: Text('${profile?.tenantName ?? "仓库"} · 工作台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoadingStats = true);
              _loadStats();
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: 'dashboard'),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome greeting
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '您好，${profile?.username ?? "用户"}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '今日运营数据一览',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  Chip(
                    label: Text(
                      profile?.subscriptionExpired == true ? '已到期' : '生效中',
                      style: TextStyle(
                        color: profile?.subscriptionExpired == true ? Colors.red : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: (profile?.subscriptionExpired == true ? Colors.red : Colors.green).withOpacity(0.1),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 8 Stats Cards Grid (2 columns)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _buildStatCard(
                    title: '在售商品',
                    value: '${_stats.totalProducts}',
                    icon: Icons.inventory_2_outlined,
                    color: Colors.blue,
                  ),
                  _buildStatCard(
                    title: '总在库件数',
                    value: NumberFormat('#,###').format(_stats.totalStock),
                    icon: Icons.category_outlined,
                    color: Colors.indigo,
                  ),
                  _buildStatCard(
                    title: '库存预警(低库存)',
                    value: '${_stats.lowStock}',
                    icon: Icons.warning_amber_rounded,
                    color: _stats.lowStock > 0 ? Colors.orange : Colors.grey,
                  ),
                  _buildStatCard(
                    title: '库存估值',
                    value: '$currency${NumberFormat('#,##0.00').format(_stats.totalValue)}',
                    icon: Icons.monetization_on_outlined,
                    color: Colors.teal,
                  ),
                  _buildStatCard(
                    title: '今日入库单数',
                    value: '${_stats.inboundToday} 单',
                    subtitle: '共 ${_stats.inboundQtyToday} 件',
                    icon: Icons.move_to_inbox_outlined,
                    color: Colors.purple,
                  ),
                  _buildStatCard(
                    title: '今日出库单数',
                    value: '${_stats.outboundToday} 单',
                    subtitle: '共 ${_stats.outboundQtyToday} 件',
                    icon: Icons.outbox_outlined,
                    color: Colors.deepOrange,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tabs: 今日订单 vs 备货清单
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey.shade700,
                  tabs: const [
                    Tab(text: '今日订单'),
                    Tab(text: '备货清单'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Today's Orders
                    StreamBuilder<List<OrderModel>>(
                      stream: firestore.watchRecentOrders(tenantId, isManager),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final orders = snapshot.data ?? [];
                        if (orders.isEmpty) {
                          return Center(
                            child: Text(
                              '今日暂无订单记录',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final o = orders[index];
                            return _buildOrderTile(o, currency, firestore);
                          },
                        );
                      },
                    ),

                    // Tab 2: Picking List
                    StreamBuilder<List<OrderModel>>(
                      stream: firestore.watchPickingList(tenantId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final orders = snapshot.data ?? [];
                        if (orders.isEmpty) {
                          return Center(
                            child: Text(
                              '备货清单为空',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final o = orders[index];
                            return _buildOrderTile(o, currency, firestore);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建单据'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrderCreateScreen()),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTile(OrderModel order, String currency, FirestoreService firestore) {
    final isInbound = order.type == 'inbound';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isInbound ? Colors.purple.shade50 : Colors.orange.shade50,
        child: Icon(
          isInbound ? Icons.move_to_inbox : Icons.outbox,
          color: isInbound ? Colors.purple : Colors.deepOrange,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: order.status == 'completed' ? Colors.green.shade50 : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              order.status == 'completed' ? '已定稿' : '草稿',
              style: TextStyle(
                fontSize: 10,
                color: order.status == 'completed' ? Colors.green.shade800 : Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        "${order.customerName ?? '散客'} · ${order.totalQuantity} 件 · $currency${order.totalAmount.toStringAsFixed(2)}",
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              order.showInPickingList ? Icons.checklist_rtl : Icons.checklist,
              color: order.showInPickingList ? Colors.blue : Colors.grey,
            ),
            tooltip: '切换备货清单',
            onPressed: () async {
              await firestore.togglePickingList(order.id, !order.showInPickingList);
            },
          ),
        ],
      ),
    );
  }
}
