import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final usersProvider = FutureProvider.family.autoDispose<List<Map<String, dynamic>>, String>((ref, search) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminUsers, queryParameters: search.isNotEmpty ? {'search': search} : null);
  return List<Map<String, dynamic>>.from(res.data['users']);
});

class WalletCreditScreen extends ConsumerStatefulWidget {
  const WalletCreditScreen({super.key});
  @override
  ConsumerState<WalletCreditScreen> createState() => _WalletCreditScreenState();
}

class _WalletCreditScreenState extends ConsumerState<WalletCreditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline, size: 18), text: 'Credit'),
            Tab(icon: Icon(Icons.remove_circle_outline, size: 18), text: 'Deduct'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _CreditTab(),
          _DeductTab(),
        ],
      ),
    );
  }
}

// ── Credit Tab ────────────────────────────────────────────────────────────────

class _CreditTab extends ConsumerStatefulWidget {
  const _CreditTab();
  @override
  ConsumerState<_CreditTab> createState() => _CreditTabState();
}

class _CreditTabState extends ConsumerState<_CreditTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  Map<String, dynamic>? _selectedUser;
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _credit() async {
    if (_selectedUser == null || _amountCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.adminCreditWallet, data: {
        'user_id': _selectedUser!['id'],
        'amount': double.parse(_amountCtrl.text),
        'description': _descCtrl.text.isEmpty ? null : _descCtrl.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${_amountCtrl.text} credited to ${_selectedUser!['name']} ✅'),
          backgroundColor: AppColors.primary,
        ));
        ref.invalidate(usersProvider(_search));
        setState(() { _selectedUser = null; _amountCtrl.clear(); _descCtrl.clear(); });
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider(_search));
    return _WalletActionLayout(
      searchCtrl: _searchCtrl,
      search: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      users: users,
      selectedUser: _selectedUser,
      onUserSelected: (u) => setState(() => _selectedUser = u),
      onResetPassword: (u) => _showResetPasswordDialog(context, ref, u),
      onRefresh: () async => ref.invalidate(usersProvider(_search)),
      actionWidget: _selectedUser == null
          ? const SizedBox.shrink()
          : Column(children: [
              const Divider(),
              Row(children: [
                const Icon(Icons.add_circle, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Credit: ${_selectedUser!['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _amountCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Credit Wallet'),
                  onPressed: _loading ? null : _credit,
                )),
            ]),
    );
  }
}

// ── Deduct Tab ────────────────────────────────────────────────────────────────

class _DeductTab extends ConsumerStatefulWidget {
  const _DeductTab();
  @override
  ConsumerState<_DeductTab> createState() => _DeductTabState();
}

class _DeductTabState extends ConsumerState<_DeductTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  Map<String, dynamic>? _selectedUser;
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _orderRefCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _deduct() async {
    if (_selectedUser == null || _amountCtrl.text.isEmpty) return;
    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reason is required for wallet deduction')));
      return;
    }

    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    final balance = ((_selectedUser!['wallet_balance'] as num?)?.toDouble() ?? 0);
    // Admin can deduct below zero — no balance check

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirm Deduction'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Customer: ${_selectedUser!['name']}'),
          Text('Amount: ₹${amount.toStringAsFixed(2)}'),
          Text('Current Balance: ₹${balance.toStringAsFixed(2)}'),
          Text('New Balance: ₹${(balance - amount).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Reason: ${_reasonCtrl.text.trim()}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deduct'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.adminDebitWallet, data: {
        'user_id': _selectedUser!['id'],
        'amount': amount,
        'description': _reasonCtrl.text.trim(),
        if (_orderRefCtrl.text.trim().isNotEmpty) 'order_ref': _orderRefCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} deducted from ${_selectedUser!['name']}'),
          backgroundColor: Colors.red.shade700,
        ));
        ref.invalidate(usersProvider(_search));
        setState(() { _selectedUser = null; _amountCtrl.clear(); _reasonCtrl.clear(); _orderRefCtrl.clear(); });
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Deduction failed')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider(_search));
    return _WalletActionLayout(
      searchCtrl: _searchCtrl,
      search: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      users: users,
      selectedUser: _selectedUser,
      onUserSelected: (u) => setState(() => _selectedUser = u),
      onResetPassword: (u) => _showResetPasswordDialog(context, ref, u),
      onRefresh: () async => ref.invalidate(usersProvider(_search)),
      actionWidget: _selectedUser == null
          ? const SizedBox.shrink()
          : Column(children: [
              const Divider(),
              Row(children: [
                const Icon(Icons.remove_circle, color: Colors.red),
                const SizedBox(width: 8),
                Text('Deduct from: ${_selectedUser!['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(width: 8),
                Text('(Balance: ₹${((_selectedUser!['wallet_balance'] as num?)?.toStringAsFixed(0) ?? '0')})',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _amountCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount to Deduct *', prefixText: '₹ ',
                      border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: _reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Reason *',
                      hintText: 'e.g. Refund for damaged goods, Return cash',
                      border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: _orderRefCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Order Reference (optional)',
                      hintText: 'Order # if linked to an order',
                      border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline),
                  label: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Deduct from Wallet'),
                  onPressed: _loading ? null : _deduct,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                )),
            ]),
    );
  }
}

