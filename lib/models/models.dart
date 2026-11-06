import 'dart:convert';

import '../utils/format.dart';

int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

String asTrimString(dynamic v, [String fallback = '']) => asString(v, fallback).trim();

/// 登录后的管理员身份。登录接口和 /admin/profile 字段略有差异，统一收在这里。
class AdminUser {
  final int id;
  final String account;
  final String name;
  final String nickname;
  final String avatar;
  final String role;
  final String prefLang;
  final bool autoTranslate;
  /// 接单状态(会话页的上线/下线)：下线只是不再接受新会话分配
  final bool onlineStatus;
  final bool isPlatform;
  final bool isOwner;
  final int tenantId;
  final String companyName;
  final int currentTenantId;
  final String currentTenantName;

  AdminUser({
    required this.id,
    required this.account,
    required this.name,
    required this.nickname,
    required this.avatar,
    required this.role,
    required this.prefLang,
    required this.autoTranslate,
    required this.onlineStatus,
    required this.isPlatform,
    required this.isOwner,
    required this.tenantId,
    required this.companyName,
    required this.currentTenantId,
    required this.currentTenantName,
  });

  bool get isAdmin => role == 'admin' || isPlatform;

  String get displayName {
    if (nickname.isNotEmpty) return nickname;
    if (name.isNotEmpty) return name;
    return account;
  }

  factory AdminUser.fromLogin(Map<String, dynamic> m) {
    return AdminUser(
      id: asInt(m['admin_id']),
      account: asString(m['account']),
      name: asString(m['name']),
      nickname: asString(m['nickname']),
      avatar: asString(m['avatar']),
      role: asString(m['role'], 'agent'),
      prefLang: asString(m['pref_lang'], 'zh'),
      autoTranslate: asInt(m['auto_translate']) == 1,
      // 老版本服务端没有这一列，按在线处理（与列默认值一致）
      onlineStatus: asInt(m['online_status'], 1) == 1,
      isPlatform: asInt(m['is_platform']) == 1,
      isOwner: asInt(m['is_owner']) == 1,
      tenantId: asInt(m['tenant_id']),
      companyName: asString(m['company_name']),
      currentTenantId: asInt(m['current_tenant_id']),
      currentTenantName: asString(m['current_tenant_name']),
    );
  }

  /// /admin/profile 返回的是 id + tenant_id(当前上下文)
  factory AdminUser.fromProfile(Map<String, dynamic> m) {
    return AdminUser(
      id: asInt(m['id']),
      account: asString(m['account']),
      name: asString(m['name']),
      nickname: asString(m['nickname']),
      avatar: asString(m['avatar']),
      role: asString(m['role'], 'agent'),
      prefLang: asString(m['pref_lang'], 'zh'),
      autoTranslate: asInt(m['auto_translate']) == 1,
      onlineStatus: asInt(m['online_status'], 1) == 1,
      isPlatform: asInt(m['is_platform']) == 1,
      isOwner: asInt(m['is_owner']) == 1,
      tenantId: asInt(m['tenant_id']),
      companyName: asString(m['company_name']),
      currentTenantId: asInt(m['tenant_id']),
      currentTenantName: asString(m['company_name']),
    );
  }

  AdminUser copyWith({bool? autoTranslate, bool? onlineStatus}) {
    return AdminUser(
      id: id,
      account: account,
      name: name,
      nickname: nickname,
      avatar: avatar,
      role: role,
      prefLang: prefLang,
      autoTranslate: autoTranslate ?? this.autoTranslate,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      isPlatform: isPlatform,
      isOwner: isOwner,
      tenantId: tenantId,
      companyName: companyName,
      currentTenantId: currentTenantId,
      currentTenantName: currentTenantName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'account': account,
        'name': name,
        'nickname': nickname,
        'avatar': avatar,
        'role': role,
        'pref_lang': prefLang,
        'auto_translate': autoTranslate ? 1 : 0,
        'online_status': onlineStatus ? 1 : 0,
        'is_platform': isPlatform ? 1 : 0,
        'is_owner': isOwner ? 1 : 0,
        'tenant_id': tenantId,
        'company_name': companyName,
        'current_tenant_id': currentTenantId,
        'current_tenant_name': currentTenantName,
      };

  factory AdminUser.fromJson(Map<String, dynamic> m) => AdminUser.fromProfile(m);
}

class Tenant {
  final int id;
  final String companyName;

