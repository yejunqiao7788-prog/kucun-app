import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/orders/order_list_screen.dart';
import '../screens/finance/finance_screen.dart';
import '../screens/settings/settings_screen.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final profile = authService.currentProfile;

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                (profile?.username.isNotEmpty == true ? profile!.username[0] : 'U').toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
            accountName: Row(
              children: [
                Text(profile?.username ?? '用户'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    profile?.role ?? 'user',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            accountEmail: Text("${profile?.tenantName ?? '租户'} · ${profile?.email ?? ''}"),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  title: '工作台',
                  route: 'dashboard',
                  visible: profile?.canOpenModule('dashboard') ?? true,
                  onTap: () => _navigate(context, const DashboardScreen()),
                ),
                _buildItem(
                  context,
                  icon: Icons.inventory_2_outlined,
                  title: '商品管理',
                  route: 'products',
                  visible: profile?.canOpenModule('products') ?? true,
                  onTap: () => _navigate(context, const ProductListScreen()),
                ),
                _buildItem(
                  context,
                  icon: Icons.warehouse_outlined,
                  title: '库存盘点',
                  route: 'inventory',
                  visible: profile?.canOpenModule('inventory') ?? true,
                  onTap: () => _navigate(context, const InventoryScreen()),
                ),
                _buildItem(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: '订单管理',
                  route: 'orders',
                  visible: profile?.canOpenModule('orders') ?? true,
                  onTap: () => _navigate(context, const OrderListScreen()),
                ),
                _buildItem(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  title: '财务中心',
                  route: 'finance',
                  visible: profile?.canOpenModule('finance') ?? true,
                  onTap: () => _navigate(context, const FinanceScreen()),
                ),
                const Divider(),
                _buildItem(
                  context,
                  icon: Icons.settings_outlined,
                  title: '系统设置',
                  route: 'settings',
                  visible: true, // Always accessible
                  onTap: () => _navigate(context, const SettingsScreen()),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              await authService.signOut();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    required bool visible,
    required VoidCallback onTap,
  }) {
    if (!visible) return const SizedBox.shrink();

    final isSelected = currentRoute == route;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).primaryColor : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).primaryColor : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        Navigator.pop(context);
        if (!isSelected) {
          onTap();
        }
      },
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
