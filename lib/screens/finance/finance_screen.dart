import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  FinanceStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFinance();
  }

  Future<void> _loadFinance() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    final tenantId = auth.currentProfile?.tenantId ?? '';

    if (tenantId.isNotEmpty) {
      final stats = await firestore.getFinanceStats(tenantId);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('财务与结算'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadFinance();
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: 'finance'),
      body: RefreshIndicator(
        onRefresh: _loadFinance,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('经营财务汇总', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '毛利依据下单时的成本快照(unit_cost)准确核算',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Big Profit Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade600, Colors.teal.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('累计毛利润', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        "$currency${NumberFormat('#,##0.00').format(_stats?.grossProfit ?? 0.0)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "销售营收: $currency${NumberFormat('#,##0.00').format(_stats?.totalRevenue ?? 0.0)}",
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            "商品成本: $currency${NumberFormat('#,##0.00').format(_stats?.totalCost ?? 0.0)}",
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Receivables & Debts row
                Row(
                  children: [
                    Expanded(
                      child: _buildSmallCard(
                        title: '已收资金',
                        value: "$currency${NumberFormat('#,##0.00').format(_stats?.totalPaid ?? 0.0)}",
                        color: Colors.green,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSmallCard(
                        title: '待收欠款',
                        value: "$currency${NumberFormat('#,##0.00').format(_stats?.totalUnpaid ?? 0.0)}",
                        color: Colors.red,
                        icon: Icons.pending_actions_outlined,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),

              // Customer Debts Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('往来客户欠款账册', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('录入客户'),
                    onPressed: () => _showAddCustomerDialog(context, firestore, tenantId),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              StreamBuilder<List<Customer>>(
                stream: firestore.watchCustomers(tenantId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final customers = snapshot.data ?? [];
                  if (customers.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(child: Text('暂无客户记录', style: TextStyle(color: Colors.grey))),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = customers[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(c.name.isNotEmpty ? c.name[0] : 'C'),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone != null ? "电话: ${c.phone}" : "地址: ${c.address ?? '未填'}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.debtAmount > 0
                                  ? "欠款: $currency${c.debtAmount.toStringAsFixed(2)}"
                                  : "无欠款",
                              style: TextStyle(
                                color: c.debtAmount > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (c.debtAmount > 0)
                              IconButton(
                                icon: const Icon(Icons.payment, color: Colors.blue),
                                tooltip: '结清欠款 (先抵最老欠款)',
                                onPressed: () {
                                  _showSettleDebtDialog(context, firestore, c, tenantId, currency);
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, FirestoreService firestore, String tenantId) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('新增往来客户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '客户名称 *', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: '联系电话', isDense: true),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: '送货/通讯地址', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final c = Customer(
                  id: '',
                  tenantId: tenantId,
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  address: addressCtrl.text.trim(),
                  debtAmount: 0.0,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await firestore.createCustomer(c);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _showSettleDebtDialog(
    BuildContext context,
    FirestoreService firestore,
    Customer customer,
    String tenantId,
    String currency,
  ) {
    final amountCtrl = TextEditingController(text: customer.debtAmount.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('结清欠款 · ${customer.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前未结清欠款: $currency${customer.debtAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              const Text(
                '系统将遵循业务不变量：优先从最老的未付订单开始逐单抵扣冲销。',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: '还款金额', border: OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim());
                if (amt == null || amt <= 0) return;

                await firestore.settleCustomerDebt(
                  tenantId: tenantId,
                  customerId: customer.id,
                  settleAmount: amt,
                );
                Navigator.pop(ctx);
                _loadFinance();
              },
              child: const Text('确认核销'),
            ),
          ],
        );
      },
    );
  }
}
