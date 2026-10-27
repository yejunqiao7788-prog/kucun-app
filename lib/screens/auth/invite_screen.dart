import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../data/entities.dart';
import '../../state/app_state.dart';

/// 邀请链路两步：`/invitations/lookup` 确认码有效并显示租户名，
/// 再 `/invitations/register` 建账号并落到该租户（契约 §5.3）。
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  InvitationPreview? _invitation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = l10n.authCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _invitation = null;
    });
    try {
      final InvitationPreview found = await app.lookupInvitation(_code.text);
      if (mounted) setState(() => _invitation = found);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = app.describeError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final AppState app = context.read<AppState>();
    final L10n l10n = app.l10n;
    if (_email.text.trim().isEmpty) {
      setState(() => _error = l10n.authEmail);
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
      await app.registerByInvitation(
        code: _code.text,
        email: _email.text,
        password: _password.text,
        username: _username.text.isEmpty ? _email.text.split('@').first : _username.text,
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
      appBar: AppBar(title: Text(l10n.authHaveCode)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppTextField(label: l10n.authCode, controller: _code, autofocus: true),
              const VGap(12),
              PrimaryButton(
                label: l10n.authInviteLookup,
                color: AppInk.info,
                loading: _busy && _invitation == null,
                onPressed: _lookup,
              ),
              if (_invitation != null) ...<Widget>[
                const VGap(18),
                AppCard(
                  accent: AppInk.info,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _invitation!.tenantName.isEmpty
                            ? l10n.commonUnnamed
                            : _invitation!.tenantName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const VGap(10),
                      KeyValueRow(
                        label: l10n.setRole,
                        value: l10n.roleLabel(_invitation!.role),
                        accent: AppInk.info,
                      ),
                      if (_invitation!.expiresAt != null) ...<Widget>[
                        const VGap(10),
                        KeyValueRow(
                          label: l10n.shrExpires,
                          value: Fmt.date(_invitation!.expiresAt),
                          accent: AppInk.warning,
                        ),
                      ],
                    ],
                  ),
                ),
                const VGap(18),
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
                const VGap(22),
                PrimaryButton(label: l10n.authJoin, loading: _busy, onPressed: _join),
              ],
              if (_error != null) ...<Widget>[
                const VGap(16),
                NoticeBanner(text: _error!, color: AppInk.danger),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
