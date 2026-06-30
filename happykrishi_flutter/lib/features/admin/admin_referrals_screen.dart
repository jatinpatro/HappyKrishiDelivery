import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/widgets/active_filter.dart';

final _referralsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.adminReferrals);
  return res.data as Map<String, dynamic>;
});

const _referralsFilterConfig = FilterFormConfig(
  title: 'Filter Referrals',
  showDateRange: true,
  showTextSearch: true,
  textSearchHint: 'Owner name, used by, referral code…',
  dynamicFields: [
    FilterDefinition(field: 'owner_name',   label: 'Owner',   type: FilterType.text, serverSide: false),
    FilterDefinition(field: 'used_by_name', label: 'Used By', type: FilterType.text, serverSide: false),
    FilterDefinition(field: 'code',         label: 'Code',    type: FilterType.text, serverSide: false),
    FilterDefinition(field: 'is_used',      label: 'Status',  type: FilterType.select,
        options: ['used', 'unused'], serverSide: false),
  ],
);

class AdminReferralsScreen extends ConsumerStatefulWidget {
  const AdminReferralsScreen({super.key});
  @override
  ConsumerState<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

class _AdminReferralsScreenState extends ConsumerState<AdminReferralsScreen> {
  final _signupCtrl  = TextEditingController();
  final _bonusCtrl   = TextEditingController();
  bool _enabled = true;
  bool _savingConfig = false;
  bool _configLoaded = false;
  FilterFormState _filter = FilterFormState.empty;

  @override
  void dispose() {
    _signupCtrl.dispose();
    _bonusCtrl.dispose();
    super.dispose();
  }

  void _loadConfig(Map<String, dynamic> cfg) {
    if (_configLoaded) return;
    _configLoaded = true;
    _signupCtrl.text = cfg['referral_signup_credit'] as String? ?? '50';
    _bonusCtrl.text  = cfg['referral_first_order_bonus'] as String? ?? '100';
    _enabled = (cfg['referral_enabled'] as String?) != '0';
  }

