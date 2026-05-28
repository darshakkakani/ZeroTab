import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';

class ConnectAccountsScreen extends StatefulWidget {
  const ConnectAccountsScreen({super.key});

  @override
  State<ConnectAccountsScreen> createState() =>
      _ConnectAccountsScreenState();
}

class _ConnectAccountsScreenState
    extends State<ConnectAccountsScreen> {
  bool _aaConnected  = false;
  bool _smsConnected = false;
  bool _aaLoading    = false;

  Future<void> _connectAA() async {
    final user = Supabase.instance.client.auth.currentUser;
    // AA consent requires a valid Indian mobile number — email-only users
    // must provide one before linking bank accounts
    String? phone = user?.phone;
    if (phone == null || phone.isEmpty) {
      phone = await _promptForPhone();
      if (phone == null) return; // user cancelled
    }
    setState(() => _aaLoading = true);
    try {
      final res = await api.post(ApiConstants.aaConsentCreate,
          data: {'phoneNumber': phone});
      final url = res.data['redirectUrl'] as String;
      if (mounted) _openFinvuWebView(url);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.red,
        ));
    } finally {
      setState(() => _aaLoading = false);
    }
  }

  Future<String?> _promptForPhone() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Enter mobile number',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'RBI\'s Account Aggregator requires your registered mobile number to link bank accounts.',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: const TextStyle(
                fontFamily: 'DMSans',
                color: AppColors.text,
              ),
              decoration: InputDecoration(
                prefixText: '+91 ',
                prefixStyle: const TextStyle(
                  fontFamily: 'DMSans',
                  color: AppColors.accent2,
                ),
                hintText: '9876543210',
                hintStyle: const TextStyle(color: AppColors.text3),
                counterText: '',
                filled: true,
                fillColor: AppColors.bg4,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.text3)),
          ),
          ElevatedButton(
            onPressed: () {
              final digits = ctrl.text.trim().replaceAll(RegExp(r'\D'), '');
              if (digits.length == 10) {
                Navigator.of(ctx).pop('+91$digits');
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _openFinvuWebView(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FinvuWebView(
        url: url,
        onSuccess: () {
          setState(() => _aaConnected = true);
          Navigator.of(context).pop();
        },
        onFailure: () => Navigator.of(context).pop(),
      ),
    ));
  }

  Future<void> _connectSms() async {
    final status = await Permission.sms.request();
    if (status.isGranted) {
      setState(() => _smsConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS access granted — parsing transactions'),
          backgroundColor: AppColors.green,
        ),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () =>
                      context.canPop() ? context.pop() : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.bg3,
                      borderRadius: BorderRadius.circular(
                          AppRadius.sm),
                      border: Border.all(
                          color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.text2,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Connect accounts',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.text,
                  ),
                ),
              ]),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    20, 28, 20, 20),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // ── Hero block — no emoji ──────────
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(
                            AppRadius.lg),
                        border: Border.all(
                            color: AppColors.accent
                                .withOpacity(0.2)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.account_tree_outlined,
                        color: AppColors.accent2,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Link your financial life',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'All secured via RBI\'s Account Aggregator framework.',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Connection items card ──────────
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(
                            AppRadius.xxl),
                        border: Border.all(
                            color: AppColors.border),
                      ),
                      child: Column(children: [
                        _ConnectRow(
                          icon: Icons.account_balance_outlined,
                          iconColor: AppColors.accent,
                          title: 'Bank accounts via AA',
                          subtitle: 'Finvu · RBI regulated',
                          tags: const ['SBI', 'HDFC', 'ICICI', '+4'],
                          status: _aaConnected
                              ? _Status.done
                              : _Status.add,
                          loading: _aaLoading,
                          onTap: _aaConnected ? null : _connectAA,
                        ),
                        const Divider(
                            color: AppColors.border,
                            height: 1,
                            indent: 66),
                        _ConnectRow(
                          icon: Icons.sms_outlined,
                          iconColor: AppColors.teal,
                          title: 'SMS transactions',
                          subtitle: 'Auto-reads bank SMS alerts',
                          tags: const [],
                          status: _smsConnected
                              ? _Status.done
                              : _Status.add,
                          onTap: _smsConnected
                              ? null
                              : _connectSms,
                        ),
                        const Divider(
                            color: AppColors.border,
                            height: 1,
                            indent: 66),
                        _ConnectRow(
                          icon: Icons.pie_chart_outline_rounded,
                          iconColor: AppColors.green,
                          title: 'Mutual Funds (CAS)',
                          subtitle:
                              'Upload CAMS / KFintech statement',
                          tags: const [],
                          status: _Status.pending,
                          onTap: () =>
                              context.go('/investments'),
                        ),
                        const Divider(
                            color: AppColors.border,
                            height: 1,
                            indent: 66),
                        _ConnectRow(
                          icon: Icons.candlestick_chart_outlined,
                          iconColor: AppColors.gold,
                          title: 'Demat / Stocks',
                          subtitle:
                              'Manual entry or CDSL import',
                          tags: const [],
                          status: _Status.add,
                          onTap: () {},
                        ),
                        const Divider(
                            color: AppColors.border,
                            height: 1,
                            indent: 66),
                        _ConnectRow(
                          icon: Icons.shield_outlined,
                          iconColor: AppColors.coral,
                          title: 'EPF / PF',
                          subtitle: 'Manual entry (EPFO V3)',
                          tags: const [],
                          status: _Status.add,
                          onTap: () {},
                          isLast: true,
                        ),
                      ]),
                    ),

                    const SizedBox(height: 32),

                    // ── CTA ────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Done — go to dashboard'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status enum ───────────────────────────────────────────