// ── Shared layout widget ──────────────────────────────────────────────────────

class _WalletActionLayout extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final AsyncValue<List<Map<String, dynamic>>> users;
  final Map<String, dynamic>? selectedUser;
  final ValueChanged<Map<String, dynamic>> onUserSelected;
  final ValueChanged<Map<String, dynamic>> onResetPassword;
  final Widget actionWidget;
  final Future<void> Function() onRefresh;

  const _WalletActionLayout({
    required this.searchCtrl,
    required this.search,
    required this.onSearchChanged,
    required this.users,
    required this.selectedUser,
    required this.onUserSelected,
    required this.onResetPassword,
    required this.actionWidget,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: searchCtrl,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
              labelText: 'Search customer', prefixIcon: Icon(Icons.search), isDense: true),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 2,
          child: users.when(
            data: (list) => list.isEmpty
                ? const Center(child: Text('No customers found', style: TextStyle(color: Colors.grey)))
                : RefreshIndicator(
                    onRefresh: onRefresh,
                    child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final u = list[i];
                          final isSelected = selectedUser?['id'] == u['id'];
                          return ListTile(
                            dense: true,
                            title: Text(u['name'] as String,
                                style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text('${u['phone']} • ₹${u['wallet_balance']}'),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            selectedTileColor: const Color(0xFFEAF2EA),
                            onTap: () => onUserSelected(u),
                            trailing: IconButton(
                              icon: const Icon(Icons.lock_reset, color: Colors.orange, size: 18),
                              tooltip: 'Reset Password',
                              onPressed: () => onResetPassword(u),
                            ),
                          );
                        })),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) { logError('admin-wallet', e); return Text(friendlyError(e)); },
          ),
        ),
        actionWidget,
      ]),
    );
  }
}

// ── Shared reset password dialog ──────────────────────────────────────────────

Future<void> _showResetPasswordDialog(
    BuildContext context, WidgetRef ref, Map<String, dynamic> user) async {
  final passCtrl = TextEditingController();
  final name = user['name'] as String;
  final id = user['id'] as int;

  await showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text('Reset Password: $name'),
      content: TextField(
        controller: passCtrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
            labelText: 'New Password (min 6 chars)', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (passCtrl.text.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')));
              return;
            }
            try {
              final dio = ref.read(dioProvider);
              await dio.post(Endpoints.adminResetCustomerPassword(id),
                  data: {'new_password': passCtrl.text});
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Password reset for $name ✅'),
                    backgroundColor: AppColors.primary));
              }
            } on DioException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.response?.data['error'] ?? 'Reset failed')));
              }
            }
          },
          child: const Text('Reset Password'),
        ),
      ],
    ),
  );
}
