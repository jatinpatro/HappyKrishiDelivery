import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/location_picker_screen.dart';
import '../admin/admin_tiers_screen.dart' show tierColor;

final addressesProvider = FutureProvider.autoDispose<List<Address>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.addresses);
  return (res.data['addresses'] as List).map((e) => Address.fromJson(e)).toList();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(addressesProvider);
              ref.read(authStateProvider.notifier).refreshUser();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(addressesProvider);
          await ref.read(authStateProvider.notifier).refreshUser();
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Verification banners ───────────────────────────────────────────
        if (user != null && !user.phoneVerified)
          _VerifyBanner(
            icon: Icons.phone_outlined,
            message: 'Verify your phone number to access all features.',
            color: Colors.orange,
            onTap: () => context.push('/auth/verify?phone=${user.phone}&mode=customer'),
          ),
        if (user != null && user.phoneVerified && user.email != null && !user.emailVerified)
          _VerifyBanner(
            icon: Icons.email_outlined,
            message: 'Verify your email for free OTP logins.',
            color: Colors.indigo,
            onTap: () => context.push('/auth/verify-email?next=/profile'),
          ),
        if (user != null && (user.phoneVerified || user.email == null) && user.emailVerified)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(children: [
              Icon(Icons.verified_outlined, color: Colors.green, size: 16),
              SizedBox(width: 10),
              Text('Phone & email verified — free OTP logins active.',
                  style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500)),
            ]),
          ),

        // User info card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.primary,
                child: Text(
                  user?.name.isNotEmpty == true
                      ? user!.name.substring(0, 1).toUpperCase()
                      : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('+91 ${user?.phone ?? ''}',
                      style: const TextStyle(color: Colors.grey)),
                  if (user?.email != null)
                    Text(user!.email!,
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  if (user?.tierName != null) ...[
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      final tc = tierColor(user!.tierColor);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tc.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tc.withValues(alpha: 0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.workspace_premium, size: 13, color: tc),
                          const SizedBox(width: 4),
                          Text(user!.tierName!,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: tc)),
                        ]),
                      );
                    }),
                  ],
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                tooltip: 'Edit Profile',
                onPressed: () => _showEditProfileSheet(context, ref, user),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Addresses header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Saved Addresses',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          TextButton.icon(
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add'),
            onPressed: () => _showAddressSheet(context, ref),
          ),
        ]),
        const SizedBox(height: 8),

        addresses.when(
          data: (list) => list.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(children: [
                    Icon(Icons.location_off_outlined, size: 48,
                        color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text('No saved addresses',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => _showAddressSheet(context, ref),
                      child: const Text('Add your first address'),
                    ),
                  ]),
                )
              : Column(
                  children: list
                      .map((a) => _AddressTile(
                            address: a,
                            onRefresh: () => ref.invalidate(addressesProvider),
                          ))
                      .toList(),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) { logError('profile', e); return Text(friendlyError(e)); },
        ),

        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.location_searching, color: AppColors.primary),
          label: const Text('My Delivery Area Requests',
              style: TextStyle(color: AppColors.primary)),
          onPressed: () => context.push('/request-delivery'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.card_giftcard_outlined, color: AppColors.primary),
          label: const Text('Referral Program',
              style: TextStyle(color: AppColors.primary)),
          onPressed: () => context.push('/referral'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.phone_outlined, color: AppColors.primary),
          label: const Text('Change Phone Number',
              style: TextStyle(color: AppColors.primary)),
          onPressed: () => _showChangePhoneSheet(context, ref),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.lock_reset, color: AppColors.primary),
          label: const Text('Change Password',
              style: TextStyle(color: AppColors.primary)),
          onPressed: () => context.push('/auth/change-password'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.info_outline, color: AppColors.primary),
          label: const Text('Delivery Info & Contact',
              style: TextStyle(color: AppColors.primary)),
          onPressed: () => context.push('/info'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('Logout', style: TextStyle(color: Colors.red)),
          onPressed: () {
            ref.read(authStateProvider.notifier).logout();
            context.go('/auth/otp');
          },
        ),
        const SizedBox(height: 24),
      ]),
      ),
    );
  }

  void _showChangePhoneSheet(BuildContext context, WidgetRef ref) {
    final phoneCtrl = TextEditingController();
    final otpCtrl   = TextEditingController();
    bool step1 = true;
    bool loading = false;
    String? pendingPhone;
    String? otpSentTo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Change Phone Number',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              step1
                  ? 'Enter your new phone number. An OTP will be sent to verify it.'
                  : otpSentTo ?? 'Enter the OTP to confirm +91 $pendingPhone',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            if (step1) ...[
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'New Phone Number',
                  prefixText: '+91 ',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ] else ...[
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'OTP',
                  counterText: '',
                ),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : () async {
                  setModalState(() => loading = true);
                  try {
                    final dio = ref.read(dioProvider);
                    if (step1) {
                      final phone = phoneCtrl.text.trim();
                      if (phone.length != 10) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter a valid 10-digit number')));
                        return;
                      }
                      pendingPhone = phone;
                      final otpRes = await dio.post(Endpoints.changePhoneRequestOtp, data: {'phone': phone});
                      final channel = otpRes.data['channel'] as String? ?? 'sms';
                      final sentMsg = channel == 'email'
                          ? 'OTP sent to your registered email'
                          : 'OTP sent to +91 $phone';
                      setModalState(() { step1 = false; otpSentTo = sentMsg; });
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(sentMsg)));
                    } else {
                      final res = await dio.post(Endpoints.changePhoneConfirm,
                          data: {'phone': pendingPhone, 'code': otpCtrl.text.trim()});
                      final user = AppUser.fromJson(res.data['user']);
                      ref.read(authStateProvider.notifier).updateUser(user);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone number updated ✅'),
                              backgroundColor: AppColors.primary));
                    }
                  } on DioException catch (e) {
                    final data = e.response?.data;
                    String msg = data?['error'] as String? ?? 'Failed';
                    final resetIn = data?['reset_in_seconds'] as int?;
                    if (resetIn != null) {
                      final mins = (resetIn / 60).ceil();
                      msg += '\n\nTry again in $mins minute${mins != 1 ? 's' : ''}.';
                    }
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
                  } finally {
                    setModalState(() => loading = false);
                  }
                },
                child: loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(step1 ? 'Send OTP' : 'Verify & Update'),
              ),
            ),
            if (!step1) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setModalState(() { step1 = true; otpCtrl.clear(); }),
                  child: const Text('← Change number'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _showEditProfileSheet(
      BuildContext context, WidgetRef ref, AppUser? user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditProfileSheet(user: user, ref: ref),
    );
  }

  void _showAddressSheet(BuildContext context, WidgetRef ref,
      [Address? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddressSheet(
        existing: existing,
        onSaved: () => ref.invalidate(addressesProvider),
      ),
    );
  }
}