  Future<void> _saveConfig() async {
    final signup = double.tryParse(_signupCtrl.text.trim());
    final bonus  = double.tryParse(_bonusCtrl.text.trim());
    if (signup == null || signup < 0 || bonus == null || bonus < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid amounts (0 or more)')));
      return;
    }
    setState(() => _savingConfig = true);
    try {
      await ref.read(dioProvider).put(Endpoints.adminConfig, data: {
        'config': {
          'referral_signup_credit': signup.toStringAsFixed(0),
          'referral_first_order_bonus': bonus.toStringAsFixed(0),
          'referral_enabled': _enabled ? '1' : '0',
        },
      });
      ref.invalidate(_referralsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Referral settings saved ✅'), backgroundColor: AppColors.primary));
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.response?.data['error'] ?? 'Save failed')));
      }
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  Future<void> _showGenerateInvitesDialog(BuildContext context) async {
    final phonesCtrl = TextEditingController();
    bool generating = false;
    List<Map<String, dynamic>> results = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
              MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Text('Generate Invite Codes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            const Text('Enter phone numbers to invite (one per line, 10 digits).',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 14),

            // Results list (shown after generation)
            if (results.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200)),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    final hasCode = r['code'] != null;
                    final isError = r['error'] != null && !hasCode;
                    final color = isError ? Colors.red : r['skipped'] == true
                        ? Colors.orange : Colors.green;
                    final icon = isError ? Icons.error_outline
                        : r['skipped'] == true ? Icons.skip_next : Icons.check_circle_outline;
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: color, size: 18),
                      title: Text('+91 ${r['phone']}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: hasCode
                          ? Text('Code: ${r['code']}',
                              style: const TextStyle(fontSize: 12, letterSpacing: 1))
                          : Text(r['error'] ?? (r['skipped'] == true ? 'Code already exists' : ''),
                              style: TextStyle(fontSize: 11, color: color)),
                      trailing: hasCode ? Row(mainAxisSize: MainAxisSize.min, children: [
                        // Copy code
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy code',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: r['code'] as String));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied'),
                                    duration: Duration(seconds: 1)));
                          },
                        ),
                        // WhatsApp share
                        IconButton(
                          icon: Image.asset('assets/whatsapp.png',
                              width: 18, height: 18,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.message, size: 16, color: Color(0xFF25D366))),
                          tooltip: 'Send via WhatsApp',
                          onPressed: () {
                            final msg = Uri.encodeComponent(
                              'Hi! 👋 You\'ve been invited to HappyKrishi Delivery — '
                              'fresh farm produce delivered to your door.\n\n'
                              'Use referral code *${r['code']}* when signing up to get a '
                              'wallet credit! 🎁\n\n'
                              'Download: https://delivery.happykrishi.com',
                            );
                            launchUrl(Uri.parse('https://wa.me/91${r['phone']}?text=$msg'),
                                mode: LaunchMode.externalApplication);
                          },
                        ),
                      ]) : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Share all valid codes
              if (results.any((r) => r['code'] != null))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Share All via WhatsApp'),
                    onPressed: () {
                      final valid = results.where((r) => r['code'] != null).toList();
                      final msg = valid.map((r) =>
                          '+91 ${r['phone']} → Code: ${r['code']}'
                      ).join('\n');
                      final full = Uri.encodeComponent(
                        'HappyKrishi Delivery — Referral Invites 🌿\n\n$msg\n\n'
                        'Sign up at: https://delivery.happykrishi.com',
                      );
                      launchUrl(Uri.parse('https://wa.me/?text=$full'),
                          mode: LaunchMode.externalApplication);
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF25D366))),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ),
            ] else ...[
              // Input field
              TextField(
                controller: phonesCtrl,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: '9876543210\n9876543211\n9876543212',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),

              // Pick from contacts — only on mobile (not supported on web)
              if (!kIsWeb) SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.contacts_outlined, size: 16),
                  label: const Text('Pick from Contacts'),
                  onPressed: () async {
                    final status = await FlutterContacts.permissions.request(PermissionType.read);
                    final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
                    if (!granted) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contacts permission denied. Please allow in Settings.')));
                      }
                      return;
                    }
                    // Load contacts with name + phone
                    final contacts = await FlutterContacts.getAll(
                        properties: {ContactProperty.name, ContactProperty.phone});
                    final withPhone = contacts.where((c) => c.phones.isNotEmpty).toList();
                    if (!ctx.mounted) return;
                    if (withPhone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No contacts with phone numbers found')));
                      return;
                    }

                    // Show searchable multi-select contact list
                    final picked = await showModalBottomSheet<List<String>>(
                      context: ctx,
                      isScrollControlled: true,
                      useSafeArea: true,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => _ContactPickerSheet(contacts: withPhone),
                    );
                    if (picked == null || picked.isEmpty) return;

                    // Append picked numbers to the text field
                    final existing = phonesCtrl.text.trim();
                    final all = [
                      if (existing.isNotEmpty) existing,
                      ...picked,
                    ].join('\n');
                    setSt(() => phonesCtrl.text = all);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: generating
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(generating ? 'Generating…' : 'Generate & Show Codes'),
                  onPressed: generating ? null : () async {
                    final lines = phonesCtrl.text.trim().split('\n')
                        .map((l) => l.trim().replaceAll(RegExp(r'\D'), ''))
                        .where((l) => l.isNotEmpty)
                        .toList();
                    if (lines.isEmpty) return;
                    setSt(() => generating = true);
                    try {
                      final res = await ref.read(dioProvider).post(
                        Endpoints.adminReferralsGenerate,
                        data: {'phones': lines},
                      );
                      final r = List<Map<String, dynamic>>.from(res.data['results']);
                      setSt(() { generating = false; results = r; });
                      ref.invalidate(_referralsProvider);
                    } catch (e, st) {
                      logError('admin-referrals-generate', e, st);
                      setSt(() => generating = false);
                      if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyError(e))));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_referralsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Program'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Generate Invite Codes',
            onPressed: () => _showGenerateInvitesDialog(context),
          ),
          IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/admin/dashboard')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            _configLoaded = false;
            ref.invalidate(_referralsProvider);
          }),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('admin-referrals', e); return Center(child: Text(friendlyError(e))); },
        data: (data) {
          final allReferrals = (data['referrals'] as List).cast<Map<String, dynamic>>();
          final stats = data['stats'] as Map<String, dynamic>;
          final cfg = data['config'] as Map<String, dynamic>;
          _loadConfig(cfg);

          // Apply local filters
          final localFilters = _filter.toLocalFilters();
          final searchQ = _filter.search.toLowerCase();
          final referrals = allReferrals.where((r) {
            final isUsed = r['used_by_user_id'] != null;
            // date range on created_at
            if (_filter.dateFrom != null) {
              final d = DateTime.tryParse(r['created_at'] as String? ?? '');
              if (d == null || d.isBefore(_filter.dateFrom!)) return false;
            }
            if (_filter.dateTo != null) {
              final d = DateTime.tryParse(r['created_at'] as String? ?? '');
              if (d == null || d.isAfter(_filter.dateTo!.add(const Duration(days: 1)))) return false;
            }
            // text search across key fields
            if (searchQ.isNotEmpty) {
              final hit = (r['owner_name']?.toString().toLowerCase().contains(searchQ) ?? false)
                  || (r['owner_phone']?.toString().contains(searchQ) ?? false)
                  || (r['used_by_name']?.toString().toLowerCase().contains(searchQ) ?? false)
                  || (r['used_by_phone']?.toString().contains(searchQ) ?? false)
                  || (r['code']?.toString().toLowerCase().contains(searchQ) ?? false);
              if (!hit) return false;
            }
            // dynamic chip filters
            for (final f in localFilters) {
              if (f.field == 'is_used') {
                final want = f.value == 'used';
                if (isUsed != want) return false;
              } else {
                final raw = r[f.field];
                if (!(raw?.toString().toLowerCase().contains(f.value.toString().toLowerCase()) ?? false)) {
                  return false;
                }
              }
            }
            return true;
          }).toList();

          return Column(children: [

            // ── Settings panel ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              color: AppColors.background,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryDark)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _AmountField(
                      controller: _signupCtrl,
                      label: 'Credit for new customer',
                      hint: 'e.g. 50',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AmountField(
                      controller: _bonusCtrl,
                      label: 'Bonus for referrer (1st order)',
                      hint: 'e.g. 100',
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Switch(
                    value: _enabled,
                    activeTrackColor: AppColors.primary,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  Expanded(
                    child: Text(
                      _enabled ? 'Referral program enabled' : 'Referral program disabled',
                      style: TextStyle(fontSize: 13, color: _enabled ? AppColors.primary : Colors.grey),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _savingConfig ? null : _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _savingConfig
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Settings'),
                  ),
                ),
              ]),
            ),
            const Divider(height: 1),

            // ── Stats bar ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFEAF2EA),
              child: Row(children: [
                _StatPill('${stats['total_codes']}', 'Total codes', Colors.indigo),
                const SizedBox(width: 8),
                _StatPill('${stats['total_used']}', 'Used', Colors.blue),
                const SizedBox(width: 8),
                _StatPill('₹${(stats['total_signup_credits'] as num).toStringAsFixed(0)}', 'Credits given', Colors.orange),
                const SizedBox(width: 8),
                _StatPill('₹${(stats['total_bonuses'] as num).toStringAsFixed(0)}', 'Bonuses paid', AppColors.primary),
              ]),
            ),
            const Divider(height: 1),

            // ── Generic codes section ───────────────────────────────────────
            _GenericCodesSection(
              genericCodes: (data['generic_codes'] as List? ?? []).cast<Map<String, dynamic>>(),
              onChanged: () { _configLoaded = false; ref.invalidate(_referralsProvider); },
            ),
            const Divider(height: 1),

            // ── Filter bar ──────────────────────────────────────────────────
            FilterBar(
              config: _referralsFilterConfig,
              state: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const Divider(height: 1),

            // ── Referral list ───────────────────────────────────────────────
            if (referrals.isEmpty)
              const Expanded(child: Center(child: Text('No referrals match the filter', style: TextStyle(color: Colors.grey))))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _configLoaded = false;
                    ref.invalidate(_referralsProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: referrals.length,
                    itemBuilder: (_, i) {
                      final r = referrals[i];
                      final isUsed        = r['used_by_user_id'] != null;
                      final bonusPaid     = r['bonus_credited_at'] != null;
                      final invitedPhone  = r['invited_phone'] as String?;
                      final ownerRole     = r['owner_role'] as String? ?? 'customer';
                      final isAdminCode   = invitedPhone != null && (ownerRole == 'admin' || ownerRole == 'subadmin');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2EA),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                ),
                                child: Text(r['code'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                                        letterSpacing: 2, color: AppColors.primary)),
                              ),
                              const SizedBox(width: 6),
                              if (isAdminCode)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.purple.shade200),
                                  ),
                                  child: Text('Admin invite',
                                      style: TextStyle(fontSize: 9, color: Colors.purple.shade700,
                                          fontWeight: FontWeight.w600)),
                                ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isUsed ? Colors.blue.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(isUsed ? 'Used' : 'Unused',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                        color: isUsed ? Colors.blue : Colors.grey)),
                              ),
                            ]),
                            const SizedBox(height: 8),

                            // Invited phone (admin-generated codes)
                            if (isAdminCode) ...[
                              Row(children: [
                                Icon(Icons.phone_forwarded_outlined, size: 14,
                                    color: Colors.purple.shade400),
                                const SizedBox(width: 4),
                                Text('For: +91 $invitedPhone',
                                    style: TextStyle(fontSize: 12,
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.w500)),
                                const Spacer(),
                                // Reshare button
                                if (!isUsed)
                                  GestureDetector(
                                    onTap: () {
                                      final msg = Uri.encodeComponent(
                                        'Hi! 👋 You\'ve been personally invited to HappyKrishi Delivery.\n\n'
                                        'Use this referral code *${r['code']}* when signing up to get '
                                        'a wallet credit! 🎁\n\n'
                                        'Download: https://delivery.happykrishi.com',
                                      );
                                      launchUrl(
                                        Uri.parse('https://wa.me/91$invitedPhone?text=$msg'),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF25D366).withValues(alpha: 0.4)),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.send_outlined, size: 13,
                                            color: Color(0xFF25D366)),
                                        const SizedBox(width: 4),
                                        const Text('Reshare',
                                            style: TextStyle(fontSize: 11,
                                                color: Color(0xFF25D366),
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  ),
                              ]),
                              const SizedBox(height: 4),
                            ],

                            Row(children: [
                              const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text('Owner: ${r['owner_name']}  •  +91 ${r['owner_phone']}',
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                            if (isUsed) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.person_add_outlined, size: 14, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text('Used by: ${r['used_by_name']}  •  +91 ${r['used_by_phone']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.blue)),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                const SizedBox(width: 18),
                                if (r['signup_credit_amount'] != null)
                                  _Badge('₹${(r['signup_credit_amount'] as num).toStringAsFixed(0)} credit given', Colors.orange),
                                const SizedBox(width: 6),
                                if (bonusPaid)
                                  _Badge('₹${(r['bonus_credit_amount'] as num).toStringAsFixed(0)} bonus paid', Colors.green)
                                else
                                  _Badge('Bonus pending first order', Colors.grey),
                              ]),
                            ],
                            const SizedBox(height: 4),
                            Text('Created: ${(r['created_at'] as String).substring(0, 10)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ── Generic Codes Section ─────────────────────────────────────────────────────

class _GenericCodesSection extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> genericCodes;
  final VoidCallback onChanged;
  const _GenericCodesSection({required this.genericCodes, required this.onChanged});
  @override
  ConsumerState<_GenericCodesSection> createState() => _GenericCodesSectionState();
}

class _GenericCodesSectionState extends ConsumerState<_GenericCodesSection> {
  bool _expanded = true;

  Future<void> _showCreateEditDialog({Map<String, dynamic>? existing}) async {
    final codeCtrl   = TextEditingController(text: existing?['code'] as String? ?? '');
    final labelCtrl  = TextEditingController(text: existing?['label'] as String? ?? '');
    final creditCtrl = TextEditingController(
        text: existing?['custom_signup_credit'] != null
            ? (existing!['custom_signup_credit'] as num).toStringAsFixed(0)
            : '');
    final maxUsesCtrl = TextEditingController(
        text: existing?['max_uses'] != null
            ? (existing!['max_uses'] as num).toStringAsFixed(0)
            : '');
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing != null ? 'Edit Generic Code' : 'New Generic Code'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: codeCtrl,
                enabled: existing == null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Code (optional — auto-generated if blank)',
                  hintText: 'e.g. HARVEST25',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: existing == null ? 'Leave blank for auto HK****** code' : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (internal description)',
                  hintText: 'e.g. Harvest Festival 2026',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Signup credit (₹)',
                  hintText: 'e.g. 75',
                  prefixText: '₹ ',
                  helperText: 'Leave blank to use global default',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max uses (optional)',
                  hintText: 'e.g. 100',
                  helperText: 'Leave blank for unlimited',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                setSt(() => saving = true);
                try {
                  final dio = ref.read(dioProvider);
                  final body = {
                    if (existing == null && codeCtrl.text.trim().isNotEmpty)
                      'code': codeCtrl.text.trim().toUpperCase(),
                    'label': labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
                    'custom_signup_credit': creditCtrl.text.trim().isEmpty
                        ? null : double.tryParse(creditCtrl.text.trim()),
                    'max_uses': maxUsesCtrl.text.trim().isEmpty
                        ? null : int.tryParse(maxUsesCtrl.text.trim()),
                  };
                  if (existing != null) {
                    await dio.put(Endpoints.adminReferralGeneric(existing['id'] as int), data: body);
                  } else {
                    await dio.post(Endpoints.adminReferralsGeneric, data: body);
                  }
                  widget.onChanged();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(existing != null ? 'Code updated ✅' : 'Generic code created ✅'),
                    backgroundColor: AppColors.primary,
                  ));
                } catch (e) {
                  setSt(() => saving = false);
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(existing != null ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Generic Code?'),
        content: Text('Delete code "${code['code']}"? Customers who already used it keep their credits.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(dioProvider).delete(Endpoints.adminReferralGeneric(code['id'] as int));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final codes = widget.genericCodes;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            const Icon(Icons.qr_code_2_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Generic Codes${codes.isNotEmpty ? ' (${codes.length})' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                  color: AppColors.primaryDark),
            )),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New'),
              onPressed: () => _showCreateEditDialog(),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey, size: 20),
          ]),
        ),
      ),

      if (_expanded) ...[
        if (codes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('No generic codes yet. Tap + New to create one.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          )
        else
          ...codes.map((c) {
            final useCount  = (c['use_count'] as num? ?? 0).toInt();
            final maxUses   = c['max_uses'] as int?;
            final credit    = c['custom_signup_credit'] as num?;
            final label     = c['label'] as String?;
            final isActive  = maxUses == null || useCount < maxUses;

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : Colors.grey.shade300),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(c['code'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                            letterSpacing: 2, color: AppColors.primary)),
                    const SizedBox(width: 8),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('Limit reached',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ),
                  ]),
                  if (label != null && label.isNotEmpty)
                    Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _SmallBadge(
                      '₹${credit != null ? credit.toStringAsFixed(0) : 'default'} credit',
                      Colors.orange,
                    ),
                    _SmallBadge(
                      '$useCount used${maxUses != null ? ' / $maxUses max' : ''}',
                      Colors.blue,
                    ),
                  ]),
                ])),
                // Actions
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                  onSelected: (v) {
                    if (v == 'edit') _showCreateEditDialog(existing: c);
                    if (v == 'delete') _delete(c);
                    if (v == 'copy') {
                      Clipboard.setData(ClipboardData(text: c['code'] as String));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied'),
                              duration: Duration(seconds: 1)));
                    }
                    if (v == 'share') {
                      final credit_ = c['custom_signup_credit'] as num?;
                      final msg = Uri.encodeComponent(
                        'Use code *${c['code']}* when signing up on HappyKrishi Delivery '
                        'to get ₹${credit_ != null ? credit_.toStringAsFixed(0) : '...'} wallet credit! 🎁\n'
                        'Download: https://delivery.happykrishi.com',
                      );
                      launchUrl(Uri.parse('https://wa.me/?text=$msg'),
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy',   child: ListTile(dense: true, leading: Icon(Icons.copy, size: 16), title: Text('Copy code'))),
                    PopupMenuItem(value: 'share',  child: ListTile(dense: true, leading: Icon(Icons.share_outlined, size: 16), title: Text('Share via WhatsApp'))),
                    PopupMenuItem(value: 'edit',   child: ListTile(dense: true, leading: Icon(Icons.edit_outlined, size: 16), title: Text('Edit'))),
                    PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, size: 16, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ]),
            );
          }),
      ],
    ]);
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
  );
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  const _AmountField({required this.controller, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: false),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: '₹ ',
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );
}

