import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/services/pdf_service.dart';
import 'topup_screen.dart';
import '../../core/widgets/active_filter.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/utils/error_handler.dart';

final _customerCreditAdvancesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/api/wallet/credit-advances');
  return List<Map<String, dynamic>>.from((res.data as Map)['advances'] as List? ?? []);
});

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.wallet);
  return res.data as Map<String, dynamic>;
});

final walletTxnsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final parts    = key.split('|');
  final type     = parts[0].isNotEmpty ? parts[0] : null;
  final dateFrom = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final dateTo   = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final page     = parts.length > 3 && parts[3].isNotEmpty ? int.tryParse(parts[3]) ?? 1 : 1;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.walletTransactions, queryParameters: {
    'limit': 50,
    'page': page,
    if (type     != null) 'type':      type,
    if (dateFrom != null) 'date_from': dateFrom,
    if (dateTo   != null) 'date_to':   dateTo,
  });
  return res.data as Map<String, dynamic>;
});

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  String? _filter;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  FilterFormState _chipFilter = FilterFormState.empty;

  List<WalletTransaction> _allTxns = [];
  int _txnPage = 1;
  int _txnTotal = 0;
  bool _txnLoadingMore = false;

  static const _walletFilterConfig = FilterFormConfig(
    title: 'Filter Transactions',
    showDateRange: false,
    showTextSearch: false,
    dynamicFields: [
      FilterDefinition(field: 'amount',      label: 'Amount',      type: FilterType.number, serverSide: false),
      FilterDefinition(field: 'description', label: 'Description', type: FilterType.text,   serverSide: false),
    ],
  );

  static const _filters = [
    (key: 'topup',    label: 'Top-up',       icon: Icons.payments,              color: Color(0xFFE65100)),
    (key: 'order',    label: 'Orders',        icon: Icons.shopping_cart,         color: Color(0xFFC62828)),
    (key: 'refund',   label: 'Refunds',       icon: Icons.undo,                  color: Color(0xFF00695C)),
    (key: 'cashback', label: 'Cashback',      icon: Icons.card_giftcard,         color: Color(0xFF6A1B9A)),
    (key: 'admin',    label: 'Admin',         icon: Icons.admin_panel_settings,  color: Color(0xFF1565C0)),
    (key: 'adjust',   label: 'Adjustments',   icon: Icons.scale,                 color: Color(0xFFE65100)),
    (key: 'fee',      label: 'Fees',          icon: Icons.lock_outline,          color: Color(0xFF424242)),
  ];

  String get _filterBase =>
      '${_filter ?? ''}|${_dateFrom != null ? _fmt(_dateFrom!) : ''}|${_dateTo != null ? _fmt(_dateTo!) : ''}';

  String get _providerKey => '$_filterBase|$_txnPage';

  bool get _hasDateFilter => _dateFrom != null || _dateTo != null;
  bool get _hasMoreTxns => _allTxns.length < _txnTotal;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _resetTxns() {
    setState(() { _allTxns = []; _txnPage = 1; _txnTotal = 0; });
  }

  Future<void> _loadMoreTxns() async {
    if (_txnLoadingMore || !_hasMoreTxns) return;
    setState(() => _txnLoadingMore = true);
    try {
      final nextPage = _txnPage + 1;
      final data = await ref.read(walletTxnsProvider('$_filterBase|$nextPage').future);
      final newTxns = (data['transactions'] as List).cast<Map<String, dynamic>>().map(WalletTransaction.fromJson).toList();
      setState(() {
        _allTxns = [..._allTxns, ...newTxns];
        _txnPage = nextPage;
        _txnTotal = (data['total'] as num?)?.toInt() ?? _txnTotal;
        _txnLoadingMore = false;
      });
    } catch (_) {
      setState(() => _txnLoadingMore = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      helpText: 'Filter by date',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
      _resetTxns();
    }
  }

  void _refresh() {
    ref.invalidate(walletProvider);
    ref.invalidate(walletTxnsProvider);
    ref.invalidate(myTopupRequestsProvider);
    ref.invalidate(_customerCreditAdvancesProvider);
    ref.read(authStateProvider.notifier).refreshUser();
    _resetTxns();
  }

  Widget _buildFilterBar() {
    final activeFilter = _filters.where((f) => f.key == _filter).firstOrNull;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        // Type filter pill — taps to open bottom sheet
        Expanded(
          child: GestureDetector(
            onTap: () => _showTypeFilterSheet(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _filter != null
                    ? (activeFilter?.color ?? const Color(0xFF2E7D32)).withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _filter != null
                      ? (activeFilter?.color ?? const Color(0xFF2E7D32))
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(children: [
                Icon(Icons.filter_list_rounded, size: 16,
                    color: _filter != null
                        ? (activeFilter?.color ?? const Color(0xFF2E7D32))
                        : Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    activeFilter?.label ?? 'All types',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _filter != null ? FontWeight.w600 : FontWeight.normal,
                      color: _filter != null
                          ? (activeFilter?.color ?? const Color(0xFF2E7D32))
                          : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 16,
                    color: _filter != null
                        ? (activeFilter?.color ?? const Color(0xFF2E7D32))
                        : Colors.grey.shade400),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Date filter pill
        Expanded(
          child: GestureDetector(
            onTap: _pickDateRange,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _hasDateFilter
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasDateFilter ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                ),
              ),
              child: Row(children: [
                Icon(Icons.calendar_month_outlined, size: 16,
                    color: _hasDateFilter ? const Color(0xFF2E7D32) : Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hasDateFilter
                        ? '${_fmt(_dateFrom!).substring(5)} → ${_fmt(_dateTo!).substring(5)}'
                        : 'Any date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _hasDateFilter ? FontWeight.w600 : FontWeight.normal,
                      color: _hasDateFilter ? const Color(0xFF2E7D32) : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_hasDateFilter)
                  GestureDetector(
                    onTap: () { setState(() { _dateFrom = null; _dateTo = null; }); _resetTxns(); },
                    child: Icon(Icons.close, size: 14, color: Colors.grey.shade500),
                  )
                else
                  Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey.shade400),
              ]),
            ),
          ),
        ),

        // Clear all — only when any filter active
        if (_filter != null || _hasDateFilter) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () { setState(() { _filter = null; _dateFrom = null; _dateTo = null; }); _resetTxns(); },
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Icon(Icons.close, size: 14, color: Colors.red.shade600),
            ),
          ),
        ],
      ]),
    );
  }

  void _showTypeFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Filter by Type',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: _filter == null
                          ? const Color(0xFF2E7D32) : Colors.grey.shade100,
                      child: Icon(Icons.all_inclusive, size: 16,
                          color: _filter == null ? Colors.white : Colors.grey),
                    ),
                    title: const Text('All Types'),
                    trailing: _filter == null
                        ? const Icon(Icons.check, color: Color(0xFF2E7D32)) : null,
                    onTap: () {
                      setState(() => _filter = null);
                      _resetTxns();
                      Navigator.pop(context);
                    },
                  ),
                  ..._filters.map((f) => ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: _filter == f.key
                          ? f.color : f.color.withValues(alpha: 0.12),
                      child: Icon(f.icon, size: 15,
                          color: _filter == f.key ? Colors.white : f.color),
                    ),
                    title: Text(f.label),
                    trailing: _filter == f.key
                        ? Icon(Icons.check, color: f.color) : null,
                    onTap: () {
                      setState(() => _filter = _filter == f.key ? null : f.key);
                      _resetTxns();
                      Navigator.pop(context);
                    },
                  )),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet   = ref.watch(walletProvider);
    final txns     = ref.watch(walletTxnsProvider(_providerKey));
    final requests = ref.watch(myTopupRequestsProvider);
    final user     = ref.watch(authStateProvider).user;

    final balance = wallet.value != null
        ? (wallet.value!['balance'] as num).toDouble()
        : (user?.walletBalance ?? 0);
    final isNeg   = balance < 0;
    final pending = requests.value?.where((r) => r['status'] == 'pending').length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('My Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download Statement',
            onPressed: () {
              if (user == null) return;
              final txnData = ref.read(walletTxnsProvider('||')).value;
              final txnList = txnData != null
                  ? (txnData['transactions'] as List)
                      .map((e) => WalletTransaction.fromJson(e)).toList()
                  : <WalletTransaction>[];
              final topups = ref.read(myTopupRequestsProvider).value ?? [];
              _showDownloadMenu(context, user: user, balance: balance,
                  txns: txnList, topups: topups);
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: CustomScrollView(
          slivers: [
            // Balance hero
            SliverToBoxAdapter(
              child: _BalanceHero(
                balance: balance,
                loading: wallet.isLoading,
                isNegative: isNeg,
                user: user,
                onAddMoney: () => _showAddMoneySheet(context),
              ),
            ),

            // Quick stats
            SliverToBoxAdapter(
              child: txns.when(
                data: (d) => _QuickStats(
                    summary: d['summary'] as Map<String, dynamic>? ?? {}),
                loading: () => const SizedBox.shrink(),
                error: (_, st) => const SizedBox.shrink(),
              ),
            ),

            // Pending topup banner (tap to add money)
            if (pending > 0)
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: () => _showAddMoneySheet(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_top, color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$pending top-up request${pending > 1 ? 's' : ''} pending approval',
                          style: TextStyle(color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.orange.shade400, size: 13),
                    ]),
                  ),
                ),
              ),

            // Inline topup request history
            if ((requests.value?.isNotEmpty ?? false))
              SliverToBoxAdapter(
                child: _TopupRequestsSection(
                  requests: requests.value!,
                  onAddMore: () => _showAddMoneySheet(context),
                ),
              ),

            // Credit advances received
            SliverToBoxAdapter(child: _CreditAdvancesSection()),

            // Filter bar
            SliverToBoxAdapter(child: _buildFilterBar()),

            // Chip filters via FilterBar
            SliverToBoxAdapter(
              child: FilterBar(
                config: _walletFilterConfig,
                state: _chipFilter,
                onChanged: (f) => setState(() => _chipFilter = f),
                onLoad: () {
                  ref.invalidate(walletTxnsProvider(_providerKey));
                  ref.invalidate(walletProvider);
                },
              ),
            ),

            // Transaction list
            txns.when(
              loading: () => _allTxns.isEmpty
                  ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (e, _) { logError('wallet', e); return SliverFillRemaining(child: Center(child: Text(friendlyError(e)))); },
              data: (data) {
                // Populate _allTxns from page 1 on first load
                final rawList = (data['transactions'] as List).cast<Map<String, dynamic>>();
                final total = (data['total'] as num?)?.toInt() ?? rawList.length;
                if (_txnPage == 1 && _allTxns.isEmpty && rawList.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {
                      _allTxns = rawList.map(WalletTransaction.fromJson).toList();
                      _txnTotal = total;
                    });
                  });
                }
                final filtered = _chipFilter.dynamicFilters.isEmpty
                    ? _allTxns
                    : _allTxns.where((t) => matchesAllFilters(
                        {'amount': t.amount, 'description': t.description},
                        _chipFilter.toLocalFilters(_walletFilterConfig))).toList();

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('No transactions', style: TextStyle(color: Colors.grey)),
                        if (_filter != null || _hasDateFilter) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () { setState(() { _filter = null; _dateFrom = null; _dateTo = null; }); _resetTxns(); },
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ]),
                    ),
                  );
                }

                final grouped = _groupByDate(filtered);
                final groups  = grouped.keys.toList();

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      if (i < groups.length) {
                        final date  = groups[i];
                        final items = grouped[date]!;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Text(date,
                                  style: const TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey, letterSpacing: 0.5)),
                            ),
                            ...items.map((t) => _TxnCard(txn: t)),
                          ]),
                        );
                      }
                      // Load More button
                      if (_hasMoreTxns) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _txnLoadingMore
                                ? const CircularProgressIndicator()
                                : ElevatedButton.icon(
                                    icon: const Icon(Icons.expand_more),
                                    label: Text('Load More (${_allTxns.length} of $_txnTotal)'),
                                    onPressed: _loadMoreTxns,
                                  ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    childCount: groups.length + 1,
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMoneySheet(context),
        backgroundColor: isNeg ? Colors.red.shade700 : const Color(0xFF2E7D32),
        icon: Icon(isNeg ? Icons.warning_amber_rounded : Icons.add),
        label: Text(isNeg ? 'Top Up Now' : 'Add Money'),
      ),
    );
  }

  Map<String, List<WalletTransaction>> _groupByDate(List<WalletTransaction> list) {
    final map = <String, List<WalletTransaction>>{};
    for (final t in list) {
      final date = t.createdAt.substring(0, 10);
      final now  = DateTime.now();
      final d    = DateTime.tryParse(date);
      String label;
      if (d != null) {
        final diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(d.year, d.month, d.day)).inDays;
        label = diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : date;
      } else {
        label = date;
      }
      (map[label] ??= []).add(t);
    }
    return map;
  }

  void _showAddMoneySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Expanded(child: TopupScreen()),
          ]),
        ),
      ),
    ).then((_) => _refresh());
  }

  void _showDownloadMenu(BuildContext context, {
    required AppUser user,
    required double balance,
    required List<WalletTransaction> txns,
    required List<Map<String, dynamic>> topups,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Download / Share', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Color(0xFF2E7D32)),
            title: const Text('Wallet Statement'),
            onTap: () {
              Navigator.pop(context);
              PdfService.shareWalletStatement(
                  context: context, user: user, balance: balance, transactions: txns);
            },
          ),
          ListTile(
            leading: const Icon(Icons.pending_actions, color: Colors.orange),
            title: const Text('Top-up Request History'),
            onTap: () {
              Navigator.pop(context);
              PdfService.shareTopupRequests(context: context, user: user, requests: topups);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Balance hero card ─────────────────────────────────────────────────────────

class _BalanceHero extends StatelessWidget {
  final double balance;
  final bool loading;
  final bool isNegative;
  final AppUser? user;
  final VoidCallback onAddMoney;
  const _BalanceHero({required this.balance, required this.loading,
      required this.isNegative, this.user, required this.onAddMoney});

  @override
  Widget build(BuildContext context) {
    final colors = isNegative
        ? [const Color(0xFFB71C1C), const Color(0xFFE53935)]
        : [const Color(0xFF1B5E20), const Color(0xFF388E3C), const Color(0xFF66BB6A)];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors,
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isNegative ? Colors.red : Colors.green).withValues(alpha: 0.3),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isNegative ? Icons.warning_amber_rounded : Icons.account_balance_wallet,
              color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isNegative ? 'Balance Overdue' : 'Wallet Balance',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13, fontWeight: FontWeight.w500)),
            if (isNegative)
              Text('Top up to place new orders',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 20),
        loading
            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '₹${balance.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 42,
                      fontWeight: FontWeight.bold, letterSpacing: -1),
                ),
              ),
        const SizedBox(height: 20),
        // Tier badge
        if (user?.tierName != null) ...[
          Builder(builder: (_) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.workspace_premium, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(user!.tierName!,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            );
          }),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(child: _HeroBtn(
            icon: Icons.add_circle_outline,
            label: isNegative ? 'Top Up Now' : 'Add Money',
            onTap: onAddMoney,
            primary: true,
          )),
          const SizedBox(width: 10),
          Expanded(child: _HeroBtn(
            icon: Icons.history_outlined,
            label: 'Topup History',
            onTap: onAddMoney,
            primary: false,
          )),
        ]),
      ]),
    );
  }
}