  const Tenant({required this.id, required this.companyName});

  factory Tenant.fromJson(Map<String, dynamic> m) => Tenant(
        id: asInt(m['id']),
        companyName: asString(m['company_name']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'company_name': companyName};
}

class Project {
  final int id;
  final String name;

  const Project({required this.id, required this.name});

  factory Project.fromJson(Map<String, dynamic> m) => Project(
        id: asInt(m['id']),
        name: asString(m['name']),
      );
}

/// 会话列表项，字段与 controller/conversation.js 的 list 保持一致
class Conversation {
  final int id;
  final int projectId;
  final String convKey;
  final String visitorId;
  final String userName;
  final String title;
  final int status;
  final int agentId;
  final String agentName;
  final int adminUnread;
  final DateTime? lastMsgTime;
  final DateTime? createTime;
  final String projectName;
  /// 最新一条消息的预览（服务端已压成单行：图片→[图片]、表单数据→[表单数据]）
  /// 列表接口字段是 last_msg，socket 会话摘要字段是 preview
  final String lastMsg;

  Conversation({
    required this.id,
    required this.projectId,
    required this.convKey,
    required this.visitorId,
    required this.userName,
    required this.title,
    required this.status,
    required this.agentId,
    required this.agentName,
    required this.adminUnread,
    required this.lastMsgTime,
    required this.createTime,
    required this.projectName,
    required this.lastMsg,
  });

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (userName.isNotEmpty) return userName;
    return visitorId;
  }

  String get userLabel => userName.isNotEmpty ? userName : visitorId;

  Conversation copyWith({int? status, int? agentId, String? agentName, int? adminUnread}) {
    return Conversation(
      id: id,
      projectId: projectId,
      convKey: convKey,
      visitorId: visitorId,
      userName: userName,
      title: title,
      status: status ?? this.status,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      adminUnread: adminUnread ?? this.adminUnread,
      lastMsgTime: lastMsgTime,
      createTime: createTime,
      projectName: projectName,
      lastMsg: lastMsg,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> m) => Conversation(
        id: asInt(m['id']),
        projectId: asInt(m['project_id']),
        convKey: asString(m['conv_key']),
        visitorId: asString(m['visitor_id']),
        userName: asString(m['user_name']),
        title: asString(m['title']),
        status: asInt(m['status']),
        agentId: asInt(m['agent_id']),
        agentName: asString(m['agent_name']),
        adminUnread: asInt(m['admin_unread']),
        lastMsgTime: parseServerTime(m['last_msg_time']),
        createTime: parseServerTime(m['create_time']),
        projectName: asString(m['project_name']),
        lastMsg: asString(m['last_msg']).isNotEmpty
            ? asString(m['last_msg'])
            : asString(m['preview']),
      );
}

/// 消息。form_data 是开放接口提交的结构化数据，content 为 JSON 数组字符串。
class ChatMessage {
  final int id;
  final String sender; // visitor / agent / ai / system
  final String msgType; // text / form / form_data / transfer ...
  final int formId; // msgType=form 时指向 chat_form
  final int agentId; // 客服消息的发送者 admin_id，用于区分「我发的」与「其他客服发的」
  final String content;
  final String translatedContent;
  final String translatedLang;
  final String senderName;
  final String senderAvatar;
  final DateTime? createTime;
  int formSeq; // 同一会话内 form_data 的提交批次，最早为 1（服务端按会话全局顺序给，分页后也稳定）

  ChatMessage({
    required this.id,
    required this.sender,
    required this.msgType,
    required this.formId,
    required this.agentId,
    required this.content,
    required this.translatedContent,
    required this.translatedLang,
    required this.senderName,
    required this.senderAvatar,
    required this.createTime,
    this.formSeq = 0,
  });

  bool get isVisitor => sender == 'visitor';
  bool get isAgent => sender == 'agent';
  bool get isAi => sender == 'ai';

