import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// 沟通页：与管理端右栏同逻辑
/// - 进入即拉消息（服务端顺带清零管理员未读）
/// - 复用全局唯一 socket 加入当前会话房间（L1）+ 5 秒轮询兜底，
///   二者用请求序号防并发覆盖；翻历史时新消息只计数，不抢滚动位置
/// - 翻译切换：客服消息优先原文、访客/AI 优先译文
/// - form_data 结构化数据按提交批次展示，历史表单可集中查看
/// - 关闭 / 重开会话，回复后未分配的会话自动接手
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const int _maxTextWidthRatio = 74; // 气泡最多占屏宽 74%
  // 一条消息最多 9 张图：与服务端单次上传上限(10)留一张余量，也贴合微信习惯
  static const int _maxImages = 9;
  // 服务端单张图上限 5MB，超过的选图在本地就拦掉，免得上传完才报错
  static const int _maxImageBytes = 5 * 1024 * 1024;

  late Conversation _conv;
  late final AppState _app;
  final TextEditingController _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, bool> _showOriginal = {};
  final ImagePicker _picker = ImagePicker();
  // 已选但还没发送的图片：发送时与文字拼成同一条消息（与 H5 发图口径一致）
  final List<XFile> _pendingImages = [];
  StreamSubscription<Map<String, dynamic>>? _msgSub;

  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _polling = false;
  bool _actionBusy = false;
  String? _error;
  int _msgSeq = 0;
  int _newCount = 0;
  // 消息分页：首屏只拉最近一页，滚到顶部再往前翻更早的历史
  static const int _pageSize = 50;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;
  // 已加载消息里的最小 id，翻更早一页时作为 before_id 传给服务端
  int _oldestLoadedId = 0;
  Timer? _poll;

  static final MarkdownStyleSheet _mdStyle = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.text),
    h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
    h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
    h3: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4),
    em: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.text),
    strong: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
    del: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textDim),
    a: const TextStyle(color: AppColors.accent, decoration: TextDecoration.underline),
    code: const TextStyle(
      fontSize: 12,
      color: AppColors.accentStrong,
      backgroundColor: Color(0xFF0A1A23),
      fontFamily: 'monospace',
    ),
    blockquote: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textDim),
    blockquoteDecoration: const BoxDecoration(
      color: AppColors.panel2,
      border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF0A1A23),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    listBullet: const TextStyle(fontSize: 13, color: AppColors.text),
    tableBorder: TableBorder.all(color: AppColors.border, width: 1),
    tableHead: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
    tableBody: const TextStyle(fontSize: 12, color: AppColors.textDim),
  );

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    _app = context.read<AppState>();
    _app.setOpenConversation(_conv.convKey);
    // 进入会话即清掉该会话的未读通知
    NotificationService.instance.cancel(_conv.id);
    // 复用全局唯一连接：只 join 会话房间，不再各自建 socket
    _app.realtime.joinConversation(_conv.convKey);
    _msgSub = _app.realtime.newMessages.listen(_onRealtimeMsg);
    _scrollCtrl.addListener(_onScroll);
    _loadMessages(initial: true);
    _poll = Timer.periodic(AppConfig.chatPollInterval, (_) => _pollTick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _app.clearOpenConversation(_conv.convKey);
    _app.realtime.leaveConversation(_conv.convKey);
    _msgSub?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 已加载这些页里的表单: 分页后这里只含已经翻到的部分, 往上翻更早的历史会跟着补齐
  List<ChatMessage> get _formMessages =>
      _messages.where((m) => m.msgType == 'form_data').toList();

  bool get _nearBottom {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return pos.maxScrollExtent - pos.pixels < 80;
  }

  String _senderLabel(ChatMessage m) {
    if (m.senderName.isNotEmpty) return m.senderName;
    if (m.isVisitor) return _conv.userLabel;
    if (m.isAgent) return '客服';
    if (m.isAi) return 'AI';
    return '系统';
  }

  bool _truthy(dynamic v) => v == true || v == 1;

  Future<void> _loadMessages({bool initial = false, bool silent = false, bool follow = false}) async {
    final api = context.read<AppState>().api;
    final seq = ++_msgSeq;
    try {
      final data = await api.get(
        '/admin/conversation/messages',
        query: {'conv_key': _conv.convKey, 'limit': _pageSize},
      );
      if (!mounted || seq != _msgSeq) return;
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final raw = m['list'];
      final page = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <ChatMessage>[];
      // 已翻到的更早历史留在前缀里：最近一页只含最新 limit 条，直接覆盖会把用户正在看的
      // 上半段冲掉；只保留 id 小于本页最早 id 的，重叠部分由本页覆盖
      final oldestInPage = page.isEmpty ? 0 : page.first.id;
      final older = oldestInPage > 0 && _oldestLoadedId > 0
          ? _messages.where((e) => e.id < oldestInPage).toList()
          : const <ChatMessage>[];
      final list = <ChatMessage>[...older, ...page];
      final convRaw = m['conv'];
      final conv = convRaw is Map ? Map<String, dynamic>.from(convRaw) : null;
      final stick = follow || initial || _nearBottom;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
        _oldestLoadedId = list.isEmpty ? 0 : list.first.id;
        // has_more 只描述本页边界之前还有没有；前缀还在时沿用上次的判断，
        // 免得每次轮询都把已经翻到的历史当成「还有更早」
        if (older.isEmpty) _hasMoreOlder = _truthy(m['has_more']);
        if (stick) _newCount = 0;
        if (conv != null) {
          _conv = _conv.copyWith(
            status: asInt(conv['status'], _conv.status),
            agentId: asInt(conv['agent_id'], _conv.agentId),
          );
        }
      });
      if (stick) _scrollToBottom();
    } catch (e) {
      if (!mounted || seq != _msgSeq) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) _error = e.toString();
      });
      if (_messages.isNotEmpty && !silent) {
        showSnack(context, e.toString(), error: true);
      }
    }
  }

  /// 贴底：列表是按需构建的，第一帧拿到的 maxScrollExtent 只是按平均行高估算出来的值，
  /// 长会话 / 图片 / Markdown 消息往往估得偏小，只跳一次会停在半路。
  /// 这里逐帧贴着底部跳，直到滚动位置不再变化（有上限，避免空列表时空转）。
  void _scrollToBottom() {
    var tries = 0;
    void step() {
      if (!mounted) return;
      var retry = false;
      if (_scrollCtrl.hasClients && _scrollCtrl.position.hasContentDimensions) {
        final pos = _scrollCtrl.position;
        final target = pos.maxScrollExtent;
        if ((target - pos.pixels).abs() > 0.5) {
          pos.jumpTo(target);
          retry = true;
        }
      } else {
        // 列表还没挂上（加载中 / 空态），下一帧再看
        retry = true;
      }
      if (retry && ++tries < 10) {
        WidgetsBinding.instance.addPostFrameCallback((_) => step());
        // jumpTo 会自己请求新帧；列表未挂上时显式补一帧，免得回调等不到下一帧
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  /// 滚到顶部翻更早的一页（服务端 before_id 游标）
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder || _oldestLoadedId <= 0) return;
    final api = context.read<AppState>().api;
    setState(() => _loadingOlder = true);
    // 列表不是 reverse 的，prepend 后顶部偏移会变，只有「距底部距离」能稳定代指当前看的那一条
    final distance = _scrollCtrl.hasClients
        ? _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels
        : 0.0;
    try {
      final data = await api.get(
        '/admin/conversation/messages',
        query: {
          'conv_key': _conv.convKey,
          'limit': _pageSize,
          'before_id': _oldestLoadedId,
        },
      );
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final raw = m['list'];
      final page = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <ChatMessage>[];
      if (!mounted) return;
      final exists = _messages.map((e) => e.id).toSet();
      final older = page.where((e) => !exists.contains(e.id)).toList();
      if (older.isEmpty) {
        // 服务端说还有更早、实际却翻空了（期间消息被删），到此为止，别再重复请求
        setState(() => _hasMoreOlder = false);
        return;
      }
      setState(() {
        _messages = <ChatMessage>[...older, ..._messages];
        _oldestLoadedId = older.first.id;
        _hasMoreOlder = _truthy(m['has_more']);
      });
      _keepBottomDistance(distance);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// 把视口按回「距底部 distance」：与 _scrollToBottom 同理，懒列表的 maxScrollExtent
  /// 第一帧只是估算值，prepend 的历史撑开高度后要逐帧补跳才能对齐。
  void _keepBottomDistance(double distance) {
    var tries = 0;
    void step() {
      if (!mounted) return;
      var retry = false;
      if (_scrollCtrl.hasClients && _scrollCtrl.position.hasContentDimensions) {
        final pos = _scrollCtrl.position;
        final target = (pos.maxScrollExtent - distance).clamp(0.0, pos.maxScrollExtent);
        if ((target - pos.pixels).abs() > 0.5) {
          pos.jumpTo(target);
          retry = true;
        }
      } else {
        retry = true;
      }
      if (retry && ++tries < 10) {
        WidgetsBinding.instance.addPostFrameCallback((_) => step());
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  Future<void> _pollTick() async {
    if (!mounted || _polling || _loading || _loadingOlder) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _polling = true;
    try {
      await _loadMessages(silent: true);
    } finally {
      _polling = false;
    }
  }

  /// 全局 socket 的会话新消息：在底部时直接贴底，翻历史时只提示不抢滚动位置
  void _onRealtimeMsg(Map<String, dynamic> payload) {
    if (!mounted) return;
    final raw = payload['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    if (asInt(data['conversation_id']) != _conv.id) return;
    final fromVisitor = asString(data['sender']) == 'visitor';
    if (!fromVisitor || _nearBottom) {
      _loadMessages(silent: true, follow: fromVisitor);
      return;
    }
    setState(() => _newCount += 1);
  }

  void _onScroll() {
    if (_newCount > 0 && _nearBottom) setState(() => _newCount = 0);
    // 接近顶部就预取更早的一页，不等用户真的划到头
    if (_scrollCtrl.hasClients && _scrollCtrl.position.pixels < 60) _loadOlder();
  }

  /// 回到底部最新消息：双击标题 / 点「N 条新消息」共用
  void _jumpToLatest() {
    setState(() => _newCount = 0);
    // 先贴底给即时反馈，再拉一次最新消息（新消息撑高后会由 _scrollToBottom 继续补跳）
    _scrollToBottom();
    _loadMessages(silent: true, follow: true);
  }

  Future<void> _send() async {
    final text = _replyCtrl.text.trim();
    if (_sending) return;
    if (text.isEmpty && _pendingImages.isEmpty) return;
    final api = context.read<AppState>().api;
    setState(() => _sending = true);
    try {
      // 先上传图片拿地址，再和文字一起发：服务端拼成同一条消息
      final urls = await _uploadPendingImages(api);
      final data = <String, dynamic>{
        'conv_key': _conv.convKey,
        if (text.isNotEmpty) 'content': text,
        if (urls.isNotEmpty) 'images': urls,
      };
      await api.post('/admin/conversation/reply', data: data);
      _replyCtrl.clear();
      if (_pendingImages.isNotEmpty) setState(() => _pendingImages.clear());
      await _loadMessages(silent: true, follow: true);
      _replyFocus.requestFocus();
    } catch (e) {
      // 失败保留已选图片与文字，方便直接重试
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 上传待发送图片，返回服务端给出的地址（未配 OSS 时为 /public/upload/... 相对地址）
  Future<List<String>> _uploadPendingImages(ApiClient api) async {
    if (_pendingImages.isEmpty) return const [];
    final form = FormData();
    for (final f in _pendingImages) {
      form.files.add(MapEntry(
        'file[]',
        await MultipartFile.fromFile(f.path, filename: f.name.isEmpty ? null : f.name),
      ));
    }
    final data = await api.post('/admin/upload/image', data: form);
    final raw = data is Map ? data['urls'] : null;
    final urls = raw is List
        ? raw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
        : <String>[];
    if (urls.length != _pendingImages.length) {
      throw const ApiException(-1, '图片上传失败，请重试');
    }
    return urls;
  }

  /// 从相册选图（只进待发送区，不立即发送）
  Future<void> _pickImages() async {
    if (_sending) return;
    final remain = _maxImages - _pendingImages.length;
    if (remain <= 0) {
      showSnack(context, '一条消息最多发送 $_maxImages 张图片');
      return;
    }
    try {
      // 压到 1920 宽 / 质量 85：服务端限单张 5MB，直传手机原图很容易超
      final picked = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      if (!mounted || picked.isEmpty) return;
      final accepted = <XFile>[];
      var tooLarge = 0;
      for (final f in picked.take(remain)) {
        if (await f.length() > _maxImageBytes) {
          tooLarge += 1;
          continue;
        }
        accepted.add(f);
      }
      if (accepted.isNotEmpty) setState(() => _pendingImages.addAll(accepted));
      if (tooLarge > 0 && mounted) {
        showSnack(context, '$tooLarge 张图片超过 5MB，已跳过', error: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, '选择图片失败：$e', error: true);
    }
  }

  /// Markdown 里的图片：按气泡宽度缩放，点击看大图
  /// 图片消息在库里的正文是 ![图片](url)，各端统一走 Markdown 渲染
  Widget _markdownImage(MarkdownImageConfig cfg) {
    final src = _absImageUrl(cfg.uri);
    if (src.isEmpty) return const Text('[图片]');
    return GestureDetector(
      onTap: () => _previewImage(src),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: Image.network(
            src,
            fit: BoxFit.scaleDown,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: 160,
                height: 100,
                color: AppColors.panel2,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: 160,
              height: 64,
              color: AppColors.panel2,
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 13, color: AppColors.textMute),
                  SizedBox(width: 4),
                  Text('图片加载失败', style: TextStyle(fontSize: 11, color: AppColors.textMute)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 服务端未配 OSS 时图片是 /public/upload/... 相对地址，按固定域名补齐
  String _absImageUrl(Uri uri) {
    final raw = uri.toString().trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.defaultBaseUrl}$raw';
    return '';
  }

  void _previewImage(String src) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogCtx) => GestureDetector(
        onTap: () => Navigator.of(dialogCtx).pop(),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              src,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                '图片加载失败',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStatus() async {
    if (_actionBusy) return;
    final closing = _conv.status != 2;
    if (closing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭会话'),
          content: const Text('关闭后访客端将结束当前会话；之后再回复会自动重新打开。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('关闭')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final api = context.read<AppState>().api;
    setState(() => _actionBusy = true);
    try {
      await api.post(
        closing ? '/admin/conversation/close' : '/admin/conversation/reopen',
        data: {'conv_key': _conv.convKey},
      );
      if (!mounted) return;
      setState(() => _conv = _conv.copyWith(status: closing ? 2 : 0));
      showSnack(context, closing ? '会话已关闭' : '会话已重新打开');
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
      // 重试等于重新开局，分页游标一起清零，否则会把上次翻到的旧历史当前缀接回来
      _hasMoreOlder = false;
      _loadingOlder = false;
      _oldestLoadedId = 0;
    });
    _loadMessages(initial: true);
  }

  void _openFormSheet() {
    final forms = _formMessages.reversed.toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '历史表单数据（${forms.length}）',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: forms.isEmpty
                      ? const EmptyState(icon: Icons.assignment_outlined, text: '暂无表单数据')
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(14),
                          itemCount: forms.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _formDataCard(forms[i]),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // 双击标题回到底部最新消息
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _jumpToLatest,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _conv.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: _conv.status, compact: true),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${_conv.userLabel} · ${_conv.projectName.isEmpty ? '-' : _conv.projectName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
              ),
            ],
          ),
        ),
        actions: [
          if (_formMessages.isNotEmpty)
            IconButton(
              tooltip: '表单数据',
              onPressed: _openFormSheet,
              icon: Badge(
                label: Text('${_formMessages.length}'),
                child: const Icon(Icons.assignment_outlined, size: 20, color: AppColors.textDim),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textDim),
            onSelected: (v) {
              if (v == 'refresh') {
                _loadMessages(silent: true, follow: true);
              } else if (v == 'status') {
                _toggleStatus();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 17, color: AppColors.textDim),
                    SizedBox(width: 10),
                    Text('刷新消息'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'status',
                child: Row(
                  children: [
                    Icon(
                      _conv.status == 2 ? Icons.lock_open_outlined : Icons.lock_outline,
                      size: 17,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 10),
                    Text(_conv.status == 2 ? '重新打开会话' : '关闭会话'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildBody()),
                // 翻历史时新消息只计数，不抢滚动位置；点一下才贴底
                if (_newCount > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: Material(
                        color: AppColors.accent,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _jumpToLatest,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Color(0xFF04121B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_newCount 条新消息',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF04121B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildReplyBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    if (_error != null && _messages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: Icons.cloud_off_outlined,
            text: '消息加载失败',
            hint: _error,
            action: FilledButton.tonal(onPressed: _retry, child: const Text('重试')),
          ),
        ],
      );
    }
    if (_messages.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        text: '还没有消息',
        hint: '访客发来消息后会显示在这里',
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: _messages.length + 1,
      itemBuilder: (context, index) {
        // 顶栏一行留给「加载更早消息」，消息本体往后错一位
        if (index == 0) return _buildOlderHeader();
        return _buildMessage(_messages[index - 1]);
      },
    );
  }

  Widget _buildOlderHeader() {
    if (_loadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMoreOlder) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: TextButton(
          onPressed: _loadOlder,
          child: const Text('加载更早消息', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage m) {
    if (m.sender == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.panel2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            m.content,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMute, height: 1.4),
          ),
        ),
      );
    }
    // 只有自己（当前登录管理员）发的在右侧；访客、AI、其他客服都在左侧
    final mine = m.sentBy(_app.admin?.id ?? 0);
    final label = _senderLabel(m);
    final isFormData = m.msgType == 'form_data';
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * _maxTextWidthRatio / 100;

    Widget content;
    if (isFormData) {
      content = _formDataCard(m);
    } else {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: _bubble(m, mine),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            UserAvatar(url: m.senderAvatar, text: label, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.isAi) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.signal.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.signal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      fmtTime(m.createTime),
                      style: const TextStyle(fontSize: 9.5, color: AppColors.textMute),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                content,
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            UserAvatar(url: m.senderAvatar, text: label, size: 30),
          ],
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m, bool mine) {
    final showOriginal = _showOriginal[m.id] == true;
    final text = showOriginal ? m.secondaryText() : m.primaryText(_conv.userLabel);
    final isAi = m.isAi;
    final bg = mine
        ? AppColors.accent.withOpacity(0.13)
        : (isAi ? const Color(0xFF0F2029) : AppColors.panel2);
    final borderColor = mine
        ? AppColors.accent.withOpacity(0.32)
        : (isAi ? AppColors.signal.withOpacity(0.28) : AppColors.border);

    Widget body;
    if (m.msgType == 'form') {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.signal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '[ 表单 ] #${m.formId}',
              style: const TextStyle(fontSize: 11, color: AppColors.signal),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownBody(
              data: text,
              selectable: false,
              styleSheet: _mdStyle,
              sizedImageBuilder: _markdownImage,
            ),
          ],
        ],
      );
    } else {
      body = MarkdownBody(
        data: text.isEmpty ? ' ' : text,
        selectable: false,
        styleSheet: _mdStyle,
        sizedImageBuilder: _markdownImage,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(mine ? 12 : 3),
          bottomRight: Radius.circular(mine ? 3 : 12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          if (m.hasTranslation) ...[
            const SizedBox(height: 7),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showOriginal[m.id] = !showOriginal),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate, size: 12, color: AppColors.accent),
                  const SizedBox(width: 4),
                  Text(
                    showOriginal ? '显示译文' : '显示原文',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.accent),
                  ),
                  if (m.translatedLang.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      m.translatedLang,
                      style: const TextStyle(fontSize: 9.5, color: AppColors.textMute),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formDataCard(ChatMessage m) {
    final items = FormDataItem.parseList(m.content);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 14, color: AppColors.signal),
              const SizedBox(width: 6),
              Text(
                '第 ${m.formSeq} 次提交',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.signal,
                ),
              ),
              const Spacer(),
              Text(
                fmtTime(m.createTime),
                style: const TextStyle(fontSize: 9.5, color: AppColors.textMute),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text(
              '（表单内容解析失败）',
              style: TextStyle(fontSize: 12, color: AppColors.textMute),
            )
          else
            ...items.map(
              (it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        it.keyName,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textDim,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _formValue(it)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 表单值：http(s) 链接渲染成可点击文本，点在系统浏览器打开
  Widget _formValue(FormDataItem it) {
    final text = it.displayValue;
    final uri = it.linkUri;
    if (uri == null) {
      return SelectableText(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.5),
      );
    }
    return InkWell(
      onTap: () => _openFormLink(uri),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.accent,
                height: 1.5,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 3),
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.open_in_new, size: 11, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Future<void> _openFormLink(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, '无法打开链接：$uri', error: true);
    } catch (_) {
      if (mounted) showSnack(context, '无法打开链接：$uri', error: true);
    }
  }

  /// 已选待发图片的缩略图行：右上角可删除，避免误发
  Widget _attachmentStrip() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = _pendingImages[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(f.path),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    color: AppColors.panel2,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, size: 18, color: AppColors.textMute),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _sending ? null : () => setState(() => _pendingImages.removeAt(i)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pickImageButton() {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: AppColors.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _sending ? null : _pickImages,
          child: Icon(
            Icons.image_outlined,
            size: 20,
            color: _sending ? AppColors.textMute : AppColors.accent,
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    final closed = _conv.status == 2;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _attachmentStrip(),
              ),
            ],
            if (closed)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: AppColors.signal),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '会话已关闭，发送消息将自动重新打开',
                        style: TextStyle(fontSize: 10.5, color: AppColors.signal),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _pickImageButton(),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    focusNode: _replyFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入回复内容…',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _replyCtrl,
                  builder: (context, value, _) {
                    final canSend =
                        (value.text.trim().isNotEmpty || _pendingImages.isNotEmpty) && !_sending;
                    return SizedBox(
                      width: 44,
                      height: 44,
                      child: FilledButton(
                        onPressed: canSend ? _send : null,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF04121B),
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