class _HeroBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _HeroBtn({required this.icon, required this.label,
      required this.onTap, required this.primary});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: primary ? Colors.white : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: primary ? null : Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16,
            color: primary ? const Color(0xFF2E7D32) : Colors.white),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: primary ? const Color(0xFF2E7D32) : Colors.white)),
      ]),
    ),
  );
}

// ── Quick stats strip ─────────────────────────────────────────────────────────

class _QuickStats extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _QuickStats({required this.summary});

  double _v(String k) => (summary[k] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.shopping_cart_outlined, label: 'Spent',     value: _v('total_spent_orders'), color: const Color(0xFFC62828)),
      (icon: Icons.payments,               label: 'Topped up', value: _v('total_topups'),        color: const Color(0xFFE65100)),
      (icon: Icons.undo_outlined,          label: 'Refunds',   value: _v('total_refunds'),       color: const Color(0xFF00695C)),
      (icon: Icons.card_giftcard_outlined, label: 'Cashback',  value: _v('total_cashback'),      color: const Color(0xFF6A1B9A)),
    ].where((e) => e.value > 0).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: items.map((it) => Expanded(child: Column(children: [
          Icon(it.icon, color: it.color, size: 20),
          const SizedBox(height: 4),
          Text('₹${it.value.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: it.color)),
          Text(it.label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]))).toList(),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

// ── Transaction card ──────────────────────────────────────────────────────────

class _TxnCard extends StatelessWidget {
  final WalletTransaction txn;
  const _TxnCard({required this.txn});

  ({Color color, IconData icon, String label}) get _style {
    final type = txn.type;
    final ref  = txn.referenceType ?? '';
    if (type == 'discount' && ref == 'reward') { return (color: const Color(0xFF6A1B9A), icon: Icons.card_giftcard, label: 'Cashback Reward'); }
    if (type == 'credit' && ref == 'admin') { return (color: const Color(0xFF1565C0), icon: Icons.admin_panel_settings, label: 'Admin Credit'); }
    if (type == 'debit' && ref == 'admin') { return (color: const Color(0xFFC62828), icon: Icons.remove_circle, label: 'Admin Deduction'); }
    if (type == 'credit' && ref == 'topup') {
      final desc = txn.description ?? '';
      if (desc.startsWith('Credit advance by')) {
        return (color: Colors.indigo, icon: Icons.add_card_outlined, label: desc);
      }
      return (color: const Color(0xFFE65100), icon: Icons.payments, label: 'Cash Topup');
    }
    if (type == 'debit' && ref == 'order') { return (color: const Color(0xFFC62828), icon: Icons.shopping_cart, label: 'Order Payment'); }
    if (type == 'refund' && ref == 'order') { return (color: const Color(0xFF00695C), icon: Icons.undo, label: 'Order Refund'); }
    if (type == 'adjustment') { return (color: const Color(0xFFE65100), icon: Icons.scale, label: 'Weight Adjustment'); }
    if (type == 'debit' && ref == 'system') { return (color: const Color(0xFF424242), icon: Icons.lock_outline, label: 'Service Fee'); }
    if (['credit', 'discount'].contains(type)) { return (color: const Color(0xFF2E7D32), icon: Icons.add_circle_outline, label: 'Credit'); }
    return (color: const Color(0xFFC62828), icon: Icons.remove_circle_outline, label: 'Debit');
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final isCredit = ['credit', 'refund', 'discount'].contains(txn.type) ||
        (txn.type == 'adjustment' && txn.amount < 0);
    final amountStr = '${isCredit ? '+' : '-'}₹${txn.amount.abs().toStringAsFixed(2)}';
    final time = txn.createdAt.length >= 16 ? txn.createdAt.substring(11, 16) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: s.color, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: s.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(s.icon, color: s.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            txn.description ?? s.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(s.label,
                  style: TextStyle(fontSize: 10, color: s.color, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ])),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(amountStr,
              style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15,
                color: isCredit ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
              )),
          const SizedBox(height: 2),
          Text('Bal ₹${txn.balanceAfter.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ]),
    );
  }
}

// ── Inline topup requests section ─────────────────────────────────────────────

// ── Credit Advances Section ───────────────────────────────────────────────────

class _CreditAdvancesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_customerCreditAdvancesProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (advances) {
        if (advances.isEmpty) return const SizedBox.shrink();
        final unpaid = advances.where((a) => (a['payment_received'] as int? ?? 0) == 0).toList();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                const Icon(Icons.add_card_outlined, size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                const Text('Credit Advances',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                const Spacer(),
                if (unpaid.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text('${unpaid.length} pending payment',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700)),
                  ),
              ]),
            ),
            const Divider(height: 1),
            ...advances.take(5).map((a) {
              final isPaid   = (a['payment_received'] as int? ?? 0) == 1;
              final amount   = (a['amount'] as num).toDouble();
              final byRole   = a['credited_by_role'] as String? ?? '';
              final byName   = a['credited_by_name'] as String? ?? byRole;
              final note     = a['admin_note'] as String?;
              final date     = (a['created_at'] as String).substring(0, 10);
              final paidDate = a['payment_received_at'] != null
                  ? (a['payment_received_at'] as String).substring(0, 10)
                  : null;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(isPaid ? Icons.check_circle_outline : Icons.hourglass_empty,
                      size: 16, color: isPaid ? Colors.green : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('₹${amount.toStringAsFixed(0)} credit from $byName ($byRole)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    if (note != null && note.isNotEmpty)
                      Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(isPaid
                        ? 'Given: $date  •  Paid back: ${paidDate ?? ''}'
                        : 'Given: $date  •  Payment pending',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isPaid ? 'Paid' : 'Pending',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green : Colors.orange)),
                  ),
                ]),
              );
            }),
            if (advances.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Text('+${advances.length - 5} more',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }
}

