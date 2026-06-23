import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

final adminCustomersProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, key) async {
  // key = "search|wallet|sort|is_active"
  final parts  = key.split('|');
  final search = parts[0];
  final wallet = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final sort   = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final active = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminUsers, queryParameters: {
    'limit': 50,
    'search': search,
    if (wallet != null) 'wallet': wallet,
    if (sort != null)   'sort':   sort,
    if (active != null) 'is_active': active,
  });
  return res.data as Map<String, dynamic>;
});

class AdminCustomersScreen extends ConsumerStatefulWidget {
  const AdminCustomersScreen({super.key});
  @override
  ConsumerState<AdminCustomersScreen> createState() =>
      _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends ConsumerState<AdminCustomersScreen> {
  final _searchCtrl = TextEditingController();
  String _search       = '';
  String _walletFilter = '';   // negative | zero | positive | low | ''
  String _sortFilter   = 'name'; // name | recent | wallet_asc | wallet_desc
  String _activeFilter = '';   // '' | 0 | 1

  String get _providerKey => '$_search|$_walletFilter|$_sortFilter|$_activeFilter';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _walletOptions = [
    (key: '',         label: 'All',       color: Color(0xFF2E7D32)),
    (key: 'negative', label: '🔴 Negative', color: Color(0xFFC62828)),
    (key: 'zero',     label: '⚪ Zero',    color: Color(0xFF757575)),
    (key: 'positive', label: '🟢 Positive', color: Color(0xFF2E7D32)),
    (key: 'low',      label: '🟡 Low',     color: Color(0xFFE65100)),
  ];

  static const _sortOptions = [
    (key: 'name',         label: 'Name A-Z'),
    (key: 'recent',       label: 'Newest first'),
    (key: 'wallet_desc',  label: 'Wallet ↓'),
    (key: 'wallet_asc',   label: 'Wallet ↑'),
  ];

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(adminCustomersProvider(_providerKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search name or phone…',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        })
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
        ),
      ),
      body: Column(children: [
        // ── Filter bar ──────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Wallet balance chips
            Row(children: [
              const Text('Wallet:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _walletOptions.map((o) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterChip(
                        label: o.label,
                        selected: _walletFilter == o.key,
                        color: o.color,
                        onTap: () => setState(() => _walletFilter = o.key),
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Sort + Active toggle row
            Row(children: [
              const Text('Sort:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _sortOptions.map((o) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterChip(
                        label: o.label,
                        selected: _sortFilter == o.key,
                        color: const Color(0xFF1565C0),
                        onTap: () => setState(() => _sortFilter = o.key),
                      ),
                    )).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Active toggle
              _FilterChip(
                label: _activeFilter == '1'
                    ? 'Active'
                    : _activeFilter == '0'
                        ? 'Inactive'
                        : 'All',
                selected: _activeFilter.isNotEmpty,
                color: _activeFilter == '0' ? Colors.red : const Color(0xFF2E7D32),
                onTap: () => setState(() {
                  if (_activeFilter == '') { _activeFilter = '1'; }
                  else if (_activeFilter == '1') { _activeFilter = '0'; }
                  else { _activeFilter = ''; }
                }),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1),

        // ── Customer list ───────────────────────────────────────────────────
        Expanded(
          child: customers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (data) {
              final list = (data['users'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              if (list.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_search_outlined,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      _search.isNotEmpty
                          ? 'No customers found for "$_search"'
                          : 'No customers yet',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    if (_walletFilter.isNotEmpty || _activeFilter.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() {
                          _walletFilter = '';
                          _activeFilter = '';
                        }),
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(adminCustomersProvider(_providerKey)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _CustomerCard(
                    customer: list[i],
                    onChanged: () =>
                        ref.invalidate(adminCustomersProvider(_providerKey)),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Customer'),
        backgroundColor: const Color(0xFF2E7D32),
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => _AddCustomerSheet(
            onCreated: () => ref.invalidate(adminCustomersProvider(_providerKey)),
          ),
        ),
      ),
    );
  }
}

// ── Reusable filter chip ──────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onChanged;
  const _CustomerCard({required this.customer, required this.onChanged});
  @override
  ConsumerState<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends ConsumerState<_CustomerCard> {
  bool _toggling = false;

  Future<void> _toggleActive() async {
    final id = widget.customer['id'] as int;
    final name = widget.customer['name'] as String;
    final isActive = (widget.customer['is_active'] as int) == 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? 'Deactivate $name?' : 'Activate $name?'),
        content: Text(isActive
            ? 'This will prevent $name from placing orders or logging in.'
            : 'This will restore $name\'s access to the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.red : const Color(0xFF2E7D32)),
            child: Text(isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _toggling = true);
    try {
      await ref.read(dioProvider).put(Endpoints.adminToggleCustomer(id));
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _resetPassword() async {
    final id = widget.customer['id'] as int;
    final name = widget.customer['name'] as String;
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: Text('Reset Password: $name'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Set a new password for $name (+91 ${widget.customer['phone']})',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New Password (min 6 chars)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  onPressed: () => setDs(() => obscure = !obscure),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (passCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content:
                                Text('Password must be at least 6 characters')));
                        return;
                      }
                      setDs(() => saving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref.read(dioProvider).post(
                              Endpoints.adminResetCustomerPassword(id),
                              data: {'new_password': passCtrl.text},
                            );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        messenger.showSnackBar(SnackBar(
                          content: Text('Password reset for $name ✅'),
                          backgroundColor: const Color(0xFF2E7D32),
                        ));
                      } on DioException catch (e) {
                        messenger.showSnackBar(SnackBar(
                            content: Text(
                                e.response?.data['error'] ?? 'Reset failed')));
                      } finally {
                        if (dialogCtx.mounted) setDs(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final name = c['name'] as String;
    final phone = c['phone'] as String;
    final email = c['email'] as String?;
    final balance = (c['wallet_balance'] as num).toDouble();
    final isActive = (c['is_active'] as int) == 1;
    final joined = (c['created_at'] as String).substring(0, 10);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: isActive ? Colors.grey.shade200 : Colors.red.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor:
                isActive ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isActive
                      ? const Color(0xFF2E7D32)
                      : Colors.grey),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (!isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200)),
                    child: Text('Inactive',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text('+91 $phone',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              if (email != null)
                Text(email,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 13, color: Color(0xFF2E7D32)),
                const SizedBox(width: 4),
                Text('₹${balance.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32))),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Joined $joined',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ]),
          ),

          // Actions column
          Column(children: [
            // Reset password
            IconButton(
              icon: const Icon(Icons.lock_reset,
                  color: Colors.orange, size: 20),
              tooltip: 'Reset Password',
              onPressed: _resetPassword,
            ),
            // Toggle active
            _toggling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(
                      isActive
                          ? Icons.person_off_outlined
                          : Icons.person_outlined,
                      color: isActive ? Colors.red : const Color(0xFF2E7D32),
                      size: 20,
                    ),
                    tooltip: isActive ? 'Deactivate' : 'Activate',
                    onPressed: _toggleActive,
                  ),
          ]),
        ]),
      ),
    );
  }
}

// ── Add Customer sheet ────────────────────────────────────────────────────────

class _AddCustomerSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _AddCustomerSheet({required this.onCreated});
  @override
  ConsumerState<_AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends ConsumerState<_AddCustomerSheet> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  bool _obscure = true;
  bool _saving  = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _show('Name is required'); return;
    }
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (phone.isEmpty && email.isEmpty) {
      _show('Enter a phone number or email'); return;
    }
    if (phone.isNotEmpty && phone.length != 10) {
      _show('Phone must be 10 digits'); return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(
        Endpoints.adminUsers,
        data: {
          'name': _nameCtrl.text.trim(),
          if (phone.isNotEmpty) 'phone': phone,
          if (email.isNotEmpty) 'email': email,
          if (_passCtrl.text.isNotEmpty) 'password': _passCtrl.text,
        },
      );
      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Customer added ✅'),
          backgroundColor: Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to add customer');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Add Customer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 14),

          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixText: '+91 ',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              counterText: '',
              helperText: 'Required if no email',
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Required if no phone',
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password (optional, min 6)',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'If no password is set the customer must log in via OTP.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create Customer'),
            ),
          ),
        ]),
      ),
    );
  }
}
