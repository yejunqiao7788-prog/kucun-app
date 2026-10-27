import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String id;
  final String email;
  final String username;
  final String tenantId;
  final String tenantName;
  final DateTime? tenantExpiresAt;
  final String subscriptionStatus; // 'trial' | 'active' | 'expired'
  final bool subscriptionExpired;
  final String role; // 'admin' | 'tenant_admin' | 'user' | 'owner'
  final String status;
  final Map<String, bool> permissions;
  final String? avatarUrl;
  final String currencySymbol;

  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.tenantId,
    required this.tenantName,
    this.tenantExpiresAt,
    required this.subscriptionStatus,
    required this.subscriptionExpired,
    required this.role,
    required this.status,
    required this.permissions,
    this.avatarUrl,
    required this.currencySymbol,
  });

  bool hasPermission(String key) {
    if (role == 'super_admin' || role == 'admin') return true;
    if (subscriptionExpired) return false;
    return permissions[key] == true;
  }

  bool canOpenModule(String key) {
    if (key == 'settings') return true;
    if (key == 'showroom') return hasPermission('showrooms');
    if (key == 'ai') return hasPermission('ai');
    if (key == 'marketplace') {
      return ['admin', 'owner', 'tenant_admin'].contains(role);
    }
    return hasPermission(key);
  }

  factory UserProfile.fromFirestore(Map<String, dynamic> data, String id) {
    Map<String, bool> parsedPermissions = {};
    if (data['permissions'] is Map) {
      (data['permissions'] as Map).forEach((k, v) {
        parsedPermissions[k.toString()] = v == true;
      });
    }

    DateTime? expiresAt;
    if (data['tenant_expires_at'] is Timestamp) {
      expiresAt = (data['tenant_expires_at'] as Timestamp).toDate();
    } else if (data['tenant_expires_at'] is String) {
      expiresAt = DateTime.tryParse(data['tenant_expires_at']);
    }

    return UserProfile(
      id: id,
      email: data['email'] ?? '',
      username: data['username'] ?? '',
      tenantId: data['tenant_id'] ?? '',
      tenantName: data['tenant_name'] ?? '',
      tenantExpiresAt: expiresAt,
      subscriptionStatus: data['subscription_status'] ?? 'trial',
      subscriptionExpired: data['subscription_expired'] ?? false,
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'active',
      permissions: parsedPermissions,
      avatarUrl: data['avatar_url'],
      currencySymbol: data['currency_symbol'] ?? '₴',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': id,
      'email': email,
      'username': username,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      if (tenantExpiresAt != null)
        'tenant_expires_at': Timestamp.fromDate(tenantExpiresAt!),
      'subscription_status': subscriptionStatus,
      'subscription_expired': subscriptionExpired,
      'role': role,
      'status': status,
      'permissions': permissions,
      'avatar_url': avatarUrl,
      'currency_symbol': currencySymbol,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }
}
