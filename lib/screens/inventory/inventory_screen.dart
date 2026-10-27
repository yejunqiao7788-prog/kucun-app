import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);
    final profile = auth.currentProfile;
    final tenantId = profile?.tenantId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('库存盘点与库位'),
      ),
      drawer: const AppDrawer(currentRoute: 'inventory'),
      body: Column(
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索商品、SKU 或库位...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: firestore.watchProducts(tenantId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var list = snapshot.data ?? [];

                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  list = list.where((p) {
                    return p.name.toLowerCase().contains(q) ||
                        p.sku.toLowerCase().contains(q) ||
                        (p.location != null && p.location!.toLowerCase().contains(q));
                  }).toList();
                }

                if (list.isEmpty) {
                  return const Center(child: Text('暂无库存数据'));
                }

                // Group by location
                Map<String, List<Product>> grouped = {};
                for (var p in list) {
                  final loc = (p.location != null && p.location!.trim().isNotEmpty)
                      ? p.location!.trim()
                      : '未分配库位';
                  grouped.putIfAbsent(loc, () => []).add(p);
                }

                final locations = grouped.keys.toList()..sort();

                return ListView.builder(
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final loc = locations[index];
                    final products = grouped[loc]!;

                    return ExpansionTile(
                      initiallyExpanded: true,
                      leading: Icon(
                        loc == '未分配库位' ? Icons.help_outline : Icons.location_on_outlined,
                        color: loc == '未分配库位' ? Colors.grey : Colors.blue,
                      ),
                      title: Text(
                        loc,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text('共 ${products.length} 个SKU'),
                      children: products.map((product) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey.shade100,
                            child: product.imageUrl != null
                                ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                                : const Icon(Icons.inventory_2, color: Colors.grey, size: 20),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _buildStatusBadge(product.stockStatus),
                            ],
                          ),
                          subtitle: Text(
                            "SKU: ${product.sku} · 预警值: ${product.minStock} · 上限: ${product.maxStock}",
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${product.quantity} ${product.unit}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_note, color: Colors.blue),
                                tooltip: '调整库存',
                                onPressed: () {
                                  _showAdjustStockDialog(
                                    context,
                                    firestore,
                                    product,
                                    tenantId,
                                    auth.currentUser!.uid,
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(StockStatus status) {
    Color bg;
    Color fg;
    String text;
    switch (status) {
      case StockStatus.outOfStock:
        bg = Colors.red.shade50;
        fg = Colors.red;
        text = '缺货';
        break;
      case StockStatus.lowStock:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        text = '低库存';
        break;
      case StockStatus.overflow:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        text = '溢出';
        break;
      case StockStatus.normal:
        bg = Colors.green.shade50;
        fg = Colors.green;
        text = '正常';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _showAdjustStockDialog(
    BuildContext context,
    FirestoreService firestore,
    Product product,
    String tenantId,
    String userId,
  ) {
    final controller = TextEditingController(text: product.quantity.toString());
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('调整库存 · ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前库存: ${product.quantity} ${product.unit} (SKU: ${product.sku})'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '调整后库存数量 *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: '变动备注 (如 盘盈/损耗/手工校正)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newQty = int.tryParse(controller.text.trim());
                if (newQty == null || newQty < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入有效正整数库存')),
                  );
                  return;
                }

                await firestore.adjustStock(
                  productId: product.id,
                  tenantId: tenantId,
                  newQuantity: newQty,
                  userId: userId,
                  reason: reasonController.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('确认调整'),
            ),
          ],
        );
      },
    );
  }
}
