import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final promoCodesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.promoCodes);
  return List<Map<String, dynamic>>.from(res.data['codes']);
});

// Providers for rule pickers
final _promoProductsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.adminProducts);
  return List<Map<String, dynamic>>.from((res.data['products'] as List).map((p) => {'id': p['id'], 'name': p['name']}));
});

final _promoCategoriesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.categories);
  return List<Map<String, dynamic>>.from((res.data['categories'] as List).map((c) => {'id': c['id'], 'name': c['name']}));
});

final _promoTiersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/api/admin/tiers');
  return List<Map<String, dynamic>>.from((res.data['tiers'] as List).map((t) => {'id': t['id'], 'name': t['name']}));
});

class AdminPromoCodesScreen extends ConsumerStatefulWidget {
  const AdminPromoCodesScreen({super.key});
  @override
  ConsumerState<AdminPromoCodesScreen> createState() => _AdminPromoCodesScreenState();
}

class _AdminPromoCodesScreenState extends ConsumerState<AdminPromoCodesScreen> {
  // Filter state
  String _statusFilter = 'all';   // all | active | inactive | expired
  String _searchQuery  = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    final now = DateTime.now();
    return list.where((c) {
      // Status filter
      final isActive   = c['is_active'] == 1;
      final validUntil = c['valid_until'] as String?;
      final expired    = validUntil != null && DateTime.tryParse(validUntil)?.isBefore(now) == true;
      switch (_statusFilter) {
        case 'active':   if (!isActive || expired) return false;
        case 'inactive': if (isActive) return false;
        case 'expired':  if (!expired) return false;
      }
      // Text search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final code  = (c['code'] as String? ?? '').toLowerCase();
        final label = (c['label'] as String? ?? '').toLowerCase();
        if (!code.contains(q) && !label.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final codes = ref.watch(promoCodesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promo Codes'),
        actions: [
          IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/admin/dashboard')),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(promoCodesProvider),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Promo Code',
            onPressed: () => _showForm(context),
          ),
        ],
      ),
      body: codes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('admin-promo', e); return Center(child: Text(friendlyError(e))); },
        data: (list) {
          final filtered = _applyFilters(list);
          return Column(children: [
            // ── Search + filter bar ───────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(children: [
                // Search
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search code or label…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.close, size: 16),
                            onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
                const SizedBox(height: 8),
                // Status filter chips
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final f in [
                        ('all',      'All',      Colors.grey),
                        ('active',   'Active',   AppColors.primary),
                        ('inactive', 'Inactive', Colors.orange),
                        ('expired',  'Expired',  Colors.red),
                      ])
                        GestureDetector(
                          onTap: () => setState(() => _statusFilter = f.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: _statusFilter == f.$1 ? f.$3 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _statusFilter == f.$1 ? f.$3 : Colors.grey.shade300),
                            ),
                            child: Text(f.$2,
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: _statusFilter == f.$1 ? Colors.white : Colors.black87)),
                          ),
                        ),
                    ]),
                  ),
                  Text('${filtered.length}/${list.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ]),
            ),
            const Divider(height: 1),

            // ── List ─────────────────────────────────────────────────────
            if (filtered.isEmpty)
              Expanded(child: Center(child: Text(
                list.isEmpty ? 'No promo codes yet' : 'No codes match the filter',
                style: const TextStyle(color: Colors.grey),
              )))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(promoCodesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _PromoCodeCard(
                        code: filtered[i],
                        onChanged: () => ref.invalidate(promoCodesProvider)),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  void _showForm(BuildContext context, {Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PromoCodeForm(
        existing: existing,
        onSaved: () => ref.invalidate(promoCodesProvider),
      ),
    );
  }
}

class _PromoCodeCard extends ConsumerWidget {
  final Map<String, dynamic> code;
  final VoidCallback onChanged;
  const _PromoCodeCard({required this.code, required this.onChanged});