  /// 是否是当前登录管理员自己发的（历史消息 agent_id=0 无法确认，按他人处理）
  bool sentBy(int adminId) => isAgent && adminId > 0 && agentId == adminId;

  bool get hasTranslation =>
      translatedContent.isNotEmpty && translatedContent != content;

  /// 与管理端一致：客服消息优先展示原文，访客/AI 消息优先展示译文
  String primaryText(String visitorName) {
    if (isAgent) return content;
    return hasTranslation ? translatedContent : content;
  }

  String secondaryText() {
    if (isAgent) return translatedContent;
    return content;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> m) => ChatMessage(
        id: asInt(m['id']),
        sender: asString(m['sender']),
        msgType: asString(m['msg_type'], 'text'),
        formId: asInt(m['form_id']),
        agentId: asInt(m['agent_id']),
        content: asString(m['content']),
        translatedContent: asString(m['translated_content']),
        translatedLang: asString(m['translated_lang']),
        senderName: asString(m['sender_name']),
        senderAvatar: asString(m['sender_avatar']),
        createTime: parseServerTime(m['create_time']),
        formSeq: asInt(m['form_seq']),
      );
}

/// 表单数据消息里一行：项目名 + 值（可能来自不同控件类型）
class FormDataItem {
  final String keyName;
  final String type;
  final dynamic value;

  const FormDataItem({required this.keyName, required this.type, required this.value});

