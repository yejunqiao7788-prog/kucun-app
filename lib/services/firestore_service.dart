import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/customer.dart';

class DashboardStats {
  final int totalProducts;
  final int totalStock;
  final int lowStock;
  final int inboundToday;
  final int outboundToday;
  final int inboundQtyToday;
  final int outboundQtyToday;
  final double totalValue;

  DashboardStats({
    required this.totalProducts,
    required this.totalStock,
    required this.lowStock,
    required this.inboundToday,
    required this.outboundToday,
    required this.inboundQtyToday,
    required this.outboundQtyToday,
    required this.totalValue,
  });

  factory DashboardStats.empty() {
    return DashboardStats(
      totalProducts: 0,
      totalStock: 0,
      lowStock: 0,
      inboundToday: 0,
      outboundToday: 0,
      inboundQtyToday: 0,
      outboundQtyToday: 0,
      totalValue: 0.0,
    );
  }
}

class FinanceStats {
  final double totalRevenue;
  final double totalCost;
  final double grossProfit;
  final double totalReceivable;
  final double totalPaid;
  final double totalUnpaid;

  FinanceStats({
    required this.totalRevenue,
    required this.totalCost,
    required this.grossProfit,
    required this.totalReceivable,
    required this.totalPaid,
    required this.totalUnpaid,
  });
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // 1. Dashboard
  // ---------------------------------------------------------------------------

  Future<DashboardStats> getDashboardStats(String tenantId) async {
    try {
      // 1. Products metrics
      final productsSnap = await _db
          .collection('products')
          .where('tenant_id', isEqualTo: tenantId)
          .where('deleted_at', isNull: true)
          .get();

      int totalProducts = productsSnap.docs.length;
      int totalStock = 0;
      int lowStock = 0;
      double totalValue = 0.0;

      for (var doc in productsSnap.docs) {
        final p = Product.fromFirestore(doc.data(), doc.id);
        totalStock += p.quantity;
        if (p.quantity <= p.minStock) {
          lowStock++;
        }
        totalValue += (p.quantity * p.price);
      }

      // 2. Orders today
      final now = DateTime.now();
      final todayStr = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final ordersSnap = await _db
          .collection('orders')
          .where('tenant_id', isEqualTo: tenantId)
          .where('order_date', isEqualTo: todayStr)
          .where('status', isEqualTo: 'completed')
          .get();

      int inboundToday = 0;
      int outboundToday = 0;
      int inboundQtyToday = 0;
      int outboundQtyToday = 0;

      for (var doc in ordersSnap.docs) {
        final o = OrderModel.fromFirestore(doc.data(), doc.id);
        if (o.type == 'inbound') {
          inboundToday++;
          inboundQtyToday += o.totalQuantity;
        } else if (o.type == 'outbound') {
          outboundToday++;
          outboundQtyToday += o.totalQuantity;
        }
      }

      return DashboardStats(
        totalProducts: totalProducts,
        totalStock: totalStock,
        lowStock: lowStock,
        inboundToday: inboundToday,
        outboundToday: outboundToday,
        inboundQtyToday: inboundQtyToday,
        outboundQtyToday: outboundQtyToday,
        totalValue: totalValue,
      );
    } catch (e) {
      debugPrint("Error getting dashboard stats: $e");
      return DashboardStats.empty();
    }
  }

  Stream<List<OrderModel>> watchRecentOrders(String tenantId, bool isManager) {
    final now = DateTime.now();
    final todayStr = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    Query query = _db
        .collection('orders')
        .where('tenant_id', isEqualTo: tenantId)
        .where('order_date', isEqualTo: todayStr);

    if (!isManager) {
      query = query.where('is_preparing', isEqualTo: true);
    }

    return query.limit(50).snapshots().map((snap) {
      return snap.docs
          .map((d) => OrderModel.fromFirestore(d.data() as Map<String, dynamic>, d.id))
          .toList();
    });
  }

