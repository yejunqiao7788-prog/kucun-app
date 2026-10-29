import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/l10n.dart';
import '../tokens.dart';
import 'controls.dart';
import 'sheets.dart';
import 'surfaces.dart';

Future<void> showWebSubscriptionGuide(
  BuildContext context, {
  required L10n l10n,
  required String email,
}) async {
  final Uri url = Uri.parse('${Env.consoleBase}/app/settings');

  await showDrawer<void>(
    context,
    title: l10n.setPayWebTitle,
    accent: AppInk.finance,
    maxHeightFactor: 0.58,
    builder: (BuildContext sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.setPayWebBody, style: Theme.of(context).textTheme.bodyMedium),
        const VGap(10),
        Text(
          l10n.setPayWebAccount(email),
          style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
        ),
        const VGap(8),
        SelectableText(
          url.toString(),
          style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
        ),
        const VGap(16),
        PrimaryButton(
          label: l10n.setPayWebOpen,
          icon: Icons.open_in_new_rounded,
          color: AppInk.finance,
          onPressed: () async {
            Navigator.of(sheetContext).pop();
            if (await _launchExternal(url)) {
              if (!context.mounted) return;
              showToast(context, l10n.setPayWebHint);
              return;
            }
            await _copy(url);
            if (!context.mounted) return;
            showToast(context, l10n.setPayWebCopied);
          },
        ),
        const VGap(8),
        GhostButton(
          label: l10n.actCopy,
          icon: Icons.copy_rounded,
          color: AppInk.finance,
          onPressed: () async {
            await _copy(url);
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            if (!context.mounted) return;
            showToast(context, l10n.setPayWebCopied);
          },
        ),
      ],
    ),
  );
}

Future<bool> _launchExternal(Uri url) async {
  try {
    return await canLaunchUrl(url) &&
        await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

Future<void> _copy(Uri url) =>
    Clipboard.setData(ClipboardData(text: url.toString()));
