import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// 自助注册新租户：`POST /register` 一次建租户 + 管理员，注册完直接登录。
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _tenant = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tenant.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    if (_tenant.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = '${l10n.authTenantName} · ${l10n.authEmail}');
      return;
    }
    if (AppState.passwordTooWeak(_password.text)) {
      setState(() => _error = l10n.authPasswordRule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.registerTenant(
        email: _email.text,
        password: _password.text,
        username: _username.text.isEmpty ? _email.text.split('@').first : _username.text,
        tenantName: _tenant.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = app.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.authRegister)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.authRegisterHint, style: Theme.of(context).textTheme.bodyMedium),
              const VGap(20),
              AppTextField(label: l10n.authTenantName, controller: _tenant, autofocus: true),
              const VGap(14),
              AppTextField(label: l10n.authUsername, controller: _username),
              const VGap(14),
              AppTextField(
                label: l10n.authEmail,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              ),
              const VGap(14),
              AppTextField(
                label: l10n.authPassword,
                controller: _password,
                obscure: true,
                hint: l10n.authPasswordRule,
              ),
              if (_error != null) ...<Widget>[
                const VGap(16),
                NoticeBanner(text: _error!, color: AppInk.danger),
              ],
              const VGap(24),
              PrimaryButton(label: l10n.actCreate, loading: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
