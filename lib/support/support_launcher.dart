import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'support_chat_page.dart';
import 'support_sdk.dart';

/// Shared "contact support" launcher used by the More tab.
///
/// Resolves the signed-in agent's fixed chat URL through the SDK (showing a
/// blocking loader), then pushes the WebView page. Kept here so both the entry
/// point and the SDK stay decoupled from any single page's state.
Future<void> openSupportChat(BuildContext context) async {
  final s = AppStrings.current;
  final admin = context.read<AppState>().admin;
  if (admin == null) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(s.supportLoading)),
        ],
      ),
    ),
  );

  String? url;
  try {
    url = await SupportSdk.instance.resolveChatUrl(admin);
  } catch (_) {
    // failures all surface through the url == null branch below
  }
  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss the loading dialog
  if (url == null) {
    showSnack(context, s.supportUnavailable, error: true);
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => SupportChatPage(url: url!)),
  );
}
