import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新消息提示音（仅前台）。
///
/// 后台提醒交给系统通知：保活 isolate 里播放音频在 Android/iOS 都不可靠，
/// 所以这里只在主 isolate、APP 处于前台时播放 assets/new_message.mp3。
class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  /// 开关的本地存储键；只影响前台提示音，与通知栏声音互不干扰
  static const String enabledKey = 'keiyo_sound_enabled';

  /// AssetSource 默认带 assets/ 前缀，对应 assets/new_message.mp3
  static const String _assetName = 'new_message.mp3';

  final AudioPlayer _player = AudioPlayer();

  bool _enabled = true;
  bool _configured = false;
  DateTime? _lastPlayedAt;

  bool get enabled => _enabled;

  /// 启动时恢复开关；读不到按开启处理（与首次安装的默认值一致）
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(enabledKey) != false;
    } catch (_) {
      _enabled = true;
    }
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, on);
    } catch (_) {
      // 写本地失败不影响本次会话内的开关
    }
  }

  /// 收到访客新消息时调用；播放失败只打日志，不影响消息处理
  Future<void> playNewMessage() async {
    if (!_enabled) return;
    // 长连接与 5 秒轮询兜底可能同时发现同一条消息，短时间内只响一次
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastPlayedAt = now;
    try {
      await _configure();
      // 连续来消息时从头重播，而不是排队积压
      await _player.stop();
      await _player.play(AssetSource(_assetName));
    } catch (e) {
      debugPrint('[sound] play failed: $e');
    }
  }

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    await _player.setReleaseMode(ReleaseMode.stop);
    // 提示音不抢音频焦点：客服在听歌/看视频时只叠加一声提示，不打断播放
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.none,
        ),
        // ambient: 遵循系统静音键、可与其他音频共存，适合短提示音
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );
  }
}