// ── Edit profile sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends ConsumerStatefulWidget {
  final AppUser? user;
  final WidgetRef ref;
  const _EditProfileSheet({required this.user, required this.ref});
  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameCtrl =
      TextEditingController(text: widget.user?.name == 'User' ? '' : widget.user?.name);
  late final _emailCtrl =
      TextEditingController(text: widget.user?.email ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.register, data: {
        'name': name,
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      });
      final updatedUser = AppUser.fromJson(res.data['user']);
      ref.read(authStateProvider.notifier).updateUser(updatedUser);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.response?.data['error'] ?? 'Update failed')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Edit Profile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full Name *',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ),
      ]),
    );
  }
}

// ── Add / Edit address sheet — matches checkout form ─────────────────────────

class _AddressSheet extends ConsumerStatefulWidget {
  final Address? existing;
  final VoidCallback onSaved;
  const _AddressSheet({this.existing, required this.onSaved});
  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  late final _labelCtrl =
      TextEditingController(text: widget.existing?.label ?? 'Home');
  late final _lineCtrl =
      TextEditingController(text: widget.existing?.addressLine ?? '');
  late final _cityCtrl =
      TextEditingController(text: widget.existing?.city ?? '');
  late final _pincodeCtrl =
      TextEditingController(text: widget.existing?.pincode ?? '');

