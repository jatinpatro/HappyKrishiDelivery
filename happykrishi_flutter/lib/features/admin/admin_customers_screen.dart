import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import 'admin_tiers_screen.dart' show tierColor;
import '../../core/widgets/active_filter.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/utils/error_handler.dart';

final adminCustomersProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, key) async {
  // key = "search|wallet|sort|is_active|page"
  final parts  = key.split('|');
  final search = parts[0];
  final wallet = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final sort   = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final active = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
  final page   = parts.length > 4 && parts[4].isNotEmpty ? int.tryParse(parts[4]) ?? 1 : 1;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminUsers, queryParameters: {
    'limit': 50,
    'page': page,
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
  String _walletFilter = '';
  String _sortFilter   = 'name';
  String _activeFilter = '';
  FilterFormState _filter = FilterFormState.empty;
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _allCustomers = [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;

  String get _baseKey => '$_search|$_walletFilter|$_sortFilter|$_activeFilter';
  String get _providerKey => '$_baseKey|$_page';

  bool get _hasMore => _allCustomers.length < _total;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _allCustomers = []; _page = 1; _total = 0; _loading = true; });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final nextPage = reset ? 1 : _page + 1;
      final data = await ref.read(adminCustomersProvider('$_baseKey|$nextPage').future);
      final users = List<Map<String, dynamic>>.from(data['users'] as List);
      final total = (data['total'] as num?)?.toInt() ?? users.length;
      setState(() {
        if (reset) {
          _allCustomers = users;
          _page = 1;
        } else {
          _allCustomers = [..._allCustomers, ...users];
          _page = nextPage;
        }
        _total = total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      setState(() { _loading = false; _loadingMore = false; });
    }
  }

  static const _customerFilterConfig = FilterFormConfig(
    title: 'Filter Customers',
    showDateRange: false,
    showTextSearch: false,
    dynamicFields: [
      FilterDefinition(field: 'tier_name',      label: 'Tier',   type: FilterType.text,   serverSide: false),
      FilterDefinition(field: 'wallet_balance', label: 'Wallet', type: FilterType.number, serverSide: false),
    ],
  );

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _walletOptions = [
    (key: '',         label: 'All',       color: AppColors.primary),
    (key: 'negative', label: '🔴 Negative', color: Color(0xFFC62828)),
    (key: 'zero',     label: '⚪ Zero',    color: Color(0xFF757575)),
    (key: 'positive', label: '🟢 Positive', color: AppColors.primary),
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
    final localFilters = _filter.toLocalFilters(_customerFilterConfig);
    final filtered = localFilters.isEmpty
        ? _allCustomers
        : _allCustomers.where((c) => matchesAllFilters(c, localFilters)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Customers'),
          if (_total > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$_total',
                  style: const TextStyle(
                      color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(reset: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                setState(() => _search = v.trim());
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
              },
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
                          _load(reset: true);
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
                        onTap: () { setState(() => _walletFilter = o.key); _load(reset: true); },
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
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
                        onTap: () { setState(() => _sortFilter = o.key); _load(reset: true); },
                      ),
                    )).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: _activeFilter == '1'
                    ? 'Active'
                    : _activeFilter == '0'
                        ? 'Inactive'
                        : 'All',
                selected: _activeFilter.isNotEmpty,
                color: _activeFilter == '0' ? Colors.red : AppColors.primary,
                onTap: () {
                  setState(() {
                    if (_activeFilter == '') { _activeFilter = '1'; }
                    else if (_activeFilter == '1') { _activeFilter = '0'; }
                    else { _activeFilter = ''; }
                  });
                  _load(reset: true);
                },
              ),
            ]),
            FilterBar(
              config: _customerFilterConfig,
              state: _filter,
              onChanged: (f) { setState(() => _filter = f); _load(reset: true); },
              onLoad: () => _load(reset: true),
            ),
          ]),
        ),
        const Divider(height: 1),

        // ── Customer list ───────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
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
                            onPressed: () { setState(() { _walletFilter = ''; _activeFilter = ''; }); _load(reset: true); },
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length + 1,
                        itemBuilder: (_, i) {
                          if (i < filtered.length) {
                            return _CustomerCard(
                              customer: filtered[i],
                              onChanged: () => _load(reset: true),
                            );
                          }
                          if (_hasMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : ElevatedButton.icon(
                                        icon: const Icon(Icons.expand_more),
                                        label: Text('Load More (${_allCustomers.length} of $_total)'),
                                        onPressed: () => _load(),
                                      ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Customer'),
        backgroundColor: AppColors.primary,
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

  String _timeAgo(String raw) {
    try {
      final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${diff.inDays}d ago';
    } catch (_) { return ''; }
  }

  Future<void> _viewWalletHistory() async {
    final c = widget.customer;
    final id = c['id'] as int;
    final name = c['name'] as String;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WalletHistorySheet(customerId: id, customerName: name),
    );
  }

  Future<void> _editCustomer() async {
    final c = widget.customer;
    final nameCtrl  = TextEditingController(text: c['name']  as String? ?? '');
    final phoneCtrl = TextEditingController(text: c['phone'] as String? ?? '');
    final emailCtrl = TextEditingController(text: c['email'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Customer'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (10 digits)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(dioProvider).put(
        Endpoints.adminUpdateCustomer(c['id'] as int),
        data: {
          'name':  nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        },
      );
      widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer updated'), backgroundColor: AppColors.primary));
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data['error'] ?? 'Failed to update')));
    }
  }

  void _call() => launchUrl(Uri.parse('tel:+91${widget.customer['phone']}'));
  void _whatsapp() => launchUrl(Uri.parse('https://wa.me/91${widget.customer['phone']}'), mode: LaunchMode.externalApplication);
  void _email() {
    final email = widget.customer['email'] as String?;
    if (email != null && email.isNotEmpty) launchUrl(Uri.parse('mailto:$email'));
  }

  Future<void> _creditTopup() async {
    final id = widget.customer['id'] as int;
    final name = widget.customer['name'] as String;
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Credit Advance for $name'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Give wallet credit before payment. Customer pays later.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹ ', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Give Credit'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final amount = double.tryParse(amtCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    try {
      await ref.read(dioProvider).post(Endpoints.adminCreditAdvance, data: {
        'user_id': id,
        'amount': amount,
        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} credit advance given to $name'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e, st) {
      logError('admin-credit-topup', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _forceLogout() async {
    final id = widget.customer['id'] as int;
    final name = widget.customer['name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Logout?'),
        content: Text('This will immediately log out $name. They will need to log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Force Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(dioProvider).post(Endpoints.adminCustomerForceLogout(id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name logged out'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (_) {}
  }

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
                backgroundColor: isActive ? Colors.red : AppColors.primary),
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
    } catch (e, st) {
      logError('admin-customers', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _setTier() async {
    final id = widget.customer['id'] as int;
    int? selectedTierId = widget.customer['tier_id'] as int?;

    // Show dialog immediately with a loading state, then populate tiers
    List<Map<String, dynamic>> tiers = [];
    String? fetchError;
    bool loading = true;

    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) {
          // Trigger fetch on first build
          if (loading && tiers.isEmpty && fetchError == null) {
            ref.read(dioProvider).get(Endpoints.adminTiers).then((res) {
              final fetched = List<Map<String, dynamic>>.from(res.data['tiers'] as List);
              setDs(() { tiers = fetched; loading = false; });
            }).catchError((e) {
              setDs(() { fetchError = e.toString(); loading = false; });
            });
          }
          return AlertDialog(
            title: Text('Set Tier: ${widget.customer['name']}'),
            content: loading
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : fetchError != null
                    ? Text('Failed to load tiers: $fetchError', style: const TextStyle(color: Colors.red))
                    : SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ListTile(
                            dense: true,
                            leading: Radio<int?>(
                              value: null,
                              groupValue: selectedTierId,
                              onChanged: (v) => setDs(() => selectedTierId = v),
                            ),
                            title: const Text('No tier'),
                            onTap: () => setDs(() => selectedTierId = null),
                          ),
                          ...tiers.map((t) {
                            final tid = t['id'] as int;
                            return ListTile(
                              dense: true,
                              leading: Radio<int?>(
                                value: tid,
                                groupValue: selectedTierId,
                                onChanged: (v) => setDs(() => selectedTierId = v),
                              ),
                              title: Text(t['name'] as String),
                              subtitle: Text(
                                'Limit: ₹${(t['max_wallet_negative_limit'] as num).toStringAsFixed(0)}  •  ${(t['cashback_multiplier'] as num).toStringAsFixed(1)}× cashback',
                              ),
                              onTap: () => setDs(() => selectedTierId = tid),
                            );
                          }),
                        ]),
                      ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              if (!loading && fetchError == null)
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref.read(dioProvider).patch(
                        Endpoints.adminAssignCustomerTier(id),
                        data: {'tier_id': selectedTierId},
                      );
                      widget.onChanged();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tier updated'), backgroundColor: AppColors.primary));
                    } on DioException catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.response?.data['error'] ?? 'Failed to set tier')));
                    }
                  },
                  child: const Text('Save'),
                ),
            ],
          );
        },
      ),
    );
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
                          backgroundColor: AppColors.primary,
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
    final hasApp = (c['has_app'] as int? ?? 0) == 1;
    final lastLoginRaw = c['last_login_at'] as String?;
    final lastActiveRaw = c['last_active_at'] as String?;
    final lastLogin = lastLoginRaw != null
        ? '${lastLoginRaw.substring(0, 16)} (${_timeAgo(lastLoginRaw)})'
        : 'Never';
    final lastActive = lastActiveRaw != null
        ? '${lastActiveRaw.substring(0, 16)} (${_timeAgo(lastActiveRaw)})'
        : 'Never';

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
                isActive ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isActive
                      ? AppColors.primary
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
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasApp ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasApp ? Colors.green.shade300 : Colors.blue.shade300,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      hasApp ? Icons.android : Icons.web,
                      size: 11,
                      color: hasApp ? Colors.green.shade700 : Colors.blue.shade700,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      hasApp ? 'App' : 'Web',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: hasApp ? Colors.green.shade700 : Colors.blue.shade700,
                      ),
                    ),
                  ]),
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
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('₹${balance.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Joined $joined',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.login_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Last login: $lastLogin',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Last active: $lastActive',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              if (c['tier_name'] != null) ...[
                const SizedBox(height: 5),
                Builder(builder: (_) {
                  final tc = tierColor(c['tier_color'] as String?);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tc.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tc.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.workspace_premium_outlined, size: 11, color: tc),
                      const SizedBox(width: 3),
                      Text(c['tier_name'] as String,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tc)),
                    ]),
                  );
                }),
              ],
              const SizedBox(height: 6),
              // Contact action buttons
              Row(children: [
                _ContactBtn(Icons.phone, Colors.green, _call),
                const SizedBox(width: 6),
                _ContactBtn(Icons.chat, const Color(0xFF25D366), _whatsapp),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _ContactBtn(Icons.email_outlined, Colors.blue, _email),
                ],
              ]),
            ]),
          ),

          // Actions column
          Column(children: [
            // Wallet history
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFF1565C0), size: 20),
              tooltip: 'Wallet History',
              onPressed: _viewWalletHistory,
            ),
            // Edit name/email/phone
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: AppColors.primary, size: 20),
              tooltip: 'Edit Customer',
              onPressed: _editCustomer,
            ),
            // Set Tier
            IconButton(
              icon: const Icon(Icons.workspace_premium_outlined,
                  color: Color(0xFF6A1B9A), size: 20),
              tooltip: 'Set Tier',
              onPressed: _setTier,
            ),
            // Reset password
            IconButton(
              icon: const Icon(Icons.lock_reset,
                  color: Colors.orange, size: 20),
              tooltip: 'Reset Password',
              onPressed: _resetPassword,
            ),
            // Credit advance
            IconButton(
              icon: const Icon(Icons.add_card_outlined,
                  color: AppColors.primary, size: 20),
              tooltip: 'Credit Advance',
              onPressed: _creditTopup,
            ),
            // Force logout
            IconButton(
              icon: Icon(Icons.logout, color: Colors.red.shade400, size: 20),
              tooltip: 'Force Logout',
              onPressed: _forceLogout,
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
                      color: isActive ? Colors.red : AppColors.primary,
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
          backgroundColor: AppColors.primary,
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

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ContactBtn(this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      );
}