  void _shareCode(BuildContext context, Map<String, dynamic> c) {
    final codeStr    = c['code'] as String;
    final label      = c['label'] as String?;
    final discType   = c['discount_type'] as String? ?? 'flat';
    final discValue  = (c['discount_value'] as num).toDouble();
    final maxDisc    = (c['max_discount_amount'] as num?)?.toDouble();
    final minOrder   = (c['min_order_amount'] as num?)?.toDouble() ?? 0;
    final validUntil = c['valid_until'] as String?;

    // Human-friendly discount description
    final discDesc = discType == 'percent'
        ? '${discValue.toStringAsFixed(0)}% off${maxDisc != null ? ' (up to ₹${maxDisc.toStringAsFixed(0)})' : ''}'
        : '₹${discValue.toStringAsFixed(0)} off';
    final minDesc   = minOrder > 0 ? ' on orders above ₹${minOrder.toStringAsFixed(0)}' : '';
    final expiryLine = validUntil != null ? '⏳ Offer valid until ${validUntil.substring(0, 10)}' : '';

    // Build WhatsApp message
    final whatsappMsg =
        '🌿 *HappyKrishi Delivery – Special Offer!*\n\n'
        '${label != null && label.isNotEmpty ? '🎁 *$label*\n\n' : ''}'
        'Get *$discDesc*$minDesc on your order of fresh farm produce.\n\n'
        '✅ Use code: *$codeStr*\n'
        '   at checkout to avail this offer.\n\n'
        '${expiryLine.isNotEmpty ? '$expiryLine\n\n' : ''}'
        '🛒 Order now: https://delivery.happykrishi.com\n'
        '📲 Or download our app for the best experience!';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Share Promo Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (label != null && label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          // Code chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2EA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Text(codeStr,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                    letterSpacing: 5, color: AppColors.primary)),
          ),
          const SizedBox(height: 8),
          Text('$discDesc$minDesc',
              style: const TextStyle(color: Colors.black87, fontSize: 14,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
          if (expiryLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(expiryLine,
                  style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          // Message preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              whatsappMsg.replaceAll('*', ''),
              style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
              maxLines: 6, overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy Code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codeStr));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied'),
                          duration: Duration(seconds: 1)));
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.message_outlined, size: 16),
                label: const Text('WhatsApp'),
                onPressed: () {
                  final msg = Uri.encodeComponent(whatsappMsg);
                  launchUrl(Uri.parse('https://wa.me/?text=$msg'),
                      mode: LaunchMode.externalApplication);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive    = code['is_active'] == 1;
    final isPercent   = code['discount_type'] == 'percent';
    final value       = (code['discount_value'] as num).toDouble();
    final useCount    = (code['use_count'] as num? ?? 0).toInt();
    final maxUses     = code['max_uses'] as int?;
    final totalDisc   = (code['total_discounted'] as num? ?? 0).toDouble();
    final validUntil  = code['valid_until'] as String?;
    final label       = code['label'] as String?;

    final bool expired = validUntil != null &&
        DateTime.tryParse(validUntil)?.isBefore(DateTime.now()) == true;
    final statusColor = !isActive || expired ? Colors.grey : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(code['code'] as String,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                      letterSpacing: 2, color: statusColor)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPercent ? Colors.purple.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isPercent ? '${value.toStringAsFixed(0)}% off' : '₹${value.toStringAsFixed(0)} off',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold,
                  color: isPercent ? Colors.purple : Colors.blue,
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (!isActive || expired) ? Colors.grey.shade100 : const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                expired ? 'Expired' : isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: (!isActive || expired) ? Colors.grey : AppColors.primary,
                ),
              ),
            ),
          ]),
          if (label != null && label.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Pill(Icons.people_outline, '$useCount used${maxUses != null ? ' / $maxUses max' : ''}'),
            _Pill(Icons.savings_outlined, '₹${totalDisc.toStringAsFixed(0)} total saved'),
            if (code['min_order_amount'] != null && (code['min_order_amount'] as num) > 0)
              _Pill(Icons.shopping_cart_outlined, 'Min ₹${(code['min_order_amount'] as num).toStringAsFixed(0)}'),
            if (code['max_discount_amount'] != null)
              _Pill(Icons.percent_outlined, 'Max ₹${(code['max_discount_amount'] as num).toStringAsFixed(0)} off'),
            if (validUntil != null)
              _Pill(Icons.schedule_outlined, 'Until ${validUntil.substring(0, 10)}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Switch(
              value: isActive,
              activeTrackColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) async {
                await ref.read(dioProvider).put(Endpoints.promoCode(code['id'] as int),
                    data: {'is_active': !isActive});
                onChanged();
              },
            ),
            Text(isActive ? 'Active' : 'Inactive',
                style: TextStyle(fontSize: 12,
                    color: isActive ? AppColors.primary : Colors.grey)),
            const Spacer(),
            // Share
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 18),
              tooltip: 'Share',
              onPressed: () => _shareCode(context, code),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Duplicate
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Duplicate',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _PromoCodeForm(
                  existing: {
                    ...code,
                    'id': null,
                    'code': '',         // blank so form auto-generates
                    'use_count': 0,
                    'label': code['label'] != null ? 'Copy of ${code['label']}' : null,
                  },
                  onSaved: onChanged,
                ),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Edit
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _PromoCodeForm(existing: code, onSaved: onChanged),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            // Delete
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Code?'),
                    content: Text('Delete promo code "${code['code']}"?'),
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
                if (ok != true) return;
                await ref.read(dioProvider).delete(Endpoints.promoCode(code['id'] as int));
                onChanged();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.grey.shade600),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
    ]),
  );
}

