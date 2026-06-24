import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final tiersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminTiers);
  return List<Map<String, dynamic>>.from(res.data['tiers'] as List);
});

/// Parse a hex color string like "#F9A825" or "F9A825" into a Color.
/// Falls back to grey if the string is null or invalid.
Color tierColor(String? hex, {Color fallback = const Color(0xFF607D8B)}) {
  if (hex == null || hex.isEmpty) return fallback;
  final h = hex.replaceFirst('#', '');
  final value = int.tryParse(h, radix: 16);
  if (value == null) return fallback;
  return Color(h.length == 6 ? 0xFF000000 | value : value);
}

/// Convenience: get color from a tier map returned by the API.
Color tierColorFromMap(Map<String, dynamic> t) =>
    tierColor(t['color'] as String?);

class AdminTiersScreen extends ConsumerWidget {
  const AdminTiersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tiersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Tiers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tiersProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Tier'),
        onPressed: () => _showForm(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('admin-tiers', e); return Center(child: Text(friendlyError(e))); },
        data: (tiers) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(tiersProvider),
          child: tiers.isEmpty
              ? const Center(child: Text('No tiers yet', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                  itemCount: tiers.length,
                  itemBuilder: (_, i) => _TierCard(tier: tiers[i], onChanged: () => ref.invalidate(tiersProvider)),
                ),
        ),
      ),
    );
  }

  void _showForm(BuildContext ctx, WidgetRef ref, Map<String, dynamic>? tier) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _TierFormSheet(tier: tier, onSaved: () => ref.invalidate(tiersProvider)),
    );
  }
}

class _TierCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> tier;
  final VoidCallback onChanged;
  const _TierCard({required this.tier, required this.onChanged});

  @override
  ConsumerState<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends ConsumerState<_TierCard> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tier;
    final name = t['name'] as String;
    final limit = (t['max_wallet_negative_limit'] as num).toDouble();
    final mult = (t['cashback_multiplier'] as num).toDouble();
    final active = (t['is_active'] as int) == 1;
    final color = tierColorFromMap(t);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 4, height: 56,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.workspace_premium_outlined, size: 16, color: color),
              const SizedBox(width: 6),
              Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              const SizedBox(width: 8),
              if (!active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Negative limit: ₹${limit.toStringAsFixed(0)}  •  Cashback: ${mult.toStringAsFixed(1)}×',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ])),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _TierFormSheet(tier: t, onSaved: widget.onChanged),
            ),
          ),
          _deleting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _confirmDelete,
                ),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tier'),
        content: Text('Delete "${widget.tier['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(dioProvider).delete(Endpoints.adminTier(widget.tier['id'] as int));
      widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.response?.data['error'] ?? 'Failed to delete tier'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}

class _TierFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? tier;
  final VoidCallback onSaved;
  const _TierFormSheet({this.tier, required this.onSaved});

  @override
  ConsumerState<_TierFormSheet> createState() => _TierFormSheetState();
}

class _TierFormSheetState extends ConsumerState<_TierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _limit;
  late TextEditingController _mult;
  late TextEditingController _sort;
  late TextEditingController _color;
  late TextEditingController _minBalance;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.tier;
    _name       = TextEditingController(text: t?['name'] as String? ?? '');
    _minBalance = TextEditingController(text: (t?['min_wallet_balance'] as num?)?.toStringAsFixed(0) ?? '0');
    _limit      = TextEditingController(text: (t?['max_wallet_negative_limit'] as num?)?.toStringAsFixed(0) ?? '0');
    _mult       = TextEditingController(text: (t?['cashback_multiplier'] as num?)?.toStringAsFixed(1) ?? '1.0');
    _sort       = TextEditingController(text: (t?['sort_order'] as int?)?.toString() ?? '0');
    _color      = TextEditingController(text: t?['color'] as String? ?? '#607D8B');
    _active = (t?['is_active'] as int? ?? 1) == 1;
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.tier != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(editing ? 'Edit Tier' : 'New Tier',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Tier Name', border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minBalance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Min Wallet Balance to Qualify (₹)',
                helperText: 'Customer must maintain ≥ this balance to hold this tier',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0) return 'Enter a number ≥ 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Max Wallet Negative Limit (₹)',
                helperText: '0 = no credit allowed; 500 = wallet can go to -₹500',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0) return 'Enter a number ≥ 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mult,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cashback Multiplier',
                helperText: '1.0 = normal; 1.5 = 1.5× cashback',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0) return 'Enter a number ≥ 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort Order',
                helperText: 'Lower number = shown first',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Color field with live preview
            StatefulBuilder(
              builder: (_, setColor) => TextFormField(
                controller: _color,
                onChanged: (_) => setColor(() {}),
                decoration: InputDecoration(
                  labelText: 'Badge Color (hex)',
                  helperText: 'e.g. #F9A825 for gold, #6A1B9A for purple',
                  border: const OutlineInputBorder(),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: tierColor(_color.text),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final h = v.trim().replaceFirst('#', '');
                  if (int.tryParse(h, radix: 16) == null) return 'Invalid hex color';
                  return null;
                },
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(editing ? 'Save Changes' : 'Create Tier'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final data = {
        'name': _name.text.trim(),
        'color': _color.text.trim().startsWith('#') ? _color.text.trim() : '#${_color.text.trim()}',
        'min_wallet_balance': double.parse(_minBalance.text),
        'max_wallet_negative_limit': double.parse(_limit.text),
        'cashback_multiplier': double.parse(_mult.text),
        'sort_order': int.tryParse(_sort.text) ?? 0,
        if (widget.tier != null) 'is_active': _active ? 1 : 0,
      };
      if (widget.tier == null) {
        await dio.post(Endpoints.adminTiers, data: data);
      } else {
        await dio.put(Endpoints.adminTier(widget.tier!['id'] as int), data: data);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.response?.data['error'] ?? 'Failed to save'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
