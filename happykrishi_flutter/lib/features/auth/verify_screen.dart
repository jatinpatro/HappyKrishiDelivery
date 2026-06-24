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
  final String mode; // 'customer' | 'admin' | 'default'
  const VerifyScreen({super.key, required this.phone, this.mode = 'default'});
  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;

  static const _otpValidSeconds = 600; // 10 minutes
  int _secondsLeft = _otpValidSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _otpValidSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _timer?.cancel();
      } else {
        setState(() => _secondsLeft--);
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
    if (_secondsLeft > 120) return const Color(0xFF2E7D32);   // green
    if (_secondsLeft > 30) return const Color(0xFFF57C00);    // orange
    return const Color(0xFFD32F2F);                            // red
  }

  Future<void> _resendOtp() async {
    setState(() => _resending = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.sendOtp, data: {'phone': widget.phone});
      _otpCtrl.clear();
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent via WhatsApp!')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data['error'] ?? 'Failed to resend';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
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
      ref.read(authStateProvider.notifier).setUserFromToken(token, user);
      if (!mounted) return;

      final isAdmin = user.role == 'admin' || user.role == 'subadmin';
      final isSalesman = user.role == 'salesman';
      final isAgent = user.role == 'agent';

      if (isNew || user.name == 'User') {
        context.go('/auth/register');
      } else if (needsPassword) {
        context.go('/auth/set-password');
      } else if (isAdmin) {
        // Admin ALWAYS goes to dashboard — mode cannot override this
        context.go('/admin/dashboard');
      } else if (isAgent) {
        context.go('/agent');
      } else if (isSalesman && widget.mode == 'customer') {
        // Salesman explicitly using customer tab → shop as customer
        context.go('/home');
      } else if (isSalesman) {
        context.go('/salesman');
      } else {
        // Regular customer
        context.go('/home');
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

  @override
  Widget build(BuildContext context) {
    final expired = _secondsLeft <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify OTP'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the OTP sent to',
                style: Theme.of(context).textTheme.titleLarge),
            Text('+91 ${widget.phone}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
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

            // Timer row
            Row(
              children: [
                // Circular countdown
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
                      ? Text(
                          'OTP expired',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Text(
                          'OTP valid for $_timerLabel',
                          style: const TextStyle(color: Colors.grey),
                        ),
                ),
                // Resend button — active only when expired
                TextButton(
                  onPressed: (!expired || _resending) ? null : _resendOtp,
                  child: _resending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Resend OTP',
                          style: TextStyle(
                            color: expired
                                ? const Color(0xFF2E7D32)
                                : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
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