// ── Create / Edit form ────────────────────────────────────────────────────────

class _PromoCodeForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _PromoCodeForm({this.existing, required this.onSaved});
  @override
  ConsumerState<_PromoCodeForm> createState() => _PromoCodeFormState();
}

class _PromoCodeFormState extends ConsumerState<_PromoCodeForm> {
  late final _codeCtrl     = TextEditingController(text: widget.existing?['code'] as String? ?? '');
  late final _labelCtrl    = TextEditingController(text: widget.existing?['label'] as String? ?? '');
  late final _valueCtrl    = TextEditingController(text: widget.existing != null ? (widget.existing!['discount_value'] as num).toStringAsFixed(0) : '');
  late final _minCtrl         = TextEditingController(text: widget.existing != null ? (widget.existing!['min_order_amount'] as num).toStringAsFixed(0) : '');
  late final _minProductCtrl  = TextEditingController(text: widget.existing?['min_product_amount'] != null ? (widget.existing!['min_product_amount'] as num).toStringAsFixed(0) : '');
  late final _maxDiscCtrl  = TextEditingController(text: widget.existing?['max_discount_amount'] != null ? (widget.existing!['max_discount_amount'] as num).toStringAsFixed(0) : '');
  late final _maxUsesCtrl  = TextEditingController(text: widget.existing?['max_uses']?.toString() ?? '');
  late final _perUserCtrl  = TextEditingController(text: widget.existing?['per_user_limit']?.toString() ?? '1');
  late final _fromCtrl     = TextEditingController(text: widget.existing?['valid_from']?.toString().substring(0, 10) ?? '');
  late final _untilCtrl    = TextEditingController(text: widget.existing?['valid_until']?.toString().substring(0, 10) ?? '');
  late final _phonesCtrl   = TextEditingController(
    text: widget.existing?['allowed_phones'] != null
        ? (widget.existing!['allowed_phones'] as String).replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').replaceAll(',', '\n')
        : '',
  );
  late String _type            = widget.existing?['discount_type'] as String? ?? 'flat';
  late bool   _firstOrderOnly  = widget.existing?['first_order_only'] == 1;
  late Set<int> _selectedProductIds   = _parseIds(widget.existing?['allowed_product_ids']);
  late Set<int> _selectedCategoryIds  = _parseIds(widget.existing?['allowed_category_ids']);
  late Set<int> _selectedTierIds      = _parseIds(widget.existing?['allowed_tier_ids']);
  bool _saving = false;

