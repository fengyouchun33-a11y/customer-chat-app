import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 平台超管进入业务页前必须选一家租户：
/// - 登录后由根路由强制打开（mandatory=true，没有返回键）
/// - 工作台顶栏也可以再进来切换（mandatory=false，选完即返回）
class TenantSelectPage extends StatefulWidget {
  const TenantSelectPage({super.key, this.mandatory = false});

  final bool mandatory;

  @override
  State<TenantSelectPage> createState() => _TenantSelectPageState();
}

class _TenantSelectPageState extends State<TenantSelectPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<Tenant> _tenants = const [];
  bool _loading = true;
  String? _error;
  String _keyword = '';
  int? _selectingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await state.fetchTenants();
      if (!mounted) return;
      setState(() {
        _tenants = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Tenant> get _filtered {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return _tenants;
    return _tenants
        .where((t) => t.companyName.toLowerCase().contains(kw) || '${t.id}' == kw)
        .toList();
  }

  Future<void> _pick(Tenant t) async {
    if (_selectingId != null) return;
    final state = context.read<AppState>();
    setState(() => _selectingId = t.id);
    try {
      await state.selectTenant(t);
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
        return;
      }
      // mandatory：AppState 已通知根路由切到工作台，本页会被自动替换
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _selectingId = null);
    }
  }

  Future<void> _logout() async {
    final s = AppStrings.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.logout),
        content: Text(s.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.logoutAction)),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.mandatory,
        title: Text(s.selectTenantTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: s.language,
            onPressed: () => showLanguagePicker(context),
            icon: const Icon(Icons.language, size: 20, color: AppColors.textDim),
          ),
          IconButton(
            tooltip: s.logout,
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 20, color: AppColors.textDim),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(state),
            if (_tenants.length > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _keyword = v),
                  decoration: InputDecoration(
                    hintText: s.searchTenantHint,
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMute),
                    isDense: true,
                  ),
                ),
              ),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppState state) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, color: AppColors.signal, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.current.platformAdmin(state.admin?.displayName ?? ''),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.current.tenantSelectHint,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMute, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppState state) {
    if (_loading && _tenants.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    if (_error != null && _tenants.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          EmptyState(
            icon: Icons.cloud_off_outlined,
            text: AppStrings.current.tenantLoadFailed,
            hint: _error,
            action: FilledButton.tonal(
              onPressed: _load,
              child: Text(AppStrings.current.retry),
            ),
          ),
          if (widget.mandatory)
            Center(
              child: TextButton(
                onPressed: _logout,
                child: Text(AppStrings.current.logout),
              ),
            ),
        ],
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 60),
            EmptyState(
              icon: Icons.business_outlined,
              text: _keyword.isEmpty
                  ? AppStrings.current.noTenants
                  : AppStrings.current.noMatchingTenants,
              hint: _keyword.isEmpty
                  ? AppStrings.current.noTenantsHint
                  : AppStrings.current.tryAnotherKeyword,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == list.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                AppStrings.current.tenantSwitchHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
              ),
            );
          }
          return _buildTile(state, list[index]);
        },
      ),
    );
  }

  Widget _buildTile(AppState state, Tenant t) {
    final selecting = _selectingId == t.id;
    final current = state.tenant?.id == t.id;
    final name = t.companyName.isEmpty
        ? AppStrings.current.tenantFallback('${t.id}')
        : t.companyName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _selectingId != null ? null : () => _pick(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: current ? AppColors.accent.withOpacity(0.55) : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.panel2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business_outlined, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      current
                          ? AppStrings.current.currentTenant
                          : AppStrings.current.tenantIdLabel('${t.id}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: current ? AppColors.accent : AppColors.textMute,
                      ),
                    ),
                  ],
                ),
              ),
              if (selecting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  current ? Icons.check_circle : Icons.chevron_right,
                  size: 18,
                  color: current ? AppColors.accent : AppColors.textMute,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
