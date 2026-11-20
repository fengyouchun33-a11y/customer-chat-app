# AI Customer Service App (Flutter)

Mobile agent workbench: conversation list, live chat, statistics, contacts and a
"More" page (preferences / built-in support / legal / about).

Used by tenant admins and platform super admins; after login you land directly
on the tabbed workbench (Conversations / Contacts / Stats / More).

## Features

### Login & tenant
- Password login `POST /api/admin/login`; token and identity persisted locally, no re-login after restart.
- **Platform super admins (`is_platform = 1`) must pick a tenant after login**
  before entering the workbench:
  - Tenant list from `GET /api/admin/tenant/options` (up to 200 entries; a search box appears beyond 8).
  - The choice is saved via `POST /api/admin/tenant/switch` as the "last used tenant" and sent as `X-Tenant-Id`.
  - The tenant can be switched at any time from the top-bar overflow menu; the whole workbench rebuilds against the new tenant.
- Regular members / tenant admins use the tenant from the login response directly.
- Server address is fixed to `https://my.reflexassist.com`; the app offers no way to change it. A `-401` response clears the local session and returns to the login page.

### Language / i18n
- 11 built-in languages: zh-CN, zh-TW, en, ja, ko, es, fr, de, pt, ru, ar (RTL for ar).
- Follows the system language on first launch; a manual choice (More → Help &
  Support → Language) is persisted to the server as `chat_admin.pref_lang` and
  follows the account across devices.
- Brand names (Reflex AI Support Cloud) stay English in all languages.

### Conversations tab
- Filters: status (all / active / needs human / closed), project, keyword search (350 ms debounce).
- Paging: first page of 20, "load more" at the bottom, auto-loads near the end of the list.
- Realtime: after login and tenant selection a single global socket (`/chat-ws`) is
  established; the server pushes `conv_updated` summaries per admin permission, so
  the list and the bottom badge update within seconds. A 5-second polling loop stays
  as a fallback.
- Unread badge: server-side `unread_total` (independent of filters, same source as the push `total_unread`).
- Row content: visitor avatar (initial letter on colored background), title, last message time, visitor ID · project, status pill, unread count, serving agent ("unassigned" when none).
- Agent online/offline: the "online / offline" pill at the top-right of the queue
  (visible only for `role = agent`) writes `chat_admin.online_status`;
  human-transfer assignment prefers online agents and only falls back to all
  on-duty agents when everyone is offline. Going offline affects new-session
  assignment only; already served sessions are untouched. Logging out sets offline automatically.

### Chat page
- Opened from a conversation; auto-scrolls to the latest message on entry (the API
  returns the most recent N; the lazily built list keeps correcting until truly pinned to the bottom).
- Realtime: reuses the single global socket — `join` the room on entry, `leave` on
  exit (event `new_msg`); 5-second polling as fallback, with request sequence numbers
  to prevent stale responses from overwriting. While scrolled back, incoming messages
  only show an "N new messages" pill without stealing the scroll position; double-tapping
  the title bar (conversation / visitor name) jumps back to the bottom.
- Bubbles:
  - Agent messages on the right (accent color), visitors on the left, AI messages carry an "AI" tag and outline, system messages centered.
  - Markdown rendering (rich text / links / lists returned by the server).
  - Translation: visitor and AI messages show the translation by default, agent messages the original; each message can be toggled "show original / show translation".
  - Form messages (`msg_type = form`) render as `[ Form ] #id`.
- Form data (`msg_type = form_data`): shown inline as a "submission N" card with selectable key-value rows; an "All form data" button above the reply box opens a bottom drawer aggregating every submission, newest first.
- Reply box: auto-growing 1–4 lines, disabled while sending; the left image button picks photos from the gallery (max 9 per message, 5 MB each);
  images upload first via `POST /api/admin/upload/image`, then travel with the text in the `images` field of
  `POST /api/admin/conversation/reply`, merged by the server into a single Markdown message; tapping an image in a bubble opens a full-size preview.
  Sending into a closed conversation reopens it automatically.
