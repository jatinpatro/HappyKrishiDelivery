import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../features/info/app_info_screen.dart';
import 'wallet_screen.dart';
import '../../core/utils/error_handler.dart';

final myTopupRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.myTopupRequests);
  return List<Map<String, dynamic>>.from(res.data['requests']);
});

// Loads active salesmen with id+name from /api/salesman/list
final activeSalesmenProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get(Endpoints.salesmanList);
    return List<Map<String, dynamic>>.from(res.data['salesmen'] ?? []);
  } catch (_) {
    return [];
  }
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
  bool _historyExpanded = false;

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

        // History — collapsible panel
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Column(children: [
            // Toggle header
            InkWell(
              onTap: () => setState(() => _historyExpanded = !_historyExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                  const Spacer(),
                  Icon(_historyExpanded ? Icons.expand_more : Icons.expand_less,
                      color: Colors.grey, size: 20),
                ]),
              ),
            ),
            // Expandable list
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _historyExpanded
                  ? SizedBox(
                      height: 220,
                      child: requests.when(
                        data: (list) => list.isEmpty
                            ? const Center(child: Text('No requests yet', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                itemCount: list.length,
                                itemBuilder: (_, i) => _RequestTile(request: list[i]),
                              ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) { logError('topup', e); return Center(child: Text(friendlyError(e))); },
                      ),
                    )
                  : const SizedBox.shrink(),
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
    // Format amount to 2 decimal places as required by UPI spec
    final formattedAmount = double.parse(amount).toStringAsFixed(2);
    final uri = Uri.parse(
      'upi://pay?pa=${Uri.encodeComponent(upiId)}'
      '&pn=${Uri.encodeComponent(upiName)}'
      '&am=$formattedAmount'
      '&cu=INR'
      '&mc=5411'  // merchant category: grocery stores
      '&tn=${Uri.encodeComponent('HappyKrishi Wallet Topup')}',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      if (!launched && mounted) {
        final launched2 = await launchUrl(uri);
        if (!launched2 && mounted) {
          _show('No UPI app found. Please pay using the QR or UPI ID above.');
        }
      }
    } catch (_) {
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
          backgroundColor: AppColors.primary,
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
              // Step 1: How to pay card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text('How to pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
                  ]),
                  const SizedBox(height: 10),
                  _HowToStep(step: '1', text: 'Open GPay, PhonePe or any UPI app on your phone'),
                  _HowToStep(step: '2', text: 'Tap "Scan QR" and scan the QR code below'),
                  _HowToStep(step: '3', text: 'OR tap the UPI ID below to copy and paste it in your app'),
                  _HowToStep(step: '4', text: 'Enter the exact amount you chose above'),
                  _HowToStep(step: '5', text: 'Complete the payment and note the UTR/Reference number'),
                  _HowToStep(step: '6', text: 'Come back here, enter the UTR and tap "I have Paid"'),
                ]),
              ),
              const SizedBox(height: 20),

              // QR Code with download hint
              Row(children: [
                const CircleAvatar(radius: 12, backgroundColor: AppColors.primary,
                    child: Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                const Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                if (qrUrl.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Save QR', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    onPressed: () async {
                      final url = Endpoints.imageUrl(qrUrl);
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                  ),
              ]),
              const SizedBox(height: 10),

              // QR Code
              if (qrUrl.isNotEmpty)
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(
                        Endpoints.imageUrl(qrUrl),
                        width: 220, height: 220, fit: BoxFit.contain,
                        loadingBuilder: (_, child, chunk) => chunk == null
                            ? child
                            : const SizedBox(width: 220, height: 220,
                                child: Center(child: CircularProgressIndicator())),
                        errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 220,
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
                      Text('QR not configured yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('Contact admin', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              const Center(child: Text('Screenshot or save this QR to pay later', style: TextStyle(fontSize: 11, color: Colors.grey))),
              const SizedBox(height: 20),

              // UPI ID
              Row(children: [
                const CircleAvatar(radius: 12, backgroundColor: AppColors.primary,
                    child: Text('2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                const Text('Or copy UPI ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 10),

              if (upiId.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: upiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UPI ID copied! Paste it in your payment app.'), duration: Duration(seconds: 2)));
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Row(children: [
                      const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(upiName, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        Text(upiId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.copy, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 20),

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
                      backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
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
                const CircleAvatar(radius: 12, backgroundColor: AppColors.primary,
                    child: Text('2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                const Text('Enter payment reference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFEAF2EA), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Amount: ₹${_amountCtrl.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                      backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('topup', e); return Center(child: Text(friendlyError(e))); },
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
  Map<String, dynamic>? _selectedSalesman; // {id, name, phone}
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
        'collected_by': _selectedSalesman!['id'],  // send salesman user ID
      });
      ref.invalidate(myTopupRequestsProvider);
      ref.invalidate(walletProvider);
      final submittedVia = _selectedSalesman!['name'] as String;
      _amountCtrl.clear();
      setState(() => _selectedSalesman = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cash request submitted via $submittedVia! Admin will credit shortly.'),
          backgroundColor: AppColors.primary,
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
    final salesmenAsync = ref.watch(activeSalesmenProvider);

    return appInfo.when(
      data: (info) {
        final payment = info['payment'] as Map<String, dynamic>? ?? {};
        // Use structured salesman list (id + name) from /api/salesman/list
        final salesmen = salesmenAsync.value ?? [];
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
              children: salesmen.map((s) {
                final name = s['name'] as String? ?? '';
                final selected = _selectedSalesman != null && _selectedSalesman!['id'] == s['id'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedSalesman = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected ? AppColors.primary : Colors.grey.shade300,
                          width: selected ? 2 : 1),
                      boxShadow: selected
                          ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 8)]
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: selected ? Colors.white24 : Colors.grey.shade100,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : AppColors.primary,
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
                    const Icon(Icons.location_on, size: 14, color: AppColors.primary),
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
                    ? 'Submit Cash via ${_selectedSalesman!['name']}'
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
        children: amounts.map((a) {
          final isSelected = ctrl.text == a.toString();
          return GestureDetector(
            onTap: () => onTap(a),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                '₹$a',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
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
    final collector = (request['collector_name'] ?? request['collected_by'])?.toString();
    final collectorDisplay = (collector != null && collector.isNotEmpty && collector != 'null' && collector != '0')
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

// ── How-to step row ────────────────────────────────────────────────────────────
class _HowToStep extends StatelessWidget {
  final String step;
  final String text;
  const _HowToStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87))),
    ]),
  );
}
