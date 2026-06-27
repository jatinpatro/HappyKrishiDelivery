import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final _referralInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.referralMyCodes);
  return res.data as Map<String, dynamic>;
});

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});
  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _codeCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _generating = false;
  bool _applying = false;
  String? _applyMsg;
  bool _applySuccess = false;

  @override
  void dispose() { _codeCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _generateCode() async {
    _phoneCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite a Friend'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Enter your friend's 10-digit mobile number.\nA unique invite code will be generated for them.",
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Friend\'s Mobile Number *',
              prefixText: '+91 ',
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Generate Code'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 10-digit number')));
      return;
    }

    setState(() => _generating = true);
    try {
      final res = await ref.read(dioProvider).post(Endpoints.referralGenerate, data: {'phone': phone});
      ref.invalidate(_referralInfoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Invite code created for +91 $phone — share it with them!'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
      // Also offer to share via WhatsApp immediately
      final code = res.data['code'] as String?;
      if (code != null && mounted) {
        final info = ref.read(_referralInfoProvider).value;
        final credit = (info?['signup_credit'] as num?)?.toDouble() ?? 0;
        _share(code, credit, phone: phone);
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.response?.data['error'] ?? 'Could not generate code')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _showApplyDialog() async {
    _codeCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply Referral Code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter the referral code shared with you.',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 14),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Referral Code *',
              hintText: 'e.g. HKAB12CD',
              prefixIcon: Icon(Icons.card_giftcard_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _applyCode();
  }

  Future<void> _applyCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _applying = true; _applyMsg = null; });
    try {
      final res = await ref.read(dioProvider).post(Endpoints.referralApply, data: {'code': code});
      setState(() { _applySuccess = true; _applyMsg = res.data['message'] as String?; });
      ref.invalidate(_referralInfoProvider);
      _codeCtrl.clear();
    } on DioException catch (e) {
      setState(() { _applySuccess = false; _applyMsg = e.response?.data['error'] ?? 'Could not apply code'; });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _share(String code, double signupCredit, {String? phone}) async {
    final forText = phone != null ? 'for +91 $phone — ' : '';
    final msg = Uri.encodeComponent(
      'Join HappyKrishi ${forText}and get ₹${signupCredit.toStringAsFixed(0)} wallet credit!\nUse my referral code: $code\nSign up here: https://delivery.happykrishi.com',
    );
    final uri = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(_referralInfoProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Program'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_referralInfoProvider)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('referral', e); return Center(child: Text(friendlyError(e))); },
        data: (info) {
          final codes         = (info['codes'] as List).cast<Map<String, dynamic>>();
          final unusedCodes   = codes.where((c) => c['used_by_user_id'] == null).toList();
          final usedCodes     = codes.where((c) => c['used_by_user_id'] != null).toList();
          final signupCredit  = (info['signup_credit'] as num?)?.toDouble() ?? 0;
          final bonus         = (info['first_order_bonus'] as num?)?.toDouble() ?? 0;
          final enabled       = info['enabled'] as bool? ?? true;
          final pendingBonus  = info['pending_bonus_count'] as int? ?? 0;
          final canApply      = info['can_apply'] as bool? ?? false;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // How it works
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('How it works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B5E20))),
                  const SizedBox(height: 10),
                  _HowItWorksRow('1', 'Generate a unique code for each friend'),
                  _HowItWorksRow('2', 'Friend applies the code → gets ₹${signupCredit.toStringAsFixed(0)} wallet credit'),
                  _HowItWorksRow('3', 'Friend places their first order → you earn ₹${bonus.toStringAsFixed(0)}'),
                  const SizedBox(height: 4),
                  const Text('Each code works for one person only', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
              const SizedBox(height: 24),

              if (!enabled)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade300)),
                  child: const Row(children: [Icon(Icons.info_outline, color: Colors.orange), SizedBox(width: 8), Text('Referral program is currently paused', style: TextStyle(color: Colors.orange))]),
                )
              else ...[

                // Stats
                Row(children: [
                  _StatChip('${unusedCodes.length} unused', Icons.confirmation_number_outlined, Colors.indigo),
                  const SizedBox(width: 8),
                  _StatChip('${usedCodes.length} used', Icons.people_outline, Colors.blue),
                  if (pendingBonus > 0) ...[
                    const SizedBox(width: 8),
                    _StatChip('$pendingBonus bonus pending', Icons.hourglass_empty, Colors.orange),
                  ],
                ]),
                const SizedBox(height: 16),

                // Generate button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _generating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                    label: const Text('Generate New Invite Code'),
                    onPressed: _generating ? null : _generateCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Unused codes (shareable)
                if (unusedCodes.isNotEmpty) ...[
                  const Text('Ready to share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...unusedCodes.map((c) => _CodeCard(
                    code: c['code'] as String,
                    isUsed: false,
                    invitedPhone: c['invited_phone'] as String?,
                    usedByName: null,
                    bonusPaid: false,
                    createdAt: c['created_at'] as String,
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: c['code'] as String));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                    },
                    onShare: () => _share(c['code'] as String, signupCredit, phone: c['invited_phone'] as String?),
                  )),
                  const SizedBox(height: 16),
                ],

                // Used codes (history)
                if (usedCodes.isNotEmpty) ...[
                  const Text('Used codes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...usedCodes.map((c) => _CodeCard(
                    code: c['code'] as String,
                    isUsed: true,
                    invitedPhone: c['invited_phone'] as String?,
                    usedByName: c['used_by_name'] as String?,
                    bonusPaid: c['bonus_credited_at'] != null,
                    createdAt: c['created_at'] as String,
                    onCopy: null,
                    onShare: null,
                  )),
                  const SizedBox(height: 16),
                ],
              ],

              const Divider(),
              const SizedBox(height: 16),

              // Apply a code section — shown when customer hasn't applied any code yet
              if (canApply) ...[
                const Text('Apply a Referral Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Have an invite code? Enter it to get wallet credit.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _applying
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Enter Referral Code'),
                    onPressed: _applying ? null : _showApplyDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (_applyMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _applySuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _applySuccess ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Row(children: [
                      Icon(_applySuccess ? Icons.check_circle_outline : Icons.error_outline,
                          color: _applySuccess ? Colors.green : Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_applyMsg!, style: TextStyle(color: _applySuccess ? Colors.green.shade800 : Colors.red.shade800, fontSize: 13))),
                    ]),
                  ),
                ],
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Referral codes can only be applied before placing your first order.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )),
                  ]),
                ),
              ],
            ]),
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  final bool isUsed;
  final String? invitedPhone;
  final String? usedByName;
  final bool bonusPaid;
  final String createdAt;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  const _CodeCard({required this.code, required this.isUsed, required this.invitedPhone,
    required this.usedByName, required this.bonusPaid, required this.createdAt,
    required this.onCopy, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUsed ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isUsed ? Colors.grey.shade300 : const Color(0xFF2E7D32).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code, style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3,
            color: isUsed ? Colors.grey : const Color(0xFF2E7D32),
          )),
          const SizedBox(height: 2),
          if (isUsed)
            Text(
              usedByName != null
                  ? 'Used by $usedByName${bonusPaid ? ' · Bonus paid ✅' : ' · Bonus pending'}'
                  : 'Used',
              style: TextStyle(fontSize: 11, color: bonusPaid ? Colors.green : Colors.grey),
            )
          else
            Text(
              invitedPhone != null
                  ? 'For +91 $invitedPhone · ${createdAt.substring(0, 10)}'
                  : 'Ready to share · ${createdAt.substring(0, 10)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ])),
        if (!isUsed) ...[
          IconButton(
            icon: const Icon(Icons.copy_outlined, color: Color(0xFF2E7D32), size: 20),
            tooltip: 'Copy',
            onPressed: onCopy,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF2E7D32), size: 20),
            tooltip: 'Share via WhatsApp',
            onPressed: onShare,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ] else
          Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 18),
      ]),
    );
  }
}

class _HowItWorksRow extends StatelessWidget {
  final String step, text;
  const _HowItWorksRow(this.step, this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
        child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
    ]),
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatChip(this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}
