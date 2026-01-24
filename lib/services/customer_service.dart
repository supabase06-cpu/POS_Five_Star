import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_db_service.dart';

class CustomerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDbService _localDb = LocalDbService();

  /// Check if online
  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sync all unsynced customers to Supabase
  Future<int> syncCustomersToSupabase() async {
    // Check offline first
    final online = await _isOnline();
    if (!online) {
      debugPrint('📴 Offline - skipping customer sync');
      return 0;
    }
    
    try {
      final unsyncedCustomers = await _localDb.getUnsyncedCustomers();
      
      if (unsyncedCustomers.isEmpty) {
        debugPrint('✅ No customers to sync');
        return 0;
      }

      int syncedCount = 0;
      
      for (var customer in unsyncedCustomers) {
        try {
          // Check if customer already exists in Supabase by phone
          if (customer.customerPhone != null && customer.customerPhone!.isNotEmpty) {
            final existing = await _supabase
                .from('customers')
                .select('id')
                .eq('org_id', customer.orgId)
                .eq('customer_phone', customer.customerPhone!)
                .maybeSingle();

            if (existing != null) {
              // Update existing customer
              await _supabase.from('customers').update({
                'customer_name': customer.customerName,
                'updated_at': DateTime.now().toIso8601String(),
              }).eq('id', existing['id']);
            } else {
              // Insert new customer
              await _supabase.from('customers').insert({
                'id': customer.id,
                'org_id': customer.orgId,
                'store_id': customer.storeId,
                'customer_name': customer.customerName,
                'customer_phone': customer.customerPhone,
                'customer_email': customer.customerEmail,
                'address': customer.address,
                'total_orders': customer.totalOrders,
                'total_spent': customer.totalSpent,
                'last_order_at': customer.lastOrderAt?.toIso8601String(),
                'created_at': customer.createdAt.toIso8601String(),
                'updated_at': customer.updatedAt.toIso8601String(),
              });
            }
          } else {
            // No phone - insert directly
            await _supabase.from('customers').insert({
              'id': customer.id,
              'org_id': customer.orgId,
              'store_id': customer.storeId,
              'customer_name': customer.customerName,
              'customer_phone': customer.customerPhone,
              'customer_email': customer.customerEmail,
              'address': customer.address,
              'total_orders': customer.totalOrders,
              'total_spent': customer.totalSpent,
              'last_order_at': customer.lastOrderAt?.toIso8601String(),
              'created_at': customer.createdAt.toIso8601String(),
              'updated_at': customer.updatedAt.toIso8601String(),
            });
          }

          // Mark as synced in local DB
          await _localDb.markCustomerSynced(customer.id);
          syncedCount++;
        } catch (e) {
          debugPrint('❌ Failed to sync customer ${customer.id}: $e');
        }
      }

      debugPrint('✅ Synced $syncedCount customers to Supabase');
      return syncedCount;
    } catch (e) {
      debugPrint('❌ Customer sync error: $e');
      return 0;
    }
  }

  /// Search customers - checks offline first, always tries local DB first
  Future<List<Map<String, dynamic>>> searchCustomers(String orgId, String query) async {
    // Check offline first
    final online = await _isOnline();
    
    if (!online) {
      debugPrint('📴 Offline - searching customers from local DB');
      return await _searchLocalCustomers(orgId, query);
    }
    
    // Even when online, try local DB first for faster response
    final localResults = await _searchLocalCustomers(orgId, query);
    if (localResults.isNotEmpty) {
      debugPrint('✅ Found ${localResults.length} customers in local DB');
      return localResults;
    }
    
    // If no local results, try Supabase
    try {
      final response = await _supabase
          .from('customers')
          .select()
          .eq('org_id', orgId)
          .eq('is_active', true)
          .or('customer_name.ilike.%$query%,customer_phone.ilike.%$query%')
          .order('customer_name')
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Customer search error: $e');
      debugPrint('📴 Falling back to local customer search');
      return localResults; // Return local results (may be empty)
    }
  }

  /// Search customers from local DB
  Future<List<Map<String, dynamic>>> _searchLocalCustomers(String orgId, String query) async {
    try {
      final customers = await _localDb.getCustomers(orgId, searchQuery: query);
      return customers.map((c) => {
        'id': c.id,
        'org_id': c.orgId,
        'store_id': c.storeId,
        'customer_name': c.customerName,
        'customer_phone': c.customerPhone,
        'customer_email': c.customerEmail,
        'address': c.address,
        'total_orders': c.totalOrders,
        'total_spent': c.totalSpent,
      }).toList();
    } catch (e) {
      debugPrint('❌ Local customer search error: $e');
      return [];
    }
  }

  /// Get customer by phone - checks offline first, always tries local DB first
  Future<Map<String, dynamic>?> getCustomerByPhone(String orgId, String phone) async {
    // Always try local DB first for faster response
    final localCustomer = await _getLocalCustomerByPhone(orgId, phone);
    if (localCustomer != null) {
      debugPrint('✅ Found customer in local DB: $phone');
      return localCustomer;
    }
    
    // Check offline before trying Supabase
    final online = await _isOnline();
    if (!online) {
      debugPrint('📴 Offline - customer not found in local DB');
      return null;
    }
    
    try {
      final response = await _supabase
          .from('customers')
          .select()
          .eq('org_id', orgId)
          .eq('customer_phone', phone)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('❌ Get customer error: $e');
      return null;
    }
  }

  /// Get customer by phone from local DB
  Future<Map<String, dynamic>?> _getLocalCustomerByPhone(String orgId, String phone) async {
    try {
      final customer = await _localDb.findCustomerByPhone(orgId, phone);
      if (customer == null) return null;
      
      return {
        'id': customer.id,
        'org_id': customer.orgId,
        'store_id': customer.storeId,
        'customer_name': customer.customerName,
        'customer_phone': customer.customerPhone,
        'customer_email': customer.customerEmail,
        'address': customer.address,
        'total_orders': customer.totalOrders,
        'total_spent': customer.totalSpent,
      };
    } catch (e) {
      debugPrint('❌ Local customer lookup error: $e');
      return null;
    }
  }

  /// Update customer stats after order completion
  Future<void> updateCustomerStats(String customerId, double orderAmount) async {
    // Check offline first
    final online = await _isOnline();
    if (!online) {
      debugPrint('📴 Offline - customer stats will sync later');
      return;
    }
    
    try {
      // Update in Supabase
      await _supabase.rpc('increment_customer_stats', params: {
        'p_customer_id': customerId,
        'p_order_amount': orderAmount,
      });
    } catch (e) {
      // If RPC doesn't exist, do manual update
      try {
        final customer = await _supabase
            .from('customers')
            .select('total_orders, total_spent')
            .eq('id', customerId)
            .single();

        await _supabase.from('customers').update({
          'total_orders': (customer['total_orders'] ?? 0) + 1,
          'total_spent': (customer['total_spent'] ?? 0) + orderAmount,
          'last_order_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', customerId);
      } catch (e2) {
        debugPrint('❌ Update customer stats error: $e2');
      }
    }
  }
}
