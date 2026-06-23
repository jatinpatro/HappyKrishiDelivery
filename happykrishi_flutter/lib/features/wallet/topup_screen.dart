import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../features/info/app_info_screen.dart';
import 'wallet_screen.dart';

final myTopupRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.myTopupRequests);
  return List<Map<String, dynamic>>.from(res.data['requests']);
});

class TopupScreen extends ConsumerStatefulWidget {
  const TopupScreen({super.key});
  @override
  ConsumerState<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends ConsumerState<TopupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;

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
    final requests = ref.watch(myTopupRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Money'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(myTopupRequestsProvider);
              ref.invalidate(walletProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code, size: 18), text: 'UPI / Scanner'),
            Tab(icon: Icon(Icons.money, size: 18), text: 'Cash via Salesman'),
          ],
        ),
      ),
      body: Column(children: [
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _UpiTabView(loading: _loading, onLoadingChange: (v) => setState(() => _loading = v)),
              _CashTabView(loading: _loading, onLoadingChange: (v) => setState(() => _loading = v)),
            ],
          ),
        ),

        // History
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                const Text('My Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 8),
                requests.when(
                  data: (list) {
                    final pending = list.where((r) => r['status'] == 'pending').length;
                    return pending > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                            child: Text('$pending pending',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        : const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ]),
            ),
            SizedBox(
              height: 180,
              child: requests.when(
                data: (list) => list.isEmpty
                    ? const Center(child: Text('No requests yet', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _RequestTile(request: list[i]),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── UPI Tab ───────────────────────────────────────────────────────────────────

class _UpiTabView extends ConsumerStatefulWidget {
  final bool loading;
  final ValueChanged<bool> onLoadingChange;
  const _UpiTabView({required this.loading, required this.onLoadingChange});
  @override
  ConsumerState<_UpiTabView> createState() => _UpiTabViewState();
}

class _UpiTabViewState extends ConsumerState<_UpiTabView> {
  final _amountCtrl = TextEditingController();
  final _utrCtrl = TextEditingController();
  bool _paidStep = false;
  final _amounts = [100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    // Eagerly trigger the app-info load so QR shows immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appInfoProvider.future).ignore();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _utrCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchUpi(String upiId, String upiName) async {
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty || double.tryParse(amount) == null) {
      _show('Enter an amount first'); return;
    }
    final uri = Uri.parse(
      'upi://pay?pa=${Uri.encodeComponent(upiId)}'
      '&pn=${Uri.encodeComponent(upiName)}'
      '&am=$amount'
      '&cu=INR'
      '&tn=${Uri.encodeComponent('HappyKrishi Wallet Topup')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _show('No UPI app found. Please pay using the QR or UPI ID above.');
    }
  }

  Future<void> _submit() async {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) { _show('Enter a valid amount'); return; }
    if (_utrCtrl.text.trim().isEmpty) { _show('Enter your UPI transaction reference (UTR)'); return; }

    widget.onLoadingChange(true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.topupRequest, data: {
        'amount': v,
        'payment_method': 'upi',
        'transaction_ref': _utrCtrl.text.trim(),
      });
      ref.invalidate(myTopupRequestsProvider);
      ref.invalidate(walletProvider);
      _amountCtrl.clear();
      _utrCtrl.clear();
      setState(() => _paidStep = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('UPI request submitted! Admin will verify and credit your wallet.'),
          backgroundColor: Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Error');
    } finally {
      widget.onLoadingChange(false);
    }
  }

  void _show(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final appInfo = ref.watch(appInfoProvider);

    return appInfo.when(
      data: (info) {
        final payment = info['payment'] as Map<String, dynamic>? ?? {};
        final upiId = payment['upi_id'] as String? ?? '';
        final upiName = payment['upi_name'] as String? ?? 'HappyKrishi';
        final qrUrl = payment['upi_qr_image_url'] as String? ?? '';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Amount picker
            _AmountPicker(ctrl: _amountCtrl, amounts: _amounts, onTap: (a) => setState(() => _amountCtrl.text = a.toString())),
            const SizedBox(height: 20),

            if (!_paidStep) ...[
              // Step 1: Show QR + UPI ID
              const Row(children: [
                CircleAvatar(radius: 12, backgroundColor: Color(0xFF2E7D32),
                    child: Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 8),
                Text('Scan QR or pay to UPI ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 14),

              // QR Code
              if (qrUrl.isNotEmpty)
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF2E7D32), width: 3),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(
                        qrUrl.startsWith('http') ? qrUrl : '${Endpoints.baseUrl}$qrUrl',
                        width: 200, height: 200, fit: BoxFit.cover,
                        loadingBuilder: (_, child, chunk) => chunk == null
                            ? child
                            : const SizedBox(width: 200, height: 200,
                                child: Center(child: CircularProgressIndicator())),
                        errorBuilder: (context3, url2, err2) => const SizedBox(width: 200, height: 200,
                            child: Center(child: Icon(Icons.qr_code, size: 80, color: Colors.grey))),
                      ),
                    ),
                  ),
                )
              else
                Center(
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.qr_code, size: 60, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('QR not set yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                  ),
                ),
              const SizedBox(height: 16),

              // UPI ID
              if (upiId.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: upiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UPI ID copied!'), duration: Duration(seconds: 1)));
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.account_balance_wallet, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(upiName, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        Text(upiId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32))),
                      ])),
                      const Icon(Icons.copy, color: Color(0xFF2E7D32), size: 18),
                    ]),
                  ),
                ),
              const SizedBox(height: 6),
              if (upiId.isNotEmpty)
                const Center(child: Text('Tap to copy UPI ID', style: TextStyle(fontSize: 11, color: Colors.grey))),
              const SizedBox(height: 16),

              // Open UPI app directly
              if (upiId.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open UPI App to Pay'),
                    onPressed: () => _launchUpi(upiId, upiName),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              if (upiId.isNotEmpty)
                const Center(
                  child: Text(
                    'Opens GPay, PhonePe, Paytm or any UPI app',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('I\'ve Paid — Enter UTR'),
                  onPressed: () {
                    final v = double.tryParse(_amountCtrl.text.trim());
                    if (v == null || v <= 0) { _show('Enter amount first'); return; }
                    setState(() => _paidStep = true);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ] else ...[
              // Step 2: Enter UTR
              Row(children: [
                GestureDetector(
                  onTap: () => setState(() => _paidStep = false),
                  child: const Row(children: [
                    Icon(Icons.arrow_back, size: 18, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('Back', style: TextStyle(color: Colors.grey)),
                  ]),
                ),
                const SizedBox(width: 12),
                const CircleAvatar(radius: 12, backgroundColor: Color(0xFF2E7D32),
                    child: Text('2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                const Text('Enter payment reference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 10),
                  Text('Amount: ₹${_amountCtrl.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                ]),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _utrCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'UTR / Transaction Reference *',
                  hintText: 'e.g. 123456789012',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long),
                  helperText: 'Find this in your UPI app → payment history → transaction ID',
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: widget.loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Submit Payment Request'),
                  onPressed: widget.loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── Cash Tab ──────────────────────────────────────────────────────────────────

class _CashTabView extends ConsumerStatefulWidget {
  final bool loading;
  final ValueChanged<bool> onLoadingChange;
  const _CashTabView({required this.loading, required this.onLoadingChange});
  @override
  ConsumerState<_CashTabView> createState() => _CashTabViewState();
}

class _CashTabViewState extends ConsumerState<_CashTabView> {
  final _amountCtrl = TextEditingController();
  String? _selectedSalesman;
  final _amounts = [100, 200, 500, 1000];

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) { _show('Enter a valid amount'); return; }
    if (_selectedSalesman == null) { _show('Select the salesman who collected your cash'); return; }

    widget.onLoadingChange(true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.topupRequest, data: {
        'amount': v,
        'payment_method': 'cash',
        'collected_by': _selectedSalesman,
      });
      ref.invalidate(myTopupRequestsProvider);
      ref.invalidate(walletProvider);
      final submittedVia = _selectedSalesman;
      _amountCtrl.clear();
      setState(() => _selectedSalesman = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cash request submitted via $submittedVia! Admin will credit shortly.'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Error');
    } finally {
      widget.onLoadingChange(false);
    }
  }

  void _show(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final appInfo = ref.watch(appInfoProvider);

    return appInfo.when(
      data: (info) {
        final payment = info['payment'] as Map<String, dynamic>? ?? {};
        final salesmen = (payment['salesmen'] as List?)?.cast<String>() ?? [];
        final cashAddress = payment['cash_payment_address'] as String? ?? '';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Amount picker
            _AmountPicker(ctrl: _amountCtrl, amounts: _amounts, onTap: (a) => setState(() => _amountCtrl.text = a.toString())),
            const SizedBox(height: 20),

            // Step 1: Select salesman
            const Row(children: [
              CircleAvatar(radius: 12, backgroundColor: Colors.orange,
                  child: Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
              SizedBox(width: 8),
              Text('Who collected your cash?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 4),
            const Text('Hand cash to a HappyKrishi salesman and select them below.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 14),

            Wrap(
              spacing: 10, runSpacing: 10,
              children: salesmen.map((name) {
                final selected = _selectedSalesman == name;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSalesman = name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF2E7D32) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                          width: selected ? 2 : 1),
                      boxShadow: selected
                          ? [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.25), blurRadius: 8)]
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: selected ? Colors.white24 : Colors.grey.shade100,
                        child: Text(name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : const Color(0xFF2E7D32),
                            )),
                      ),
                      const SizedBox(width: 10),
                      Text(name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: selected ? Colors.white : Colors.black87,
                          )),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                      ],
                    ]),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Step 2: Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  CircleAvatar(radius: 12, backgroundColor: Colors.orange,
                      child: Text('2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  Text('Submit request', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text('After submitting, admin verifies the cash collection and credits your wallet.',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
                if (cashAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on, size: 14, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(cashAddress, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))),
                  ]),
                ],
              ]),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: widget.loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_selectedSalesman != null
                    ? 'Submit Cash via $_selectedSalesman'
                    : 'Submit Cash Request'),
                onPressed: (widget.loading || _selectedSalesman == null) ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load payment info')),
    );
  }
}