- Close / reopen conversation: `POST /api/admin/conversation/close|reopen`, with a confirmation step.
- Entering a conversation clears its server-side unread count (done by the messages API); the list refreshes silently on return.

### Contacts tab
- Tenant contacts with avatar / name / role; filter people by tags. No delete function by design.

### Stats tab
- Range: last 7 / 30 / 90 days; project filter (`GET /api/admin/project/options`).
- KPIs: conversations, AI answers, human-served conversations, knowledge base hit rate.
- Charts (`fl_chart`):
  - Line: daily conversations / AI answers.
  - Line: human-served conversations / human-transfer requests (dashed).
  - Bar: knowledge base retrievals / hits.
- Hot keywords (font size scaled by frequency), top knowledge entries (rank + progress bar + count).
- AI summary: `POST /api/admin/stats/summary`, generated on button press with up to 90 s wait; shows content, model, timestamp and quota hints.

### More tab
- Gradient account card (avatar/logo, nickname or account, company name).
- Preferences: auto-translate and message-sound switches (moved out of the old top-bar overflow menu).
- Help & support: contact support (embedded agent-side support chat via the SDK in `lib/support/`), language picker.
- Legal: privacy policy and terms of service (open `reflexassist.com` pages in the system browser).
- About: official website, app version; single-line footer brand "Reflex AI Support Cloud".
- The top-bar overflow menu now only keeps tenant switching (platform admins) and logout.

### Realtime & notifications (L1 / L2 / L3)

Three layers, each covering a different gap; failure of any layer never loses messages:

- **L1 global socket (live refresh)**
  - One socket (`/chat-ws`) per login + tenant; after `identify` the server joins the `admin_{id}` room.
    Whenever a permitted conversation gets a visitor message, only permitted admins receive `conv_updated` (unread count, preview, message id).
  - Conversation list and bottom badge refresh within seconds; the chat page reuses the same connection to join rooms instead of opening its own.
  - With multiple server workers, the Egg messenger relays between them transparently for clients.
- **L2 Android background keep-alive**
  - `flutter_foreground_task` foreground service (persistent "agent online" notification + `remoteMessaging` type, holds `WAKE_LOCK` / Wi-Fi lock).
  - The task isolate keeps its own socket, so summaries still arrive instantly in the background; while the socket is healthy the 15 s polling degrades to a 60 s self-check,
    reconnecting instantly restores full 15 s polling; token/tenant changes rebuild the connection automatically.
  - Users are guided to disable battery optimization and allow autostart; after a system or manual force-stop the app must be opened again.
- **L3 system push (survives process kill)**
  - Server side: Android via FCM HTTP v1; iOS connects APNs directly (not through FCM; the two credential sets are independent).
  - After login the app registers the device token via `POST /api/admin/push/register`, and `POST /api/admin/push/unregister` on logout / account switch.
  - Visitor messages trigger system notifications, merged per conversation (Android `tag` / `collapse_key`, iOS `thread-id`);
    no banner in the foreground (the socket refreshes live); tapping a notification deep-links to the conversation (works on cold start too).
  - When FCM is registered the background keep-alive no longer duplicates local notifications; without Firebase config it automatically falls back to local notifications.
- **Skip push while online (system push only covers "can't pop live")**
  - Without coordination the same visitor message would show a live banner and then a FCM/APNs notification. The server now checks the online heartbeat first and pushes only to admins who genuinely cannot pop at that moment (socket summaries always go out).
  - "Online" means truly able to pop: app in foreground (page pops its own banner + sound) or an admin web tab visible. The background keep-alive isolate does **not** count (it hands reminders to system push anyway).
  - Clients renew the heartbeat every 15 s (immediately on foreground/background switch), stored in `chat_admin_presence`;
    the server only trusts freshness within 45 s (same window as the L2 zombie-connection check). Process kill / network loss / frozen tab simply stop renewing and time out to offline.
  - Every failure path favors "one extra push over a missed one": missing table, query error or dropped connection are all treated as offline.
    To rule out this gate when debugging, disable it with `PUSH_SKIP_ONLINE=0` (window tunable via `PUSH_PRESENCE_TTL_SEC`).
  - The admin web therefore also starts `identify` (it used to only join rooms, with list badges relying purely on polling) and gets `conv_updated` live refresh for free.
