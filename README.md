# Keiyo 智能客服 APP（Flutter）

移动端客服工作台，逻辑与 `keiyo-chat-admin` 管理端对齐：会话列表、实时沟通、数据统计。
面向租户管理员 / 平台超级管理员使用，登录后直接进入「会话 + 统计」两个 Tab。

## 功能

### 登录与租户
- 账号密码登录 `POST /api/admin/login`，令牌与身份本地持久化，重启免登录。
- **平台超级管理员（`is_platform = 1`）登录后必须选择一家租户**，否则不进入业务页：
  - 租户列表来自 `GET /api/admin/tenant/options`（上限 200 家，>8 家时出现搜索框）。
  - 选择后调用 `POST /api/admin/tenant/switch` 落库为「最近使用租户」，并写入 `X-Tenant-Id`。
  - 工作台右上角可随时切换租户，切换后整个工作台按新租户重建数据。
- 普通成员 / 租户管理员直接使用登录响应里的租户，无需选择。
- 服务器地址固定为 `https://support.breathmeters.net`，App 内不提供修改入口；请求返回 `-401` 时自动清除本地会话回到登录页。

### 会话列表 Tab
- 筛选：状态（全部 / 进行中 / 需人工 / 已关闭）、项目、关键词搜索（350ms 防抖）。
- 分页：首屏 20 条，底部「加载更多」，滚动到底附近自动加载。
- 实时：登录并选定租户后建立一条全局 socket（`/chat-ws`），服务端按管理员身份推 `conv_updated` 摘要，
  列表与底部角标秒级更新；每 5 秒轮询继续保留作为兜底。
- 未读角标：使用服务端 `unread_total`（不受筛选影响，与推送 `total_unread` 同口径）。
- 列表项展示：访客头像（首字彩色底）、标题、最后消息时间、访客 ID · 项目、状态胶囊、未读数、接待客服（未分配时显示「待分配」）。
- 客服上线/下线：队列右上角的「在线 / 离线」胶囊（仅 `role = agent` 显示）写入 `chat_admin.online_status`；
  转人工分配时优先选择在线客服，全员下线才退回全体在岗客服。下线只影响新会话分配，已接待的会话不受影响；退出登录会自动置为下线。

### 沟通页
- 点击会话进入，进入后自动定位到底部最新消息（接口返回最近若干条；列表按需构建，长会话会逐帧补跳直到真正贴底）。
- 实时性：复用全局唯一 socket，进入时 `join` 会话房间、退出时 `leave`（事件 `new_msg`）；
  每 5 秒轮询兜底，二者用请求序号防并发覆盖。翻历史时新消息只显示「N 条新消息」胶囊，不抢滚动位置；
  双击标题栏（会话名 / 访客名）可随时回到底部最新消息。
- 消息气泡：
  - 客服消息在右（强调色），访客在左，AI 消息带「AI」标识与描边，系统消息居中。
  - Markdown 渲染（服务端返回的富文本 / 链接 / 列表）。
  - 翻译：访客与 AI 默认显示译文，客服默认显示原文，可逐条「显示原文 / 显示译文」切换。
  - 表单消息 `msg_type = form` 显示为 `[ 表单 ] #编号`。
- 表单数据（`msg_type = form_data`）：气泡内直接展示为「第 N 次提交」卡片 + 键值行（可选中复制），回复栏上方「全部表单数据」按钮打开底部抽屉，按时间倒序汇总全部提交。
- 回复框：1–4 行自适应输入，发送中禁用；左侧图片按钮可从相册选图（单条最多 9 张、单张不超过 5MB），
  图片先传 `POST /api/admin/upload/image` 再随文字发给 `POST /api/admin/conversation/reply` 的 `images` 字段，
  由服务端拼成同一条 Markdown 消息；气泡内图片点击可看大图。会话关闭时发送会自动重新打开。
- 关闭 / 重新打开会话：`POST /api/admin/conversation/close|reopen`，操作前二次确认。
- 进入会话会清零服务端未读数（由 messages 接口完成），返回列表后静默刷新。

