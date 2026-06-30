import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _referralCtrl = TextEditingController();

  bool _loading   = false;
  bool _sendingOtp = false;
  bool _emailVerified = false;
  bool _showOtpField  = false;
  String? _emailError;
  String? _otpError;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      // No email — skip verification
      _completeRegistration();
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }
    setState(() { _sendingOtp = true; _emailError = null; _otpError = null; });
    try {
      await ref.read(dioProvider).post(Endpoints.sendEmailVerification, data: {'email': email});
      setState(() { _showOtpField = true; _resendCooldown = 60; });
      _startCooldown();
    } on DioException catch (e) {
      setState(() => _emailError = e.response?.data['error'] ?? 'Could not send verification code');
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  void _startCooldown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown = (_resendCooldown - 1).clamp(0, 60));
      return _resendCooldown > 0;
    });
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code sent to your email');
      return;
    }
    setState(() { _loading = true; _otpError = null; });
    try {
      final res = await ref.read(dioProvider).post(Endpoints.verifyEmail,
          data: {'email': _emailCtrl.text.trim(), 'code': otp});
      // Email saved on backend; update local user state
      final user = AppUser.fromJson(res.data['user']);
      ref.read(authStateProvider.notifier).updateUser(user);
      setState(() { _emailVerified = true; _showOtpField = false; });
      // Now complete name update
      await _completeRegistration(skipEmail: true);
    } on DioException catch (e) {
      setState(() => _otpError = e.response?.data['error'] ?? 'Invalid code');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeRegistration({bool skipEmail = false}) async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.register, data: {
        'name': _nameCtrl.text.trim(),
        if (!skipEmail && !_emailVerified)
          'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      });
      final user = AppUser.fromJson(res.data['user']);
      ref.read(authStateProvider.notifier).updateUser(user);

      // Apply referral code if entered (for generic codes)
      final referralCode = _referralCtrl.text.trim().toUpperCase();
      if (referralCode.isNotEmpty && mounted) {
        try {
          final r = await dio.post(Endpoints.referralApply, data: {'code': referralCode});
          final credit = (r.data['signup_credit'] as num?)?.toDouble() ?? 0;
          if (mounted && credit > 0) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('🎉 ₹${credit.toStringAsFixed(0)} referral bonus added to your wallet!'),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 4),
            ));
          }
        } catch (_) {
          // Non-blocking — referral errors don't block registration
        }
      }

      if (mounted) context.go('/home');
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.response?.data['error'] ?? 'Error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onGetStarted() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your name')));
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      // No email — register without it
      _completeRegistration();
    } else if (_emailVerified) {
      // Already verified — just update name
      _completeRegistration(skipEmail: true);
    } else {
      // Need to verify email first
      await _sendVerificationOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(height: 16),
          Image.asset('assets/images/logo.png', height: 80, width: 80, fit: BoxFit.contain),
          const SizedBox(height: 10),
          const Text('HappyKrishi',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                  color: AppColors.primary, letterSpacing: 0.3)),
          const Text('Farm Fresh Delivery',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 28),

          // Name
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Your Name *'),
          ),
          const SizedBox(height: 16),

          // Email field
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            enabled: !_emailVerified && !_showOtpField,
            decoration: InputDecoration(
              labelText: 'Email (optional)',
              errorText: _emailError,
              suffixIcon: _emailVerified
                  ? const Icon(Icons.verified, color: AppColors.primary)
                  : null,
            ),
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
              if (_showOtpField) setState(() { _showOtpField = false; _otpCtrl.clear(); });
            },
          ),

          // OTP verification step
          if (_showOtpField) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'We sent a 6-digit code to ${_emailCtrl.text.trim()}',
                  style: const TextStyle(fontSize: 13, color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '_ _ _ _ _ _',
                    counterText: '',
                    errorText: _otpError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Verify Email'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: (_resendCooldown > 0 || _sendingOtp) ? null : _sendVerificationOtp,
                    child: Text(
                      _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend',
                      style: TextStyle(
                          color: _resendCooldown > 0 ? Colors.grey : AppColors.primary),
                    ),
                  ),
                ]),
              ]),
            ),
          ],

          if (_emailVerified) ...[
            const SizedBox(height: 8),
            const Row(children: [
              Icon(Icons.check_circle, color: AppColors.primary, size: 16),
              SizedBox(width: 6),
              Text('Email verified', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ]),
          ],

          const SizedBox(height: 32),

          // Referral code (optional — for generic codes shared by admin)
          if (!_showOtpField) ...[
            TextField(
              controller: _referralCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Referral Code (optional)',
                hintText: 'e.g. HKABCD12',
                prefixIcon: const Icon(Icons.card_giftcard_outlined, size: 20),
                helperText: 'Got a code? Enter it to get wallet credit',
                helperStyle: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (!_showOtpField)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_loading || _sendingOtp) ? null : _onGetStarted,
                child: (_loading || _sendingOtp)
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Get Started'),
              ),
            ),
        ]),
      ),
    );
  }
}