enum _Status { done, pending, add }

// ── Connect row ───────────────────────────────────────────

class _ConnectRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<String> tags;
  final _Status status;
  final VoidCallback? onTap;
  final bool loading;
  final bool isLast;

  const _ConnectRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.status,
    this.onTap,
    this.loading = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    // Right-side status indicator
    Widget statusBadge;
    if (loading) {
      statusBadge = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppColors.accent,
        ),
      );
    } else {
      final (bgColor, borderColor, child) =
          switch (status) {
        _Status.done => (
            AppColors.greenSoft,
            AppColors.green,
            const Icon(Icons.check_rounded,
                size: 13, color: AppColors.green),
          ),
        _Status.pending => (
            AppColors.goldSoft,
            AppColors.gold,
            const Icon(Icons.upload_rounded,
                size: 13, color: AppColors.gold),
          ),
        _Status.add => (
            AppColors.bg4,
            AppColors.border2,
            const Icon(Icons.add_rounded,
                size: 14, color: AppColors.text2),
          ),
      };

      statusBadge = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          border: Border.all(color: borderColor, width: 1.5),
        ),
        alignment: Alignment.center,
        child: child,
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            14, 14, 14, isLast ? 14 : 14),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.10),
                borderRadius:
                    BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),

            // Text + tags
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      children: tags
                          .map((t) => Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius:
                                      BorderRadius.circular(
                                          AppRadius.xs),
                                ),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w500,
                                    color: AppColors.accent2,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            statusBadge,
          ],
        ),
      ),
    );
  }
}

// ── Finvu WebView ─────────────────────────────────────────

class _FinvuWebView extends StatefulWidget {
  final String url;
  final VoidCallback onSuccess;
  final VoidCallback onFailure;

  const _FinvuWebView({
    required this.url,
    required this.onSuccess,
    required this.onFailure,
  });

  @override
  State<_FinvuWebView> createState() => _FinvuWebViewState();
}

class _FinvuWebViewState extends State<_FinvuWebView> {
  late WebViewController _wvc;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          if (req.url.contains('consent_status=ACTIVE') ||
              req.url.contains('success=true')) {
            widget.onSuccess();
            return NavigationDecision.prevent;
          }
          if (req.url.contains('consent_status=REJECTED') ||
              req.url.contains('cancelled=true')) {
            widget.onFailure();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Connect Bank Accounts'),
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: AppColors.text2),
          onPressed: widget.onFailure,
        ),
      ),
      body: WebViewWidget(controller: _wvc),
    );
  }
}
