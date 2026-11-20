import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../services/sound_service.dart';
import '../state/app_state.dart';
import '../support/support_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// "More" tab: account header plus grouped entries — support, language,
/// legal documents and about. The support entry was moved here from the
/// top-bar overflow menu to free that menu for operational toggles.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  static const String _privacyUrl = 'https://reflexassist.com/privacy.html';
  static const String _termsUrl = 'https://reflexassist.com/terms.html';
  static const String _websiteUrl = 'https://reflexassist.com';

  Future<void> _openUrl(BuildContext context, String url) async {
    final s = AppStrings.current;
    final uri = Uri.tryParse(url);
    final ok = uri != null && await canLaunchUrl(uri);
    if (!ok) {
      if (context.mounted) showSnack(context, s.supportUnavailable, error: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Toggle the new-message sound (relocated from the top-bar overflow menu).
  Future<void> _toggleSound(BuildContext context) async {
    final state = context.read<AppState>();
    final s = AppStrings.of(context);
    final next = !state.soundEnabled;
    await state.setSoundEnabled(next);
    if (!context.mounted) return;
    showSnack(context, next ? s.soundOnToast : s.soundOffToast);
    // preview the sound once so the agent can confirm the volume
    if (next) unawaited(SoundService.instance.playNewMessage());
  }

  /// Toggle auto-translate for incoming visitor messages.
  Future<void> _toggleTranslate(BuildContext context) async {
    final state = context.read<AppState>();
    final s = AppStrings.of(context);
    final next = !(state.admin?.autoTranslate ?? false);
    try {
      await state.setAutoTranslate(next);
      if (context.mounted) {
        showSnack(context, next ? s.translateOnToast : s.translateOffToast);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings.of(context);
    final admin = state.admin;
    final account = admin == null
        ? ''
        : (admin.nickname.isNotEmpty
              ? admin.nickname
              : (admin.name.isNotEmpty ? admin.name : admin.account));
    final company = admin?.companyName ?? state.tenant?.companyName ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _HeaderCard(
            account: account,
            company: company,
          ),
          const SizedBox(height: 22),
          _SectionHeader(s.moreSectionPrefs),
          _SectionCard(
            children: [
              _SwitchTile(
                icon: Icons.translate,
                color: AppColors.accent,
                title: s.prefAutoTranslate,
                value: state.admin?.autoTranslate ?? false,
                onChanged: () => _toggleTranslate(context),
              ),
              _SwitchTile(
                icon: Icons.volume_up,
                color: AppColors.signal,
                title: s.prefSound,
                value: state.soundEnabled,
                onChanged: () => _toggleSound(context),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionHeader(s.moreSectionHelp),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.headset_mic_outlined,
                color: AppColors.accent,
                title: s.supportEntry,
                onTap: () => openSupportChat(context),
              ),
              _Tile(
                icon: Icons.language,
                color: AppColors.signal,
                title: s.languageMenu(
                  AppStrings.nativeName(
                    AppStrings.effectiveCode(state.languagePref),
                  ),
                ),
                onTap: () => showLanguagePicker(context),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionHeader(s.moreSectionLegal),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.privacy_tip_outlined,
                color: AppColors.ok,
                title: s.privacyPolicy,
                onTap: () => _openUrl(context, _privacyUrl),
              ),
              _Tile(
                icon: Icons.description_outlined,
                color: AppColors.accentStrong,
                title: s.userAgreement,
                onTap: () => _openUrl(context, _termsUrl),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionHeader(s.moreSectionAbout),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.public,
                color: AppColors.accent,
                title: s.officialWebsite,
                onTap: () => _openUrl(context, _websiteUrl),
              ),
              const _VersionTile(),
            ],
          ),
          const SizedBox(height: 28),
          const _FooterBrand(),
        ],
      ),
    );
  }
}

/// Gradient account card at the top: logo, display name, company and role chip.
class _HeaderCard extends StatelessWidget {
  final String account;
  final String company;
  const _HeaderCard({required this.account, required this.company});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12303F), Color(0xFF0C1C25)],
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/support-logo.png',
                width: 38,
                height: 38,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.support_agent,
                  color: AppColors.accent,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.isEmpty ? s.appName : account,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                if (company.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textMute,
        ),
      ),
    );
  }
}

/// Rounded panel that stacks tiles with hairline dividers between them.
class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final tiled = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        tiled.add(
          const Divider(height: 1, thickness: 1, color: AppColors.border),
        );
      }
      tiled.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: tiled),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14.5, color: AppColors.text),
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMute,
                ),
          ],
        ),
      ),
    );
  }
}

/// Preference row with a trailing switch; the whole row toggles the value.
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final bool value;
  final VoidCallback onChanged;
  const _SwitchTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14.5, color: AppColors.text),
              ),
            ),
            // Display-only switch: the InkWell owns the tap so pressing the
            // thumb does not toggle twice.
            IgnorePointer(
              child: Switch(
                value: value,
                onChanged: (_) => onChanged(),
                activeThumbColor: color,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Version" row: label on the left, resolved version string on the right.
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (!mounted) return;
          final build = info.buildNumber;
          setState(
            () => _version =
                build.isEmpty ? info.version : '${info.version} ($build)',
          );
        })
        .catchError((_) {
          // unreadable package info (test env) — leave the trailing blank
        });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return _Tile(
      icon: Icons.info_outline,
      color: AppColors.textDim,
      title: s.appVersion,
      trailing: Text(
        _version.isEmpty ? '—' : 'v$_version',
        style: const TextStyle(fontSize: 13, color: AppColors.textMute),
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    // Single-line brand line: "Reflex AI" slightly stronger than "Support Cloud"
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Reflex AI ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.textMute,
            ),
          ),
          TextSpan(
            text: 'Support Cloud',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: AppColors.textMute,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