### 统计 Tab
- 时间范围：近 7 / 30 / 90 天；项目筛选（`GET /api/admin/project/options`）。
- KPI：会话数、AI 回答数、人工接待会话、知识库命中率。
- 图表（`fl_chart`）：
  - 折线：每日会话数 / AI 回答数。
  - 折线：人工接待会话 / 转人工请求（虚线）。
  - 柱状：知识库检索 / 命中。
- 热门关键词（按出现次数缩放字号）、Top 知识库（名次 + 进度条 + 次数）。
- AI 总结：`POST /api/admin/stats/summary`，单独按钮触发生成，最长等待 90 秒，展示生成内容、模型、时间与用量提示。

### 实时与通知（L1 / L2 / L3）

三层机制各管一段，任何一层失效都不会让消息丢失：

- **L1 全局长连接（实时刷新）**
  - 登录并选租户后建立一条 socket（`/chat-ws`），`identify` 成功后服务端加入 `admin_{id}` 房间，
    后续任何有权限的会话产生访客消息，只向有权限的管理员推 `conv_updated`（未读数、预览、消息 id）。
  - 会话列表与底部角标秒级更新；沟通页复用同一条连接加入会话房间，不再各自建连。
  - 多 worker 部署时由服务端通过 Egg messenger 中继到所有 worker，客户端无感。
- **L2 Android 后台长连接（保活加速）**
  - `flutter_foreground_task` 前台服务（常驻通知「智能客服在线」+ `remoteMessaging` 类型，持 `WAKE_LOCK` / Wi-Fi Lock）。
  - 任务 isolate 内维持一条 socket，后台也能秒收摘要；socket 在线时 15 秒轮询降级为 60 秒自检，
    断线立即恢复 15 秒全量轮询，令牌/租户变化会自动重建连接。
  - 引导用户关闭电池优化、允许自启动；被系统或用户强制停止后需重新打开 APP。
- **L3 系统推送（进程被杀也能到）**
  - 服务端 Android 走 FCM HTTP v1，iOS 直连 APNs（不经 FCM 转发，两套凭证互相独立）。
  - APP 登录后把设备 token 登记到 `POST /api/admin/push/register`，退出/换账号时 `POST /api/admin/push/unregister`。
  - 访客消息触发系统通知，按会话合并（Android `tag` / `collapse_key`，iOS `thread-id`）；
    前台不弹横幅，由 socket 实时刷新；点击通知直达对应会话（冷启动同样有效）。
  - FCM 已登记时后台保活不再重复弹本地通知；未配置 Firebase 时自动回退到本地通知。
- **在线不推（系统推送只兜“实时弹不出来”）**
  - 三层与系统推送互不知情时，同一条访客消息会先弹实时横幅、再吃一条 FCM/APNs。
    现在服务端发推送前先查在线心跳，只把消息推给此刻真的弹不出来的管理员（socket 摘要照发）。
  - 在线口径按“真能弹出来”定：APP 在前台（页面自己会弹横幅 + 提示音）、
    或管理端网页标签页可见才算在线；后台保活 isolate **不算在线**（它收到摘要后仍把提醒交给系统推送）。
  - 心跳由客户端每 15 秒续一次（前后台切换那一下立即上报），落 `chat_admin_presence` 表；
    服务端只看 45 秒内的新鲜度（与 L2 的僵尸连接判定同口径），进程被杀 / 断网 / 标签页冻结
    都只是停止续期，超时自动降级成离线。
  - 所有失败方向都是“宁可多推一条，不能漏推”：表未建、查库报错、连接断开一律当离线照推。
    排查时若怀疑这道闸门误伤，可用 `PUSH_SKIP_ONLINE=0` 整体关掉（`PUSH_PRESENCE_TTL_SEC` 可调窗口）。
  - 管理端网页因此也开始 `identify`（以前只 join 会话房间，列表红点全靠轮询顶着），
    顺带收到 `conv_updated` 秒级刷新。
- **通知范围**：服务端按租户 + `admin.project_ids` 计算有权限的管理员，只向他们推摘要与系统通知；
  客服自己回复产生的新消息不会增加管理员未读，不会误报。
- **通知内容**：标题为「访客名 发来新消息」，正文为该会话**最新一条消息**（单行预览：图片→`[图片]`、
  表单数据→`[表单数据]`、超长截断；拿不到正文时回退为未读条数），同一会话的通知会被新消息覆盖。