class _TopupRequestsSection extends StatefulWidget {
  final List<Map<String, dynamic>> requests;
  final VoidCallback onAddMore;
  const _TopupRequestsSection({required this.requests, required this.onAddMore});

  @override
  State<_TopupRequestsSection> createState() => _TopupRequestsSectionState();
}

class _TopupRequestsSectionState extends State<_TopupRequestsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.requests]
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    final visible = _expanded ? sorted : sorted.take(3).toList();
    final pending = sorted.where((r) => r['status'] == 'pending').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Topup Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          if (pending > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300)),
              child: Text('$pending pending', style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 14),
            label: const Text('New', style: TextStyle(fontSize: 12)),
            onPressed: widget.onAddMore,
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ]),
        const SizedBox(height: 6),
        ...visible.map((r) {
          final status = r['status'] as String;
          final amount = (r['amount'] as num).toDouble();
          final method = r['payment_method'] as String? ?? 'cash';
          final statusColor = status == 'approved' ? const Color(0xFF2E7D32)
              : status == 'rejected' ? Colors.red : Colors.orange;
          final statusIcon  = status == 'approved' ? Icons.check_circle
              : status == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Icon(method == 'upi' ? Icons.credit_card_outlined : Icons.payments_outlined,
                  color: Colors.grey, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(method == 'upi' ? 'UPI' : method == 'credit_advance' ? 'Credit Advance' : 'Cash',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text((r['created_at'] as String).substring(0, 10),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (r['admin_note'] != null && (r['admin_note'] as String).isNotEmpty)
                  Text(r['admin_note'] as String,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
              const SizedBox(width: 8),
              Text('₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 11, color: statusColor),
                  const SizedBox(width: 3),
                  Text(status.toUpperCase(), style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
          );
        }),
        if (sorted.length > 3)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: Text(_expanded ? 'Show less' : 'Show all ${sorted.length}',
                style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}
