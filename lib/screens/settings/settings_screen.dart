import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _feedbackController = TextEditingController();
  String _feedbackCategory = 'suggestion';

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);
    final profile = auth.currentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统设置'),
      ),
      drawer: const AppDrawer(currentRoute: 'settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        child: Text(
                          (profile?.username.isNotEmpty == true ? profile!.username[0] : 'U').toUpperCase(),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.username ?? '用户',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              profile?.email ?? '',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "角色: ${profile?.role ?? 'user'}",
                                style: TextStyle(color: Colors.blue.shade800, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildProfileRow('当前租户', profile?.tenantName ?? '未命名'),
                  _buildProfileRow('租户编号', profile?.tenantId ?? ''),
                  _buildProfileRow('结算货币符号', profile?.currencySymbol ?? '₴'),
                  _buildProfileRow(
                    '订阅状态',
                    profile?.subscriptionExpired == true ? '已到期' : '有效 (${profile?.subscriptionStatus})',
                    valueColor: profile?.subscriptionExpired == true ? Colors.red : Colors.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Feedback Section (Available even if subscription expired!)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.feedback_outlined, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('意见反馈与工单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '即使租户订阅已到期，此反馈通道依然永久畅通。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _feedbackCategory,
                    decoration: const InputDecoration(labelText: '反馈分类', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'suggestion', child: Text('功能建议')),
                      DropdownMenuItem(value: 'bug', child: Text('缺陷报告 (Bug)')),
                      DropdownMenuItem(value: 'billing', child: Text('续费与账单')),
                      DropdownMenuItem(value: 'marketplace', child: Text('集市咨询')),
                      DropdownMenuItem(value: 'other', child: Text('其他问题')),
                    ],
                    onChanged: (val) => setState(() => _feedbackCategory = val!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _feedbackController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '请详细描述您遇到的问题或建议 (5-2000字)...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final text = _feedbackController.text.trim();
                      if (text.length < 5) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('反馈内容至少输入 5 个字')),
                        );
                        return;
                      }

                      await firestore.submitFeedback(
                        tenantId: profile?.tenantId ?? '',
                        category: _feedbackCategory,
                        content: text,
                        userId: auth.currentUser!.uid,
                      );

                      _feedbackController.clear();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('反馈提交成功，客服将尽快核实处理')),
                        );
                      }
                    },
                    child: const Text('提交反馈'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Logout Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                await auth.signOut();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: valueColor),
          ),
        ],
      ),
    );
  }
}
