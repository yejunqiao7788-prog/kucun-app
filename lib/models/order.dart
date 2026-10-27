import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItem {
  final String? id;
  final String productId;
  final String productName;
  final String productSku;
  final int quantity; // base unit
  final double unitCost; // snapshot cost
  final double unitPrice; // blended unit price
  final double subtotal;
  final int? boxCount;
  final int? unitsPerBox;
  final String? categoryName;
  final String? imageUrl;

  OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.subtotal,
    this.boxCount,
    this.unitsPerBox,
    this.categoryName,
    this.imageUrl,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'],
      productId: map['product_id'] ?? '',
      productName: map['product_name'] ?? '',
      productSku: map['product_sku'] ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      boxCount: (map['box_count'] as num?)?.toInt(),
      unitsPerBox: (map['units_per_box'] as num?)?.toInt(),
      categoryName: map['category_name'],
      imageUrl: map['image_url'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_cost': unitCost,
      'unit_price': unitPrice,
      'subtotal': subtotal,
      'box_count': boxCount,
      'units_per_box': unitsPerBox,
      'category_name': categoryName,
      'image_url': imageUrl,
    };
  }
}

class OrderModel {
  final String id;
  final String tenantId;
  final String orderNumber;
  final String type; // 'inbound' | 'outbound'
  final String status; // 'pending' | 'completed'
  final String orderDate; // 'YYYY-MM-DD'
  final String? notes;
  final bool isPreparing;
  final bool showInPickingList;
  final String createdBy;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final List<OrderItem> items;
  final int totalQuantity;
  final double totalAmount;
  final double payableAmount;
  final double paidAmount;
  final String paymentStatus; // 'unpaid' | 'partial' | 'paid'
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrderModel({
    required this.id,
    required this.tenantId,
    required this.orderNumber,
    required this.type,
    required this.status,
    required this.orderDate,
    this.notes,
    this.isPreparing = false,
    this.showInPickingList = false,
    required this.createdBy,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    required this.payableAmount,
    required this.paidAmount,
    required this.paymentStatus,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderModel.fromFirestore(Map<String, dynamic> data, String id) {
    List<OrderItem> parsedItems = [];
    if (data['items'] is List) {
      parsedItems = (data['items'] as List)
          .map((item) => OrderItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    }

    return OrderModel(
      id: id,
      tenantId: data['tenant_id'] ?? '',
      orderNumber: data['order_number'] ?? '',
      type: data['type'] ?? 'outbound',
      status: data['status'] ?? 'pending',
      orderDate: data['order_date'] ?? '',
      notes: data['notes'],
      isPreparing: data['is_preparing'] ?? false,
      showInPickingList: data['show_in_picking_list'] ?? false,
      createdBy: data['created_by'] ?? '',
      customerId: data['customer_id'],
      customerName: data['customer_name'],
      customerPhone: data['customer_phone'],
      items: parsedItems,
      totalQuantity: (data['total_quantity'] as num?)?.toInt() ?? 0,
      totalAmount: (data['total_amount'] as num?)?.toDouble() ?? 0.0,
      payableAmount: (data['payable_amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (data['paid_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: data['payment_status'] ?? 'unpaid',
      completedAt: data['completed_at'] is Timestamp
          ? (data['completed_at'] as Timestamp).toDate()
          : null,
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updated_at'] is Timestamp
          ? (data['updated_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'order_number': orderNumber,
      'type': type,
      'status': status,
      'order_date': orderDate,
      'notes': notes,
      'is_preparing': isPreparing,
      'show_in_picking_list': showInPickingList,
      'created_by': createdBy,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'items': items.map((i) => i.toMap()).toList(),
      'total_quantity': totalQuantity,
      'total_amount': totalAmount,
      'payable_amount': payableAmount,
      'paid_amount': paidAmount,
      'payment_status': paymentStatus,
      if (completedAt != null) 'completed_at': Timestamp.fromDate(completedAt!),
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }
}
