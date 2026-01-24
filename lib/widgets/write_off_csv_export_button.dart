import 'package:flutter/material.dart';
import '../models/simple_write_off_model.dart';
import '../services/simple_write_off_service.dart';
import '../services/write_off_csv_export_service.dart';

class WriteOffCsvExportButton extends StatefulWidget {
  final String? storeId;
  final List<SimpleWriteOffHeader> writeOffs;
  final SimpleWriteOffService writeOffService;
  final String? buttonText;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const WriteOffCsvExportButton({
    super.key,
    required this.storeId,
    required this.writeOffs,
    required this.writeOffService,
    this.buttonText,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<WriteOffCsvExportButton> createState() => _WriteOffCsvExportButtonState();
}

class _WriteOffCsvExportButtonState extends State<WriteOffCsvExportButton> {
  bool _isExporting = false;
  late WriteOffCsvExportService _csvExportService;

  @override
  void initState() {
    super.initState();
    _csvExportService = WriteOffCsvExportService(widget.writeOffService);
  }

  Future<void> _exportToCsv() async {
    if (widget.storeId == null) {
      _showError('Store ID not available');
      return;
    }

    setState(() => _isExporting = true);

    try {
      await _csvExportService.exportWriteOffToCsv(
        storeId: widget.storeId!,
        writeOffs: widget.writeOffs,
        onSuccess: _showSuccess,
        onError: _showError,
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isExporting || widget.writeOffs.isEmpty ? null : _exportToCsv,
      icon: _isExporting 
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(widget.icon ?? Icons.download, size: 18),
      label: Text(_isExporting ? 'Exporting...' : (widget.buttonText ?? 'Export CSV')),
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.backgroundColor ?? Colors.green[600],
        foregroundColor: widget.foregroundColor ?? Colors.white,
      ),
    );
  }
}