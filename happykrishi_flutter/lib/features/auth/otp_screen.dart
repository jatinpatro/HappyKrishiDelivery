import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  // Customer login fields
  final _identifierCtrl  = TextEditingController();
  final _passCtrl        = TextEditingController();
  bool _usePassword      = false;
  bool _passObscure      = true;

  bool _loading = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  bool get _identifierIsEmail => _identifierCtrl.text.trim().contains('@');

  // ── Customer: send OTP (phone or email) ──────────────────────────────────
  Future<void> _sendOtp() async {
    final id = _identifierCtrl.text.trim();
    if (id.isEmpty) { _show('Enter your phone number or email'); return; }

    setState(() => _loading = true);
    try {
      if (!_identifierIsEmail && id.length != 10) {
        _show('Enter a valid 10-digit phone number');
        return;
      }

      final dio = ref.read(dioProvider);

      // For phone input — check channel and warn if SMS charge applies
      if (!_identifierIsEmail) {
        final channelRes = await dio.get(Endpoints.otpChannel, queryParameters: {'phone': id});
        final cost = (channelRes.data['cost'] as num?)?.toDouble() ?? 0;
        final walletBalance = (channelRes.data['wallet_balance'] as num?)?.toDouble();
        final needsEmailVerify = channelRes.data['needs_email_verify'] == true;

        if (cost > 0 && mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('SMS OTP Charge'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('₹${cost.toStringAsFixed(0)} will be deducted from your wallet to send OTP via SMS.',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                if (walletBalance != null)
                  Text('Your wallet balance: ₹${walletBalance.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                if (needsEmailVerify) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.email_outlined, color: Colors.green.shade700, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Verify your email to get free OTPs forever.',
                          style: TextStyle(fontSize: 12, color: Colors.green))),
                    ]),
                  ),
                ],
              ]),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                if (needsEmailVerify)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx, false);
                      setState(() => _usePassword = false);
                      _identifierCtrl.text = '';
                      _show('Enter your email to get free OTPs');
                    },
                    child: const Text('Use Email Instead'),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: Text('Send OTP (₹${cost.toStringAsFixed(0)})'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
        }
      }

      // Call backend to send OTP
      final data = _identifierIsEmail ? {'email': id} : {'phone': id};
      final res = await dio.post(Endpoints.sendOtp, data: data);
      if (!mounted) return;
      final phone = res.data['phone'] as String? ?? id;
      final channel = res.data['channel'] as String? ?? 'sms';
      final hint = res.data['hint'] as String?;
      final smsCost = res.data['sms_cost'];

      String msg;
      if (channel == 'email') {
        msg = hint != null ? 'OTP sent to $hint' : 'OTP sent to your email';
      } else {
        msg = smsCost != null ? 'OTP sent via SMS (₹$smsCost charged)' : 'OTP sent to your phone';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      final encodedHint = hint != null ? Uri.encodeComponent(hint) : '';
      final channelParam = channel ?? 'sms';
      context.go('/auth/verify?phone=$phone&mode=customer&channel=$channelParam${encodedHint.isNotEmpty ? "&hint=$encodedHint" : ""}');
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data?['error'] as String? ?? 'Failed to send OTP';
      final canUsePassword = data?['can_use_password'] == true;
      final needsEmailVerify = data?['needs_email_verify'] == true;
      final walletBalance = data?['wallet_balance'];
      final smsCost = data?['sms_cost'];

      if (e.response?.statusCode == 402) {
        // Insufficient wallet
        _showOtpBlockedDialog(
          error: error,
          canUsePassword: canUsePassword,
          needsEmailVerify: needsEmailVerify,
          walletBalance: walletBalance?.toString(),
          smsCost: smsCost?.toString(),
        );
      } else if (e.response?.statusCode == 503) {
        // Service down
        _showOtpBlockedDialog(
          error: error,
          canUsePassword: canUsePassword,
          needsEmailVerify: needsEmailVerify,
        );
      } else {
        _show(error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOtpBlockedDialog({
    required String error,
    required bool canUsePassword,
    required bool needsEmailVerify,
    String? walletBalance,
    String? smsCost,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot Send OTP'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(error, style: const TextStyle(fontSize: 13)),
          if (walletBalance != null && smsCost != null) ...[
            const SizedBox(height: 8),
            Text('Wallet: ₹$walletBalance · SMS cost: ₹$smsCost',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 12),
          if (canUsePassword)
            const Text('💡 Use Password login instead — no OTP needed.',
                style: TextStyle(fontSize: 13, color: AppColors.primary)),
          if (needsEmailVerify)
            const Text('📧 Verify your email to get free OTPs.',
                style: TextStyle(fontSize: 13, color: Colors.indigo)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          if (canUsePassword)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _usePassword = true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Use Password'),
            ),
        ],
      ),
    );
  }

  // ── Customer: password login (phone or email + password) ──────────────────
  Future<void> _passwordLogin() async {
    final id   = _identifierCtrl.text.trim();
    final pass = _passCtrl.text;
    if (id.isEmpty)   { _show('Enter your phone number or email'); return; }
    if (pass.isEmpty) { _show('Enter your password'); return; }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final isEmail = id.contains('@');
      final res = await dio.post(Endpoints.emailLogin, data: {
        if (isEmail) 'email': id else 'phone': id,
        'password': pass,
      });
      final token = res.data['token'] as String;
      final user  = AppUser.fromJson(res.data['user']);
      ref.read(authStateProvider.notifier).setUserFromToken(token, user);
      if (!mounted) return;
      context.go('/home');
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data?['needs_otp'] == true) {
        _show('No password set yet — use OTP to log in.');
        setState(() => _usePassword = false);
      } else {
        _show(data?['error'] ?? 'Login failed');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Salesman login (kept for staff screen reuse) ─────────────────────────
  // moved to StaffLoginScreen

  // ── Admin OTP (kept for staff screen reuse) ──────────────────────────────
  // moved to StaffLoginScreen

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),

            // ── Hero header ──────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(children: [
                // Emoji product strip
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🥦', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 10),
                    Text('🍅', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 10),
                    Text('🥕', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 10),
                    Text('🌽', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 10),
                    Text('🥬', style: TextStyle(fontSize: 28)),
                  ],
                ),
                const SizedBox(height: 16),
                Image.asset('assets/images/logo.png', width: 64, height: 64),
                const SizedBox(height: 10),
                Text('HappyKrishi',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Farm fresh, delivered daily 🌿',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: 16),
                // Second emoji row — fruit & dairy
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🍋', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🥛', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🍳', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🫙', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🐟', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🍇', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('🧅', style: TextStyle(fontSize: 22)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 28),

            // ── Customer login card ──────────────────────────────────────────
            _TabCard(
              icon: Icons.person_outline,
              title: 'Customer Login',
              color: AppColors.primary,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _identifierCtrl,
                  keyboardType: _usePassword
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Phone number or Email',
                    prefixIcon: Icon(
                      _identifierIsEmail ? Icons.email_outlined : Icons.phone_outlined,
                      size: 18,
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: _usePassword ? null : 'OTP sent to verified email or phone',
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Login via:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'OTP',
                    selected: !_usePassword,
                    onTap: () => setState(() { _usePassword = false; _passCtrl.clear(); }),
                  ),
                  const SizedBox(width: 6),
                  _ModeChip(
                    label: 'Password',
                    selected: _usePassword,
                    onTap: () => setState(() => _usePassword = true),
                  ),
                ]),
                if (_usePassword) ...[
                  const SizedBox(height: 8),
                  _PasswordField(
                    controller: _passCtrl,
                    obscure: _passObscure,
                    label: 'Password',
                    onToggle: () => setState(() => _passObscure = !_passObscure),
                  ),
                ],
                const SizedBox(height: 10),
                _FullButton(
                  label: _usePassword ? 'Log In' : 'Send OTP',
                  loading: _loading,
                  onPressed: _usePassword ? _passwordLogin : _sendOtp,
                  icon: _usePassword ? Icons.login : Icons.send_outlined,
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/auth/signup'),
                    style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 4)),
                    child: const Text('New here? Create account →',
                        style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  ),
                ),
              ]),
            ),

            // ── Download APK banner (web only) ──────────────────────────────
            if (kIsWeb) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://delivery.happykrishi.com/happykrishi-delivery.apk'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    const Icon(Icons.android, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Download Android App',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Better experience · works offline',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      child: const Text('Download',
                          style: TextStyle(color: Colors.white,
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Staff login link ─────────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: () => context.push('/staff'),
                style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(vertical: 4)),
                child: Text('Staff login →',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ),
            ),

            // ── WhatsApp help button ─────────────────────────────────────────
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.chat_outlined, size: 16, color: Color(0xFF25D366)),
                label: const Text(
                  'Need help? Contact us on WhatsApp',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onPressed: () async {
                  try {
                    final dio = ref.read(dioProvider);
                    final res = await dio.get(Endpoints.appInfo);
                    final wa = res.data['contact']?['whatsapp'] as String? ?? '';
                    if (wa.isNotEmpty) {
                      final msg = Uri.encodeComponent('Hi, I need help with my HappyKrishi account login.');
                      final uri = Uri.parse('https://wa.me/91$wa?text=$msg');
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  } catch (_) {}
                },
              ),
            ),

            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ── Mode chip (OTP / Password toggle) ────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            )),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _TabCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  const _TabCard({required this.icon, required this.title,
      required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(12),
      color: color.withValues(alpha: 0.04),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final String label;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.obscure,
      required this.label, required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      prefixIcon: const Icon(Icons.lock_outline, size: 18),
      isDense: true,
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, size: 18),
        onPressed: onToggle,
      ),
    ),
  );
}

class _FullButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final IconData? icon;
  const _FullButton({required this.label, required this.loading,
      required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: loading
          ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Icon(icon ?? Icons.arrow_forward, size: 16),
      label: Text(label),
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 38),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    ),
  );
}
