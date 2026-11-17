import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../l10n/app_strings.dart';
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

  // 发送前翻译预览：译文可编辑，确认后随回复一起下发（服务端不再重复翻译）
  final TextEditingController _transCtrl = TextEditingController();
  bool _transOpen = false; // 译文面板是否展开
  bool _transLoading = false; // 正在请求译文
  bool _transSame = false; // 原文已是访客语言，无需翻译
  bool _transStale = false; // 预览后原文又被改动，译文待更新
  String _transLang = ''; // 目标语言码（服务端按会话访客语言返回）
  int _transSeq = 0; // 防并发覆盖：只认最后一次预览的结果
  bool _attachOpen = false; // 微信式「+」扩展面板（图片上传 / 翻译预览）

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
  // 用户档案（查看用户信息用）：仅开放接口创建的会话(userId>0)可查，与 Web 管理端口径一致
  UserDetail? _userDetail;
  bool _userLoading = false;

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
    _replyCtrl.addListener(_onReplyChanged);
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
    _replyCtrl.removeListener(_onReplyChanged);
    _replyCtrl.dispose();
    _transCtrl.dispose();
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
    if (m.isAgent) return AppStrings.current.senderAgent;
    if (m.isAi) return AppStrings.current.senderAi;
    return AppStrings.current.senderSystem;
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
            aiPaused: asInt(conv['ai_paused'], _conv.aiPaused),
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

  /// 原文（客服输入框）变化后：已加载的译文随之过期，提示重新翻译，避免把旧译文发出去
  void _onReplyChanged() {
    if (!_transOpen || _transLoading || _transStale) return;
    setState(() => _transStale = true);
  }

  /// 微信式「+」扩展面板开合：展开时收起键盘，避免与面板争空间
  void _toggleAttachPanel() {
    setState(() => _attachOpen = !_attachOpen);
    if (_attachOpen) _replyFocus.unfocus();
  }

  void _toggleTranslationPanel() {
    if (_transOpen) {
      _closeTranslation();
    } else {
      setState(() {
        _transOpen = true;
        _transStale = false;
      });
      _runTranslationPreview();
    }
  }

  void _closeTranslation() {
    _transSeq++; // 作废在途的预览请求
    _transCtrl.clear();
    if (!mounted) return;
    setState(() {
      _transOpen = false;
      _transLoading = false;
      _transSame = false;
      _transStale = false;
      _transLang = '';
    });
  }

  /// 拉取当前原文按访客语言的译文，填入可编辑区。失败只提示，不阻断发送。
  Future<void> _runTranslationPreview() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _transLoading = false;
        _transStale = false;
      });
      return;
    }
    final api = context.read<AppState>().api;
    final seq = ++_transSeq;
    setState(() => _transLoading = true);
    try {
      final data = await api.post('/admin/conversation/translatePreview', data: {
        'conv_key': _conv.convKey,
        'content': text,
      });
      if (!mounted || seq != _transSeq) return;
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      setState(() {
        _transCtrl.text = asString(m['translated_content']);
        _transCtrl.selection =
            TextSelection.collapsed(offset: _transCtrl.text.length);
        _transLang = asString(m['translated_lang']);
        _transSame = m['same'] == true;
        _transStale = false;
        _transLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _transSeq) return;
      setState(() => _transLoading = false);
      showSnack(context, e.toString(), error: true);
    }
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
      // 面板展开且译文已确认（非过期）：把客服编辑过的译文一起下发，服务端不再重复翻译
      final translatedText = _transCtrl.text.trim();
      final useManualTranslation =
          _transOpen && text.isNotEmpty && translatedText.isNotEmpty && !_transStale;
      final data = <String, dynamic>{
        'conv_key': _conv.convKey,
        if (text.isNotEmpty) 'content': text,
        if (urls.isNotEmpty) 'images': urls,
        if (useManualTranslation) 'translated_content': translatedText,
        if (useManualTranslation && _transLang.isNotEmpty) 'translated_lang': _transLang,
      };
      await api.post('/admin/conversation/reply', data: data);
      _replyCtrl.clear();
      _closeTranslation();
      if (mounted) setState(() => _attachOpen = false);
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
      throw ApiException(-1, AppStrings.current.imageUploadFailed);
    }
    return urls;
  }

  /// 从相册选图（只进待发送区，不立即发送）
  Future<void> _pickImages() async {
    if (_sending) return;
    final remain = _maxImages - _pendingImages.length;
    if (remain <= 0) {
      showSnack(context, AppStrings.current.maxImages('$_maxImages'));
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
        showSnack(context, AppStrings.current.imagesTooLarge('$tooLarge'), error: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, AppStrings.current.pickImageFailed('$e'), error: true);
    }
  }

  /// Markdown 里的图片：按气泡宽度缩放，点击看大图
  /// 图片消息在库里的正文是 ![图片](url)，各端统一走 Markdown 渲染
  Widget _markdownImage(MarkdownImageConfig cfg) {
    final src = _absImageUrl(cfg.uri);
    if (src.isEmpty) return Text(AppStrings.current.imagePlaceholder);
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 13, color: AppColors.textMute),
                  const SizedBox(width: 4),
                  Text(
                    AppStrings.current.imageLoadFailed,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMute),
                  ),
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
              errorBuilder: (_, __, ___) => Text(
                AppStrings.current.imageLoadFailed,
                style: const TextStyle(fontSize: 13, color: Colors.white),
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
      final s = AppStrings.current;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.closeConversation),
          content: Text(s.closeConversationBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.close)),
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
      final s = AppStrings.current;
      showSnack(context, closing ? s.conversationClosed : s.conversationReopened);
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// 手动暂停/恢复AI回答: 不依赖访客转人工, 不改会话状态
  Future<void> _toggleAi() async {
    if (_actionBusy) return;
    final pausing = _conv.aiPaused != 1;
    final api = context.read<AppState>().api;
    setState(() => _actionBusy = true);
    try {
      await api.post(
        '/admin/conversation/toggle-ai',
        data: {'conv_key': _conv.convKey, 'paused': pausing ? 1 : 0},
      );
      if (!mounted) return;
      setState(() => _conv = _conv.copyWith(aiPaused: pausing ? 1 : 0));
      final s = AppStrings.current;
      showSnack(context, pausing ? s.aiPaused : s.aiResumed);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// 会话转移 / 指定客服：拉取可分配成员，弹层选择后调用 assign。
  /// status==0：替访客转人工并指定负责人；status==1：转交给另一位；status==2 不提供入口。
  Future<void> _openAssignSheet() async {
    if (_actionBusy) return;
    final s = AppStrings.current;
    final api = context.read<AppState>().api;
    setState(() => _actionBusy = true);
    List<Map<String, dynamic>> candidates;
    try {
      final data = await api.get(
        '/admin/conversation/assign-candidates',
        query: {'conv_key': _conv.convKey},
      );
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      candidates = ((m['list'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
      if (mounted) setState(() => _actionBusy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _actionBusy = false);
    final isReassign = _conv.status == 1;
    int pick = _defaultAssignPick(candidates);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderStrong,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isReassign ? s.reassign : s.assign,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    const SizedBox(height: 6),
                    Text(s.assignTip,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textDim, height: 1.4)),
                    const SizedBox(height: 8),
                    if (candidates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(s.assignEmpty,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMute)),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final a in candidates)
                                _assignRow(
                                  a: a,
                                  selected: pick == asInt(a['id']),
                                  onTap: a['current'] == true
                                      ? null
                                      : () => setSheet(() => pick = asInt(a['id'])),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting ? null : () => Navigator.pop(sheetCtx),
                            child: Text(s.cancel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: (submitting || pick == 0)
                                ? null
                                : () async {
                                    setSheet(() => submitting = true);
                                    try {
                                      final data = await api.post(
                                        '/admin/conversation/assign',
                                        data: {
                                          'conv_key': _conv.convKey,
                                          'agent_id': pick,
                                        },
                                      );
                                      final d = data is Map
                                          ? Map<String, dynamic>.from(data)
                                          : const <String, dynamic>{};
                                      final name = asString(d['agent_name']);
                                      if (mounted) {
                                        setState(() => _conv = _conv.copyWith(
                                              agentId: asInt(d['agent_id']),
                                              agentName: name,
                                              status: d.containsKey('status')
                                                  ? asInt(d['status'])
                                                  : null));
                                      }
                                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                      if (mounted) showSnack(context, s.assignDone(name));
                                      await _loadMessages(silent: true, follow: true);
                                    } catch (e) {
                                      if (sheetCtx.mounted) {
                                        setSheet(() => submitting = false);
                                        showSnack(sheetCtx, e.toString(), error: true);
                                      }
                                    }
                                  },
                            child: submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(s.confirm),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 默认选在线且接待量最少的一位（与服务端自动分配同优先级），没人在线退到离线负载最少
  int _defaultAssignPick(List<Map<String, dynamic>> list) {
    int best = 0, bestLoad = 1 << 30, bestId = 1 << 30;
    int fb = 0, fbLoad = 1 << 30, fbId = 1 << 30;
    for (final a in list) {
      if (a['current'] == true) continue;
      final id = asInt(a['id']);
      final load = asInt(a['load']);
      if (load < fbLoad || (load == fbLoad && id < fbId)) {
        fbLoad = load;
        fbId = id;
        fb = id;
      }
      if (a['online'] == true && (load < bestLoad || (load == bestLoad && id < bestId))) {
        bestLoad = load;
        bestId = id;
        best = id;
      }
    }
    return best != 0 ? best : fb;
  }

  Widget _assignRow({
    required Map<String, dynamic> a,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final s = AppStrings.current;
    final online = a['online'] == true;
    final onDuty = a['on_duty'] == true;
    final current = a['current'] == true;
    final load = asInt(a['load']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent.withOpacity(0.4) : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? AppColors.ok : AppColors.textMute,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  asString(a['name']),
                  style: TextStyle(
                      fontSize: 13,
                      color: current ? AppColors.textMute : AppColors.text),
                ),
              ),
              if (current)
                _assignBadge(s.assignCurrent, AppColors.accent)
              else if (!onDuty)
                _assignBadge(s.assignOffDuty, AppColors.textMute),
              const SizedBox(width: 8),
              Text(online ? s.online : s.offline,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
              const SizedBox(width: 8),
              Text(s.agentLoad('$load'),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMute)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assignBadge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 9.5, color: color, height: 1.2)),
      ),
    );
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
                    AppStrings.current.historyForms('${forms.length}'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: forms.isEmpty
                      ? EmptyState(
                          icon: Icons.assignment_outlined,
                          text: AppStrings.current.noForms,
                        )
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

  /// 拉取会话对象的用户档案并弹出信息面板（对应 Web 管理端「查看用户信息」）
  Future<void> _openUserInfo() async {
    if (_userLoading) return;
    final api = context.read<AppState>().api;
    setState(() {
      _userLoading = true;
      _userDetail = null;
    });
    try {
      final data = await api.get('/admin/user/detail', query: {'id': _conv.userId});
      if (!mounted) return;
      setState(() {
        _userDetail =
            data is Map ? UserDetail.fromJson(Map<String, dynamic>.from(data)) : null;
        _userLoading = false;
      });
      _showUserInfoSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _userLoading = false);
      showSnack(context, AppStrings.current.userInfoLoadFailed, error: true);
    }
  }

  /// 用户信息面板：字段与 Web 管理端弹窗一致（姓名/账号/手机号/邮箱/外部用户ID/项目/注册时间/备注）
  void _showUserInfoSheet() {
    final detail = _userDetail;
    if (detail == null) return;
    final s = AppStrings.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  s.userInfo,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: Column(
                    children: [
                      _UserInfoRow(label: s.userName, value: detail.name.isEmpty ? '-' : detail.name),
                      _UserInfoRow(label: s.userAccount, value: detail.account.isEmpty ? '-' : detail.account),
                      _UserInfoRow(label: s.userPhone, value: detail.phone.isEmpty ? '-' : detail.phone),
                      _UserInfoRow(label: s.userEmail, value: detail.email.isEmpty ? '-' : detail.email),
                      _UserInfoRow(
                          label: s.userExternalId,
                          value: detail.externalUserId.isEmpty ? '-' : detail.externalUserId),
                      _UserInfoRow(label: s.userProject, value: _conv.projectName.isEmpty ? '-' : _conv.projectName),
                      _UserInfoRow(
                          label: s.userRegTime,
                          value: detail.createTime == null ? '-' : fmtDateTime(detail.createTime)),
                      if (detail.remark.isNotEmpty)
                        _UserInfoRow(label: s.userRemark, value: detail.remark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
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
                  // AI被手动暂停时挂个警示胶囊, 客服一眼能看出这条会话机器人不再接话
                  if (_conv.aiPaused == 1 && _conv.status != 2) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.signal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.signal.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        s.aiPaused,
                        style: const TextStyle(color: AppColors.signal, fontSize: 10, height: 1.2),
                      ),
                    ),
                  ],
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
          // 仅开放接口创建的会话(userId>0)才有用户档案，与 Web 管理端的按钮显示条件一致
          if (_conv.userId > 0)
            IconButton(
              tooltip: s.userInfo,
              onPressed: _openUserInfo,
              icon: const Icon(Icons.person_outline, size: 20, color: AppColors.textDim),
            ),
          if (_formMessages.isNotEmpty)
            IconButton(
              tooltip: s.formData,
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
              } else if (v == 'ai') {
                _toggleAi();
              } else if (v == 'assign') {
                _openAssignSheet();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh, size: 17, color: AppColors.textDim),
                    const SizedBox(width: 10),
                    Text(s.refreshMessages),
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
                    Text(_conv.status == 2 ? s.reopenConversation : s.closeConversation),
                  ],
                ),
              ),
              if (_conv.status != 2)
                PopupMenuItem<String>(
                  value: 'assign',
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz_outlined,
                          size: 17, color: AppColors.textDim),
                      const SizedBox(width: 10),
                      Text(_conv.status == 1 ? s.reassign : s.assign),
                    ],
                  ),
                ),
              PopupMenuItem<String>(
                value: 'ai',
                child: Row(
                  children: [
                    Icon(
                      _conv.aiPaused == 1 ? Icons.play_circle_outline : Icons.pause_circle_outline,
                      size: 17,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 10),
                    Text(_conv.aiPaused == 1 ? s.resumeAi : s.pauseAi),
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
                                  s.newMessages('$_newCount'),
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
            text: AppStrings.current.messageLoadFailed,
            hint: _error,
            action: FilledButton.tonal(
              onPressed: _retry,
              child: Text(AppStrings.current.retry),
            ),
          ),
        ],
      );
    }
    if (_messages.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        text: AppStrings.current.noMessages,
        hint: AppStrings.current.noMessagesHint,
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
          child: Text(
            AppStrings.current.loadOlder,
            style: const TextStyle(fontSize: 12),
          ),
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
          child: SelectableText(
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
              AppStrings.current.formTag('${m.formId}'),
              style: const TextStyle(fontSize: 11, color: AppColors.signal),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: _mdStyle,
              sizedImageBuilder: _markdownImage,
            ),
          ],
        ],
      );
    } else {
      body = MarkdownBody(
        data: text.isEmpty ? ' ' : text,
        selectable: true,
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
                    showOriginal
                        ? AppStrings.current.showTranslation
                        : AppStrings.current.showOriginal,
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
                AppStrings.current.formSubmitNo('${m.formSeq}'),
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
            Text(
              AppStrings.current.formParseFailed,
              style: const TextStyle(fontSize: 12, color: AppColors.textMute),
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
      if (!ok && mounted) {
        showSnack(context, AppStrings.current.openLinkFailed('$uri'), error: true);
      }
    } catch (_) {
      if (mounted) showSnack(context, AppStrings.current.openLinkFailed('$uri'), error: true);
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

  /// 「+」按钮：微信式，点开 / 收起扩展面板
  Widget _attachButton() {
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
          onTap: _sending ? null : _toggleAttachPanel,
          child: Icon(
            _attachOpen ? Icons.close_rounded : Icons.add_rounded,
            size: 22,
            color: _sending ? AppColors.textMute : AppColors.textDim,
          ),
        ),
      ),
    );
  }

  /// 微信式扩展面板：图片上传、翻译预览都收在「+」里
  Widget _attachPanel() {
    final s = AppStrings.current;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _replyCtrl,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return Row(
            children: [
              _attachTile(
                icon: Icons.image_outlined,
                label: s.attachImage,
                enabled: !_sending,
                onTap: () {
                  setState(() => _attachOpen = false);
                  _pickImages();
                },
              ),
              const SizedBox(width: 18),
              _attachTile(
                icon: Icons.translate,
                label: s.previewTranslation,
                enabled: !_sending && (_transOpen || hasText),
                onTap: () {
                  setState(() => _attachOpen = false);
                  if (!_transOpen) _toggleTranslationPanel();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _attachTile({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color = enabled ? AppColors.textDim : AppColors.textMute;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.panel2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 译文预览/编辑面板：展示将下发给访客(H5)的译文，可编辑；确认后随回复发送且不再重译
  Widget _translationPreviewPanel() {
    final s = AppStrings.current;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate, size: 13, color: AppColors.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  s.visitorWillSee,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ),
              if (_transLang.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _transLang,
                    style: const TextStyle(
                        fontSize: 9.5, color: AppColors.accent, height: 1.2),
                  ),
                ),
              ],
              if (_transLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: s.retranslate,
                onPressed: _transLoading ? null : _runTranslationPreview,
                icon: const Icon(Icons.refresh, size: 16, color: AppColors.textDim),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: s.close,
                onPressed: _closeTranslation,
                icon: const Icon(Icons.close, size: 16, color: AppColors.textMute),
              ),
            ],
          ),
          if (_transSame && !_transLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                s.translationSameLang,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
              ),
            )
          else if (_transStale)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                s.translationStale,
                style: const TextStyle(fontSize: 10.5, color: AppColors.signal),
              ),
            ),
          TextField(
            controller: _transCtrl,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
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
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 12, color: AppColors.signal),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        AppStrings.current.closedBarHint,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.signal),
                      ),
                    ),
                  ],
                ),
              ),
            if (_transOpen) _translationPreviewPanel(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _attachButton(),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    focusNode: _replyFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: AppStrings.current.replyHint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            if (_attachOpen) _attachPanel(),
          ],
        ),
      ),
    );
  }
}

/// 用户信息面板行：点击值即可复制（占位符"-"不可复制）
/// 复制后尾部图标短暂变绿色对勾：SnackBar 会被底部弹窗遮挡，改用行内反馈
class _UserInfoRow extends StatefulWidget {
  const _UserInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  State<_UserInfoRow> createState() => _UserInfoRowState();
}

class _UserInfoRowState extends State<_UserInfoRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
    SemanticsService.sendAnnouncement(
        View.of(context), AppStrings.current.copied, TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    final copyable = widget.value != '-';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: copyable
                ? InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.value,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.text, height: 1.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              _copied ? Icons.check_rounded : Icons.copy_rounded,
                              size: 13,
                              color: _copied ? AppColors.ok : AppColors.textMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Text(
                    widget.value,
                    style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.5),
                  ),
          ),
        ],
      ),
    );
  }
}
