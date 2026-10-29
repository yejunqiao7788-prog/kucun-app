import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/env.dart';
import '../../core/l10n.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import 'invite_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '${l10n.authEmail} · ${l10n.authPassword}');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.signIn(email: _email.text, password: _password.text);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.isUnauthorized ? l10n.authSignedOutElsewhere : error.display);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = app.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    if (_email.text.trim().isEmpty) {
      setState(() => _error = l10n.authEmail);
      return;
    }
    try {
      await app.sendPasswordReset(_email.text);
      if (mounted) showToast(context, l10n.authResetSent);
    } on Object catch (error) {
      if (mounted) setState(() => _error = app.describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    child: Image(
                      image: AssetImage('assets/brand/app_icon.png'),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const HGap(10),
                  Text(Env.appName,
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const VGap(28),
              Text(l10n.authWelcome,
                  style: Theme.of(context).textTheme.displaySmall),
              const VGap(24),
              AppTextField(
                label: l10n.authEmail,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const VGap(14),
              AppTextField(
                label: l10n.authPassword,
                controller: _password,
                obscure: _obscure,
                textInputAction: TextInputAction.done,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              if (_error != null) ...<Widget>[
                const VGap(14),
                NoticeBanner(text: _error!, color: AppInk.danger, icon: Icons.error_outline_rounded),
              ],
              const VGap(22),
              PrimaryButton(label: l10n.authSignIn, loading: _busy, onPressed: _submit),
              const VGap(6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextAction(label: l10n.authForgot, onPressed: _forgot),
                  TextAction(
                    label: l10n.authHaveCode,
                    onPressed: () => pushSheet<void>(context, child: const InviteScreen()),
                  ),
                ],
              ),
              const VGap(10),
              AppCard(
                accent: AppInk.success,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.authRegister, style: Theme.of(context).textTheme.titleMedium),
                    const VGap(4),
                    Text(l10n.authRegisterHint, style: Theme.of(context).textTheme.bodySmall),
                    const VGap(12),
                    PrimaryButton(
                      label: l10n.authRegister,
                      color: AppInk.success,
                      expanded: false,
                      onPressed: () => pushSheet<void>(context, child: const RegisterScreen()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
