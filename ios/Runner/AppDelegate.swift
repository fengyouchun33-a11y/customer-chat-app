import Flutter
import flutter_foreground_task
import UserNotifications
import UIKit

/// iOS 直连 APNs：设备令牌与通知点击都由本文件经 MethodChannel 交给 Dart，不引 Firebase。
private let kPushChannelName = "keiyo/push_bridge"
private let kTokenDefaultsKey = "keiyo.apns.deviceToken"
private let kTapDefaultsKey = "keiyo.apns.pendingTap"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_foreground_task 在 iOS 上会另起一个后台 FlutterEngine 跑保活 isolate，
    // 它的 initialize() 第一道门槛就是这个回调：拿不到就直接 return（只 print 一行），
    // 保活 isolate 根本不会启动。新模板把插件注册挪到了 didInitializeImplicitFlutterEngine，
    // configure_platform.ps1 原来那条 register(with: self) 的注入 pattern 已经匹配不上了，所以这里显式补上。
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // 必须显式把自己设成 center delegate：系统只在它上面回调远程推送的点击与前台展示。
    // 原来没人设置，所以 iOS 上通知点了没反应、前台本地通知也不显示。
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      // 授权通过才注册；不注册拿不到 device token，服务端无从推起
      if granted {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // applicationRegistrar 是隐式引擎暴露给 App 层的注册上下文，messenger 指向根引擎
    let channel = FlutterMethodChannel(
      name: kPushChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler(handlePushCall)
    pushChannel = channel
    // 系统回调可能早于引擎就绪（冷启动首次授权后立刻拿到令牌），补发一次
    if cachedToken().isEmpty == false {
      channel.invokeMethod("onToken", arguments: nil)
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    // 服务端只在未读数 >0 时下发 badge，清零只能靠 App 自己：回前台即清
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 0
    }
    super.applicationDidBecomeActive(application)
  }

  // MARK: - 设备令牌

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // APNs 令牌是 32 字节二进制，苹果要求按小写 hex 放进 :device_token 路径
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: kTokenDefaultsKey)
    pushChannel?.invokeMethod("onToken", arguments: nil)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // 常见原因：Xcode 没勾 Push Notifications capability（缺 aps-environment）、
    // 描述文件不含推送 entitlement、或跑在模拟器上。此时只停系统推送，
    // socket + 轮询照常工作，所以不打扰用户，只留日志。
    NSLog("[keiyo][push] APNs 注册失败: %@", error.localizedDescription)
  }

  // MARK: - 通知展示与点击

  // FlutterAppDelegate 自身已遵从 UNUserNotificationCenterDelegate（把回调转发给插件），
  // 所以这两个回调必须写 override、类声明里不能再重复列协议（会报冗余遵从）。
  // 本类接管路由后不调 super：completionHandler 必须且只能调一次，由这里负责。
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if isRemotePush(notification.request) {
      // 前台不弹远程推送横幅：前台的横幅与提示音由 socket 那一路的本地通知负责
      // （AppState._notifyWhileForeground），两条都弹会出现内容相同的两条横幅。
      // 角标仍按服务端下发的未读数更新，和原来 FCM 的前台展示配置保持一致。
      completionHandler([.badge])
      return
    }
    let content = notification.request.content
    var options: UNNotificationPresentationOptions = [.badge]
    if content.title.isEmpty == false || content.body.isEmpty == false {
      if #available(iOS 14.0, *) {
        options.insert(.banner)
      } else {
        options.insert(.alert)
      }
    }
    if content.sound != nil {
      options.insert(.sound)
    }
    completionHandler(options)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let request = response.notification.request
    let userInfo = request.content.userInfo
    if isRemotePush(request) {
      deliverTap(remoteData(from: userInfo))
    } else if let payload = userInfo["payload"] as? String,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      // flutter_local_notifications 把会话 JSON 放在 userInfo["payload"]，这里按同一份
      // 约定取出来，和远程推送共用一个入口；插件的点击转发不再经过（见上方 override 说明）。
      deliverTap(json)
    }
    completionHandler()
  }

  private func isRemotePush(_ request: UNNotificationRequest) -> Bool {
    return request.trigger is UNPushNotificationTrigger
  }

  /// aps 是苹果的控制字段，业务字段全部平铺在它外面
  private func remoteData(from userInfo: [AnyHashable: Any]) -> [String: Any] {
    var data: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let name = key as? String, name != "aps" else { continue }
      data[name] = value
    }
    return data
  }

  // MARK: - 与 Dart 的通道

  private func handlePushCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getToken":
      result(cachedToken())
    case "takePendingTap":
      result(takePendingTap())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func cachedToken() -> String {
    return UserDefaults.standard.string(forKey: kTokenDefaultsKey) ?? ""
  }

  /// 先落盘再发信号，载荷统一由 Dart 侧 takePendingTap 取走：
  /// handler 挂载前消息被丢弃也能在 init 时补上，且取一次清一次不会重复打开会话。
  private func deliverTap(_ data: [String: Any]) {
    guard let json = try? JSONSerialization.data(withJSONObject: data),
          let text = String(data: json, encoding: .utf8) else { return }
    UserDefaults.standard.set(text, forKey: kTapDefaultsKey)
    pushChannel?.invokeMethod("onTap", arguments: nil)
  }

  private func takePendingTap() -> [String: Any]? {
    guard let text = UserDefaults.standard.string(forKey: kTapDefaultsKey) else { return nil }
    UserDefaults.standard.removeObject(forKey: kTapDefaultsKey)
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json
  }
}