// ── Amount picker ─────────────────────────────────────────────────────────────

class _AmountPicker extends StatelessWidget {
  final TextEditingController ctrl;
  final List<int> amounts;
  final ValueChanged<int> onTap;
  const _AmountPicker({required this.ctrl, required this.amounts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10, runSpacing: 8,
        children: amounts.map((a) => ChoiceChip(
          label: Text('₹$a', style: const TextStyle(fontWeight: FontWeight.w600)),
          selected: ctrl.text == a.toString(),
          selectedColor: const Color(0xFFE8F5E9),
          onSelected: (_) => onTap(a),
        )).toList(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Or enter custom amount',
          prefixText: '₹ ',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    ]);
  }
}

// ── Request history tile ──────────────────────────────────────────────────────

class _RequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  const _RequestTile({required this.request});

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String;
    final amount = (request['amount'] as num).toDouble();
    final method = request['payment_method'] as String? ?? 'cash';
    final ref_ = request['transaction_ref'] as String?;
    final collector = request['collected_by'] as String?;
    final collectorDisplay = (collector != null && collector.isNotEmpty && collector != 'null')
        ? collector
        : null;
    final createdAt = (request['created_at'] as String).substring(0, 10);
    final note = request['admin_note'] as String?;

    Color color;
    IconData icon;
    if (status == 'approved') { color = Colors.green; icon = Icons.check_circle; }
    else if (status == 'rejected') { color = Colors.red; icon = Icons.cancel; }
    else { color = Colors.orange; icon = Icons.hourglass_empty; }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 16),
        ),
        title: Row(children: [
          Text('₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: (method == 'upi' ? Colors.purple : Colors.blue).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(method.toUpperCase(),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                    color: method == 'upi' ? Colors.purple : Colors.blue)),
          ),
        ]),
        subtitle: Text(
          [
            createdAt,
            if (ref_ != null) 'UTR: $ref_',
            if (collectorDisplay != null) 'via $collectorDisplay',
            if (note != null && note.isNotEmpty) note,
          ].join('  •  '),
          style: const TextStyle(fontSize: 10),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(status.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ),
      ),
    );
  }
}