class _StatPill extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatPill(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
  );
}

// ── Contact Picker Sheet ──────────────────────────────────────────────────────

class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  const _ContactPickerSheet({required this.contacts});
  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  final Set<String> _selected = {};  // normalized 10-digit phones

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  String _normalize(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^(91|\+91)'), '');

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final filtered = widget.contacts.where((c) {
      if (q.isEmpty) return true;
      final name = (c.displayName ?? '').toLowerCase();
      final phone = c.phones.map((p) => p.number).join(' ');
      return name.contains(q) || phone.contains(q);
    }).toList()
      ..sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));

    return Column(children: [
      // Handle
      Container(
        margin: const EdgeInsets.only(top: 10),
        width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2)),
      ),
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          const Icon(Icons.contacts_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Select Contacts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: Text('Add ${_selected.length}',
                  style: const TextStyle(color: AppColors.primary,
                      fontWeight: FontWeight.bold)),
            ),
          IconButton(icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, null)),
        ]),
      ),
      // Search
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextField(
          controller: _searchCtrl,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search name or number…',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            suffixIcon: _search.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close, size: 16),
                    onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                : null,
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
      ),
      const Divider(height: 1),
      // Contact list
      Expanded(
        child: filtered.isEmpty
            ? const Center(child: Text('No contacts found',
                style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  // Pick first valid 10-digit phone
                  final phones = c.phones
                      .map((p) => _normalize(p.number))
                      .where((n) => n.length == 10)
                      .toList();
                  if (phones.isEmpty) return const SizedBox.shrink();
                  final primary = phones.first;
                  final isSelected = _selected.contains(primary);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? AppColors.primary
                          : Colors.grey.shade200,
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : Text(
                              (c.displayName?.isNotEmpty == true)
                                  ? c.displayName![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54),
                            ),
                    ),
                    title: Text(c.displayName ?? '(No Name)',
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text('+91 $primary',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    trailing: phones.length > 1
                        ? Text('+${phones.length - 1} more',
                            style: const TextStyle(fontSize: 11, color: Colors.grey))
                        : null,
                    onTap: () => setState(() {
                      if (isSelected) { _selected.remove(primary); } else { _selected.add(primary); }
                    }),
                  );
                },
              ),
      ),
      // Bottom Add button
      if (_selected.isNotEmpty)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _selected.toList()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text('Add ${_selected.length} Contact${_selected.length == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ),
    ]);
  }
}
