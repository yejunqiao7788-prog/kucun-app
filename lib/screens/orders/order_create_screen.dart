import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

class OrderCreateScreen extends StatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  String _orderType = 'outbound'; // 'outbound' | 'inbound'
  final _customerController = TextEditingController();
  final _notesController = TextEditingController();
  late String _orderDate;
  final List<OrderItem> _selectedItems = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _orderDate = DateFormat('yyyy-MM-dd').format(now);
  }

  @override
  void dispose() {
    _customerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    return _selectedItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int get _totalQuantity {
    return _selectedItems.fold(0, (sum, item) => sum + item.quantity);
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
        title: const Text('开立新订单'),
        actions: [
          TextButton(
            onPressed: _selectedItems.isEmpty
                ? null
                : () async {
                    try {
                      final orderNum = "ORD-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}";
                      final order = OrderModel(
                        id: const Uuid().v4(),
                        tenantId: tenantId,
                        orderNumber: orderNum,
                        type: _orderType,
                        status: 'pending',
                        orderDate: _orderDate,
                        notes: _notesController.text.trim(),
                        isPreparing: false,
                        showInPickingList: false,
                        createdBy: auth.currentUser!.uid,
                        customerName: _customerController.text.trim().isNotEmpty
                            ? _customerController.text.trim()
                            : '默认散客',
                        items: _selectedItems,
                        totalQuantity: _totalQuantity,
                        totalAmount: _totalAmount,
                        payableAmount: _totalAmount,
                        paidAmount: 0.0,
                        paymentStatus: 'unpaid',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      );

                      await firestore.createOrderDraft(order);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('草稿订单 $orderNum 创建成功')),
                        );
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('创建失败: $e')),
                      );
                    }
                  },
            child: const Text('保存草稿', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Type Segment
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('出库销售单 (扣库存)')),
                    selected: _orderType == 'outbound',
                    selectedColor: Colors.deepOrange.shade100,
                    onSelected: (val) {
                      if (val) setState(() => _orderType = 'outbound');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('入库进货单 (加库存)')),
                    selected: _orderType == 'inbound',
                    selectedColor: Colors.purple.shade100,
                    onSelected: (val) {
                      if (val) setState(() => _orderType = 'inbound');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Form inputs
            TextField(
              controller: _customerController,
              decoration: const InputDecoration(
                labelText: '客户 / 往来单位名称',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: '订单备注 (如 配送地址/特殊要求)',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // Items section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '订单明细 (${_selectedItems.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加商品'),
                  onPressed: () => _showAddProductPicker(context, firestore, tenantId),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Items list
            if (_selectedItems.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.add_shopping_cart, size: 36, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('请点击右上角"添加商品"录入明细', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _selectedItems[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      "SKU: ${item.productSku} · 单价: $currency${item.unitPrice.toStringAsFixed(2)}${item.boxCount != null && item.boxCount! > 0 ? ' (${item.boxCount}箱)' : ''}",
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "x${item.quantity} = $currency${item.subtotal.toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () {
                            setState(() => _selectedItems.removeAt(index));
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),
            // Summary Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("合计数量: $_totalQuantity 件", style: const TextStyle(fontSize: 15)),
                  Text(
                    "应收合计: $currency${_totalAmount.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProductPicker(BuildContext context, FirestoreService firestore, String tenantId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: StreamBuilder<List<Product>>(
            stream: firestore.watchProducts(tenantId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final products = snapshot.data ?? [];
              if (products.isEmpty) {
                return const Center(child: Text('仓库中暂无商品'));
              }

              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('选择要加入订单的商品', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = products[index];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text("SKU: ${p.sku} · 现存: ${p.quantity} ${p.unit} · 单价: ${p.price}"),
                          trailing: ElevatedButton(
                            child: const Text('添加'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showItemQtyDialog(context, p);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showItemQtyDialog(BuildContext context, Product product) {
    final qtyController = TextEditingController(text: '1');
    final boxController = TextEditingController(text: '0');
    final priceController = TextEditingController(text: product.price.toString());
    final hasBoxes = product.unitsPerBox != null && product.unitsPerBox! > 1;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('添加: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasBoxes) ...[
                TextField(
                  controller: boxController,
                  decoration: InputDecoration(
                    labelText: '整箱数 (每箱 ${product.unitsPerBox} ${product.unit})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyController,
                  decoration: InputDecoration(
                    labelText: '散装件数 (${product.unit})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ] else ...[
                TextField(
                  controller: qtyController,
                  decoration: InputDecoration(
                    labelText: '数量 (${product.unit})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: '单价',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                final looseQty = int.tryParse(qtyController.text) ?? 0;
                final boxes = int.tryParse(boxController.text) ?? 0;
                final unitPrice = double.tryParse(priceController.text) ?? product.price;

                int totalUnits = looseQty;
                if (hasBoxes && boxes > 0) {
                  totalUnits += (boxes * product.unitsPerBox!);
                }

                if (totalUnits <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('商品数量必须大于 0')),
                  );
                  return;
                }

                final item = OrderItem(
                  productId: product.id,
                  productName: product.name,
                  productSku: product.sku,
                  quantity: totalUnits,
                  unitCost: product.cost, // Snapshot cost
                  unitPrice: unitPrice,
                  subtotal: totalUnits * unitPrice,
                  boxCount: hasBoxes && boxes > 0 ? boxes : null,
                  unitsPerBox: product.unitsPerBox,
                  categoryName: product.categoryName,
                  imageUrl: product.imageUrl,
                );

                setState(() => _selectedItems.add(item));
                Navigator.pop(ctx);
              },
              child: const Text('加入清单'),
            ),
          ],
        );
      },
    );
  }
}
