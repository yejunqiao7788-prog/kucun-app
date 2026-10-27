import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  String _searchQuery = '';
  bool _lowStockOnly = false;
  bool _hideZeroStock = false;
  final Set<String> _selectedProductIds = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);
    final profile = auth.currentProfile;
    final currency = profile?.currencySymbol ?? '₴';
    final tenantId = profile?.tenantId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已选 ${_selectedProductIds.length} 项')
            : const Text('商品管理'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.price_change_outlined),
              tooltip: '批量改价',
              onPressed: _selectedProductIds.isEmpty
                  ? null
                  : () => _showBatchPriceSheet(context, firestore, tenantId),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedProductIds.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '多选模式',
              onPressed: () {
                setState(() => _isSelectionMode = true);
              },
            ),
          ],
        ],
      ),
      drawer: const AppDrawer(currentRoute: 'products'),
      body: Column(
        children: [
          // Search & Filters bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '搜索商品名称 / SKU / 库位...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('低库存预警'),
                      selected: _lowStockOnly,
                      onSelected: (val) => setState(() => _lowStockOnly = val),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('隐藏零库存'),
                      selected: _hideZeroStock,
                      onSelected: (val) => setState(() => _hideZeroStock = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Products Stream
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: firestore.watchProducts(tenantId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var list = snapshot.data ?? [];

                // Filter logic
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  list = list.where((p) {
                    return p.name.toLowerCase().contains(q) ||
                        p.sku.toLowerCase().contains(q) ||
                        (p.location != null && p.location!.toLowerCase().contains(q));
                  }).toList();
                }

                if (_lowStockOnly) {
                  list = list.where((p) => p.quantity <= p.minStock).toList();
                }

                if (_hideZeroStock) {
                  list = list.where((p) => p.quantity > 0).toList();
                }

                if (list.isEmpty) {
                  return const Center(
                    child: Text('没有符合条件的商品', style: TextStyle(color: Colors.grey)),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.76,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final product = list[index];
                    final isSelected = _selectedProductIds.contains(product.id);

                    return GestureDetector(
                      onLongPress: () {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedProductIds.add(product.id);
                        });
                      },
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedProductIds.remove(product.id);
                            } else {
                              _selectedProductIds.add(product.id);
                            }
                          });
                        } else {
                          _showEditProductSheet(context, firestore, product, tenantId, auth.currentUser!.uid);
                        }
                      },
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.shade200,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cover Image
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                    ),
                                    child: product.imageUrl != null
                                        ? Image.network(
                                            product.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Colors.grey,
                                            ),
                                          )
                                        : const Icon(Icons.inventory_2, color: Colors.grey, size: 36),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "SKU: ${product.sku}",
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "$currency${product.price.toStringAsFixed(2)}",
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          _buildStockBadge(product.stockStatus),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "库存: ${product.quantity} ${product.unit}${product.unitsPerBox != null ? ' (${product.boxCount}箱+${product.looseCount}${product.unit})' : ''}",
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isSelectionMode)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          _showEditProductSheet(context, firestore, null, tenantId, auth.currentUser!.uid);
        },
      ),
    );
  }

  Widget _buildStockBadge(StockStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case StockStatus.outOfStock:
        bg = Colors.red.shade50;
        fg = Colors.red;
        label = '缺货';
        break;
      case StockStatus.lowStock:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        label = '低库存';
        break;
      case StockStatus.overflow:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        label = '溢出';
        break;
      case StockStatus.normal:
        bg = Colors.green.shade50;
        fg = Colors.green;
        label = '正常';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  // Add / Edit Product Sheet
  void _showEditProductSheet(
    BuildContext context,
    FirestoreService firestore,
    Product? product,
    String tenantId,
    String userId,
  ) {
    final isEdit = product != null;
    final skuController = TextEditingController(text: product?.sku ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toString() : '');
    final costController = TextEditingController(text: product != null ? product.cost.toString() : '');
    final unitController = TextEditingController(text: product?.unit ?? '件');
    final unitsPerBoxController = TextEditingController(
      text: product?.unitsPerBox != null ? product!.unitsPerBox.toString() : '',
    );
    final boxPriceController = TextEditingController(
      text: product?.boxPrice != null ? product!.boxPrice.toString() : '',
    );
    final quantityController = TextEditingController(
      text: product != null ? product.quantity.toString() : '0',
    );
    final minStockController = TextEditingController(
      text: product != null ? product.minStock.toString() : '0',
    );
    final maxStockController = TextEditingController(
      text: product != null ? product.maxStock.toString() : '1000',
    );
    final locationController = TextEditingController(text: product?.location ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? '编辑商品' : '新建商品',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (isEdit)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await firestore.softDeleteProduct(product.id);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: skuController,
                  decoration: const InputDecoration(labelText: '商品编码 (SKU，租户内唯一) *', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '商品名称 *', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        decoration: const InputDecoration(labelText: '销售单价 *', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: costController,
                        decoration: const InputDecoration(labelText: '进货成本 *', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unitController,
                        decoration: const InputDecoration(labelText: '基本单位 *', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: unitsPerBoxController,
                        decoration: const InputDecoration(labelText: '每箱件数 (选填)', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: boxPriceController,
                        decoration: const InputDecoration(labelText: '整箱售价 (选填)', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantityController,
                        decoration: const InputDecoration(labelText: '当前库存 *', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minStockController,
                        decoration: const InputDecoration(labelText: '缺货预警阈值', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxStockController,
                        decoration: const InputDecoration(labelText: '溢出上限阈值', isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: '仓储库位 (如 A区-3)', isDense: true),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () async {
                    if (skuController.text.trim().isEmpty || nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请填写必填的 SKU 和商品名称')),
                      );
                      return;
                    }

                    try {
                      final p = Product(
                        id: product?.id ?? const Uuid().v4(),
                        tenantId: tenantId,
                        sku: skuController.text.trim(),
                        name: nameController.text.trim(),
                        price: double.tryParse(priceController.text) ?? 0.0,
                        cost: double.tryParse(costController.text) ?? 0.0,
                        unit: unitController.text.trim().isNotEmpty ? unitController.text.trim() : '件',
                        unitsPerBox: int.tryParse(unitsPerBoxController.text),
                        boxPrice: double.tryParse(boxPriceController.text),
                        quantity: int.tryParse(quantityController.text) ?? 0,
                        minStock: int.tryParse(minStockController.text) ?? 0,
                        maxStock: int.tryParse(maxStockController.text) ?? 1000,
                        location: locationController.text.trim(),
                        createdBy: userId,
                        createdAt: product?.createdAt ?? DateTime.now(),
                        updatedAt: DateTime.now(),
                      );

                      if (isEdit) {
                        await firestore.updateProduct(p);
                      } else {
                        await firestore.createProduct(p);
                      }
                      Navigator.pop(ctx);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  child: Text(isEdit ? '保存修改' : '确认新增'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Batch Price Sheet
  void _showBatchPriceSheet(BuildContext context, FirestoreService firestore, String tenantId) {
    String mode = 'percent';
    final valueController = TextEditingController();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('批量改价', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: mode,
                    decoration: const InputDecoration(labelText: '改价方式', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'percent', child: Text('按现售价比例 (+/- 百分比)')),
                      DropdownMenuItem(value: 'markup_cost', child: Text('基于成本加价 (+/- 百分比)')),
                      DropdownMenuItem(value: 'amount', child: Text('按固定金额增减 (+/- 元)')),
                      DropdownMenuItem(value: 'set', child: Text('统一设置为指定价格')),
                    ],
                    onChanged: (val) => setSheetState(() => mode = val!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueController,
                    decoration: InputDecoration(
                      labelText: mode == 'set' || mode == 'amount' ? '调整值 (金额)' : '调整百分比 (如 10 代表上浮 10%)',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () async {
                      final val = double.tryParse(valueController.text);
                      if (val == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效数字')),
                        );
                        return;
                      }
                      await firestore.batchPriceUpdate(
                        tenantId: tenantId,
                        productIds: _selectedProductIds.toList(),
                        mode: mode,
                        value: val,
                      );
                      setState(() {
                        _isSelectionMode = false;
                        _selectedProductIds.clear();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('执行批量调整'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
