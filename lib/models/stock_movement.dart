import 'package:cloud_firestore/cloud_firestore.dart';

class StockMovement {
  final String id;
  final String tenantId;
  final String productId;
  final String productName;
  final String sku;
  final String? orderId;
  final int delta;
  final int quantityAfter;
  final String movementType; // 'inbound' | 'outbound' | 'manual_adjust' | 'import'
  final String createdBy;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.productName,
    required this.sku,
    this.orderId,
    required this.delta,
    required this.quantityAfter,
    required this.movementType,
    required this.createdBy,
    required this.createdAt,
  });

  factory StockMovement.fromFirestore(Map<String, dynamic> data, String id) {
    return StockMovement(
      id: id,
      tenantId: data['tenant_id'] ?? '',
      productId: data['product_id'] ?? '',
      productName: data['product_name'] ?? '',
      sku: data['sku'] ?? '',
      orderId: data['order_id'],
      delta: (data['delta'] as num?)?.toInt() ?? 0,
      quantityAfter: (data['quantity_after'] as num?)?.toInt() ?? 0,
      movementType: data['movement_type'] ?? 'manual_adjust',
      createdBy: data['created_by'] ?? '',
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'product_id': productId,
      'product_name': productName,
      'sku': sku,
      'order_id': orderId,
      'delta': delta,
      'quantity_after': quantityAfter,
      'movement_type': movementType,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}