  static List<FormDataItem> parseList(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        return FormDataItem(
          keyName: asString(m['key_name']),
          type: asString(m['type']),
          value: m['key_value'],
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 把值转成一行可读文本（曲线/柱状数据拆成「轴: 值」序列）
  String get displayValue {
    switch (type) {
      case 'link':
        return asString(value);
      case 'tags':
        if (value is List) return value.map((e) => asString(e)).where((e) => e.isNotEmpty).join('、');
        return asString(value);
      case 'curve_graph':
      case 'bar_chart':
        if (value is Map) {
          final x = (value['x'] is List) ? value['x'] as List : const [];
          final y = (value['y'] is List) ? value['y'] as List : const [];
          final n = y.isEmpty ? 0 : (x.isEmpty ? y.length : (x.length < y.length ? x.length : y.length));
          final parts = <String>[];
          for (var i = 0; i < n; i++) {
            final label = asString(x.length > i ? x[i] : '').trim();
            parts.add(label.isEmpty ? _fdNum(y[i]) : '$label: ${_fdNum(y[i])}');
          }
          return parts.join(', ');
        }
        return asString(value);
      default:
        return asString(value);
    }
  }

  /// 可点击打开的 http(s) 链接：`link` 类型或值本身就是绝对地址时返回 Uri
  Uri? get linkUri {
    final text = displayValue.trim();
    if (!text.startsWith('http://') && !text.startsWith('https://')) return null;
    return Uri.tryParse(text);
  }

  static String _fdNum(dynamic v) {
    final n = double.tryParse(asString(v));
    if (n == null || n.isNaN || n.isInfinite) return '';
    final a = n.abs();
    if (a >= 1000) return n.round().toString();
    if (a >= 10) {
      final s = n.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }
    var s = n.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}

/// 统计总数
class StatsTotals {
  final int conversations;
  final int aiAnswers;
  final double? aiPerConversation;
  final int humanConversations;
  final double? humanRate;
  final int transferRequests;
  final int kbSearches;
  final int kbHits;
  final double? kbHitRate;

  const StatsTotals({
    required this.conversations,
    required this.aiAnswers,
    required this.aiPerConversation,
    required this.humanConversations,
    required this.humanRate,
    required this.transferRequests,
    required this.kbSearches,
    required this.kbHits,
    required this.kbHitRate,
  });

  static const empty = StatsTotals(
    conversations: 0,
    aiAnswers: 0,
    aiPerConversation: null,
    humanConversations: 0,
    humanRate: null,
    transferRequests: 0,
    kbSearches: 0,
    kbHits: 0,
    kbHitRate: null,
  );

  factory StatsTotals.fromJson(Map<String, dynamic> m) => StatsTotals(
        conversations: asInt(m['conversations']),
        aiAnswers: asInt(m['ai_answers']),
        aiPerConversation: asDoubleOrNull(m['ai_per_conversation']),
        humanConversations: asInt(m['human_conversations']),
        humanRate: asDoubleOrNull(m['human_rate']),
        transferRequests: asInt(m['transfer_requests']),
        kbSearches: asInt(m['kb_searches']),
        kbHits: asInt(m['kb_hits']),
        kbHitRate: asDoubleOrNull(m['kb_hit_rate']),
      );
}

class StatsPoint {
  final String date;
  final int conversations;
  final int aiAnswers;
  final int humanConversations;
  final int transfers;
  final int kbSearches;
  final int kbHits;

  const StatsPoint({
    required this.date,
    required this.conversations,
    required this.aiAnswers,
    required this.humanConversations,
    required this.transfers,
    required this.kbSearches,
    required this.kbHits,
  });

  factory StatsPoint.fromJson(Map<String, dynamic> m) => StatsPoint(
        date: asString(m['date']),
        conversations: asInt(m['conversations']),
        aiAnswers: asInt(m['ai_answers']),
        humanConversations: asInt(m['human_conversations']),
        transfers: asInt(m['transfers']),
        kbSearches: asInt(m['kb_searches']),
        kbHits: asInt(m['kb_hits']),
      );
}

class KeywordCount {
  final String word;
  final int count;

  const KeywordCount({required this.word, required this.count});

  factory KeywordCount.fromJson(Map<String, dynamic> m) => KeywordCount(
        word: asString(m['word']),
        count: asInt(m['count']),
      );
}

class TopKnowledge {
  final int id;
  final String title;
  final int count;

  const TopKnowledge({required this.id, required this.title, required this.count});

  factory TopKnowledge.fromJson(Map<String, dynamic> m) => TopKnowledge(
        id: asInt(m['id']),
        title: asString(m['title']),
        count: asInt(m['count']),
      );
}

class StatsSummary {
  final String content;
  final String model;
  final DateTime? updateTime;

  const StatsSummary({required this.content, required this.model, required this.updateTime});

  factory StatsSummary.fromJson(Map<String, dynamic> m) => StatsSummary(
        content: asString(m['content']),
        model: asString(m['model']),
        updateTime: parseServerTime(m['update_time'] ?? m['create_time']),
      );
}

class StatsData {
  final int days;
  final String rangeStart;
  final String rangeEnd;
  final List<StatsPoint> series;
  final StatsTotals totals;
  final List<KeywordCount> keywords;
  final List<TopKnowledge> topKnowledge;
  final StatsSummary? summary;

  const StatsData({
    required this.days,
    required this.rangeStart,
    required this.rangeEnd,
    required this.series,
    required this.totals,
    required this.keywords,
    required this.topKnowledge,
    required this.summary,
  });

  static const empty = StatsData(
    days: 30,
    rangeStart: '',
    rangeEnd: '',
    series: [],
    totals: StatsTotals.empty,
    keywords: [],
    topKnowledge: [],
    summary: null,
  );

  factory StatsData.fromJson(Map<String, dynamic> m) {
    final range = m['range'];
    final rangeMap = range is Map ? Map<String, dynamic>.from(range) : const <String, dynamic>{};
    final totalsRaw = m['totals'];
    final keywordsRaw = m['keywords'];
    final topRaw = m['top_knowledge'];
    final seriesRaw = m['series'];
    final summaryRaw = m['summary'];
    return StatsData(
      days: asInt(m['days'], 30),
      rangeStart: asString(rangeMap['start']),
      rangeEnd: asString(rangeMap['end']),
      series: seriesRaw is List
          ? seriesRaw.whereType<Map>().map((e) => StatsPoint.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      totals: totalsRaw is Map ? StatsTotals.fromJson(Map<String, dynamic>.from(totalsRaw)) : StatsTotals.empty,
      keywords: keywordsRaw is List
          ? keywordsRaw.whereType<Map>().map((e) => KeywordCount.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      topKnowledge: topRaw is List
          ? topRaw.whereType<Map>().map((e) => TopKnowledge.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      summary: summaryRaw is Map ? StatsSummary.fromJson(Map<String, dynamic>.from(summaryRaw)) : null,
    );
  }
}
