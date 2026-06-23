import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Customer tab — shared identifier (phone or email)
  final _identifierCtrl  = TextEditingController();
  final _passCtrl        = TextEditingController();
  bool _usePassword      = false;   // false = OTP mode, true = password mode
  bool _passObscure      = true;

  // Salesman tab
  final _salesmanPhoneCtrl = TextEditingController();
  final _salesmanPassCtrl  = TextEditingController();
  bool _salesmanObscure    = true;

  // Admin tab
  final _adminPhoneCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    _salesmanPhoneCtrl.dispose();
    _salesmanPassCtrl.dispose();
    _adminPhoneCtrl.dispose();
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
      final dio = ref.read(dioProvider);
      Map<String, dynamic> data;
      if (_identifierIsEmail) {
        data = {'email': id};
      } else {
        if (id.length != 10) { _show('Enter a valid 10-digit phone number'); return; }
        data = {'phone': id};
      }
      final res = await dio.post(Endpoints.sendOtp, data: data);
      if (!mounted) return;
      // Backend returns phone even when email was used (needed for verify route)
      final phone = res.data['phone'] as String? ?? id;
      context.go('/auth/verify?phone=$phone&mode=customer');
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to send OTP');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  // ── Salesman login ────────────────────────────────────────────────────────
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

  // ── Admin OTP ─────────────────────────────────────────────────────────────
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            Image.asset('assets/images/logo.png', width: 80, height: 80),
            const SizedBox(height: 12),
            Text('HappyKrishi',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32))),
            Text('Farm Fresh Delivery',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 24),

            // ── Tab bar ─────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                  color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabs,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey.shade600,
                indicator: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(12),
                ),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                tabs: const [
                  Tab(text: 'Customer'),
                  Tab(text: 'Salesman'),
                  Tab(text: 'Admin'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Tab views ───────────────────────────────────────────────────
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabs,
                children: [

                  // ── Customer tab ──────────────────────────────────────────
                  _TabCard(
                    icon: Icons.person_outline,
                    title: 'Customer Login',
                    color: const Color(0xFF2E7D32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // Identifier field — phone or email
                      TextField(
                        controller: _identifierCtrl,
                        keyboardType: _usePassword
                            ? TextInputType.emailAddress
                            : TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Phone number or Email',
                          prefixIcon: Icon(
                            _identifierIsEmail
                                ? Icons.email_outlined
                                : Icons.phone_outlined,
                            size: 18,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          helperText: _usePassword
                              ? null
                              : 'OTP sent to phone & email',
                          helperStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // OTP vs Password toggle
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
                              style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
                        ),
                      ),
                    ]),
                  ),

                  // ── Salesman tab ──────────────────────────────────────────
                  _TabCard(
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
                      const SizedBox(height: 10),
                      _FullButton(
                        label: 'Salesman Login',
                        loading: _loading,
                        onPressed: _salesmanLogin,
                        color: Colors.orange.shade700,
                      ),
                    ]),
                  ),

                  // ── Admin tab ─────────────────────────────────────────────
                  _TabCard(
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
                      const SizedBox(height: 10),
                      _FullButton(
                        label: 'Send OTP',
                        loading: _loading,
                        onPressed: _sendAdminOtp,
                        color: Colors.indigo,
                        icon: Icons.email_outlined,
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

                ],
              ),
            ),
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
    const color = Color(0xFF2E7D32);
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

class _FullButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;
  const _FullButton({required this.label, required this.loading,
      required this.onPressed, this.color, this.icon});

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
        backgroundColor: color ?? const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 38),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    ),
  );
}
