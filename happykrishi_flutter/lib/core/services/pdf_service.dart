import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';

class PdfService {
  // Load Unicode-capable fonts once and cache
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    _regular ??= await PdfGoogleFonts.notoSansRegular();
    _bold ??= await PdfGoogleFonts.notoSansBold();
  }

  static pw.TextStyle _style({
    double fontSize = 10,
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.TextStyle(
      font: bold ? _bold : _regular,
      fontBold: _bold,
      fontSize: fontSize,
      color: color,
    );
  }

  // ── Wallet Statement ────────────────────────────────────────────────────────
  static Future<void> shareWalletStatement({
    required BuildContext context,
    required AppUser user,
    required double balance,
    required List<WalletTransaction> transactions,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        _header('Wallet Statement', user),
        pw.SizedBox(height: 16),
        _balanceBadge(balance),
        pw.SizedBox(height: 20),
        pw.Text('Transaction History', style: _style(fontSize: 13, bold: true)),
        pw.SizedBox(height: 8),
        if (transactions.isEmpty)
          pw.Text('No transactions yet.', style: _style(color: PdfColors.grey))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Description', 'Type', 'Amount', 'Balance'],
            headerStyle: _style(bold: true, fontSize: 10),
            cellStyle: _style(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            data: transactions.map((t) {
              final isCredit = ['credit', 'refund', 'discount'].contains(t.type);
              return [
                t.createdAt.substring(0, 10),
                t.description ?? t.type,
                t.type,
                '${isCredit ? '+' : '-'}Rs.${t.amount.toStringAsFixed(2)}',
                'Rs.${t.balanceAfter.toStringAsFixed(2)}',
              ];
            }).toList(),
          ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'wallet_statement_${user.phone}.pdf');
  }

  // ── Top-up Requests ──────────────────────────────────────────────────────────
  static Future<void> shareTopupRequests({
    required BuildContext context,
    required AppUser user,
    required List<Map<String, dynamic>> requests,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        _header('Top-up Request History', user),
        pw.SizedBox(height: 20),
        if (requests.isEmpty)
          pw.Text('No requests yet.', style: _style())
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Amount', 'Status', 'Admin Note'],
            headerStyle: _style(bold: true, fontSize: 10),
            cellStyle: _style(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            data: requests.map((r) => [
                  (r['created_at'] as String).substring(0, 16),
                  'Rs.${(r['amount'] as num).toStringAsFixed(0)}',
                  (r['status'] as String).toUpperCase(),
                  r['admin_note'] ?? '-',
                ]).toList(),
          ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'topup_requests_${user.phone}.pdf');
  }

  // ── Order History ────────────────────────────────────────────────────────────
  static Future<void> shareOrderHistory({
    required BuildContext context,
    required AppUser user,
    required List<Order> orders,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        _header('Order History', user),
        pw.SizedBox(height: 20),
        if (orders.isEmpty)
          pw.Text('No orders yet.', style: _style())
        else
          pw.TableHelper.fromTextArray(
            headers: ['Order #', 'Date', 'Status', 'Delivery Slot', 'Amount'],
            headerStyle: _style(bold: true, fontSize: 10),
            cellStyle: _style(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            data: orders.map((o) => [
                  o.orderNumber,
                  o.deliveryDate,
                  o.status.toUpperCase(),
                  o.slotLabel ?? '-',
                  'Rs.${o.finalAmount.toStringAsFixed(2)}',
                ]).toList(),
          ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'orders_${user.phone}.pdf');
  }

  // ── Single Order Invoice ──────────────────────────────────────────────────────
  static Future<void> shareOrderInvoice({
    required BuildContext context,
    required AppUser user,
    required Order order,
    required List<OrderItem> items,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Order Invoice', user),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.green50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Order: ${order.orderNumber}', style: _style(bold: true, fontSize: 13)),
              pw.Text('Date: ${order.deliveryDate}  |  Slot: ${order.slotLabel ?? '-'}', style: _style()),
              pw.Text('Status: ${order.status.toUpperCase()}', style: _style()),
              if (order.city != null)
                pw.Text('Delivery: ${order.addressLine ?? ''}, ${order.city}', style: _style()),
            ]),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Items', style: _style(bold: true, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Product', 'Qty', 'Unit Price', 'Total'],
            headerStyle: _style(bold: true, fontSize: 10),
            cellStyle: _style(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            data: items.map((i) => [
                  i.productName ?? '-',
                  '${(i.actualQty ?? i.estimatedQty).toStringAsFixed(2)} ${i.unit ?? ''}',
                  'Rs.${i.unitPrice.toStringAsFixed(2)}',
                  'Rs.${(i.actualTotal ?? i.estimatedTotal).toStringAsFixed(2)}',
                ]).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          _summaryRow('Subtotal', 'Rs.${order.subtotal.toStringAsFixed(2)}'),
          _summaryRow('Delivery Charge',
              order.deliveryCharge == 0 ? 'FREE' : 'Rs.${order.deliveryCharge.toStringAsFixed(2)}'),
          if (order.discountAmount > 0)
            _summaryRow('Discount', '-Rs.${order.discountAmount.toStringAsFixed(2)}'),
          pw.Divider(),
          _summaryRow('Total Paid', 'Rs.${order.finalAmount.toStringAsFixed(2)}',
              bold: true, color: PdfColors.green800),
          pw.SizedBox(height: 20),
          _footer(),
        ],
      ),
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'invoice_${order.orderNumber}.pdf');
  }

  // ── Admin: Products Report ────────────────────────────────────────────────────
  static Future<void> shareAdminProductsReport({
    required BuildContext context,
    required List<Product> products,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
            style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Product', 'Category', 'Price', 'Unit', 'Stock', 'Min Qty', 'Status'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
          data: products.map((p) => [
            p.name,
            p.categoryName ?? '-',
            'Rs.${p.pricePerUnit.toStringAsFixed(2)}',
            p.unit,
            p.stockQty.toStringAsFixed(1),
            p.minQty.toStringAsFixed(1),
            p.isActive ? 'Active' : 'Inactive',
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Total: ${products.length} products  |  '
          'Active: ${products.where((p) => p.isActive).length}  |  '
          'Out of stock: ${products.where((p) => p.stockQty <= 0).length}',
          style: _style(bold: true, fontSize: 10),
        ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'products_report.pdf');
  }

  // ── Admin: Topup Requests Report ─────────────────────────────────────────────
  static Future<void> shareAdminTopupsReport({
    required BuildContext context,
    required List<Map<String, dynamic>> requests,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}', style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Customer', 'Amount', 'Method', 'Status', 'Collector', 'Settlement'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
          data: requests.map((r) => [
            (r['created_at'] as String).substring(0, 16),
            r['user_name'] ?? '',
            'Rs.${(r['amount'] as num).toStringAsFixed(0)}',
            r['payment_method'] ?? '-',
            (r['status'] as String? ?? '').toUpperCase(),
            r['collector_name'] ?? r['collected_by'] ?? '-',
            r['settlement_id'] != null ? 'Settled' : 'Unsettled',
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Total: ${requests.length} requests  |  '
          'Approved: Rs.${requests.where((r) => r['status'] == 'approved').fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()).toStringAsFixed(0)}  |  '
          'Pending: Rs.${requests.where((r) => r['status'] == 'pending').fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()).toStringAsFixed(0)}',
          style: _style(bold: true, fontSize: 10),
        ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'topups_report.pdf');
  }

  // ── Admin: Advances Report ────────────────────────────────────────────────────
  static Future<void> shareAdminAdvancesReport({
    required BuildContext context,
    required List<Map<String, dynamic>> advances,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}', style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Customer', 'Amount', 'Credited By', 'Payment Received'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange50),
          data: advances.map((r) => [
            (r['created_at'] as String).substring(0, 16),
            r['user_name'] ?? '',
            'Rs.${(r['amount'] as num).toStringAsFixed(0)}',
            '${r['credited_by_role'] ?? '-'} ${r['credited_by_name'] ?? ''}'.trim(),
            (r['payment_received'] as int? ?? 0) == 1 ? 'Yes' : 'No',
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Total: ${advances.length} advances  |  '
          'Unpaid: Rs.${advances.where((r) => (r['payment_received'] as int? ?? 0) == 0).fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()).toStringAsFixed(0)}  |  '
          'Paid: Rs.${advances.where((r) => (r['payment_received'] as int? ?? 0) == 1).fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()).toStringAsFixed(0)}',
          style: _style(bold: true, fontSize: 10),
        ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'advances_report.pdf');
  }

  // ── Admin: Settlements Report ─────────────────────────────────────────────────
  static Future<void> shareAdminSettlementsReport({
    required BuildContext context,
    required List<Map<String, dynamic>> settlements,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}', style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Salesman', 'Amount', 'Status', 'Acknowledged By'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
          data: settlements.map((r) => [
            (r['created_at'] as String? ?? '').substring(0, 16),
            r['salesman_name'] ?? '',
            'Rs.${(r['amount'] as num).toStringAsFixed(0)}',
            (r['status'] as String? ?? 'pending').toUpperCase(),
            r['acknowledged_by_name'] ?? '-',
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Total: ${settlements.length} settlements  |  '
          'Total amount: Rs.${settlements.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()).toStringAsFixed(0)}',
          style: _style(bold: true, fontSize: 10),
        ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'settlements_report.pdf');
  }

  // ── Admin: Direct Transactions Report ────────────────────────────────────────
  static Future<void> shareAdminDirectTransactionsReport({
    required BuildContext context,
    required List<Map<String, dynamic>> transactions,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final credited = transactions.where((t) => t['type'] == 'credit').fold<double>(0, (s, t) => s + (t['amount'] as num).toDouble());
    final debited  = transactions.where((t) => t['type'] != 'credit').fold<double>(0, (s, t) => s + (t['amount'] as num).toDouble());
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}', style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 8),
        pw.Text(
          'Credited: Rs.${credited.toStringAsFixed(0)}  |  Debited: Rs.${debited.toStringAsFixed(0)}  |  Total: ${transactions.length} transactions',
          style: _style(bold: true, fontSize: 10),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Customer', 'Phone', 'Type', 'Amount', 'Description', 'Balance After'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
          data: transactions.map((t) => [
            (t['created_at'] as String? ?? '').substring(0, 16),
            t['customer_name'] ?? t['user_name'] ?? '',
            t['customer_phone'] ?? t['user_phone'] ?? '',
            (t['type'] as String? ?? '').toUpperCase(),
            '${t['type'] == 'credit' ? '+' : '-'}Rs.${(t['amount'] as num).toStringAsFixed(0)}',
            t['description'] ?? '-',
            'Rs.${(t['balance_after'] as num?)?.toStringAsFixed(0) ?? '-'}',
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'direct_transactions_report.pdf');
  }

  // ── Admin: Orders Report ──────────────────────────────────────────────────
  static Future<void> shareAdminOrdersReport({
    required BuildContext context,
    required List<Map<String, dynamic>> orders,
    required String title,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      build: (pw.Context ctx) => [
        pw.Text('HappyKrishi Delivery', style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
        pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
        pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
            style: _style(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Order #', 'Customer', 'Date', 'Status', 'Amount', 'Agent'],
          headerStyle: _style(bold: true, fontSize: 9),
          cellStyle: _style(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
          data: orders.map((o) => [
                o['order_number'] ?? '',
                o['customer_name'] ?? '',
                o['delivery_date'] ?? '',
                (o['status'] as String? ?? '').toUpperCase(),
                'Rs.${(o['final_amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                o['agent_name'] ?? '-',
              ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
            'Total: ${orders.length} orders  |  Revenue: Rs.${orders.fold<double>(0, (s, o) => s + (o['final_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
            style: _style(bold: true, fontSize: 11)),
        pw.SizedBox(height: 20),
        _footer(),
      ],
    ));
    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'orders_report.pdf');
  }

  // ── Theme ─────────────────────────────────────────────────────────────────────

  static pw.ThemeData _theme() => pw.ThemeData.withFont(
        base: _regular!,
        bold: _bold!,
      );

  // ── Private helpers ───────────────────────────────────────────────────────────

  static pw.Widget _header(String title, AppUser user) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('HappyKrishi Delivery',
                style: _style(fontSize: 18, bold: true, color: PdfColors.green800)),
            pw.Text(DateTime.now().toString().substring(0, 16),
                style: _style(fontSize: 9, color: PdfColors.grey)),
          ]),
          pw.Text(title, style: _style(fontSize: 13, color: PdfColors.grey)),
          pw.Divider(),
          pw.Text('Name: ${user.name}  |  Phone: +91 ${user.phone}',
              style: _style(fontSize: 10)),
        ],
      );

  static pw.Widget _balanceBadge(double balance) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.green800,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Current Balance',
              style: _style(color: PdfColors.white, fontSize: 10)),
          pw.Text('Rs.${balance.toStringAsFixed(2)}',
              style: _style(color: PdfColors.white, fontSize: 22, bold: true)),
        ]),
      );

  static pw.Widget _summaryRow(String label, String value,
          {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: _style(fontSize: 11, bold: bold)),
          pw.Text(value, style: _style(fontSize: 11, bold: bold, color: color)),
        ]),
      );

  static pw.Widget _footer() => pw.Column(children: [
        pw.Divider(),
        pw.Text('HappyKrishi Delivery  -  Farm Fresh to Your Door',
            style: _style(fontSize: 9, color: PdfColors.grey),
            textAlign: pw.TextAlign.center),
      ]);
}