- **Notification scope**: the server computes permitted admins per tenant + `admin.project_ids` and pushes summaries/notifications only to them;
  an agent's own replies never increase admin unread counts.
- **Notification content**: title "<visitor> sent a new message", body is the conversation's **latest message** (single-line preview: image → `[image]`,
  form data → `[form data]`, long text truncated; falls back to the unread count when the body is unavailable). Notifications for the same conversation are replaced by newer ones.
- **New-message sound**: the "message sound" switch on the More page plays
  `assets/new_message.mp3` when a visitor message arrives while the app is in the
  foreground; at most once per 1.5 s (socket and polling may both observe the same
  message); never steals audio focus or interrupts music/video (Android `audioFocus: none`,
  iOS `ambient` honors the silent switch). When off there is no foreground sound and
  background notifications use the silent channel `keiyo_chat_messages_silent` (still shown, just mute).
  The switch persists locally as `keiyo_sound_enabled`, default on, not synced per account.
- **Noise control**: no system banner while the app is in the foreground (the server also skips the push then); opening a conversation clears its notifications;
  logout / tenant switch clears snapshots, removes the old tenant's notifications and unregisters push tokens.
- **Platform scope**: push integrates Google FCM and Apple APNs only; Chinese vendor channels (Xiaomi/Huawei/OPPO/vivo) are not supported.
- First entry into the workbench shows a one-time "enable notifications" guide for the notification permission and battery optimization;
  the sound can be toggled anytime from More → Preferences (a preview chime plays when enabling).

## Directory layout

```
lib/
├── main.dart                  # Entry: creates AppState and bootstraps
├── app.dart                   # Root routing gate: splash / login / tenant select / workbench
├── config/app_config.dart     # Fixed server address, paging/polling intervals, stats ranges
├── api/api_client.dart        # Dio wrapper: X-Token / X-Tenant-Id, unified response unwrapping
├── services/realtime_service.dart # Global socket (L1): identify, rooms, heartbeat, broadcast streams
├── services/push_service.dart  # FCM/APNs (L3): init, token registration, tap callbacks
├── services/notification_service.dart # Local notifications: permission, channels (sound/silent), display, tap/cold-start payload
├── services/sound_service.dart # New-message sound: switch persistence + foreground playback of assets/new_message.mp3
├── services/background_watch_service.dart # Foreground service + keep-alive isolate socket + polling downgrade
├── state/app_state.dart       # Session, current tenant, unread totals, auto-translate, locale override
├── models/models.dart         # AdminUser / Tenant / Project / Conversation / ChatMessage / Stats
├── theme/app_theme.dart       # Material 3 dark theme
├── l10n/                      # app_strings.dart + 11 strings_*.dart tables
├── support/                   # Built-in agent support SDK (config / sdk / WebView page / launcher)
├── utils/format.dart          # Time, number, percentage formatting
├── widgets/common.dart        # Shared widgets (avatar, status pill, card, empty state, error bar, ...)
└── pages/
    ├── login_page.dart        # Login
    ├── tenant_select_page.dart# Platform super-admin tenant picker (forced / switch modes)
    ├── home_shell.dart        # Tabbed workbench shell + unread badges + top-bar menu
    ├── conversations_page.dart# Conversation list
    ├── chat_page.dart         # Chat page
    ├── contacts_page.dart     # Contacts
    ├── stats_page.dart        # Statistics
    └── more_page.dart         # More: preferences / support / legal / about

tool/
├── configure_platform.ps1    # Patches Android/iOS native config for notifications and keep-alive
├── run_android.ps1           # Windows-friendly build/run wrapper (JAVA_HOME, no Gradle daemon)
└── make_icons.ps1            # Generates both platforms' launcher icons from design/app-icon-source.png

design/
└── app-icon-source.png       # Launcher icon source (square, full bleed)
```

