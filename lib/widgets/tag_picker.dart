import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 标签未指定颜色时按 id 循环取色（与 Web 后台同一色板，保证同标签处处同色）。
const List<Color> kTagPalette = [
  Color(0xFF4BA6DE), // 蓝
  Color(0xFF4CAF7D), // 绿
  Color(0xFFE2A03F), // 琥珀
  Color(0xFFE0705F), // 红
  Color(0xFF9B7FD4), // 紫
  Color(0xFF3FB8AF), // 青
  Color(0xFFD4749B), // 粉
  Color(0xFF8AA0B4), // 灰蓝
];

/// 解析标签色值：支持 #RRGGBB / RRGGBB / #AARRGGBB，非法或空则回落到 id 对应的色板色。
Color tagColor(Tag tag) {
  final raw = tag.color.trim().replaceFirst('#', '');
  if (raw.length == 6 || raw.length == 8) {
    final hex = raw.length == 6 ? 'FF$raw' : raw;
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(v);
  }
  return kTagPalette[tag.id.abs() % kTagPalette.length];
}

/// 拉取本租户标签全量目录（勾选弹层与管理页共用）。
Future<List<Tag>> fetchTagCatalog(ApiClient api) async {
  final data = await api.get('/admin/tag/list');
  final m = data is Map
      ? Map<String, dynamic>.from(data)
      : const <String, dynamic>{};
  final raw = m['list'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Tag.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

/// 展示用的小标签芯片行（联系人列表/详情、聊天页头部）。
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tags, this.dense = false});

  final List<Tag> tags;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: dense ? 3 : 5,
      children: [for (final t in tags) _chip(t)],
    );
  }

  Widget _chip(Tag tag) {
    final color = tagColor(tag);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        tag.name,
        style: TextStyle(fontSize: dense ? 10 : 11, height: 1.2, color: color),
      ),
    );
  }
}

