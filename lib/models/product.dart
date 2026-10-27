import 'package:cloud_firestore/cloud_firestore.dart';

enum StockStatus { outOfStock, lowStock, overflow, normal }

class Product {
  final String id;
  final String tenantId;
  final String sku;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final double price;
  final double cost;
  final String unit;
  final int? unitsPerBox; // null = no whole box sales
  final double? boxPrice;
  final String? description;
  final String? imageUrl;
  final List<String> imageUrls;
  final int quantity; // Base unit
  final int minStock;
  final int maxStock;
  final String? location;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Product({
    required this.id,
    required this.tenantId,
    required this.sku,
    required this.name,
    this.categoryId,
    this.categoryName,
    required this.price,
    required this.cost,
    required this.unit,
    this.unitsPerBox,
    this.boxPrice,
    this.description,
    this.imageUrl,
    this.imageUrls = const [],
    required this.quantity,
    this.minStock = 0,
    this.maxStock = 1000,
    this.location,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  StockStatus get stockStatus {
    if (quantity == 0) return StockStatus.outOfStock;
    if (quantity > 0 && quantity <= minStock) return StockStatus.lowStock;
    if (quantity >= maxStock * 0.95) return StockStatus.overflow;
    return StockStatus.normal;
  }

  int get boxCount => unitsPerBox != null && unitsPerBox! > 0 ? quantity ~/ unitsPerBox! : 0;
  int get looseCount => unitsPerBox != null && unitsPerBox! > 0 ? quantity % unitsPerBox! : quantity;

  factory Product.fromFirestore(Map<String, dynamic> data, String id) {
    List<String> urls = [];
    if (data['image_urls'] is List) {
      urls = List<String>.from(data['image_urls']);
    } else if (data['image_url'] != null && (data['image_url'] as String).isNotEmpty) {
      urls = [data['image_url'] as String];
    }

    return Product(
      id: id,
      tenantId: data['tenant_id'] ?? '',
      sku: data['sku'] ?? '',
      name: data['name'] ?? '',
      categoryId: data['category_id'],
      categoryName: data['category_name'],
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      unit: data['unit'] ?? '件',
      unitsPerBox: (data['units_per_box'] as num?)?.toInt(),
      boxPrice: (data['box_price'] as num?)?.toDouble(),
      description: data['description'],
      imageUrl: urls.isNotEmpty ? urls.first : null,
      imageUrls: urls,
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      minStock: (data['min_stock'] as num?)?.toInt() ?? 0,
      maxStock: (data['max_stock'] as num?)?.toInt() ?? 1000,
      location: data['location'],
      createdBy: data['created_by'] ?? '',
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updated_at'] is Timestamp
          ? (data['updated_at'] as Timestamp).toDate()
          : DateTime.now(),
      deletedAt: data['deleted_at'] is Timestamp
          ? (data['deleted_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'sku': sku,
      'name': name,
      'category_id': categoryId,
      'category_name': categoryName,
      'price': price,
      'cost': cost,
      'unit': unit,
      'units_per_box': unitsPerBox,
      'box_price': boxPrice,
      'description': description,
      'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
      'image_urls': imageUrls,
      'quantity': quantity,
      'min_stock': minStock,
      'max_stock': maxStock,
      'location': location,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      if (deletedAt != null) 'deleted_at': Timestamp.fromDate(deletedAt!),
    };
  }
}
