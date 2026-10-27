import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Email form
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Register form
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regTenantController = TextEditingController();

  // Phone form
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  String? _verificationId;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regUsernameController.dispose();
    _regTenantController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Brand Logo & Name
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.warehouse_rounded,
                      size: 44,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'torgseek 库存端',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '专业云端多租户进销存与仓储管理',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  if (auth.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey.shade700,
                      tabs: const [
                        Tab(text: '密码登录'),
                        Tab(text: '手机验证'),
                        Tab(text: '注册账号'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildEmailLoginForm(auth),
                        _buildPhoneLoginForm(auth),
                        _buildRegisterForm(auth),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或通过第三方登录', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Google Sign-In Button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    icon: Image.network(
                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                      height: 20,
                      width: 20,
                      errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
                    ),
                    label: const Text('使用 Google 账号登录', style: TextStyle(color: Colors.black87)),
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            await auth.signInWithGoogle();
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. Email Password Form
  Widget _buildEmailLoginForm(AuthService auth) {
    return Column(
      children: [
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: '登录邮箱',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: '登录密码',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: auth.isLoading
              ? null
              : () async {
                  if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入邮箱和密码')),
                    );
                    return;
                  }
                  await auth.signInWithEmail(
                    _emailController.text.trim(),
                    _passwordController.text,
                  );
                },
          child: auth.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('登 录', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  // 2. Phone Login Form
  Widget _buildPhoneLoginForm(AuthService auth) {
    return Column(
      children: [
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: '手机号码 (带国家区号，如 +86 / +380)',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        if (_codeSent)
          TextField(
            controller: _smsCodeController,
            decoration: const InputDecoration(
              labelText: '6位短信验证码',
              prefixIcon: Icon(Icons.sms_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: auth.isLoading
              ? null
              : () async {
                  if (!_codeSent) {
                    if (_phoneController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入有效手机号')),
                      );
                      return;
                    }
                    await auth.verifyPhone(
                      phoneNumber: _phoneController.text.trim(),
                      onCodeSent: (id, token) {
                        setState(() {
                          _verificationId = id;
                          _codeSent = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('短信验证码已发送')),
                        );
                      },
                      onVerificationFailed: (err) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('验证失败: $err')),
                        );
                      },
                      onAutoVerified: (cred) async {
                        // Auto-verified on Android
                      },
                    );
                  } else {
                    if (_smsCodeController.text.trim().isEmpty || _verificationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入短信验证码')),
                      );
                      return;
                    }
                    await auth.signInWithPhoneCode(
                      _verificationId!,
                      _smsCodeController.text.trim(),
                    );
                  }
                },
          child: auth.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(_codeSent ? '确认验证码并登录' : '发送验证码', style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  // 3. Register Form
  Widget _buildRegisterForm(AuthService auth) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: _regEmailController,
          decoration: const InputDecoration(
            labelText: '注册邮箱',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regPasswordController,
          decoration: const InputDecoration(
            labelText: '设置密码 (至少6位)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regUsernameController,
          decoration: const InputDecoration(
            labelText: '管理员姓名',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regTenantController,
          decoration: const InputDecoration(
            labelText: '租户/企业/店铺名称',
            prefixIcon: Icon(Icons.storefront_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: auth.isLoading
              ? null
              : () async {
                  if (_regEmailController.text.trim().isEmpty || _regPasswordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请填写完整的注册信息')),
                    );
                    return;
                  }
                  await auth.registerWithEmail(
                    _regEmailController.text.trim(),
                    _regPasswordController.text,
                    _regUsernameController.text.trim(),
                    _regTenantController.text.trim(),
                  );
                },
          child: auth.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('立即注册并开通租户', style: TextStyle(fontSize: 15)),
        ),
      ],
    );
  }
}
