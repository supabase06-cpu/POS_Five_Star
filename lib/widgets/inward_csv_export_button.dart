import 'package:flutter/material.dart';
import '../models/inward_model.dart';
import '../services/inward_service.dart';
import '../services/inward_csv_export_service.dart';

class InwardCsvExportButton extends StatefulWidget {
  final String? storeId;
  final List<InwardHeader> inwards;
  final InwardService inwardService;
  final String? buttonText;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const InwardCsvExportButton({
    super.key,
    required this.storeId,
    required this.inwards,
    required this.inwardService,
    this.buttonText,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<InwardCsvExportButton> createState() => _InwardCsvExportButtonState();
}

class _InwardCsvExportButtonState extends State<InwardCsvExportButton> {
  bool _isExporting = false;
  late InwardCsvExportService _csvExportService;

  @override
  void initState() {
    super.initState();
    _csvExportService = InwardCsvExportService(widget.inwardService);
  }

  Future<void> _exportToCsv() async {
    if (widget.storeId == null) {
      _showError('Store ID not available');
      return;
    }

    print('🚀 Starting CSV export for ${widget.inwards.length} inwards');
    setState(() => _isExporting = true);

    try {
      await _csvExportService.exportInwardToCsv(
        storeId: widget.storeId!,
        inwards: widget.inwards,
        onSuccess: (message) {
          print('✅ Export success: $message');
          _showSuccess(message);
        },
        onError: (error) {
          print('❌ Export error: $error');
          _showError(error);
        },
      );
    } catch (e, stackTrace) {
      print('❌ Unexpected error in _exportToCsv: $e');
      print('Stack trace: $stackTrace');
      _showError('Unexpected error during export: $e');
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
      onPressed: _isExporting || widget.inwards.isEmpty ? null : _exportToCsv,
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