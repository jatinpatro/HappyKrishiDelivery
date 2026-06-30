import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  Future<void> _setPassword() async {
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      _show('Password must be at least 6 characters');
      return;
    }
    if (pass != _confirmCtrl.text) {
      _show('Passwords do not match');
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.setPassword, data: {'password': pass});
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password set successfully ✅'), backgroundColor: AppColors.primary));
        final user = ref.read(authStateProvider).user;
        if (user?.role == 'admin' || user?.role == 'subadmin') {
          context.go('/admin/dashboard');
        } else if (user?.role == 'agent') {
          context.go('/agent');
        } else if (user?.role == 'salesman') {
          context.go('/salesman');
        } else {
          context.go('/home');
        }
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to set password');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Password'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text('Create Your Password',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Set a password for faster login next time.\nYou can change it anytime from your profile.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 32),
          _PasswordField(
            controller: _passCtrl,
            label: 'New Password (min 6 chars)',
            obscure: _obscure1,
            onToggle: () => setState(() => _obscure1 = !_obscure1),
          ),
          const SizedBox(height: 16),
          _PasswordField(
            controller: _confirmCtrl,
            label: 'Confirm Password',
            obscure: _obscure2,
            onToggle: () => setState(() => _obscure2 = !_obscure2),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _setPassword,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Set Password & Continue'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Skip for now', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.label, required this.obscure, required this.onToggle});

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