  // Pincode validation state
  bool _checkingPincode = false;
  bool? _pincodeDeliverable;
  String _pincodeMsg = '';
  String? _lastCheckedPincode;
  double? _pincodeDistanceKm;
  double? _pincodeLat;
  double? _pincodeLng;

  bool _isDefault = false;
  bool _saving = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _isDefault = widget.existing?.isDefault ?? false;
    _lat = widget.existing?.lat;
    _lng = widget.existing?.lng;
    // If editing and has a pincode, pre-check it
    final pin = widget.existing?.pincode ?? '';
    if (pin.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPincode(pin));
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _lineCtrl.dispose();
    _cityCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPincode(String pincode) async {
    if (pincode.length != 6) {
      setState(() {
        _pincodeDeliverable = null;
        _pincodeMsg = '';
        _pincodeDistanceKm = null;
      });
      return;
    }
    if (pincode == _lastCheckedPincode) return;
    setState(() {
      _checkingPincode = true;
      _pincodeDeliverable = null;
      _pincodeMsg = '';
    });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(Endpoints.checkPincode,
          queryParameters: {'pincode': pincode});
      final data = res.data as Map<String, dynamic>;
      final deliverable = data['deliverable'] as bool?;
      final distKm = data['distance_km'] as num?;
      final district = data['district'] as String? ?? '';
      final pLat = (data['lat'] as num?)?.toDouble();
      final pLng = (data['lng'] as num?)?.toDouble();
      if (mounted) {
        setState(() {
          _lastCheckedPincode = pincode;
          _checkingPincode = false;
          _pincodeDeliverable = deliverable;
          _pincodeDistanceKm = distKm?.toDouble();
          _pincodeLat = pLat;
          _pincodeLng = pLng;
          _pincodeMsg = deliverable == true
              ? '✓ Deliverable${district.isNotEmpty ? ' — $district' : ''}${distKm != null ? ' (${distKm}km)' : ''}'
              : deliverable == false
                  ? '✗ Outside 20 km delivery area${distKm != null ? ' ($distKm km away)' : ''}'
                  : 'Could not verify — you can still save';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingPincode = false;
          _pincodeDeliverable = null;
          _pincodeMsg = 'Could not verify pincode';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_lineCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address line and city are required')));
      return;
    }

    final pincode = _pincodeCtrl.text.trim();

    // If pincode typed but not checked yet — check first
    if (pincode.length == 6 && _pincodeDeliverable == null && !_checkingPincode) {
      await _checkPincode(pincode);
    }

    if (!mounted) return;

    // Block if confirmed out of range
    if (_pincodeDeliverable == false) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_pincodeMsg.isNotEmpty
              ? _pincodeMsg
              : 'This pincode is outside our 20 km delivery area')));
      return;
    }

    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final data = {
        'label': _labelCtrl.text.trim(),
        'address_line': _lineCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'pincode': pincode.isEmpty ? null : pincode,
        'is_default': _isDefault,
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
      };
      if (widget.existing != null) {
        await dio.put(Endpoints.address(widget.existing!.id), data: data);
      } else {
        await dio.post(Endpoints.addresses, data: data);
      }
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.existing != null
              ? 'Address updated ✅'
              : 'Address saved ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to save address')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              widget.existing == null ? 'Add Address' : 'Edit Address',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),

          // Label + Pincode row
          Row(children: [
            Expanded(
              child: TextField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Home / Office',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _pincodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: (v) {
                  if (v.length == 6) {
                    _checkPincode(v);
                  } else {
                    setState(() {
                      _pincodeDeliverable = null;
                      _pincodeMsg = '';
                      _pincodeDistanceKm = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Pincode',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                  suffixIcon: _checkingPincode
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : _pincodeDeliverable == true
                          ? const Icon(Icons.check_circle,
                              color: Colors.green, size: 20)
                          : _pincodeDeliverable == false
                              ? const Icon(Icons.cancel,
                                  color: Colors.red, size: 20)
                              : null,
                ),
              ),
            ),
          ]),

          // Pincode status message
          if (_pincodeMsg.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _pincodeMsg,
              style: TextStyle(
                fontSize: 11,
                color: _pincodeDeliverable == true
                    ? Colors.green.shade700
                    : _pincodeDeliverable == false
                        ? Colors.red
                        : Colors.orange.shade700,
              ),
            ),
          ],

          // Pin exact location — shown once pincode is deliverable
          if (_pincodeDeliverable == true && _pincodeLat != null) ...[
            const SizedBox(height: 8),
            if (_lat != null && _lng != null)
              Row(children: [
                const Icon(Icons.location_pin, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Location pinned',
                      style: TextStyle(fontSize: 12, color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await Navigator.push<LatLng>(
                      context,
                      MaterialPageRoute(builder: (_) => LocationPickerScreen(
                        initialCenter: LatLng(_pincodeLat!, _pincodeLng!),
                        existingPin: LatLng(_lat!, _lng!),
                      )),
                    );
                    if (picked != null && mounted) {
                      setState(() { _lat = picked.latitude; _lng = picked.longitude; });
                    }
                  },
                  style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
              ])
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.pin_drop_outlined, size: 16),
                  label: const Text('Pin your exact location'),
                  onPressed: () async {
                    final picked = await Navigator.push<LatLng>(
                      context,
                      MaterialPageRoute(builder: (_) => LocationPickerScreen(
                        initialCenter: LatLng(_pincodeLat!, _pincodeLng!),
                      )),
                    );
                    if (picked != null && mounted) {
                      setState(() { _lat = picked.latitude; _lng = picked.longitude; });
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],

          // Out-of-range: request custom delivery banner
          if (_pincodeDeliverable == false) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                context.push(
                  '/request-delivery'
                  '?pincode=${_pincodeCtrl.text.trim()}'
                  '${_pincodeDistanceKm != null ? '&distance_km=$_pincodeDistanceKm' : ''}',
                );
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.local_shipping_outlined,
                      color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Outside delivery area — tap to request special delivery',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios,
                      size: 12, color: Colors.orange.shade600),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Address line
          TextField(
            controller: _lineCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Address Line *',
              hintText: 'House no., street, village',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),

          // City
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City / Town *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          // Set as default toggle
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
          activeThumbColor: AppColors.primary,
            title: const Text('Set as default address',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text('Used automatically at checkout',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          const SizedBox(height: 4),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(widget.existing == null
                      ? 'Save Address'
                      : 'Update Address'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Address tile ──────────────────────────────────────────────────────────────

class _AddressTile extends ConsumerWidget {
  final Address address;
  final VoidCallback onRefresh;
  const _AddressTile({required this.address, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: address.isDefault
            ? const BorderSide(color: AppColors.primary, width: 1.5)
            : BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: address.isDefault
                  ? const Color(0xFFEAF2EA)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              address.label.toLowerCase().contains('office')
                  ? Icons.business_outlined
                  : Icons.home_outlined,
              color: address.isDefault
                  ? AppColors.primary
                  : Colors.grey,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(address.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (address.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Default',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text('${address.addressLine}, ${address.city}',
                  style: const TextStyle(fontSize: 13)),
              if (address.pincode != null) ...[
                const SizedBox(height: 2),
                Text('PIN ${address.pincode}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.primary),
              tooltip: 'Edit',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _AddressSheet(
                  existing: address,
                  onSaved: () {
                    ref.invalidate(addressesProvider);
                    onRefresh();
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () => _delete(context, ref),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address?'),
        content: Text(
            'Remove "${address.label} — ${address.addressLine}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dioProvider).delete(Endpoints.address(address.id));
      ref.invalidate(addressesProvider);
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Address deleted')));
      }
    } catch (e, st) {
      logError('profile', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }
}

class _VerifyBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onTap;
  const _VerifyBanner({required this.icon, required this.message, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(message,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
            Icon(Icons.arrow_forward_ios, color: color, size: 12),
          ]),
        ),
      ),
    ),
  );
}
