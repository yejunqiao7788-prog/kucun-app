import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String tenantId;
  final String name;
  final String? phone;
  final String? address;
  final double debtAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.tenantId,
    required this.name,
    this.phone,
    this.address,
    this.debtAmount = 0.0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Customer.fromFirestore(Map<String, dynamic> data, String id) {
    return Customer(
      id: id,
      tenantId: data['tenant_id'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'],
      address: data['address'],
      debtAmount: (data['debt_amount'] as num?)?.toDouble() ?? 0.0,
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
      'name': name,
      'phone': phone,
      'address': address,
      'debt_amount': debtAmount,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }
}
