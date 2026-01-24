import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'printer_service.dart';

class InvoicePrinterService {
  static final InvoicePrinterService _instance = InvoicePrinterService._internal();
  factory InvoicePrinterService() => _instance;
  InvoicePrinterService._internal();

  final PrinterService _printerService = PrinterService();

  // Standard printable width for 80mm paper (72mm is safe)
  static const double _printableWidth = 72 * PdfPageFormat.mm;

  Future<bool> printInvoice(InvoiceData invoiceData) async {
    try {
      print('DEBUG: Customer name received: "${invoiceData.customerName}"');
      
      // Check if printer is selected
      if (!_printerService.hasSelectedPrinter) {
        throw Exception('No printer selected. Please configure a printer first.');
      }

      // Generate PDF as before
      final pdfBytes = await _generateInvoicePdf(invoiceData);

      // Print using direct connection (on-demand)
      await _printerService.printDirectPDF(pdfBytes);
      
      return true;

    } catch (e) {
      print('Invoice printing failed: $e');
      rethrow;
    }
  }

  Future<Uint8List> _generateInvoicePdf(InvoiceData invoiceData) async {
    final pdf = pw.Document();

    // Load a Unicode-compatible font
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    // Load SVG Logo
    String? logoSvg;
    try {
      logoSvg = await rootBundle.loadString('assets/LOGO.svg');
    } catch (e) {
      print('Error loading SVG logo: $e');
      logoSvg = null;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          _printableWidth,
          double.infinity,
          marginAll: 0,
        ),
        build: (pw.Context context) {
          // Layout: Left Padding 3mm, Right Padding 0mm
          return pw.Padding(
            padding: const pw.EdgeInsets.only(left: 3 * PdfPageFormat.mm, right: 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(logoSvg, fontBold),
                pw.SizedBox(height: 5),
                _buildStoreInfo(invoiceData, font),
                pw.SizedBox(height: 5),
                _buildInvoiceDetails(invoiceData, font, fontBold),
                pw.SizedBox(height: 5),
                _buildItemsTable(invoiceData, font, fontBold),
                pw.SizedBox(height: 5),
                _buildTotalsSection(invoiceData, font, fontBold),
                pw.SizedBox(height: 8),
                _buildPaymentInfo(invoiceData, font, fontBold),
                pw.SizedBox(height: 8),
                _buildFooter(invoiceData, font, fontBold), // Updated Footer
                pw.SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- WIDGET BUILDERS ---

  pw.Widget _buildHeader(String? logoSvg, pw.Font fontBold) {
    return pw.Column(
      children: [
        if (logoSvg != null) ...[
          pw.Center(
            child: pw.SizedBox(
              width: 55, // Logo Size 55
              height: 55,
              child: pw.SvgImage(
                svg: logoSvg,
                fit: pw.BoxFit.fill, 
              ),
            ),
          ),
          pw.SizedBox(height: 3), // Gap 3
        ],
        pw.Center(
          child: pw.Text(
            'FIVE STAR CHICKEN',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: fontBold),
          ),
        ),
      ],
    );
  }

  pw.Widget _divider() {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      height: 1,
      width: double.infinity,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed),
        ),
      ),
    );
  }

  pw.Widget _buildStoreInfo(InvoiceData invoiceData, pw.Font font) {
    return pw.Column(
      children: [
        if (invoiceData.storeAddress.isNotEmpty)
          pw.Center(child: pw.Text(invoiceData.storeAddress, style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center)),
        if (invoiceData.storePhone.isNotEmpty)
          pw.Center(child: pw.Text('Tel: ${invoiceData.storePhone}', style: pw.TextStyle(fontSize: 8, font: font))),
        pw.SizedBox(height: 2),
        _divider(),
      ],
    );
  }

  pw.Widget _buildInvoiceDetails(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Invoice: ${invoiceData.invoiceNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: fontBold)),
        pw.SizedBox(height: 2),
        pw.Text('Customer Name: ${invoiceData.customerName.trim().isNotEmpty ? invoiceData.customerName.trim() : "Walk-in Customer"}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: fontBold)),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Date: ${invoiceData.date}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold)),
            pw.Text('Time: ${invoiceData.time}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      children: [
        _divider(),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 48, 
              child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: fontBold))
            ),
            pw.Expanded(
              flex: 11, 
              child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: fontBold), textAlign: pw.TextAlign.center)
            ),
            pw.Expanded(
              flex: 19, 
              child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: fontBold), textAlign: pw.TextAlign.right)
            ),
            pw.Expanded(
              flex: 19, 
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 1.5),
                child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: fontBold), textAlign: pw.TextAlign.right)
              )
            ),
          ],
        ),
        _divider(),
        ...invoiceData.items.map((item) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.0), 
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 48, 
                child: pw.Text(item.name, style: pw.TextStyle(fontSize: 9, font: font), maxLines: 2)
              ),
              pw.Expanded(
                flex: 11, 
                child: pw.Text('${item.quantity}', style: pw.TextStyle(fontSize: 9, font: font), textAlign: pw.TextAlign.center)
              ),
              pw.Expanded(
                flex: 19, 
                child: pw.Text(item.price.toStringAsFixed(0), style: pw.TextStyle(fontSize: 9, font: font), textAlign: pw.TextAlign.right)
              ),
              pw.Expanded(
                flex: 19, 
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 1.5),
                  child: pw.Text(item.total.toStringAsFixed(0), style: pw.TextStyle(fontSize: 9, font: font), textAlign: pw.TextAlign.right)
                )
              ),
            ],
          ),
        )),
        _divider(),
      ],
    );
  }

  pw.Widget _buildTotalsSection(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      children: [
        _buildTotalRow('Subtotal:', invoiceData.subtotal.toStringAsFixed(0), font),
        
        if (invoiceData.discount > 0)
          _buildTotalRow('Discount:', '-${invoiceData.discount.toStringAsFixed(0)}', font),
        
        pw.SizedBox(height: 4),

        if (invoiceData.tax > 0) 
          _buildTaxTable(invoiceData, font, fontBold),

        pw.SizedBox(height: 4),
        _divider(),
        pw.SizedBox(height: 2),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, font: fontBold)),
            pw.Text('Rs ${invoiceData.total.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, font: fontBold)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildTaxTable(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    final borderSide = const pw.BorderSide(width: 0.5, color: PdfColors.black);
    final halfTax = invoiceData.tax / 2;
    
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.black),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              _buildTaxHeaderCell('CGST', borderSide, fontBold, flex: 5, isLast: false),
              _buildTaxHeaderCell('SGST', borderSide, fontBold, flex: 5, isLast: false),
              _buildTaxHeaderCell('Total', borderSide, fontBold, flex: 5, isLast: true),
            ],
          ),
          pw.Container(height: 0.5, color: PdfColors.black),
          pw.Row(
            children: [
              _buildTaxSubCell('%', borderSide, font, flex: 2),
              _buildTaxSubCell('Value', borderSide, font, flex: 3),
              _buildTaxSubCell('%', borderSide, font, flex: 2),
              _buildTaxSubCell('Value', borderSide, font, flex: 3),
              _buildTaxSubCell('%', borderSide, font, flex: 2),
              _buildTaxSubCell('Value', borderSide, font, flex: 3, isLast: true),
            ],
          ),
          pw.Container(height: 0.5, color: PdfColors.black),
          pw.Row(
            children: [
              _buildTaxSubCell('2.5%', borderSide, font, flex: 2),
              _buildTaxSubCell(halfTax.toStringAsFixed(2), borderSide, font, flex: 3),
              _buildTaxSubCell('2.5%', borderSide, font, flex: 2),
              _buildTaxSubCell(halfTax.toStringAsFixed(2), borderSide, font, flex: 3),
              _buildTaxSubCell('5%', borderSide, font, flex: 2),
              _buildTaxSubCell(invoiceData.tax.toStringAsFixed(2), borderSide, font, flex: 3, isLast: true),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTaxHeaderCell(String text, pw.BorderSide border, pw.Font fontBold, {int flex = 1, bool isLast = false}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
        decoration: isLast ? null : pw.BoxDecoration(border: pw.Border(right: border)),
        child: pw.Center(
          child: pw.Text(
            text, 
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: fontBold)
          ),
        ),
      ),
    );
  }

  pw.Widget _buildTaxSubCell(String text, pw.BorderSide border, pw.Font font, {int flex = 1, bool isLast = false}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
        decoration: isLast ? null : pw.BoxDecoration(border: pw.Border(right: border)),
        child: pw.Center(
          child: pw.Text(
            text, 
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, font: font)
          ),
        ),
      ),
    );
  }

  pw.Widget _buildTotalRow(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, font: font)),
          pw.Text(value, style: pw.TextStyle(fontSize: 8, font: font)),
        ],
      ),
    );
  }

  pw.Widget _buildPaymentInfo(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Payment Method: ${invoiceData.paymentMethod}', style: pw.TextStyle(fontSize: 8, font: font)),
        if (invoiceData.amountPaid > 0)
           pw.Text('Amount Paid: Rs ${invoiceData.amountPaid.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 8, font: font)),
        if (invoiceData.change > 0)
           pw.Text('Change: Rs ${invoiceData.change.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 8, font: font)),
      ],
    );
  }

  // --- UPDATED FOOTER ---
  pw.Widget _buildFooter(InvoiceData invoiceData, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      children: [
        // 1. Website QR Code
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: 'https://www.sattvasupermart.in', // Fixed website URL
            width: 50,
            height: 50,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 1),
        
        // 2. Scan for Website
        pw.Center(child: pw.Text('Scan for Website', style: pw.TextStyle(fontSize: 8, font: font))),
        pw.SizedBox(height: 5),
        
        // 3. Thank You Text
        pw.Center(child: pw.Text('Thank You For Your Business', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: fontBold))),
        pw.SizedBox(height: 2),
        
        // 4. Online Order Info
        pw.Center(child: pw.Text('For get the Online Order Visit:', style: pw.TextStyle(fontSize: 9, font: font))),
        pw.Center(child: pw.Text('www.sattvasupermart.in', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: fontBold))),
      ],
    );
  }

  // --- HELPER METHODS ---
  bool isPrinterReady() {
    return _printerService.hasSelectedPrinter && _printerService.isPrinterAvailable();
  }

  String? getSelectedPrinterName() {
    return _printerService.selectedPrinterName;
  }
}

// --- DATA MODELS ---

class InvoiceData {
  final String invoiceNumber;
  final String date;
  final String time;
  final String cashierName;
  final String customerName;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String paymentMethod;
  final double amountPaid;
  final double change;
  final String qrData;

  InvoiceData({
    required this.invoiceNumber,
    required this.date,
    required this.time,
    required this.cashierName,
    this.customerName = '',
    required this.storeName,
    this.storeAddress = '',
    this.storePhone = '',
    required this.items,
    required this.subtotal,
    this.discount = 0.0,
    this.tax = 0.0,
    required this.total,
    required this.paymentMethod,
    this.amountPaid = 0.0,
    this.change = 0.0,
    this.qrData = '',
  });
}

class InvoiceItem {
  final String name;
  final int quantity;
  final double price;
  final double total;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });
}