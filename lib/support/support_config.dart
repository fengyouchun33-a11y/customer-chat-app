/// Support SDK configuration (the only file integrators need to touch)
///
/// Contract mirrors keiyo-app/pages/support/supportWin.nvue:
/// call /api/open/conversation with AppID + AppKey to get the fixed chat URL,
/// then embed the returned chat_url (visitor H5 chat.html) in a WebView.
class SupportConfig {
  SupportConfig._();

  /// Support server (open API and visitor H5 share this origin)
  static const String apiBase = 'https://my.reflexassist.com';

  /// AppID of the "Agent Support" project (public identifier; it also appears
  /// in the anonymous fallback URL)
  static const String appId = 'd1fb6b6ffd6d4915';

  /// Project AppKey (server-side secret. Packing it into the app binary carries
  /// an unpacking risk, but it can only create/reuse the signed-in agent's own
  /// conversation; long term it should move to a self-hosted signing backend so
  /// the secret never ships with the client)
  static const String appKey = '9eaa7bbcbc2dcf353fef8ecb88316de1';

  /// Anonymous fallback link when the fixed conversation cannot be resolved
  /// (a new conversation on every entry; only guarantees a non-blank screen).
  /// require_info=0: the visitor H5 asks for a name/email by default, but agents
  /// here are already signed in, so the support entry must stay one tap away.
  static String get fallbackUrl =>
      '$apiBase/public/chat.html?appId=$appId&header=0&require_info=0';

  /// SDK refuses to start while AppID/AppKey are not configured
  static bool get isConfigured => appId.isNotEmpty && appKey.isNotEmpty;
}