## Running

### 1. Requirements
- Flutter **3.27 or newer** (`CardThemeData` / `DialogThemeData` need the new Material theme API), Dart ≥ 3.4
  (required by `flutter_foreground_task 9.x`).
- Push depends on Firebase: Android needs `minSdk 23` / `compileSdk 34`, iOS 13+ (the script raises these automatically).
- After cloning, make sure platform directories exist (already committed in this repo) and run the scripts once:

```bash
cd keiyo-chat-app
flutter create --platforms=android,ios .
powershell -ExecutionPolicy Bypass -File tool/configure_platform.ps1
powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1   # launcher icons, see "7. Launcher icons"
```

> `flutter create` only fills in missing `android/`, `ios/` scaffolding; existing `lib/` and `pubspec.yaml` are not overwritten.
> The script adds Android notification / foreground-service permissions and the `remoteMessaging` service declaration, cleartext HTTP,
> Gradle core library desugaring (required by `flutter_local_notifications`), `minSdk 23`,
> FCM default-channel meta-data, and wires the google-services plugin when `google-services.json` exists.
> On iOS it adds `UIBackgroundModes=fetch,remote-notification`, `BGTaskSchedulerPermittedIdentifiers`, ATS,
> iOS 13 deployment target and AppDelegate plugin registration.
> The script is idempotent; rerun it after another `flutter create` or when Firebase config changes.

> Note: iOS integration uses Swift Package Manager. Do not reintroduce a CocoaPods `ios/Podfile`;
> a stray Podfile makes `flutter build ipa` take the CocoaPods path and fail with "sandbox not in sync".

### 2. Push configuration (L3; auto-degrades when absent)

Without push credentials the app still works fully: L1 socket and L2 keep-alive polling
behave as usual, and background reminders fall back to local notifications.

Both platforms share the app identity `com.reflex.customer.service` (Android `applicationId` = iOS bundle ID).
The package name is the app identity that cannot change after launch, and the key shared by
Firebase / Play Console / Apple App ID.