// ── Customer wallet history sheet ─────────────────────────────────────────────

class _WalletHistorySheet extends ConsumerStatefulWidget {
  final int customerId;
  final String customerName;
  const _WalletHistorySheet({required this.customerId, required this.customerName});

  @override
  ConsumerState<_WalletHistorySheet> createState() => _WalletHistorySheetState();
}

class _WalletHistorySheetState extends ConsumerState<_WalletHistorySheet> {
  List<Map<String, dynamic>> _txns = [];
  Map<String, dynamic>? _customer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get(
        Endpoints.adminCustomerWalletHistory(widget.customerId),
      );
      setState(() {
        _customer = res.data['customer'] as Map<String, dynamic>?;
        _txns = List<Map<String, dynamic>>.from(res.data['transactions'] as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _txnColor(Map<String, dynamic> t) {
    final type = t['type'] as String;
    final ref = t['reference_type'] as String? ?? '';
    if (type == 'debit') return Colors.red.shade600;
    if (type == 'discount' && ref == 'reward') return const Color(0xFF6A1B9A);
    if (type == 'adjustment') return Colors.orange;
    return AppColors.primary;
  }

  IconData _txnIcon(Map<String, dynamic> t) {
    final type = t['type'] as String;
    final ref = t['reference_type'] as String? ?? '';
    if (type == 'debit' && ref == 'order') return Icons.shopping_cart_outlined;
    if (type == 'credit' && ref == 'topup') return Icons.payments_outlined;
    if (type == 'refund') return Icons.undo;
    if (type == 'discount') return Icons.card_giftcard;
    if (type == 'adjustment') return Icons.scale_outlined;
    if (ref == 'admin') return Icons.admin_panel_settings_outlined;
    return Icons.account_balance_wallet_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final balance = (_customer?['wallet_balance'] as num?)?.toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.customerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (balance != null)
                Text('Balance: ₹${balance.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 13,
                        color: balance < 0 ? Colors.red : AppColors.primary,
                        fontWeight: FontWeight.w600)),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const Divider(height: 1),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
        else if (_error != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red)))
        else if (_txns.isEmpty)
          const Padding(padding: EdgeInsets.all(32),
              child: Text('No transactions yet', style: TextStyle(color: Colors.grey)))
        else
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              itemCount: _txns.length,
              itemBuilder: (_, i) {
                final t = _txns[i];
                final amount = (t['amount'] as num).toDouble();
                final color = _txnColor(t);
                final isCredit = ['credit', 'refund', 'discount'].contains(t['type']);
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(_txnIcon(t), size: 16, color: color),
                  ),
                  title: Text(
                    t['description'] as String? ?? t['type'] as String,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    (t['created_at'] as String).substring(0, 16).replaceFirst('T', ' '),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      '${isCredit ? '+' : '-'}₹${amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                    ),
                    Text(
                      '₹${(t['balance_after'] as num).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}
