import '../../core/theme/app_theme.dart'; 
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../wallet/wallet_screen.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  int _step = 1;
  String? _sentTo;     // 'email' or 'phone'
  String? _hint;       // email address or last-4 of phone

  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  int _otpSecondsLeft = 600;
  Timer? _timer;

  void _startTimer() {
    _timer?.cancel();
    setState(() => _otpSecondsLeft = 600);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_otpSecondsLeft <= 0) { _timer?.cancel(); }
      else { setState(() => _otpSecondsLeft--); }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.changePasswordRequestOtp);
      _sentTo = res.data['sent_to'] as String?;
      _hint = res.data['hint'] as String?;
      setState(() => _step = 2);
      _startTimer();
      if (mounted) {
        final msg = _sentTo == 'email'
            ? 'OTP sent to your email: $_hint'
            : 'OTP sent to your phone (****$_hint)';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to send OTP');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changePassword() async {
    final otp = _otpCtrl.text.trim();
    final pass = _passCtrl.text;
    if (otp.length != 6) { _show('Enter 6-digit OTP'); return; }
    if (pass.length < 6) { _show('Password must be at least 6 characters'); return; }
    if (pass != _confirmCtrl.text) { _show('Passwords do not match'); return; }
    if (_otpSecondsLeft <= 0) { _show('OTP expired. Go back and request again.'); return; }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.changePassword, data: {
        'otp': otp,
        'new_password': pass,
      });
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password changed successfully ✅'),
          backgroundColor: AppColors.primary,
        ));
        Navigator.of(context).pop();
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to change password');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _step == 1 ? _buildStep1(user) : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1(AppUser? user) {
    final email = user?.email;
    final hasEmail = email != null && email.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.lock_reset, size: 52, color: AppColors.primary),
      const SizedBox(height: 16),
      const Text('Change Password',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),

      // Info card — free, no charge
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2EA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle, color: AppColors.primary, size: 18),
            SizedBox(width: 8),
            Text('Free — no charge', style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.primary)),
          ]),
          const SizedBox(height: 6),
          Text(
            hasEmail
                ? 'A one-time code will be sent to your email: $email'
                : 'A one-time code will be sent to your phone via WhatsApp / SMS.',
            style: const TextStyle(fontSize: 13),
          ),
        ]),
      ),
      const SizedBox(height: 28),

      ElevatedButton.icon(
        icon: _loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Icon(hasEmail ? Icons.email_outlined : Icons.message_outlined),
        label: Text(hasEmail ? 'Send OTP to Email' : 'Send OTP to Phone'),
        onPressed: _loading ? null : _requestOtp,
      ),
    ]);
  }

  Widget _buildStep2() {
    final expired = _otpSecondsLeft <= 0;
    final m = _otpSecondsLeft ~/ 60;
    final s = _otpSecondsLeft % 60;
    final timerLabel =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Sent-to banner
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2EA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(
            _sentTo == 'email' ? Icons.email_outlined : Icons.message_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _sentTo == 'email'
                  ? 'OTP sent to email: $_hint'
                  : 'OTP sent to phone (****$_hint)',
              style: const TextStyle(color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      TextField(
        controller: _otpCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        enabled: !expired,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: 'Enter OTP',
          counterText: '',
          border: const OutlineInputBorder(),
          helperText: expired
              ? 'OTP expired — go back and try again'
              : 'Valid for $timerLabel',
          helperStyle: TextStyle(
              color: expired ? Colors.red : Colors.grey),
        ),
      ),
      const SizedBox(height: 16),

      _PasswordField(
        controller: _passCtrl,
        label: 'New Password (min 6 chars)',
        obscure: _obscure1,
        onToggle: () => setState(() => _obscure1 = !_obscure1),
      ),
      const SizedBox(height: 12),
      _PasswordField(
        controller: _confirmCtrl,
        label: 'Confirm New Password',
        obscure: _obscure2,
        onToggle: () => setState(() => _obscure2 = !_obscure2),
      ),
      const SizedBox(height: 24),

      ElevatedButton(
        onPressed: (_loading || expired) ? null : _changePassword,
        child: _loading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Change Password'),
      ),

      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () => setState(() { _step = 1; _timer?.cancel(); }),
          child: const Text('← Go back & resend'),
        ),
      ),
    ]);
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.label,
      required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: onToggle,
          ),
        ),
      );
}