1. Android: create a [Firebase](https://console.firebase.google.com/) project, add an Android app
   (package `com.reflex.customer.service`), drop the downloaded `google-services.json` into
   `android/app/google-services.json`, then rerun:
   ```bash
   powershell -ExecutionPolicy Bypass -File tool/configure_platform.ps1
   ```
   The script applies the `com.google.gms.google-services` plugin (only when the config file exists).
   The plugin verifies that `package_name` in the json matches `applicationId`, failing the build otherwise —
   so changing the package name requires replacing the json at the same time.
2. iOS does not use Firebase: generate an APNs Auth Key on the Apple Developer Keys page
   (the `.p8` downloads only once; KeyID and TeamID are shown on the same page); in Xcode →
   Signing & Capabilities add **Push Notifications** (produces the `aps-environment` entitlement),
   and preferably enable **Background Modes → Remote notifications** as well.
   Hence `ios/Runner/` needs no `GoogleService-Info.plist`.
3. Server, Android side: upload the service-account JSON of the same Firebase project
   (Console → Project settings → Service accounts → Generate a new private key), by default at
   `keiyo-chat-server/config/fcm-service-account.json`, or point `FCM_SERVICE_ACCOUNT_FILE` elsewhere.
4. Server, iOS side: put the `.p8` at `keiyo-chat-server/config/apns-auth-key.p8` (already gitignored,
   do not commit), and set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` (`com.reflex.customer.service`);
   with `APNS_ENV=auto` the production endpoint is tried first and falls back to sandbox on an
   environment-mismatch rejection. The two channels are independent — a missing credential only
   disables that platform; `PUSH_ENABLED=0` turns push off entirely.
5. Create the `chat_push_token` and `chat_admin_presence` (online heartbeat) tables:
   ```bash
   cd keiyo-chat-server
   node sql/migrate.js
   ```
6. Verify: after login the server log shows `[push] FCM enabled for project ...`; on iOS with
   incomplete config it logs `APNs not configured, skipped N ios device(s)`. `chat_push_token`
   should contain both `platform=android` and `platform=ios` rows. With the app in the foreground,
   send a visitor message: the server should log `[push] skip system push for online admin(s): <id>`
   and the phone must not get a duplicate notification; background the app and the line disappears,
   system push resumes.

> Only Google FCM (Android) and APNs (iOS direct, not via FCM) are supported; no Chinese vendor channels.

### 3. Get dependencies and run

```bash
flutter pub get
flutter run
```

On Windows, if you hit `BindException: Address already in use` (Gradle daemon won't start) or the
plugins' Kotlin incremental compile reports `different roots`, use the wrapper script, which sets
`JAVA_HOME` and `GRADLE_OPTS=-Dorg.gradle.daemon=false`:

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_android.ps1 -DeviceId <adb-id>
powershell -ExecutionPolicy Bypass -File tool/run_android.ps1 -BuildOnly
```

The server address is fixed to `https://my.reflexassist.com`; the login page offers no editor.
For local debugging against another server, change `defaultBaseUrl` in `lib/config/app_config.dart`
and rebuild.

### 4. Notification & keep-alive native config (handled by the script)

`tool/configure_platform.ps1` writes the following, listed here for troubleshooting:

Android (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<application ...>
    <!-- Notification-bar alerts use flutter_local_notifications; no extra service needed -->
    <service
        android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
        android:foregroundServiceType="remoteMessaging"
        android:exported="false" />

    <!-- FCM delivery shares the same channel as server/local notifications -->
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="keiyo_chat_messages" />
</application>
```

> Android 14+ requires a foreground service type. `remoteMessaging` is used instead of
> `dataSync`, which is capped at 6 cumulative hours per day on Android 15.

`android/app/build.gradle(.kts)` — mandatory for `flutter_local_notifications` 10+:

```gradle
android {
    compileSdk = 34
    defaultConfig {
        minSdk = 23            // required by Firebase BoM 33
    }
    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

> Without desugaring the build fails outright: `Dependency ':flutter_local_notifications' requires core library desugaring`.

iOS (`ios/Runner/Info.plist`):

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.pravera.flutter_foreground_task.refresh</string>
</array>
```

`ios/Runner/AppDelegate.swift` registers the plugin and the notification delegate:

```swift
import flutter_foreground_task
import UserNotifications

// inside application(_:didFinishLaunchingWithOptions:)
SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
  GeneratedPluginRegistrant.register(with: registry)
}
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
}
```

### 5. Cleartext HTTP (only needed for plain http)

`keiyo-chat-server` usually runs on http locally, and Android 9+ blocks cleartext traffic by default:

`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:usesCleartextTraffic="true"
        ... >
```

On iOS relax ATS in `ios/Runner/Info.plist` (or per-domain):

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

Use https in production and revoke these relaxations.

### 6. Grants required on first launch

1. Allow notifications (system prompt on Android 13+ and iOS).
2. On Android, allowing "ignore battery optimizations" is recommended, plus per-vendor autostart / background activity —
   some ROMs otherwise kill the foreground service on screen-off or task swipe.
3. System permissions (notification / battery) can only be inspected in system settings; the in-app re-grant entry only appears in the first-run guide.
   The More-page switch is the message-sound toggle — it only controls audibility, never notification delivery.

### 7. Launcher icons

The source is `design/app-icon-source.png` (square, full bleed, key artwork within the
central ~2/3). All platform icons are generated by the script — never edit the outputs by hand:

```powershell
powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1
# To swap the logo: replace design/app-icon-source.png (or pass -SourcePath), then rerun
```

Outputs:

- Android `res/mipmap-*/`: `ic_launcher.png` (48–192, for API ≤ 25 and non-adaptive launchers),
  `ic_launcher_round.png` (same sizes, circular crop), `ic_launcher_foreground.png`
  (108 dp canvas, artwork centered at 84 dp).
- Android `res/mipmap-anydpi-v26/`: adaptive icon; the background layer is the diagonal
  gradient in `drawable/ic_launcher_background.xml` (following the source's dark-blue
  bottom-left → cyan top-right), letting each launcher apply its own mask.
  The foreground uses 84 dp rather than a full 108 dp because the headphones in the source
  span about 2/3 of the frame — a full bleed would clip the ear cups under the circular mask.
- Android `res/drawable/ic_stat_keiyo.xml`: status-bar small icon (monochrome headphone
  silhouette). Once the launcher icon became adaptive, `@mipmap/ic_launcher` can no longer
  serve as the small icon (adaptive icons render as a solid white block), so
  `default_notification_icon` points at this vector instead.
- iOS `Assets.xcassets/AppIcon.appiconset/`: same file names and `Contents.json`, images only;
  output is opaque true-color PNG (an alpha-bearing 1024 image is rejected by App Store validation).

Notes:

1. On a fresh machine run `flutter create` **before** `make_icons.ps1`; the order is
   `flutter create` → `configure_platform.ps1` → `make_icons.ps1`.
2. The current source is only 320×320; the iOS 1024 marketing image and the Android xxxhdpi
   foreground are upscaled and slightly soft. Replace with a ≥1024×1024 original before release.
3. Icon changes require reinstall (or waiting for launcher cache refresh); don't judge from
   the home screen alone during on-device verification.

## API surface

| Purpose | Endpoint |
| --- | --- |
| Login / logout | `POST /api/admin/login`, `POST /api/admin/logout` |
| Current identity / prefs | `GET /api/admin/profile`, `POST /api/admin/profile/update` |
| Tenants (platform super admin) | `GET /api/admin/tenant/options`, `POST /api/admin/tenant/switch` |
| Project dropdown | `GET /api/admin/project/options` |
| Conversation list / messages | `GET /api/admin/conversation/list`, `GET /api/admin/conversation/messages` |
| Conversation actions | `POST /api/admin/conversation/reply` (`images` accepts image URLs), `/close`, `/reopen` |
| Image upload | `POST /api/admin/upload/image` (multipart, field `file[]`, returns `{ urls }`) |
| Push tokens | `POST /api/admin/push/register`, `POST /api/admin/push/unregister` |
| Statistics | `GET /api/admin/stats/overview`, `POST /api/admin/stats/summary` |
| Agent support (built-in SDK) | `POST /api/open/conversation` with `X-App-Id` / `X-App-Key`, returns `chat_url` / `conv_key` |

Conventions:
- Unified envelope `{ code, msg, data }`; `code = 0` success, `-401` session expired, `-403` no permission.
- Requests authenticate via the `X-Token` header; the platform super admin's current tenant goes in `X-Tenant-Id`.
- Conversation list sorts by `status asc, last_msg_time desc` — "needs human" first, then by last message time descending.
- `conversation/messages` paging: returns the latest 50 by default (`limit` clamped to 1–200); to go further back pass the returned `oldest_id` as `before_id`, `has_more=false` marks the oldest page; `form_seq` (form submission batch) is assigned by the server over the conversation's global order and stays stable across pages.

## Notes & limitations

- Mobile uses "first page + load more"; the admin console's jump-to-page is not ported.
- Unread totals use the server's `unread_total` (all conversations within tenant + authorized projects), same source as the push `total_unread`.
- Conversation realtime is "global socket first + 5 s polling fallback"; socket drops never block usage.
- The conversation list intentionally omits admin-console power ops (delete / transfer); only close, reopen, reply, view forms.
- Push covers Google FCM and Apple APNs only — no Chinese vendor channels, and no targeting of Chinese app stores;
  on devices without Google services, rely on L1/L2 (socket + keep-alive polling).
  - If the Android foreground service is force-stopped by the system or user, or after power-off, no messages arrive until the app is manually reopened.
  - iOS keeps no background socket and relies entirely on APNs; with notification permission denied only foreground live refresh remains.
  - After a platform super admin switches tenants, pushes for the old tenant may already sit in the notification shade; pruning is left to the server or system layer.
- Sending non-image files and voice messages is not supported; image limits come from the server's `config.upload` (5 MB each, 10 per message).