  Stream<List<OrderModel>> watchPickingList(String tenantId) {
    return _db
        .collection('orders')
        .where('tenant_id', isEqualTo: tenantId)
        .where('show_in_picking_list', isEqualTo: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => OrderModel.fromFirestore(d.data() as Map<String, dynamic>, d.id))
          .toList();
    });
  }

  // ---------------------------------------------------------------------------
  // 2. Products & Inventory
  // ---------------------------------------------------------------------------

  Stream<List<Product>> watchProducts(String tenantId) {
    return _db
        .collection('products')
        .where('tenant_id', isEqualTo: tenantId)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => Product.fromFirestore(d.data(), d.id))
          .where((p) => p.deletedAt == null)
          .toList();
    });
  }

  Future<void> createProduct(Product product) async {
    // Check SKU uniqueness in tenant
    final existing = await _db
        .collection('products')
        .where('tenant_id', isEqualTo: product.tenantId)
        .where('sku', isEqualTo: product.sku)
        .where('deleted_at', isNull: true)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('DUPLICATE_SKU: 商品编码(SKU) "${product.sku}" 在当前租户内已存在');
    }

    final id = product.id.isEmpty ? _uuid.v4() : product.id;
    await _db.collection('products').doc(id).set(product.toFirestore());

    // Record initial stock if > 0
    if (product.quantity > 0) {
      final movementId = _uuid.v4();
      final movement = StockMovement(
        id: movementId,
        tenantId: product.tenantId,
        productId: id,
        productName: product.name,
        sku: product.sku,
        delta: product.quantity,
        quantityAfter: product.quantity,
        movementType: 'inbound',
        createdBy: product.createdBy,
        createdAt: DateTime.now(),
      );
      await _db.collection('stock_movements').doc(movementId).set(movement.toFirestore());
    }
  }

  Future<void> updateProduct(Product product) async {
    // Check SKU conflict with other products
    final existing = await _db
        .collection('products')
        .where('tenant_id', isEqualTo: product.tenantId)
        .where('sku', isEqualTo: product.sku)
        .where('deleted_at', isNull: true)
        .get();

    for (var doc in existing.docs) {
      if (doc.id != product.id) {
        throw Exception('DUPLICATE_SKU: 商品编码(SKU) "${product.sku}" 已被其他商品占用');
      }
    }

    await _db.collection('products').doc(product.id).update(product.toFirestore());
  }

  Future<void> softDeleteProduct(String productId) async {
    await _db.collection('products').doc(productId).update({
      'deleted_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> adjustStock({
    required String productId,
    required String tenantId,
    required int newQuantity,
    required String userId,
    String? reason,
  }) async {
    final docRef = _db.collection('products').doc(productId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception('NOT_FOUND: 商品不存在');
      }

      final p = Product.fromFirestore(snapshot.data()!, snapshot.id);
      final delta = newQuantity - p.quantity;

      transaction.update(docRef, {
        'quantity': newQuantity,
        'updated_at': FieldValue.serverTimestamp(),
      });

      final movementId = _uuid.v4();
      final movement = StockMovement(
        id: movementId,
        tenantId: tenantId,
        productId: productId,
        productName: p.name,
        sku: p.sku,
        delta: delta,
        quantityAfter: newQuantity,
        movementType: 'manual_adjust',
        createdBy: userId,
        createdAt: DateTime.now(),
      );

      transaction.set(_db.collection('stock_movements').doc(movementId), movement.toFirestore());
    });
  }

  Future<void> batchPriceUpdate({
    required String tenantId,
    required List<String> productIds,
    required String mode, // 'set' | 'markup_cost' | 'percent' | 'amount'
    required double value,
  }) async {
    final batch = _db.batch();
    for (String id in productIds) {
      final docRef = _db.collection('products').doc(id);
      final doc = await docRef.get();
      if (!doc.exists) continue;

      final p = Product.fromFirestore(doc.data()!, doc.id);
      double newPrice = p.price;

      switch (mode) {
        case 'set':
          newPrice = value;
          break;
        case 'markup_cost':
          newPrice = p.cost * (1 + value / 100);
          break;
        case 'percent':
          newPrice = p.price * (1 + value / 100);
          break;
        case 'amount':
          newPrice = p.price + value;
          break;
      }

      if (newPrice < 0) newPrice = 0;
      batch.update(docRef, {
        'price': double.parse(newPrice.toStringAsFixed(2)),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // 3. Orders
  // ---------------------------------------------------------------------------

  Stream<List<OrderModel>> watchOrders(String tenantId, {String? type, String? status}) {
    Query query = _db.collection('orders').where('tenant_id', isEqualTo: tenantId);
    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type);
    }
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots().map((snap) {
      return snap.docs
          .map((d) => OrderModel.fromFirestore(d.data() as Map<String, dynamic>, d.id))
          .toList();
    });
  }

  Future<void> createOrderDraft(OrderModel order) async {
    final id = order.id.isEmpty ? _uuid.v4() : order.id;
    await _db.collection('orders').doc(id).set(order.toFirestore());
  }

  Future<void> deleteOrderDraft(String orderId) async {
    final docRef = _db.collection('orders').doc(orderId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final o = OrderModel.fromFirestore(doc.data()!, doc.id);
    if (o.status != 'pending') {
      throw Exception('FORBIDDEN: 只有草稿态订单允许删除');
    }
    await docRef.delete();
  }

  Future<void> togglePickingList(String orderId, bool show) async {
    await _db.collection('orders').doc(orderId).update({
      'show_in_picking_list': show,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Atomic Finalize Order Transaction:
  /// Verifies stock availability for all items.
  /// If any item insufficient -> rollbacks entire order with detailed error:
  /// "库存不足：[商品名] / [SKU]（需要 N，现有 M）"
  Future<void> finalizeOrder({
    required String orderId,
    required String tenantId,
    required String userId,
  }) async {
    final orderRef = _db.collection('orders').doc(orderId);

    await _db.runTransaction((transaction) async {
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) {
        throw Exception('NOT_FOUND: 订单不存在');
      }

      final order = OrderModel.fromFirestore(orderSnap.data()!, orderSnap.id);
      if (order.status == 'completed') {
        throw Exception('ORDER_ALREADY_FINALIZED: 订单已经定稿，不可重复操作');
      }

      // Check stock for each product
      Map<String, Product> productSnapshots = {};
      for (var item in order.items) {
        final pRef = _db.collection('products').doc(item.productId);
        final pSnap = await transaction.get(pRef);
        if (!pSnap.exists) {
          throw Exception('NOT_FOUND: 商品 ${item.productName} 不存在');
        }

        final p = Product.fromFirestore(pSnap.data()!, pSnap.id);
        productSnapshots[item.productId] = p;

        if (order.type == 'outbound') {
          if (p.quantity < item.quantity) {
            throw Exception(
              '库存不足：${p.name} / ${p.sku}（需要 ${item.quantity}，现有 ${p.quantity}）',
            );
          }
        }
      }

      // If all products valid, update inventory & append stock movements
      for (var item in order.items) {
        final p = productSnapshots[item.productId]!;
        final pRef = _db.collection('products').doc(item.productId);

        int newQty = p.quantity;
        int delta = 0;

        if (order.type == 'outbound') {
          newQty -= item.quantity;
          delta = -item.quantity;
        } else if (order.type == 'inbound') {
          newQty += item.quantity;
          delta = item.quantity;
        }

        transaction.update(pRef, {
          'quantity': newQty,
          'updated_at': FieldValue.serverTimestamp(),
        });

        final movementId = _uuid.v4();
        final movement = StockMovement(
          id: movementId,
          tenantId: tenantId,
          productId: p.id,
          productName: p.name,
          sku: p.sku,
          orderId: orderId,
          delta: delta,
          quantityAfter: newQty,
          movementType: order.type,
          createdBy: userId,
          createdAt: DateTime.now(),
        );

        transaction.set(
          _db.collection('stock_movements').doc(movementId),
          movement.toFirestore(),
        );
      }

      // Mark order completed and keep picking list updated
      transaction.update(orderRef, {
        'status': 'completed',
        'completed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 4. Finance
  // ---------------------------------------------------------------------------

  Future<FinanceStats> getFinanceStats(String tenantId) async {
    final ordersSnap = await _db
        .collection('orders')
        .where('tenant_id', isEqualTo: tenantId)
        .where('type', isEqualTo: 'outbound')
        .where('status', isEqualTo: 'completed')
        .get();

    double revenue = 0.0;
    double cost = 0.0;
    double payable = 0.0;
    double paid = 0.0;

    for (var doc in ordersSnap.docs) {
      final o = OrderModel.fromFirestore(doc.data(), doc.id);
      revenue += o.totalAmount;
      payable += o.payableAmount;
      paid += o.paidAmount;

      for (var item in o.items) {
        // Profit is calculated from snapshot unit_cost!
        cost += (item.unitCost * item.quantity);
      }
    }

    return FinanceStats(
      totalRevenue: revenue,
      totalCost: cost,
      grossProfit: revenue - cost,
      totalReceivable: payable,
      totalPaid: paid,
      totalUnpaid: (payable - paid) > 0 ? (payable - paid) : 0.0,
    );
  }

  // Settle debt from oldest unpaid order
  Future<void> settleCustomerDebt({
    required String tenantId,
    required String customerId,
    required double settleAmount,
  }) async {
    final unpaidOrdersSnap = await _db
        .collection('orders')
        .where('tenant_id', isEqualTo: tenantId)
        .where('customer_id', isEqualTo: customerId)
        .where('status', isEqualTo: 'completed')
        .where('payment_status', whereIn: ['unpaid', 'partial'])
        .orderBy('created_at', descending: false)
        .get();

    double remainingSettle = settleAmount;
    final batch = _db.batch();

    for (var doc in unpaidOrdersSnap.docs) {
      if (remainingSettle <= 0) break;
      final o = OrderModel.fromFirestore(doc.data(), doc.id);
      double unpaid = o.payableAmount - o.paidAmount;
      if (unpaid <= 0) continue;

      double toPay = remainingSettle >= unpaid ? unpaid : remainingSettle;
      double newPaid = o.paidAmount + toPay;
      String newStatus = (newPaid >= o.payableAmount) ? 'paid' : 'partial';

      batch.update(doc.reference, {
        'paid_amount': newPaid,
        'payment_status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });

      remainingSettle -= toPay;
    }

    // Update customer debt balance
    final customerRef = _db.collection('customers').doc(customerId);
    final customerSnap = await customerRef.get();
    if (customerSnap.exists) {
      final c = Customer.fromFirestore(customerSnap.data()!, customerSnap.id);
      double newDebt = c.debtAmount - settleAmount;
      if (newDebt < 0) newDebt = 0;
      batch.update(customerRef, {
        'debt_amount': newDebt,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // 5. Customers & Feedback
  // ---------------------------------------------------------------------------

  Stream<List<Customer>> watchCustomers(String tenantId) {
    return _db
        .collection('customers')
        .where('tenant_id', isEqualTo: tenantId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Customer.fromFirestore(d.data(), d.id)).toList());
  }

  Future<void> createCustomer(Customer customer) async {
    final id = customer.id.isEmpty ? _uuid.v4() : customer.id;
    await _db.collection('customers').doc(id).set(customer.toFirestore());
  }

  Future<void> submitFeedback({
    required String tenantId,
    required String category,
    required String content,
    required String userId,
  }) async {
    final id = _uuid.v4();
    await _db.collection('feedback').doc(id).set({
      'id': id,
      'tenant_id': tenantId,
      'category': category,
      'content': content,
      'created_by': userId,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
