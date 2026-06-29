import '../../core/theme/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';

class VerifyScreen extends ConsumerStatefulWidget {
  final String phone;
  final String mode;
  final String? channel;
  final String? hint;
  const VerifyScreen({super.key, required this.phone, this.mode = 'default', this.channel, this.hint});
  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _otpCtrl = TextEditingController();
  String? _rateLimitMsg;
  bool _loading = false;
  bool _resending = false;

  static const _otpValidSeconds = 600;
  int _secondsLeft = _otpValidSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtpOnLoad());
  }

  Future<void> _sendOtpOnLoad() async {
    await _sendOtp();
  }

  Future<void> _sendOtp() async {
    try {
      final dio = ref.read(dioProvider);
      final data = widget.phone.contains('@')
          ? {'email': widget.phone}
          : {'phone': widget.phone};
      final res = await dio.post(Endpoints.sendOtp, data: data);
      final channel = res.data['channel'] as String?;
      final hint    = res.data['hint'] as String?;
      if (mounted) {
        final msg = channel == 'email' && hint != null
            ? 'OTP sent to $hint'
            : 'OTP sent to +91 ${widget.phone}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data?['error'] as String? ?? '';
      final resetIn = data?['reset_in_seconds'] as int?;
      if (mounted && msg.isNotEmpty) {
        String display = msg;
        if (resetIn != null) {
          final mins = (resetIn / 60).ceil();
          display = '$msg\nYou can try again in $mins minute${mins != 1 ? 's' : ''}.';
        }
        setState(() => _rateLimitMsg = display);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _otpValidSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _timer?.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _timerLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _timerProgress => _secondsLeft / _otpValidSeconds;

  Color get _timerColor {
    if (_secondsLeft > 120) return AppColors.primary;
    if (_secondsLeft > 30) return const Color(0xFFF57C00);
    return const Color(0xFFD32F2F);
  }

  Future<void> _resendOtp() async {
    setState(() { _resending = true; _rateLimitMsg = null; });
    try {
      await _sendOtp();
      _otpCtrl.clear();
      _startTimer();
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter 6-digit OTP')),
      );
      return;
    }
    if (_secondsLeft <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP expired. Please resend.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.verifyOtp, data: {'phone': widget.phone, 'code': code});
      final token = res.data['token'] as String;
      final user = AppUser.fromJson(res.data['user']);
      final isNew = res.data['is_new'] == true;
      final needsPassword = res.data['needs_password'] == true;
      final needsEmailVerify = res.data['needs_email_verify'] == true;
      final emailHint = res.data['email_hint'] as String?;
      final referralCredited = res.data['referral_credited'] is num
          ? (res.data['referral_credited'] as num).toDouble()
          : null;
      ref.read(authStateProvider.notifier).setUserFromToken(token, user);
      if (!mounted) return;

      if (isNew && referralCredited != null && referralCredited > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎉 Welcome bonus! ₹${referralCredited.toStringAsFixed(0)} added to your wallet from your invite.'),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 4),
        ));
      }
      if (!mounted) return;

      final isAdmin = user.role == 'admin' || user.role == 'subadmin';
      final isSalesman = user.role == 'salesman';

      String destination;
      if (isNew || user.name == 'User') {
        destination = '/auth/register';
      } else if (needsPassword) {
        destination = '/auth/set-password';
      } else if (isAdmin) {
        destination = '/admin/dashboard';
      } else if (isSalesman && widget.mode == 'customer') {
        destination = '/home';
      } else if (isSalesman) {
        destination = '/salesman';
      } else {
        destination = '/home';
      }

      if (needsEmailVerify && !isAdmin && !isSalesman &&
          destination != '/auth/register' && destination != '/auth/set-password') {
        await _showEmailVerifyPrompt(emailHint, destination);
      } else {
        context.go(destination);
      }
    } on DioException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data['error'] ?? 'Invalid OTP')),
      );
    } catch (e, st) {
      logError('auth-verify', e, st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showEmailVerifyPrompt(String? emailHint, String destination) async {
    if (!mounted) return;
    final verify = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Your Email'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (emailHint != null)
            Text('Verify $emailHint for free OTP logins in the future.',
                style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          const Text('Would you like to verify your email now?',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip for now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Verify Email'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (verify == true) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post(Endpoints.sendEmailVerification);
        if (mounted) context.go('/auth/verify-email?next=${Uri.encodeComponent(destination)}');
      } catch (_) {
        if (mounted) context.go(destination);
      }
    } else {
      context.go(destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _secondsLeft <= 0;
    final channel = widget.channel;
    final hint = widget.hint;

    String sentToLabel;
    String sentToValue;
    if (channel == 'email' && hint != null) {
      sentToLabel = 'OTP sent to email';
      sentToValue = hint;
    } else if (channel == 'sms' || channel == 'whatsapp') {
      sentToLabel = channel == 'whatsapp' ? 'OTP sent via WhatsApp' : 'OTP sent via SMS';
      sentToValue = '+91 ${widget.phone}';
    } else {
      sentToLabel = 'Enter the OTP sent to';
      sentToValue = widget.phone.contains('@') ? widget.phone : '+91 ${widget.phone}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify OTP'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/auth/otp'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sentToLabel, style: Theme.of(context).textTheme.titleLarge),
            Text(sentToValue,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (channel == 'email')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Check your inbox and spam folder.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ),
            const SizedBox(height: 32),

            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              enabled: !expired,
              style: const TextStyle(fontSize: 28, letterSpacing: 10),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'OTP',
                counterText: '',
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: _timerProgress,
                        strokeWidth: 4,
                        backgroundColor: Colors.grey.shade200,
                        color: _timerColor,
                      ),
                      Center(
                        child: Text(
                          _timerLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _timerColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: expired
                      ? Text('OTP expired',
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))
                      : Text('OTP valid for $_timerLabel',
                          style: const TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: (!expired || _resending) ? null : _resendOtp,
                  child: _resending
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Resend OTP',
                          style: TextStyle(
                            color: expired ? AppColors.primary : Colors.grey,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ],
            ),

            // Rate limit message
            if (_rateLimitMsg != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_outlined, color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_rateLimitMsg!,
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
                ]),
              ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_loading || expired) ? null : _verify,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
