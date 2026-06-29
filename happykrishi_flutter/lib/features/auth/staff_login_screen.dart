import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});
  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final _salesmanPhoneCtrl = TextEditingController();
  final _salesmanPassCtrl  = TextEditingController();
  bool _salesmanObscure    = true;

  final _adminPhoneCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _salesmanPhoneCtrl.dispose();
    _salesmanPassCtrl.dispose();
    _adminPhoneCtrl.dispose();
    super.dispose();
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _salesmanLogin() async {
    final phone = _salesmanPhoneCtrl.text.trim();
    final pass  = _salesmanPassCtrl.text;
    if (phone.length != 10) { _show('Enter a valid 10-digit number'); return; }
    if (pass.isEmpty) { _show('Enter your password'); return; }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.salesmanLogin,
          data: {'phone': phone, 'password': pass});
      final token = res.data['token'] as String;
      final user  = AppUser.fromJson(res.data['user']);
      ref.read(authStateProvider.notifier).setUserFromToken(token, user);
      if (!mounted) return;
      context.go('/salesman');
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendAdminOtp() async {
    final phone = _adminPhoneCtrl.text.trim();
    if (phone.length != 10) { _show('Enter admin phone number'); return; }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.sendOtp, data: {'phone': phone});
      if (mounted) context.go('/auth/verify?phone=$phone&mode=admin');
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to send OTP');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Login'),
        backgroundColor: Colors.grey.shade800,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/auth/otp'),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade400,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Salesman'),
            Tab(text: 'Admin'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: TabBarView(
          controller: _tabs,
          children: [

            // ── Salesman tab ────────────────────────────────────────────────
            SingleChildScrollView(
              child: Column(children: [
                const SizedBox(height: 16),
                _StaffCard(
                  icon: Icons.badge_outlined,
                  title: 'Salesman Login',
                  color: Colors.orange.shade700,
                  child: Column(children: [
                    _PhoneField(controller: _salesmanPhoneCtrl, label: 'Salesman Phone'),
                    const SizedBox(height: 8),
                    _PasswordField(
                      controller: _salesmanPassCtrl,
                      obscure: _salesmanObscure,
                      label: 'Password',
                      onToggle: () => setState(() => _salesmanObscure = !_salesmanObscure),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _salesmanLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _loading
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Login'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),

            // ── Admin tab ───────────────────────────────────────────────────
            SingleChildScrollView(
              child: Column(children: [
                const SizedBox(height: 16),
                _StaffCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Admin Login',
                  color: Colors.indigo,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _PhoneField(controller: _adminPhoneCtrl, label: 'Admin Phone Number'),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.email_outlined, size: 14, color: Colors.indigo),
                      const SizedBox(width: 6),
                      Text('OTP sent to your registered email',
                          style: TextStyle(color: Colors.indigo.shade400, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _loading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.email_outlined, size: 16),
                        label: const Text('Send OTP'),
                        onPressed: _loading ? null : _sendAdminOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.lock_outline, size: 14),
                        label: const Text('Login with Password instead'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            textStyle: const TextStyle(fontSize: 12)),
                        onPressed: () => context.push('/auth/admin'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),

          ],
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  const _StaffCard({required this.icon, required this.title, required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
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
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _PhoneField({required this.controller, this.label = 'Phone Number'});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.phone,
    maxLength: 10,
    decoration: InputDecoration(
      labelText: label,
      prefixText: '+91 ',
      counterText: '',
      border: const OutlineInputBorder(),
      prefixIcon: const Icon(Icons.phone, size: 18),
      isDense: true,
    ),
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
