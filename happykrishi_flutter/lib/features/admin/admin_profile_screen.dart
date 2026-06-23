import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

class AdminProfileScreen extends ConsumerStatefulWidget {
  const AdminProfileScreen({super.key});
  @override
  ConsumerState<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends ConsumerState<AdminProfileScreen> {
  late final _nameCtrl = TextEditingController();
  late final _emailCtrl = TextEditingController();
  bool _saving = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).user;
    _nameCtrl.text = user?.name ?? '';
    _emailCtrl.text = user?.email ?? '';
    _nameCtrl.addListener(_onChanged);
    _emailCtrl.addListener(_onChanged);
  }

  void _onChanged() {
    final user = ref.read(authStateProvider).user;
    setState(() {
      _changed = _nameCtrl.text.trim() != (user?.name ?? '') ||
          _emailCtrl.text.trim().toLowerCase() != (user?.email ?? '').toLowerCase();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _show('Name cannot be empty');
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.patch(Endpoints.updateProfile, data: {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      });
      // Refresh user in state
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        setState(() => _changed = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.data['message'] as String? ?? 'Profile updated ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to update profile');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (_changed)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar
          Center(
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Center(
                child: Text(
                  (user?.name.isNotEmpty == true ? user!.name[0] : 'A').toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 32,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                (user?.role ?? 'admin').toUpperCase(),
                style: const TextStyle(color: Color(0xFF2E7D32),
                    fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Read-only phone
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: '+91 ${user?.phone ?? ''}',
            readonly: true,
          ),
          const SizedBox(height: 16),

          // Editable name
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Editable email — critical for OTP login
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
              helperText: 'Admin OTP is sent to this email',
              helperStyle: TextStyle(color: Color(0xFF2E7D32)),
            ),
          ),

          // Email warning if empty
          if (_emailCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_outlined, color: Colors.orange.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No email set. Admin login OTP will fall back to WhatsApp/SMS.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 32),

          // Save button
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Changes'),
            onPressed: (_saving || !_changed) ? null : _save,
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Change password
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Change Password'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32),
              side: const BorderSide(color: Color(0xFF2E7D32)),
            ),
            onPressed: () => _showChangePasswordDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final otpCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    bool obscureNew = true;
    bool sendingOtp = false;
    bool saving     = false;
    bool otpSent    = false;
    final user = ref.read(authStateProvider).user;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!otpSent) ...[
                Text(
                  'An OTP will be sent to your email:\n${user?.email ?? 'your registered email'}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: sendingOtp
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.email_outlined, size: 16),
                    label: const Text('Send OTP'),
                    onPressed: sendingOtp ? null : () async {
                      setDs(() => sendingOtp = true);
                      try {
                        await ref.read(dioProvider).post(
                          Endpoints.changePasswordRequestOtp);
                        setDs(() { otpSent = true; sendingOtp = false; });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('OTP sent to your email')));
                        }
                      } on DioException catch (e) {
                        setDs(() => sendingOtp = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(e.response?.data['error'] ?? 'Failed to send OTP')));
                        }
                      }
                    },
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('OTP sent to ${user?.email ?? 'your email'}',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade700))),
                    TextButton(
                      onPressed: sendingOtp ? null : () async {
                        setDs(() => sendingOtp = true);
                        try {
                          await ref.read(dioProvider).post(Endpoints.changePasswordRequestOtp);
                          setDs(() => sendingOtp = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('OTP resent')));
                          }
                        } catch (_) { setDs(() => sendingOtp = false); }
                      },
                      child: const Text('Resend', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Enter OTP',
                    prefixIcon: Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password (min 6)',
                    prefixIcon: const Icon(Icons.lock_open_outlined),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setDs(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            if (otpSent)
              ElevatedButton(
                onPressed: saving ? null : () async {
                  if (otpCtrl.text.length != 6) { _show('Enter the 6-digit OTP'); return; }
                  if (newCtrl.text.length < 6)  { _show('Password must be at least 6 characters'); return; }
                  if (newCtrl.text != confCtrl.text) { _show('Passwords do not match'); return; }
                  setDs(() => saving = true);
                  try {
                    await ref.read(dioProvider).post(
                      Endpoints.changePassword,
                      data: {'otp': otpCtrl.text.trim(), 'new_password': newCtrl.text},
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Password changed successfully ✅'),
                        backgroundColor: Color(0xFF2E7D32),
                      ));
                    }
                  } on DioException catch (e) {
                    setDs(() => saving = false);
                    if (context.mounted) {
                      _show(e.response?.data['error'] ?? 'Failed to change password');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                child: saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Change Password'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool readonly;
  const _InfoRow({required this.icon, required this.label,
      required this.value, this.readonly = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(children: [
      Icon(icon, color: Colors.grey, size: 20),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ]),
      const Spacer(),
      if (readonly)
        const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
    ]),
  );
}
