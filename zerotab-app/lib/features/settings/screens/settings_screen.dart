import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/zt_card.dart';

// ── Finance-themed emoji avatars ─────────────────────────────
const _avatarEmojis = ['🦁', '🦊', '🐯', '🦋', '🌟', '⚡', '🎯', '🌊', '🏆', '💎', '🔥', '🚀'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool    _weeklyInsight = true;
  bool    _emiReminder   = true;
  bool    _unusualSpend  = false;
  String? _selectedEmoji;
  String  _appVersion   = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadAppVersion();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weeklyInsight = prefs.getBool('notif_weekly_insight') ?? true;
      _emiReminder   = prefs.getBool('notif_emi_reminder')   ?? true;
      _unusualSpend  = prefs.getBool('notif_unusual_spend')  ?? false;
      _selectedEmoji = prefs.getString('profile_emoji');
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_weekly_insight', _weeklyInsight);
    await prefs.setBool('notif_emi_reminder',   _emiReminder);
    await prefs.setBool('notif_unusual_spend',  _unusualSpend);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (_) {
      _appVersion = 'v1.0.0';
    }
  }

  // ── Compute a clean display name ─────────────────────────
  String _displayName(String? profileName) {
    final authUser = Supabase.instance.client.auth.currentUser;
    final isDefault = profileName == null ||
        profileName.isEmpty ||
        profileName.toLowerCase() == 'demo user';
    if (!isDefault) return profileName!;
    final email = profileName == null || isDefault
        ? (authUser?.email ?? '')
        : '';
    if (email.isNotEmpty) return email.split('@').first;
    if (authUser?.phone?.isNotEmpty == true) return authUser!.phone!;
    return 'User';
  }

  void _showEditProfile(String currentDisplayName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialName:  currentDisplayName,
        initialEmoji: _selectedEmoji,
        onSaved: (name, emoji) async {
          // Save emoji locally
          final prefs = await SharedPreferences.getInstance();
          if (emoji != null) {
            await prefs.setString('profile_emoji', emoji);
          } else {
            await prefs.remove('profile_emoji');
          }
          setState(() => _selectedEmoji = emoji);
          // Patch name in backend
          try {
            await api.patch(ApiConstants.userMe, data: {'name': name});
            ref.invalidate(userProfileProvider);
          } catch (_) {}
        },
      ),
    );
  }

  Future<void> _revokeConsent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:        'Revoke AA Consent',
        body:         'This will disconnect all bank accounts linked via Finvu Account Aggregator. Your existing transaction history will remain.',
        confirmLabel: 'Revoke',
        confirmColor: AppColors.red,
      ),
    );
    if (confirm == true && mounted) {
      try {
        await api.post(ApiConstants.aaConsentRevoke);
        ref.invalidate(accountsProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AA consent revoked'), backgroundColor: AppColors.gold),
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _loadDemoData() async {
    try {
      await api.post(ApiConstants.demoSeed);
      ref.invalidate(accountsProvider);
      ref.invalidate(financialSummaryProvider);
      ref.invalidate(snapshotProvider);
      ref.invalidate(userProfileProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sample data loaded — explore away!'), backgroundColor: AppColors.teal),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    }
  }

  Future<void> _clearDemoData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Clear demo data',
        body: 'This will remove all sample accounts and transactions that were loaded for demo purposes.',
        confirmLabel: 'Clear',
        confirmColor: AppColors.gold,
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await api.delete(ApiConstants.demoSeed);
      ref.invalidate(accountsProvider);
      ref.invalidate(financialSummaryProvider);
      ref.invalidate(snapshotProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo data cleared'), backgroundColor: AppColors.gold),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:        'Delete Account',
        body:         'All your data will be permanently deleted. This action cannot be undone.',
        confirmLabel: 'Delete forever',
        confirmColor: AppColors.red,
      ),
    );
    if (confirm == true && mounted) {
      try {
        await api.delete(ApiConstants.userMe);
        await Supabase.instance.client.auth.signOut();
        if (mounted) context.go('/onboard');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link'), backgroundColor: AppColors.text3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync  = ref.watch(userProfileProvider);
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [

            // ── Header ──────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Text(
                  'Profile',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),

            // ── Profile card ─────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: profileAsync.when(
                  loading: () => const ZTShimmerBox(width: double.infinity, height: 88, radius: 16),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (profile) {
                    final dispName    = _displayName(profile?.name);
                    final avatarLabel = _selectedEmoji ?? (dispName.isNotEmpty ? dispName[0].toUpperCase() : 'U');
                    final showEmoji   = _selectedEmoji != null;
                    final authUser    = Supabase.instance.client.auth.currentUser;
                    final email       = profile?.email ?? authUser?.email ?? '';
                    final phone       = profile?.phone ?? authUser?.phone ?? '';
                    final createdAt   = authUser?.createdAt != null ? DateTime.tryParse(authUser!.createdAt) : null;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppDecorations.card(radius: AppRadius.xl),
                      child: Row(children: [
                        // Avatar — emoji or initial
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentSoft,
                            border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                          ),
                          alignment: Alignment.center,
                          child: showEmoji
                              ? Text(avatarLabel, style: const TextStyle(fontSize: 24))
                              : Text(
                                  avatarLabel,
                                  style: const TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent2,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dispName,
                                style: const TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontFamily: 'DMMono',
                                    fontSize: 11,
                                    color: AppColors.text2,
                                  ),
                                )
                              else if (phone.isNotEmpty)
                                Text(
                                  phone,
                                  style: const TextStyle(
                                    fontFamily: 'DMMono',
                                    fontSize: 11,
                                    color: AppColors.text2,
                                  ),
                                ),
                              if (createdAt != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Member since ${_monthYear(createdAt)}',
                                    style: const TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 11,
                                      color: AppColors.text3,
                                    ),
                                  ),
                                ),
                              if (profile?.financialArchetype != null) ...[
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Text(
                                    profile!.financialArchetype!.replaceAll('_', ' '),
                                    style: const TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.accent2,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Edit + Score buttons column
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _showEditProfile(dispName),
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  color: AppColors.bg3,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: AppColors.border),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.edit_rounded, size: 15, color: AppColors.text2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => context.go('/health'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.goldSoft,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                                ),
                                child: const Text(
                                  'Score',
                                  style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Connected accounts ───────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('CONNECTED ACCOUNTS'),
                    const SizedBox(height: 10),
                    accountsAsync.when(
                      loading: () => const ZTShimmerBox(width: double.infinity, height: 100, radius: 16),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (accounts) => accounts.isEmpty
                          ? Container(
                              decoration: AppDecorations.card(radius: AppRadius.xl),
                              child: GestureDetector(
                                onTap: () => context.go('/connect'),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    Container(
                                      width: 36, height: 36,
                                      decoration: AppDecorations.iconContainer(AppColors.accent, radius: AppRadius.sm),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.link_rounded, color: AppColors.accent2, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(child: Text('Connect your accounts',
                                      style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.accent2))),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.accent2),
                                  ]),
                                ),
                              ),
                            )
                          : Container(
                              decoration: AppDecorations.card(radius: AppRadius.xl),
                              child: Column(
                                children: accounts.map((a) => Column(children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: AppDecorations.iconContainer(AppColors.teal, radius: AppRadius.sm),
                                        alignment: Alignment.center,
                                        child: Icon(_sourceIcon(a.sourceType), color: AppColors.teal, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${a.institutionName ?? ''}${a.maskedNumber != null ? ' ••${a.maskedNumber}' : ''}',
                                            style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                                              fontWeight: FontWeight.w500, color: AppColors.text),
                                          ),
                                          Text(
                                            a.lastSyncedAt != null
                                                ? 'Synced ${formatDateFull(a.lastSyncedAt!)}'
                                                : 'Never synced',
                                            style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3),
                                          ),
                                        ],
                                      )),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentSoft,
                                          borderRadius: BorderRadius.circular(AppRadius.xs),
                                        ),
                                        child: Text(
                                          _sourceLabel(a.sourceType),
                                          style: const TextStyle(fontFamily: 'DMSans', fontSize: 10,
                                            fontWeight: FontWeight.w500, color: AppColors.accent2),
                                        ),
                                      ),
                                    ]),
                                  ),
                                  const Divider(color: AppColors.border, height: 1, indent: 62),
                                ])).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Notifications ────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('NOTIFICATIONS'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: AppDecorations.card(radius: AppRadius.xl),
                      child: Column(children: [
                        _ToggleRow(
                          label: 'Weekly AI insight',
                          value: _weeklyInsight,
                          onChanged: (v) { setState(() => _weeklyInsight = v); _savePrefs(); },
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ToggleRow(
                          label: 'EMI due reminder',
                          value: _emiReminder,
                          onChanged: (v) { setState(() => _emiReminder = v); _savePrefs(); },
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ToggleRow(
                          label: 'Unusual spend alert',
                          value: _unusualSpend,
                          onChanged: (v) { setState(() => _unusualSpend = v); _savePrefs(); },
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Demo Data ────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('DEMO DATA'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: AppDecorations.card(radius: AppRadius.xl),
                      child: Column(children: [
                        _ActionRow(
                          label: 'Load sample data',
                          color: AppColors.accent2,
                          icon: Icons.science_outlined,
                          onTap: _loadDemoData,
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ActionRow(
                          label: 'Clear demo data',
                          color: AppColors.text2,
                          icon: Icons.cleaning_services_outlined,
                          onTap: _clearDemoData,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Privacy & Data ───────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('PRIVACY & DATA'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: AppDecorations.card(radius: AppRadius.xl),
                      child: Column(children: [
                        _ActionRow(
                          label: 'Revoke AA consent',
                          color: AppColors.red,
                          icon: Icons.link_off_rounded,
                          onTap: _revokeConsent,
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ActionRow(
                          label: 'Delete my account',
                          color: AppColors.red,
                          icon: Icons.delete_outline_rounded,
                          onTap: _deleteAccount,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── About App ────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('ABOUT APP'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: AppDecorations.card(radius: AppRadius.xl),
                      child: Column(children: [
                        _InfoRow(label: 'App Version', value: _appVersion.isEmpty ? 'v1.0.0' : _appVersion),
                        const Divider(color: AppColors.border, height: 1),
                        _ActionRow(
                          label: 'Rate ZeroTab ⭐',
                          color: AppColors.gold,
                          icon: Icons.star_outline_rounded,
                          onTap: () => _launchUrl('https://play.google.com/store'),
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ActionRow(
                          label: 'Privacy Policy',
                          color: AppColors.text2,
                          icon: Icons.privacy_tip_outlined,
                          onTap: () => _launchUrl('https://zerotab.in/privacy'),
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        _ActionRow(
                          label: 'Terms of Service',
                          color: AppColors.text2,
                          icon: Icons.gavel_outlined,
                          onTap: () => _launchUrl('https://zerotab.in/terms'),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Sign out ─────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (mounted) context.go('/onboard');
                  },
                  child: const Text('Sign out'),
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 36)),
          ],
        ),
      ),
    );
  }

  IconData _sourceIcon(String src) {
    switch (src) {
      case 'aa_bank':  return Icons.account_balance_outlined;
      case 'sms_card': return Icons.sms_outlined;
      case 'mf_cas':   return Icons.pie_chart_outline_rounded;
      case 'demo':     return Icons.science_outlined;
      default:         return Icons.edit_outlined;
    }
  }

  String _sourceLabel(String src) {
    const map = {
      'aa_bank':  'AA',
      'sms_card': 'SMS',
      'mf_cas':   'CAS',
      'manual':   'Manual',
      'demo':     'Demo',
    };
    return map[src] ?? src;
  }

  String _monthYear(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ── Edit Profile Sheet ────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String  initialName;
  final String? initialEmoji;
  final Future<void> Function(String name, String? emoji) onSaved;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialEmoji,
    required this.onSaved,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  String? _emoji;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _emoji    = widget.initialEmoji;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.onSaved(name, _emoji);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Edit Profile',
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 17,
              fontWeight: FontWeight.w700, color: AppColors.text,
            ),
          ),
          const SizedBox(height: 20),

          // ── Name field ──
          _label('Display Name'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.text),
              decoration: const InputDecoration(
                hintText: 'Your name',
                hintStyle: TextStyle(color: AppColors.text3, fontSize: 13),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Avatar emoji picker ──
          _label('Choose Avatar'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
            children: [
              // None option
              GestureDetector(
                onTap: () => setState(() => _emoji = null),
                child: Container(
                  decoration: BoxDecoration(
                    color: _emoji == null ? AppColors.accentSoft : AppColors.bg3,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: _emoji == null ? AppColors.accent : AppColors.border,
                      width: _emoji == null ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'A',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _emoji == null ? AppColors.accent2 : AppColors.text3,
                    ),
                  ),
                ),
              ),
              ..._avatarEmojis.map((e) => GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: _emoji == e ? AppColors.accentSoft : AppColors.bg3,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: _emoji == e ? AppColors.accent : AppColors.border,
                      width: _emoji == e ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              )),
            ],
          ),
          const SizedBox(height: 24),

          // ── Save button ──
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3));
}

// ── Reusable section label ────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'DMSans', fontSize: 11,
      fontWeight: FontWeight.w500, letterSpacing: 0.10, color: AppColors.text3,
    ),
  );
}

// ── Toggle row ────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(
        fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.text))),
      Switch(
        value: value, onChanged: onChanged,
        activeColor: AppColors.accent,
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ]),
  );
}

// ── Action row ────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionRow({required this.label, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 18, color: color.withOpacity(0.7)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(
          fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w400, color: color))),
        Icon(Icons.arrow_forward_ios_rounded, size: 13, color: color.withOpacity(0.5)),
      ]),
    ),
  );
}

// ── Info row (no arrow, just label + value) ───────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.text3),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: const TextStyle(
        fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.text2))),
      Text(value, style: const TextStyle(
        fontFamily: 'DMMono', fontSize: 12, color: AppColors.text3)),
    ]),
  );
}

// ── Confirm dialog ────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;
  const _ConfirmDialog({
    required this.title, required this.body,
    required this.confirmLabel, required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.bg3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      side: const BorderSide(color: AppColors.border),
    ),
    title: Text(title, style: const TextStyle(
      fontFamily: 'DMSans', fontWeight: FontWeight.w700,
      fontSize: 17, color: AppColors.text, letterSpacing: -0.3,
    )),
    content: Text(body, style: const TextStyle(
      fontFamily: 'DMSans', color: AppColors.text2, fontSize: 14, height: 1.55,
    )),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel', style: TextStyle(color: AppColors.text2)),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirmLabel, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600)),
      ),
    ],
  );
}
