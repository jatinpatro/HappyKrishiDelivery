import '../../core/theme/app_theme.dart'; 
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String next; // route to go after verified
  const VerifyEmailScreen({super.key, required this.next});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  int _secondsLeft = 600;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOnLoad());
  }

  Future<void> _sendOnLoad() async {
    try {
      await ref.read(dioProvider).post(Endpoints.sendEmailVerification);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent to your email.')));
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '';
      if (mounted && msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 600);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) { _timer?.cancel(); }
      else { if (mounted) setState(() => _secondsLeft--); }
    });
  }

  @override
  void dispose() { _timer?.cancel(); _codeCtrl.dispose(); super.dispose(); }

  String get _timerLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(dioProvider).post(Endpoints.sendEmailVerification);
      _codeCtrl.clear();
      _startTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email resent!')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resend. Try again.')));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter 6-digit code')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.verifyEmail, data: {'code': code});
      await ref.read(authStateProvider.notifier).refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Email verified ✅ Login OTPs will now be sent free to your email.'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 3),
      ));
      context.go(widget.next);
    } on DioException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Invalid code')));
    } catch (e, st) {
      logError('verify-email', e, st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final expired = _secondsLeft <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Skip for now',
          onPressed: () => context.go(widget.next),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Check your email', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (user?.email != null)
            Text('We sent a 6-digit code to ${user!.email}',
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 6),
          const Text('Verifying your email lets you receive free OTP logins.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 32),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            enabled: !expired,
            style: const TextStyle(fontSize: 28, letterSpacing: 10),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'Verification Code',
              counterText: '',
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Text(expired ? 'Code expired' : 'Valid for $_timerLabel',
                style: TextStyle(
                    color: expired ? Colors.red : Colors.grey, fontSize: 13)),
            const Spacer(),
            TextButton(
              onPressed: (!expired || _resending) ? null : _resend,
              child: _resending
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Resend',
                      style: TextStyle(color: expired ? AppColors.primary : Colors.grey)),
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_loading || expired) ? null : _verify,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Verify Email'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => context.go(widget.next),
              child: const Text('Skip — verify later from Profile',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
        ]),
      ),
    );
  }
}
