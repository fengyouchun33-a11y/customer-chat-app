import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// 统计页：对齐管理端 StatsDashboard
/// - 区间 7/30/90 天 + 项目筛选
/// - 4 个 KPI、会话/AI、人工/转人工、知识库检索/命中三张趋势图
/// - 关键词字号按词频对数缩放、Top 知识库、AI 话题总结（现场跑模型，90s 超时）
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _days = AppConfig.statRangeDays;
  int _projectId = 0;
  int _reqSeq = 0;

  List<Project> _projects = const [];
  StatsData _data = StatsData.empty;
  StatsSummary? _summary;
  bool _loading = true;
  bool _loadedOnce = false;
  bool _summing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _load();
  }

  Future<void> _loadProjects() async {
    final api = context.read<AppState>().api;
    try {
      final data = await api.get('/admin/project/options');
      if (!mounted) return;
      setState(() {
        _projects = data is List
            ? data
                .whereType<Map>()
                .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [];
      });
    } catch (_) {
      // 项目下拉失败不影响统计主流程
    }
  }

  Future<void> _load() async {
    final seq = ++_reqSeq;
    final api = context.read<AppState>().api;
    if (_loadedOnce) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await api.get(
        '/admin/stats/overview',
        query: {
          'days': _days,
          if (_projectId > 0) 'project_id': _projectId,
        },
      );
      if (!mounted || seq != _reqSeq) return;
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final parsed = StatsData.fromJson(m);
      setState(() {
        _data = parsed;
        _summary = parsed.summary;
        _loading = false;
        _loadedOnce = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _genSummary() async {
    if (_summing) return;
    final api = context.read<AppState>().api;
    setState(() => _summing = true);
    try {
      final body = <String, dynamic>{'days': _days, 'lang': 'zh'};
      if (_projectId > 0) body['project_id'] = _projectId;
      final data = await api.post(
        '/admin/stats/summary',
        data: body,
        receiveTimeout: AppConfig.summaryTimeout,
      );
      if (!mounted) return;
      if (data is Map) {
        setState(() {
          _summary = StatsSummary.fromJson(Map<String, dynamic>.from(data));
        });
      }
      showSnack(context, '总结已更新');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _summing = false);
    }
  }

  void _setDays(int d) {
    if (_days == d) return;
    setState(() => _days = d);
    _load();
  }

  void _setProject(int id) {
    if (_projectId == id) return;
    setState(() => _projectId = id);
    _load();
  }

  String get _projectLabel {
    if (_projectId <= 0) return '全部项目';
    for (final p in _projects) {
      if (p.id == _projectId) return p.name;
    }
    return '项目 #$_projectId';
  }

  List<String> get _dateLabels => _data.series
      .map((p) => p.date.length >= 10 ? p.date.substring(5) : p.date)
      .toList();

  String _num1(double? v) {
    if (v == null) return '—';
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _data.totals;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _buildFilterCard(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ErrorBanner(message: _error!, onRetry: _load),
            ),
          const SizedBox(height: 12),
          _buildKpiGrid(totals),
          const SizedBox(height: 12),
          _buildConvChart(),
          const SizedBox(height: 12),
          _buildHumanChart(),
          const SizedBox(height: 12),
          _buildKbChart(),
          const SizedBox(height: 12),
          _buildKeywordsCard(),
          const SizedBox(height: 12),
          _buildTopKbCard(),
          const SizedBox(height: 12),
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in AppConfig.statRanges)
                      PillButton(
                        label: '$d 天',
                        selected: _days == d,
                        onTap: () => _setDays(d),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildProjectFilter(),
            ],
          ),
          if (_data.rangeStart.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${_data.rangeStart} → ${_data.rangeEnd}',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectFilter() {
    final active = _projectId > 0;
    return PopupMenuButton<int>(
      tooltip: '项目筛选',
      onSelected: _setProject,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        const PopupMenuItem<int>(value: 0, child: Text('全部项目')),
        ..._projects.map((p) => PopupMenuItem<int>(value: p.id, child: Text(p.name))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.14) : AppColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.accent.withOpacity(0.55) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                _projectLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: active ? AppColors.accentStrong : AppColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 14, color: AppColors.textMute),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid(StatsTotals t) {
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: half,
              child: _kpiCard(
                '会话数',
                fmtNumber(t.conversations),
                '最近 $_days 天新建',
                AppColors.text,
              ),
            ),
            SizedBox(
              width: half,
              child: _kpiCard(
                'AI 回答数',
                fmtNumber(t.aiAnswers),
                '平均每会话 ${_num1(t.aiPerConversation)} 轮',
                AppColors.ok,
              ),
            ),
            SizedBox(
              width: half,
              child: _kpiCard(
                '人工接待会话',
                fmtNumber(t.humanConversations),
                '${t.humanRate == null ? '占比 —' : '占会话 ${fmtPercent(t.humanRate)}'} · 转人工 ${fmtNumber(t.transferRequests)} 次',
                AppColors.signal,
              ),
            ),
            SizedBox(
              width: half,
              child: _kpiCard(
                '知识库命中率',
                t.kbHitRate == null ? '—' : fmtPercent(t.kbHitRate),
                t.kbSearches > 0
                    ? '${fmtNumber(t.kbSearches)} 次检索命中 ${fmtNumber(t.kbHits)} 次'
                    : '该区间还没有检索记录',
                AppColors.text,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, String sub, Color valueColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMute, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String tip,
    required List<Widget> legend,
    required Widget chart,
    double height = 190,
  }) {
    return SectionCard(
      title: title,
      tip: tip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 14, runSpacing: 4, children: legend),
          const SizedBox(height: 10),
          SizedBox(height: height, child: chart),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? color.withOpacity(0.7) : color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textDim)),
      ],
    );
  }

  List<FlSpot> _spots(int Function(StatsPoint) pick) {
    return [
      for (var i = 0; i < _data.series.length; i++)
        FlSpot(i.toDouble(), pick(_data.series[i]).toDouble()),
    ];
  }

  Widget _buildConvChart() {
    final spotsA = _spots((p) => p.conversations);
    final spotsB = _spots((p) => p.aiAnswers);
    return _chartCard(
      title: '每日会话数与 AI 回答数',
      tip: '没有数据的日子补 0，曲线不会把两天连成直线',
      legend: [
        _legendItem('新建会话', AppColors.accent),
        _legendItem('AI 回答', AppColors.ok),
      ],
      chart: _lineChart(
        spotsA: spotsA,
        spotsB: spotsB,
        colorA: AppColors.accent,
        colorB: AppColors.ok,
        labelA: '新建会话',
        labelB: 'AI 回答',
      ),
    );
  }

  Widget _buildHumanChart() {
    final spotsA = _spots((p) => p.humanConversations);
    final spotsB = _spots((p) => p.transfers);
    return _chartCard(
      title: '每日人工接待会话量',
      tip: '人工接待按当天有客服发言的会话去重统计',
      legend: [
        _legendItem('人工接待会话', AppColors.signal),
        _legendItem('转人工申请', AppColors.accentStrong, dashed: true),
      ],
      chart: _lineChart(
        spotsA: spotsA,
        spotsB: spotsB,
        colorA: AppColors.signal,
        colorB: AppColors.accentStrong,
        labelA: '人工接待',
        labelB: '转人工',
        dashedB: true,
        areaB: false,
      ),
    );
  }

  Widget _buildKbChart() {
    return _chartCard(
      title: '每日知识库检索与命中',
      tip: 'AI 每回答一次就检索一次，未命中也计入检索数',
      legend: [
        _legendItem('检索次数', AppColors.accent.withOpacity(0.55)),
        _legendItem('命中次数', AppColors.ok),
      ],
      height: 200,
      chart: _barChart(),
    );
  }

  Widget _lineChart({
    required List<FlSpot> spotsA,
    required List<FlSpot> spotsB,
    required Color colorA,
    required Color colorB,
    required String labelA,
    required String labelB,
    bool dashedB = false,
    bool areaB = true,
  }) {
    if (_data.series.isEmpty) {
      return const Center(
        child: Text('该区间暂无数据', style: TextStyle(fontSize: 11.5, color: AppColors.textMute)),
      );
    }
    final maxY = [...spotsA, ...spotsB].fold<double>(1, (m, s) => math.max(m, s.y));
    final maxX = _data.series.length <= 1 ? 1.0 : (_data.series.length - 1).toDouble();
    final yInterval = maxY <= 4 ? 1.0 : (maxY / 4).ceilToDouble();
    final showDots = _data.series.length <= 32;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
            dashArray: [3, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(yInterval),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => AppColors.panel2,
            tooltipRoundedRadius: 8,
            getTooltipItems: (spots) => spots.map((s) {
              final name = s.barIndex == 0 ? labelA : labelB;
              return LineTooltipItem(
                '$name ${s.y.toInt()}',
                const TextStyle(color: AppColors.text, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spotsA,
            isCurved: true,
            curveSmoothness: 0.18,
            color: colorA,
            barWidth: 1.8,
            dotData: FlDotData(show: showDots),
            belowBarData: BarAreaData(show: true, color: colorA.withOpacity(0.10)),
          ),
          LineChartBarData(
            spots: spotsB,
            isCurved: true,
            curveSmoothness: 0.18,
            color: colorB,
            barWidth: dashedB ? 1.4 : 1.8,
            dashArray: dashedB ? const [4, 4] : null,
            dotData: FlDotData(show: showDots),
            belowBarData: BarAreaData(show: areaB, color: colorB.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  Widget _barChart() {
    if (_data.series.isEmpty) {
      return const Center(
        child: Text('该区间暂无数据', style: TextStyle(fontSize: 11.5, color: AppColors.textMute)),
      );
    }
    final maxY = _data.series
        .expand((p) => [p.kbSearches, p.kbHits])
        .fold<int>(1, math.max)
        .toDouble();
    final yInterval = maxY <= 4 ? 1.0 : (maxY / 4).ceilToDouble();
    final barWidth = _data.series.length > 60 ? 2.0 : (_data.series.length > 30 ? 3.5 : 6.0);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
            dashArray: [3, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(yInterval),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppColors.panel2,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${rodIndex == 0 ? '检索' : '命中'} ${rod.toY.toInt()}',
              const TextStyle(color: AppColors.text, fontSize: 11),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < _data.series.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                  toY: _data.series[i].kbSearches.toDouble(),
                  color: AppColors.accent.withOpacity(0.45),
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                BarChartRodData(
                  toY: _data.series[i].kbHits.toDouble(),
                  color: AppColors.ok,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  FlTitlesData _titlesData(double yInterval) {
    final labels = _dateLabels;
    final xInterval = math.max(1.0, (labels.length / 4).ceilToDouble());
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: yInterval,
          getTitlesWidget: (value, meta) => Text(
            value.toInt().toString(),
            style: const TextStyle(fontSize: 9, color: AppColors.textMute),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          interval: xInterval,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                labels[i],
                style: const TextStyle(fontSize: 8.5, color: AppColors.textMute),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeywordsCard() {
    final keywords = _data.keywords;
    return SectionCard(
      title: '热门关键词 / 话题',
      tip: '由 AI 定时归纳访客提问话题',
      child: keywords.isEmpty
          ? const Text(
              '该区间没有可用于统计的访客提问',
              style: TextStyle(fontSize: 12, color: AppColors.textMute),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keywords.map((k) {
                final size = _keywordSize(k.count, keywords.first.count);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.panel2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        k.word,
                        style: TextStyle(fontSize: size, color: AppColors.text, height: 1.2),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${k.count}',
                        style: const TextStyle(fontSize: 9.5, color: AppColors.accent),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  /// 与管理端一致：词频取对数映射到 12~18px，最多的词最大
  double _keywordSize(int count, int max) {
    final m = max <= 1 ? 1 : max;
    final r = (math.log(math.max(1, count)) / math.log(math.max(2, m))).clamp(0.0, 1.0);
    return 12 + r * 6;
  }

  Widget _buildTopKbCard() {
    final list = _data.topKnowledge;
    final max = list.fold<int>(0, (m, x) => math.max(m, x.count));
    return SectionCard(
      title: '被引用最多的知识条目',
      tip: '按 AI 检索命中次数排序',
      child: list.isEmpty
          ? const Text(
              '该区间没有知识库命中记录',
              style: TextStyle(fontSize: 12, color: AppColors.textMute),
            )
          : Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == list.length - 1 ? 0 : 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: i < 3 ? AppColors.signal : AppColors.textMute,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.text),
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: max > 0 ? list[i].count / max : 0,
                                  minHeight: 4,
                                  backgroundColor: AppColors.panel2,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${list[i].count}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _summary;
    return SectionCard(
      title: 'AI 话题总结',
      tip: '把这段区间的访客提问归纳成几条要点',
      trailing: FilledButton(
        onPressed: _summing ? null : _genSummary,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11.5),
        ),
        child: _summing
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF04121B),
                ),
              )
            : const Text('生成 AI 总结'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary != null) ...[
            Text(
              summary.content,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textDim, height: 1.75),
            ),
            const SizedBox(height: 10),
            Text(
              '模型 ${summary.model.isEmpty ? '—' : summary.model} · 生成于 ${fmtDateTime(summary.updateTime)}',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
            ),
          ] else ...[
            Text(
              _summing
                  ? '正在归纳，请稍候（约十几秒）…'
                  : '还没有生成过总结。点右上角按钮，让 AI 把这段区间的访客提问归纳成几条要点。',
              style: TextStyle(
                fontSize: 12,
                color: _summing ? AppColors.accent : AppColors.textMute,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '总结会现场调用大模型，约十几秒，并消耗 token。',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMute),
            ),
          ],
        ],
      ),
    );
  }
}
