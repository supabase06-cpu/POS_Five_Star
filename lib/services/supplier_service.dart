import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inward_model.dart';

class SupplierService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Generate next supplier code
  Future<String> generateSupplierCode(String orgId, String? storeId) async {
    try {
      // Get all existing supplier codes for this org
      final response = await _supabase
          .from('suppliers')
          .select('supplier_code')
          .eq('org_id', orgId)
          .order('supplier_code');

      // Find the highest number from existing codes
      int maxNumber = 0;
      for (var row in response) {
        final code = row['supplier_code'] as String?;
        if (code != null) {
          // Extract number from codes like SUP001, SUP005, etc.
          final match = RegExp(r'SUP(\d+)').firstMatch(code);
          if (match != null) {
            final number = int.tryParse(match.group(1)!) ?? 0;
            if (number > maxNumber) {
              maxNumber = number;
            }
          }
        }
      }

      // Generate next code
      final nextNumber = maxNumber + 1;
      final supplierCode = 'SUP${nextNumber.toString().padLeft(3, '0')}';
      debugPrint('📝 Generated supplier code: $supplierCode (max was: $maxNumber)');
      return supplierCode;
    } catch (e) {
      debugPrint('❌ Generate supplier code error: $e');
      return 'SUP001'; // Default fallback
    }
  }

  /// Check if supplier code already exists
  Future<bool> checkDuplicateSupplierCode(String orgId, String supplierCode) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select('id')
          .eq('org_id', orgId)
          .eq('supplier_code', supplierCode)
          .limit(1);
      
      final exists = response.isNotEmpty;
      if (exists) {
        debugPrint('⚠️ Duplicate supplier code: $supplierCode');
      }
      return exists;
    } catch (e) {
      debugPrint('❌ Check duplicate supplier error: $e');
      return false;
    }
  }

  /// Update an existing supplier
  Future<Supplier?> updateSupplier({
    required String supplierId,
    required String supplierName,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    String? gstNumber,
    String? panNumber,
    double creditLimit = 0,
  }) async {
    try {
      debugPrint('📝 Updating supplier: $supplierName');
      
      final response = await _supabase.from('suppliers').update({
        'supplier_name': supplierName,
        'contact_person': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'postal_code': postalCode,
        'gst_number': gstNumber,
        'pan_number': panNumber,
        'credit_limit': creditLimit,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', supplierId).select().single();
      
      debugPrint('✅ Supplier updated: $supplierName');
      return Supplier.fromMap(response);
    } catch (e) {
      debugPrint('❌ Update supplier error: $e');
      return null;
    }
  }

  /// Create a new supplier
  Future<Supplier?> createSupplier({
    required String orgId,
    required String supplierCode,
    required String supplierName,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    String? gstNumber,
    String? panNumber,
    double creditLimit = 0,
  }) async {
    try {
      debugPrint('📝 Creating supplier: $supplierName ($supplierCode)');
      
      final response = await _supabase.from('suppliers').insert({
        'org_id': orgId,
        'supplier_code': supplierCode,
        'supplier_name': supplierName,
        'contact_person': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'postal_code': postalCode,
        'gst_number': gstNumber,
        'pan_number': panNumber,
        'credit_limit': creditLimit,
        'current_balance': 0,
        'is_active': true,
      }).select().single();
      
      debugPrint('✅ Supplier created: $supplierName');
      return Supplier.fromMap(response);
    } catch (e) {
      debugPrint('❌ Create supplier error: $e');
      return null;
    }
  }

  /// Get all active suppliers for org
  Future<List<Supplier>> getSuppliers(String orgId, {String? searchQuery}) async {
    try {
      debugPrint('🔍 Fetching suppliers for org: $orgId');
      
      var query = _supabase
          .from('suppliers')
          .select()
          .eq('org_id', orgId)
          .eq('is_active', true);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('supplier_name.ilike.%$searchQuery%,supplier_code.ilike.%$searchQuery%,phone.ilike.%$searchQuery%');
      }

      final response = await query.order('supplier_name');
      debugPrint('📥 Suppliers response: ${response.length} records');
      final suppliers = response.map<Supplier>((s) => Supplier.fromMap(s)).toList();
      debugPrint('📦 Suppliers loaded: ${suppliers.length}');
      return suppliers;
    } catch (e) {
      debugPrint('❌ Get suppliers error: $e');
      return [];
    }
  }

  /// Get supplier by ID
  Future<Supplier?> getSupplierById(String supplierId) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .eq('id', supplierId)
          .single();
      debugPrint('✅ Supplier found: ${response['supplier_name']}');
      return Supplier.fromMap(response);
    } catch (e) {
      debugPrint('❌ Get supplier error: $e');
      return null;
    }
  }
}