  static Set<int> _parseIds(dynamic json) {
    if (json == null || json.toString() == 'null' || json.toString() == '[]') return {};
    try {
      final list = json is String
          ? (json.replaceAll('[','').replaceAll(']','').split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList())
          : (json as List).map<int>((e) => e as int).toList();
      return list.toSet();
    } catch (_) { return {}; }
  }

  // True only when editing an existing saved code (has a real id)
  bool get _isEditing => widget.existing != null && widget.existing!['id'] != null;

  @override
  void dispose() {
    for (final c in [_codeCtrl,_labelCtrl,_valueCtrl,_minCtrl,_minProductCtrl,_maxDiscCtrl,_maxUsesCtrl,_perUserCtrl,_fromCtrl,_untilCtrl,_phonesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      ctrl.text = '${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
    }
  }

  Future<void> _submit() async {
    if (_codeCtrl.text.trim().isEmpty || _valueCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code and discount value are required')));
      return;
    }
    setState(() => _saving = true);
    // Parse phones — one per line, 10 digits each
    final phones = _phonesCtrl.text.split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'\D'), ''))
        .where((l) => l.length == 10)
        .toList();
    try {
      final body = {
        if (!_isEditing) 'code': _codeCtrl.text.trim().toUpperCase(),
        if (_isEditing && _codeCtrl.text.trim().isNotEmpty) 'code': _codeCtrl.text.trim().toUpperCase(),
        'label': _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        'discount_type': _type,
        'discount_value': double.tryParse(_valueCtrl.text.trim()) ?? 0,
        'min_order_amount': double.tryParse(_minCtrl.text.trim()) ?? 0,
        'min_product_amount': _minProductCtrl.text.trim().isEmpty ? null : double.tryParse(_minProductCtrl.text.trim()),
        'max_discount_amount': _maxDiscCtrl.text.trim().isEmpty ? null : double.tryParse(_maxDiscCtrl.text.trim()),
        'max_uses': _maxUsesCtrl.text.trim().isEmpty ? null : int.tryParse(_maxUsesCtrl.text.trim()),
        'per_user_limit': int.tryParse(_perUserCtrl.text.trim()) ?? 1,
        'valid_from': _fromCtrl.text.trim().isEmpty ? null : _fromCtrl.text.trim(),
        'valid_until': _untilCtrl.text.trim().isEmpty ? null : _untilCtrl.text.trim(),
        'first_order_only': _firstOrderOnly ? 1 : 0,
        'allowed_phones': phones.isEmpty ? null : phones,
        'allowed_product_ids': _selectedProductIds.isEmpty ? null : _selectedProductIds.toList(),
        'allowed_category_ids': _selectedCategoryIds.isEmpty ? null : _selectedCategoryIds.toList(),
        'allowed_tier_ids': _selectedTierIds.isEmpty ? null : _selectedTierIds.toList(),
      };
      if (_isEditing) {
        await ref.read(dioProvider).put(Endpoints.promoCode(widget.existing!['id'] as int), data: body);
      } else {
        await ref.read(dioProvider).post(Endpoints.promoCodes, data: body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Promo code updated ✅' : 'Promo code created ✅'),
        backgroundColor: AppColors.primary,
      ));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Widget _field(TextEditingController c, String label, {TextInputType? kb, String? suffix, String? hint, VoidCallback? onTap, bool readOnly = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: kb,
          readOnly: readOnly,
          maxLines: maxLines,
          onTap: onTap,
          decoration: InputDecoration(
            labelText: label, hintText: hint, suffixText: suffix,
            border: const OutlineInputBorder(), isDense: true,
          ),
        ),
      );

  Widget _multiPicker<T>(String title, AsyncValue<List<Map<String,dynamic>>> async, Set<T> selected, T Function(Map<String,dynamic>) idOf) {
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (selected.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('${selected.length} selected',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => selected.clear()),
                  child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.red)),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: list.map((item) {
                final id = idOf(item);
                final isSel = selected.contains(id);
                return GestureDetector(
                  onTap: () => setState(() { isSel ? selected.remove(id) : selected.add(id); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.primary : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSel ? AppColors.primary : Colors.grey.shade300),
                    ),
                    child: Text(item['name'] as String,
                        style: TextStyle(fontSize: 12, color: isSel ? Colors.white : Colors.black87,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final products   = ref.watch(_promoProductsProvider);
    final categories = ref.watch(_promoCategoriesProvider);
    final tiers      = ref.watch(_promoTiersProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(_isEditing ? 'Edit Promo Code' : 'New Promo Code',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),

          // ── Basic ──────────────────────────────────────────────────────────
          if (!_isEditing)
            _field(_codeCtrl, 'Code *', hint: 'e.g. HARVEST25')
          else
            _field(_codeCtrl, 'Code', hint: 'Change code (will invalidate old code for customers)'),
          _field(_labelCtrl, 'Label (shown to customer)', hint: 'e.g. Harvest Festival Discount'),

          Row(children: [
            const Text('Discount type:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            ChoiceChip(label: const Text('Flat ₹'), selected: _type == 'flat',
                onSelected: (_) => setState(() => _type = 'flat'),
                selectedColor: const Color(0xFFEAF2EA)),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Percent %'), selected: _type == 'percent',
                onSelected: (_) => setState(() => _type = 'percent'),
                selectedColor: Colors.purple.shade50),
          ]),
          const SizedBox(height: 12),

          _field(_valueCtrl, 'Discount Value *', kb: TextInputType.number,
              suffix: _type == 'percent' ? '%' : '₹'),
          if (_type == 'percent')
            _field(_maxDiscCtrl, 'Max discount cap (₹)', kb: TextInputType.number, hint: 'e.g. 100'),
          _field(_minCtrl, 'Min cart total (₹)', kb: TextInputType.number, hint: '0 = no minimum'),
          _field(_minProductCtrl, 'Min spend on selected products/categories (₹)',
              kb: TextInputType.number, hint: 'e.g. 200 — blank = no minimum on those items'),

          Row(children: [
            Expanded(child: _field(_maxUsesCtrl, 'Max total uses', kb: TextInputType.number, hint: 'Unlimited')),
            const SizedBox(width: 8),
            Expanded(child: _field(_perUserCtrl, 'Per customer limit', kb: TextInputType.number)),
          ]),
          Row(children: [
            Expanded(child: _field(_fromCtrl, 'Valid from', hint: 'YYYY-MM-DD',
                readOnly: true, onTap: () => _pickDate(_fromCtrl))),
            const SizedBox(width: 8),
            Expanded(child: _field(_untilCtrl, 'Valid until', hint: 'YYYY-MM-DD',
                readOnly: true, onTap: () => _pickDate(_untilCtrl))),
          ]),

          // ── Rules ──────────────────────────────────────────────────────────
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Restrictions (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),

          // First order only
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _firstOrderOnly ? const Color(0xFFEAF2EA) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _firstOrderOnly ? AppColors.primary : Colors.grey.shade300),
            ),
            child: Row(children: [
              const Icon(Icons.fiber_new_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              const Expanded(child: Text('First order only', style: TextStyle(fontSize: 13))),
              Switch(
                value: _firstOrderOnly,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _firstOrderOnly = v),
              ),
            ]),
          ),

          // Specific phones
          _field(_phonesCtrl, 'Specific customers (phones)',
              hint: '9876543210\n9876543211\n(one per line, blank = all)',
              maxLines: 3, kb: TextInputType.multiline),

          // Products
          _multiPicker('Specific Products', products, _selectedProductIds, (p) => p['id'] as int),

          // Categories
          _multiPicker('Specific Categories', categories, _selectedCategoryIds, (c) => c['id'] as int),

          // Tiers
          _multiPicker('Customer Tiers', tiers, _selectedTierIds, (t) => t['id'] as int),

          // ── Submit ─────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isEditing ? 'Save Changes' : 'Create Code'),
            ),
          ),
        ]),
      ),
    );
  }
}