- **新消息提示音**：工作台右上角菜单「提示音」开关控制 APP 在前台收到访客新消息时播放
  `assets/new_message.mp3`；1.5 秒内只响一次（长连接与轮询兜底可能同时发现同一条消息），
  不抢音频焦点、不打断正在播放的音乐/视频（Android `audioFocus: none`，iOS `ambient` 遵循静音键）。
  关闭后前台不响，后台通知改走无声渠道 `keiyo_chat_messages_silent`（通知仍展示，只是不发声）。
  开关状态保存在本地 `keiyo_sound_enabled`，默认开启，不随账号同步。
- **去噪**：APP 在前台时不弹系统横幅（服务端这时也不会再发一条推送），由页面与角标实时刷新；进入会话自动清除该会话通知；
  退出登录 / 切换租户会清空快照、清除旧租户通知并注销推送令牌。
- **平台范围**：推送只对接 Google FCM 与 Apple APNs，暂不接入国内厂商通道（小米/华为/OPPO/vivo）。
- 首次进入工作台会弹一次「开启消息提醒」引导，用于申请通知权限与关闭电池优化；
  提示音是否播放随时可从右上角菜单「提示音：已开启 / 已关闭」切换（开启时会试听一次）。

## 目录结构

```
lib/
├── main.dart                  # 入口，创建 AppState 并 bootstrap
├── app.dart                   # 根路由 gate：启动页 / 登录 / 选租户 / 工作台
├── config/app_config.dart     # 固定服务器地址、分页与轮询间隔、统计范围
├── api/api_client.dart        # Dio 封装：X-Token / X-Tenant-Id、统一响应解包
├── services/realtime_service.dart # 全局长连接（L1）：identify、会话房间、在线心跳、三条广播流
├── services/push_service.dart  # FCM/APNs（L3）：初始化、token 登记、点击回调
├── services/notification_service.dart # 本地通知：权限、渠道（有声/静音）、展示、点击/冷启动 payload
├── services/sound_service.dart # 新消息提示音：开关持久化 + 前台播放 assets/new_message.mp3
├── services/background_watch_service.dart # 前台服务 + 保活 isolate socket + 轮询降级
├── state/app_state.dart       # 登录态、当前租户、未读汇总、自动翻译
├── models/models.dart         # AdminUser / Tenant / Project / Conversation / ChatMessage / Stats
├── theme/app_theme.dart       # Material 3 暗色主题
├── utils/format.dart          # 时间、数字、百分比格式化
├── widgets/common.dart        # 通用组件（头像、状态胶囊、卡片、空态、错误条等）
└── pages/
    ├── login_page.dart        # 登录
    ├── tenant_select_page.dart# 平台超管选租户（强制/切换两种模式）
    ├── home_shell.dart        # 两 Tab 工作台 + 未读角标 + 菜单
    ├── conversations_page.dart# 会话列表
    ├── chat_page.dart         # 沟通页
    └── stats_page.dart        # 统计页

tool/
├── configure_platform.ps1    # 补 Android/iOS 通知与后台保活所需原生配置
└── make_icons.ps1            # 从 design/app-icon-source.png 生成双端桌面图标

design/
└── app-icon-source.png       # 桌面图标源图（正方形、满幅出血）
```

## 运行

### 1. 环境要求
- Flutter **3.27 及以上**（`CardThemeData` / `DialogThemeData` 需要新版 Material 主题 API），Dart ≥ 3.4
  （`flutter_foreground_task 9.x` 的要求）。
- 推送依赖 Firebase：Android 需 `minSdk 23` / `compileSdk 34`，iOS 需 13+（脚本会自动抬到这些版本）。
- 本仓库只包含 `lib/`、`pubspec.yaml`、`design/` 与 `tool/`，首次使用需补齐平台目录再跑脚本：

```bash
cd keiyo-chat-app
flutter create --platforms=android,ios .
powershell -ExecutionPolicy Bypass -File tool/configure_platform.ps1
powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1   # 桌面图标，见「7. 桌面图标」
```