/// 标签选择弹层：勾选本租户标签并保存（全量覆盖）。
/// 客服与管理员都能勾选；[canManage] 为真时额外显示「管理标签」入口（增删改）。
/// 保存成功后回调最新选中的标签列表，供调用方就地更新 UI。
Future<void> showTagPickerSheet(
  BuildContext context, {
  required ApiClient api,
  required int userId,
  required List<Tag> assigned,
  required bool canManage,
  required void Function(List<Tag> result) onSaved,
}) async {
  final s = AppStrings.current;
  List<Tag> catalog = const [];
  final picked = <int>{...assigned.map((t) => t.id)};
  bool loading = true;
  bool saving = false;
  String? error;
  String query = '';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // edge-to-edge(Android 15 强制)下弹层会铺到状态栏底下, 标题与状态栏重叠;
    // useSafeArea 让弹层避开顶部/左右系统侵入, 底部仍需自己预留(见下)
    useSafeArea: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> loadCatalog() async {
            setSheetState(() {
              loading = true;
              error = null;
            });
            try {
              final list = await fetchTagCatalog(api);
              setSheetState(() {
                catalog = list;
                loading = false;
              });
            } catch (e) {
              setSheetState(() {
                loading = false;
                error = e.toString();
              });
            }
          }

          if (loading && catalog.isEmpty) loadCatalog();

          Future<void> save() async {
            if (saving) return;
            setSheetState(() => saving = true);
            try {
              await api.post(
                '/admin/tag/assign',
                data: {'user_id': userId, 'tag_ids': picked.toList()},
              );
              final result = catalog
                  .where((t) => picked.contains(t.id))
                  .toList();
              if (ctx.mounted) Navigator.pop(ctx);
              onSaved(result);
              if (ctx.mounted) showSnack(ctx, s.tagsUpdated);
            } catch (e) {
              setSheetState(() => saving = false);
              if (ctx.mounted) showSnack(ctx, e.toString(), error: true);
            }
          }

          Future<void> openManage() async {
            final fresh = await showTagManageSheet(ctx, api: api);
            if (fresh != null) {
              // 管理后目录可能增删改，同步去掉已不存在标签的勾选
              final ids = fresh.map((t) => t.id).toSet();
              setSheetState(() {
                catalog = fresh;
                picked.removeWhere((id) => !ids.contains(id));
              });
            }
          }

          // 键盘弹出时 viewInsets 盖过导航条, 收起时用 padding.bottom 垫高,
          // 取两者较大值作底部留白, 避免保存/取消按钮被系统虚拟按键遮挡
          final mq = MediaQuery.of(ctx);
          final bottomGap = mq.viewInsets.bottom > mq.padding.bottom
              ? mq.viewInsets.bottom
              : mq.padding.bottom;
          // 搜索只影响展示勾选列表; picked/save 仍走全量 catalog, 收起关键词后勾选不丢
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? catalog
              : catalog.where((t) => t.name.toLowerCase().contains(q)).toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGap + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.setTags,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (canManage)
                      TextButton.icon(
                        onPressed: openManage,
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(
                          s.manageTags,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (catalog.isNotEmpty)
                  _TagSearchField(
                    hint: s.searchTags,
                    onChanged: (v) => setSheetState(() => query = v),
                  ),
                Flexible(
                  child: loading && catalog.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : error != null && catalog.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.danger,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: loadCatalog,
                                child: Text(s.retry),
                              ),
                            ],
                          ),
                        )
                      : catalog.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              Text(
                                s.noTags,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                canManage ? s.noTagsHintManage : s.noTagsHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMute,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            s.noTagMatch,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMute,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (var i = 0; i < shown.length; i++)
                              _buildTagOption(
                                ctx,
                                shown[i],
                                picked.contains(shown[i].id),
                                (checked) {
                                  setSheetState(() {
                                    if (checked) {
                                      picked.add(shown[i].id);
                                    } else {
                                      picked.remove(shown[i].id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: Text(s.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (saving || catalog.isEmpty && error != null)
                            ? null
                            : save,
                        child: Text(s.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// 弹层内的标签搜索框: controller 由自身 State 持有并在真正卸载时 dispose,
/// 避免重蹈旧 bug(弹层关闭动画期间外层提前 dispose 导致渲染崩乱)。
class _TagSearchField extends StatefulWidget {
  const _TagSearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TagSearchField> createState() => _TagSearchFieldState();
}

class _TagSearchFieldState extends State<_TagSearchField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (v) {
          widget.onChanged(v);
          // 控制清除按钮的显隐(局部重建, 不影响弹层列表状态)
          setState(() {});
        },
      ),
    );
  }
}

Widget _buildTagOption(
  BuildContext context,
  Tag tag,
  bool checked,
  ValueChanged<bool> onChanged,
) {
  final color = tagColor(tag);
  return InkWell(
    onTap: () => onChanged(!checked),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: checked ? color : AppColors.textMute,
          ),
          const SizedBox(width: 10),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tag.name,
              style: const TextStyle(fontSize: 13.5, color: AppColors.text),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 管理标签弹层（仅管理员调用）：新增 / 改名 / 删除本租户标签。
/// 关闭时返回操作后的最新全量目录；若一次都没成功改动则返回 null。
Future<List<Tag>?> showTagManageSheet(
  BuildContext context, {
  required ApiClient api,
}) {
  final s = AppStrings.current;
  List<Tag> catalog = const [];
  bool loading = true;
  bool changed = false;
  String query = '';
  return showModalBottomSheet<List<Tag>>(
    context: context,
    isScrollControlled: true,
    // 同选择弹层: 避开状态栏, 底部另留导航条高度
    useSafeArea: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetCtx) {
      final sheetNav = Navigator.of(sheetCtx);
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> load() async {
            setSheetState(() => loading = true);
            try {
              final list = await fetchTagCatalog(api);
              setSheetState(() {
                catalog = list;
                loading = false;
              });
            } catch (e) {
              setSheetState(() => loading = false);
              if (ctx.mounted) showSnack(ctx, e.toString(), error: true);
            }
          }

          if (loading && catalog.isEmpty) load();

          Future<void> addOrEdit([Tag? existing]) async {
            final name = await _promptTagName(
              ctx,
              initial: existing?.name ?? '',
            );
            if (name == null) return;
            try {
              await api.post(
                '/admin/tag/save',
                data: {if (existing != null) 'id': existing.id, 'name': name},
              );
              setSheetState(() => changed = true);
              await load();
            } catch (e) {
              if (ctx.mounted) showSnack(ctx, e.toString(), error: true);
            }
          }

          Future<void> remove(Tag tag) async {
            final ok = await _confirm(ctx, s.deleteTag, s.deleteTagConfirm);
            if (!ok) return;
            try {
              await api.post('/admin/tag/delete', data: {'id': tag.id});
              setSheetState(() => changed = true);
              await load();
            } catch (e) {
              if (ctx.mounted) showSnack(ctx, e.toString(), error: true);
            }
          }

          // 同选择弹层: 搜索只过滤展示, 目录本身保持全量
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? catalog
              : catalog.where((t) => t.name.toLowerCase().contains(q)).toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.manageTags,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: s.newTag,
                      onPressed: () => addOrEdit(),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (catalog.isNotEmpty)
                  _TagSearchField(
                    hint: s.searchTags,
                    onChanged: (v) => setSheetState(() => query = v),
                  ),
                Flexible(
                  child: loading && catalog.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : catalog.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            s.noTagsHintManage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMute,
                              height: 1.5,
                            ),
                          ),
                        )
                      : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            s.noTagMatch,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMute,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (var i = 0; i < shown.length; i++)
                              _buildManageRow(
                                ctx,
                                shown[i],
                                onEdit: () => addOrEdit(shown[i]),
                                onDelete: () => remove(shown[i]),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    final result = changed ? catalog : null;
                    // 弹层是从选择弹层里叠着打开的，这里只关闭自身
                    sheetNav.pop(result);
                  },
                  child: Text(s.done),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _buildManageRow(
  BuildContext context,
  Tag tag, {
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final color = tagColor(tag);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tag.name,
            style: const TextStyle(fontSize: 13.5, color: AppColors.text),
          ),
        ),
        IconButton(
          tooltip: AppStrings.current.editTag,
          onPressed: onEdit,
          icon: const Icon(
            Icons.edit_outlined,
            size: 18,
            color: AppColors.textDim,
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(
            Icons.delete_outline,
            size: 18,
            color: AppColors.danger,
          ),
        ),
      ],
    ),
  );
}

/// 单行输入弹窗：新增/改名标签。取消返回 null。
/// controller 的生命周期由 _TagNameDialog 的 State 持有: 弹窗关闭动画期间
/// TextField 还会重建, 若在外层 await 返回后立即 dispose 会把退出中的弹窗
/// 打崩(渲染错乱顶出屏幕), 交给 State.dispose 在真正卸载时才释放。
Future<String?> _promptTagName(BuildContext context, {String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TagNameDialog(initial: initial),
  );
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({required this.initial});

  final String initial;

  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text;
    // 空串按取消处理(调用方也做了兜底): 避免保存一个空标签再弹一次报错
    if (v.trim().isEmpty) {
      Navigator.pop(context);
    } else {
      Navigator.pop(context, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.current;
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? s.newTag : s.editTag),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(labelText: s.tagName, counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(s.save)),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final s = AppStrings.current;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.confirm),
        ),
      ],
    ),
  );
  return ok == true;
}
