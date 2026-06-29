import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

class EmailSignupScreen extends ConsumerStatefulWidget {
  const EmailSignupScreen({super.key});
  @override
  ConsumerState<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends ConsumerState<EmailSignupScreen> {
  final _nameCtrl      = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _passCtrl      = TextEditingController();
  final _confirmCtrl   = TextEditingController();

  bool _obscure        = true;
  bool _obscureConfirm = true;
  bool _loading        = false;

  String? _gender;
  DateTime? _birthdate;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass  = _passCtrl.text;

    if (name.isEmpty)  { _show('Name is required'); return; }
    if (email.isEmpty) { _show('Email is required'); return; }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _show('Invalid email address'); return;
    }
    if (phone.isEmpty) { _show('Phone number is required'); return; }
    if (phone.length != 10) {
      _show('Phone must be 10 digits'); return;
    }
    if (pass.length < 6) { _show('Password must be at least 6 characters'); return; }
    if (pass != _confirmCtrl.text) { _show('Passwords do not match'); return; }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.emailSignup, data: {
        'name': name,
        'email': email,
        if (phone.isNotEmpty) 'phone': phone,
        'password': pass,
        if (_gender != null) 'gender': _gender,
        if (_birthdate != null)
          'birthdate': '${_birthdate!.year}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
      });
      final returnedPhone = res.data['phone'] as String? ?? phone;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account created! Please verify your phone number.'),
          backgroundColor: AppColors.primary,
        ));
        context.go('/auth/verify?phone=$returnedPhone&mode=customer');
      }
    } on DioException catch (e) {
      final error = e.response?.data['error'] as String? ?? 'Signup failed';
      // If phone already exists, user may have signed up before and cancelled OTP
      // — redirect them to verify instead of showing an error
      if (error.contains('Phone number already registered') && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account exists for this phone — please verify with OTP.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ));
        context.go('/auth/verify?phone=${_phoneCtrl.text.trim()}&mode=customer');
      } else {
        _show(error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
      helpText: 'Select Date of Birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')} / ${d.month.toString().padLeft(2,'0')} / ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/auth/otp'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          const Icon(Icons.agriculture, size: 48, color: AppColors.primary),
          const SizedBox(height: 8),
          const Text('Join HappyKrishi',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const Text('Fresh farm products delivered to your door',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),

          // ── Required fields ───────────────────────────────────────────────
          _Label('Full Name *'),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your full name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),

          _Label('Email Address *'),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),

          _Label('Password *'),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'Min. 6 characters',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),

          _Label('Confirm Password *'),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              hintText: 'Re-enter password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 14),

          _Label('Phone Number *'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              hintText: '10-digit mobile number',
              prefixText: '+91 ',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
              counterText: '',
              helperText: 'Used for OTP login and delivery updates',
            ),
          ),
          const SizedBox(height: 20),

          // ── Optional profile fields ───────────────────────────────────────
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('Optional Details',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 14),

          _Label('Date of Birth'),
          GestureDetector(
            onTap: _pickBirthdate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.cake_outlined, color: Colors.grey, size: 20),
                const SizedBox(width: 12),
                Text(
                  _birthdate != null ? _formatDate(_birthdate!) : 'Select date of birth',
                  style: TextStyle(
                    fontSize: 16,
                    color: _birthdate != null ? Colors.black87 : Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
              ]),
            ),
          ),
          const SizedBox(height: 14),

          _Label('Gender'),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            hint: const Text('Select gender'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.wc_outlined),
              border: OutlineInputBorder(),
            ),
            items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 28),

          // ── Submit ────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create Account', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => context.go('/auth/otp'),
              child: const Text('Already have an account? Log in'),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
  );
}