> `flutter create` 会在当前目录补 `android/`、`ios/` 等平台工程，已存在的 `lib/` 与 `pubspec.yaml` 不会被覆盖。
> 脚本为 Android 补通知 / 前台服务权限与 `remoteMessaging` 服务声明、明文 HTTP、
> Gradle 的 core library desugaring（`flutter_local_notifications` 必需）、`minSdk 23`、
> FCM 默认渠道 meta-data，并在存在 `google-services.json` 时接入 google-services 插件；
> 为 iOS 补 `UIBackgroundModes=fetch,remote-notification`、`BGTaskSchedulerPermittedIdentifiers`、ATS、
> `platform :ios, '13.0'` 与 AppDelegate 插件注册。
> 脚本幂等，可重复执行；再次 `flutter create` 或新增 Firebase 配置后建议重跑一次。

### 2. 推送配置（L3，不配则自动降级）

未配置推送凭证时 APP 仍可正常运行：L1 socket 与 L2 保活轮询照常工作，后台提醒回退到本地通知。

双端应用身份统一为 `com.reflex.customer.service`（Android `applicationId` 与 iOS Bundle ID 同名）。
包名即上架后改不了的应用身份，也是 Firebase / Play Console / 苹果 App ID 三方共同的键。

1. Android：在 [Firebase 控制台](https://console.firebase.google.com/) 创建项目并添加 Android 应用
   （包名填 `com.reflex.customer.service`），把下载到的 `google-services.json` 放到
   `android/app/google-services.json`，重新执行：
   ```bash
   powershell -ExecutionPolicy Bypass -File tool/configure_platform.ps1
   ```
   脚本会接入 `com.google.gms.google-services` 插件（只在配置文件存在时）。
   该插件会校验 json 里的 `package_name` 与 `applicationId` 是否一致，对不上直接构建失败，
   所以换包名必须同时换 json，不能只改一边。
2. iOS 不接 Firebase：在苹果开发者后台 Keys 页生成 APNs Auth Key（`.p8` 只能下载一次），
   同页可见 KeyID 与 TeamID；Xcode → Signing & Capabilities 添加 **Push Notifications**（生成
   `aps-environment` 权限），建议同时开启 **Background Modes → Remote notifications**。
   因此 `ios/Runner/` 下不需要 `GoogleService-Info.plist`。
3. 服务端 Android 侧：上传同一个 Firebase 项目的服务账号 JSON（控制台 → 项目设置 → 服务账号
   → 生成新的私钥），默认放到 `keiyo-chat-server/config/fcm-service-account.json`，
   也可用环境变量 `FCM_SERVICE_ACCOUNT_FILE` 指定路径。
4. 服务端 iOS 侧：`.p8` 默认放 `keiyo-chat-server/config/apns-auth-key.p8`（已在 .gitignore 里，
   不要提交），并配 `APNS_KEY_ID`、`APNS_TEAM_ID`、`APNS_BUNDLE_ID`（填 `com.reflex.customer.service`）；
   `APNS_ENV` 留 `auto` 时先发生产端点，被拒成环境不匹配会自动退到开发端点。
   两条通道凭证互相独立，缺哪边只停哪边推送；`PUSH_ENABLED=0` 可整体关掉。
5. 导入 `chat_push_token` 与 `chat_admin_presence`（在线心跳）两张表：
   ```bash
   cd keiyo-chat-server
   node sql/migrate.js
   ```
6. 验证：登录后看服务端日志 `[push] FCM enabled for project ...`；iOS 未配齐时会打
   `APNs not configured, skipped N ios device(s)`。`chat_push_token` 里应能同时看到
   `platform=android` 与 `platform=ios` 的行。APP 停在前台时发一条访客消息，服务端应打
   `[push] skip system push for online admin(s): <id>` 且手机不再吃第二条通知；
   退到后台后同一行日志消失，系统推送恢复。

> 只支持 Google FCM（Android）与 APNs（iOS 直连，不经 FCM 转发），不包含国内厂商推送通道。

### 3. 拉依赖并运行

```bash
flutter pub get
flutter run
```

Windows 本机如果遇到 `BindException: Address already in use`（Gradle daemon 起不来）或
插件 Kotlin 增量编译报 `different roots`，用封装脚本运行，它会设好 `JAVA_HOME` 与
`GRADLE_OPTS=-Dorg.gradle.daemon=false`：

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_android.ps1
powershell -ExecutionPolicy Bypass -File tool/run_android.ps1 -BuildOnly
```

新环境首次构建前需要先生成平台目录（本仓库已包含）：`flutter create --platforms=android,ios .`，
然后执行 `tool/configure_platform.ps1` 写入权限、minSdk、前台服务与通知配置。

服务器地址固定为 `https://support.breathmeters.net`，登录页不再提供修改入口；
本地联调需要换地址时，改 `lib/config/app_config.dart` 里的 `defaultBaseUrl` 重新打包即可。

### 4. 通知与后台保活配置（脚本已自动处理）

执行 `tool/configure_platform.ps1` 后会写入以下内容，便于排查问题：

Android（`android/app/src/main/AndroidManifest.xml`）：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<application ...>
    <!-- 通知栏提醒使用 flutter_local_notifications，无需额外 service -->
    <service
        android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
        android:foregroundServiceType="remoteMessaging"
        android:exported="false" />

    <!-- FCM 下发时与服务端/本地通知使用同一个渠道 -->
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="keiyo_chat_messages" />
</application>
```

> Android 14+ 必须声明前台服务类型。这里用 `remoteMessaging` 而不是 `dataSync`，
> 后者在 Android 15 有每日 6 小时累计限制。

`android/app/build.gradle`（或 `.kts`）— `flutter_local_notifications` 10+ 强制要求：

```gradle
android {
    compileSdk = 34
    defaultConfig {
        minSdk = 23            // Firebase BoM 33 要求
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

> 不开 desugaring 会在编译阶段直接报 `Dependency ':flutter_local_notifications' requires core library desugaring`。

iOS（`ios/Runner/Info.plist`）：

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

`ios/Podfile` 需要 iOS 13+（Firebase iOS 11 的要求）：

```ruby
platform :ios, '13.0'
```

`ios/Runner/AppDelegate.swift` 需要注册插件与通知代理：

```swift
import flutter_foreground_task
import UserNotifications

// application(_:didFinishLaunchingWithOptions:) 内
SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
  GeneratedPluginRegistrant.register(with: registry)
}
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
}
```

### 5. 明文 HTTP 配置（仅 http 需要）

`keiyo-chat-server` 本地通常是 http，Android 9+ 默认禁止明文流量：

`android/app/src/main/AndroidManifest.xml`：

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:usesCleartextTraffic="true"
        ... >
```

iOS 在 `ios/Runner/Info.plist` 中放开 ATS（或只对指定域名放开）：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

生产环境请使用 https，并回收上述放宽配置。

### 6. 首次启动必须完成的授权

1. 允许通知（Android 13+ / iOS 均会弹系统授权框）。
2. Android 建议允许「忽略电池优化」，并按厂商设置允许自启动 / 后台活动，
   否则部分 ROM 会在息屏或清理后台时杀掉前台服务。
3. 系统权限（通知 / 电池优化）只能在本机系统设置里查看，应用内的重新授权入口只在首次引导时出现；
   右上角菜单提供的是「提示音：已开启 / 已关闭」开关，只影响新消息是否出声，不影响通知送达。

### 7. 桌面图标

源图是 `design/app-icon-source.png`（正方形、满幅出血、关键图形落在中间约 2/3 范围内），
双端图标全部由脚本生成，不要手改生成物：

```powershell
powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1
# 换 logo：先把新图覆盖 design/app-icon-source.png（或用 -SourcePath 指定）再重跑
```

产出：

- Android `res/mipmap-*/`：`ic_launcher.png`（48~192，API 25 及以下与不认自适应图标的启动器）、
  `ic_launcher_round.png`（同尺寸裁圆）、`ic_launcher_foreground.png`（108dp 画布，图形占中心 84dp）。
- Android `res/mipmap-anydpi-v26/`：自适应图标，背景层是 `drawable/ic_launcher_background.xml`
  的对角渐变（跟随源图左下深蓝 → 右上青的走势），启动器按圆形/方形/水滴自行裁切。
  前景取 84dp 而不是铺满 108dp，是因为源图耳机横跨约 2/3 幅面，铺满会被圆形遮罩切掉耳罩。
- Android `res/drawable/ic_stat_keiyo.xml`：状态栏小图标（单色耳机剪影）。桌面图标改成
  自适应图标后不能再拿 `@mipmap/ic_launcher` 当 small icon（adaptive-icon 会被系统涂成
  一整块白色），所以 `default_notification_icon` 已指向这个矢量图。
- iOS `Assets.xcassets/AppIcon.appiconset/`：沿用原有文件名与 `Contents.json`，只替换图片；
  统一输出不带 alpha 的真彩色 PNG（带 alpha 的 1024 图会被 App Store 校验拒收）。

注意事项：

1. 新环境是先 `flutter create` 再 `make_icons.ps1`：前者补出来的是一整套 Flutter 默认图标，
   顺序是 `flutter create` → `configure_platform.ps1` → `make_icons.ps1`。
2. 源图目前只有 320×320，iOS 的 1024 营销图与 Android xxxhdpi 前景是放大得来的，偏软。
   上架前建议换成 ≥1024×1024 的原图重跑脚本。
3. 图标改动需要卸载重装或等启动器刷新缓存，真机验证时不要只看桌面。

## 对接接口

| 用途 | 接口 |
| --- | --- |
| 登录 / 退出 | `POST /api/admin/login`、`POST /api/admin/logout` |
| 当前身份 / 偏好 | `GET /api/admin/profile`、`POST /api/admin/profile/update` |
| 租户（平台超管） | `GET /api/admin/tenant/options`、`POST /api/admin/tenant/switch` |
| 项目下拉 | `GET /api/admin/project/options` |
| 会话列表 / 消息 | `GET /api/admin/conversation/list`、`GET /api/admin/conversation/messages` |
| 会话操作 | `POST /api/admin/conversation/reply`（`images` 可传图片地址）、`/close`、`/reopen` |
| 图片上传 | `POST /api/admin/upload/image`（multipart，字段名 `file[]`，返回 `{ urls }`） |
| 推送令牌 | `POST /api/admin/push/register`、`POST /api/admin/push/unregister` |
| 统计 | `GET /api/admin/stats/overview`、`POST /api/admin/stats/summary` |

约定：
- 统一响应 `{ code, msg, data }`，`code = 0` 成功，`-401` 登录失效，`-403` 无权限。
- 请求头 `X-Token` 鉴权；平台超管的当前租户通过 `X-Tenant-Id` 传递。
- 会话列表排序为 `status asc, last_msg_time desc`，即「需人工」优先，其次按最后消息时间倒序。
- `conversation/messages` 分页：默认只回最近 50 条（`limit` 夹在 1~200），更早的历史拿返回的 `oldest_id` 当 `before_id` 往前翻，`has_more=false` 即已到最早一页；`form_seq`（表单提交批次）由服务端按会话全局顺序给，分页前后不变。

## 说明与限制

- 移动端采用「首屏 + 加载更多」，管理端的页码跳转未移植。
- 未读汇总使用服务端 `unread_total`（租户 + 授权项目内全部会话），与推送 `total_unread` 同口径。
- 会话实时性为「全局 socket 优先 + 5 秒轮询兜底」，socket 断线不影响使用。
- 会话列表不单独提供「删除 / 转移」等管理端高级操作，仅保留关闭、重开、回复、查看表单。
- 推送只对接 Google FCM 与 Apple APNs，暂不接入国内厂商通道，也不针对国内应用商店上架；
  国内设备若无 Google 服务，请依赖 L1/L2（socket + 保活轮询）。
  - Android 前台服务被系统或用户强制停止、拔电关机后不会再收到消息，重启手机后需手动打开一次 APP。
  - iOS 后台不维持 socket，完全依赖 APNs；通知权限关闭时只剩前台实时刷新。
  - 平台超管切换租户后，旧租户的推送可能已到达通知栏，需要在服务端或系统层自行取舍。
- 暂不支持发送文件（非图片）与语音；图片上限由服务端 `config.upload` 控制（单张 5MB、单次 10 张）。
