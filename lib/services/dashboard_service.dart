import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get last 7 days sales data with daily breakdown
  Future<Last7DaysSalesData> getLast7DaysSales(String storeId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 6));
      
      final response = await _supabase
          .from('sales_orders')
          .select('order_date, final_amount, id')
          .eq('store_id', storeId)
          .gte('order_date', sevenDaysAgo.toIso8601String().split('T')[0])
          .lte('order_date', now.toIso8601String().split('T')[0])
          .eq('order_status', 'completed');

      // Group by date
      final Map<String, DailySalesData> dailyData = {};
      
      // Initialize all 7 days
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        dailyData[dateStr] = DailySalesData(
          date: date,
          totalSales: 0,
          orderCount: 0,
        );
      }

      // Populate with actual data
      for (var row in response) {
        final dateStr = row['order_date'] as String;
        final amount = (row['final_amount'] as num?)?.toDouble() ?? 0;
        
        if (dailyData.containsKey(dateStr)) {
          dailyData[dateStr]!.totalSales += amount;
          dailyData[dateStr]!.orderCount++;
        }
      }

      // Calculate totals and ABV
      double totalSales = 0;
      int totalOrders = 0;
      
      final sortedData = dailyData.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      
      final dailyList = sortedData.map((e) => e.value).toList();
      
      for (var day in dailyList) {
        totalSales += day.totalSales;
        totalOrders += day.orderCount;
        day.abv = day.orderCount > 0 ? day.totalSales / day.orderCount : 0;
      }

      final overallAbv = totalOrders > 0 ? totalSales / totalOrders : 0.0;

      debugPrint('📊 Last 7 days: ₹$totalSales, $totalOrders orders, ABV: ₹$overallAbv');
      
      return Last7DaysSalesData(
        dailyData: dailyList,
        totalSales: totalSales,
        totalOrders: totalOrders,
        averageBillValue: overallAbv,
      );
    } catch (e) {
      debugPrint('❌ Get last 7 days sales error: $e');
      return Last7DaysSalesData.empty();
    }
  }

  /// Get new vs old customers comparison for last 7 days
  Future<CustomerComparisonData> getCustomerComparison(String storeId, String orgId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 6));
      
      // Get all orders from last 7 days with customer phone
      final response = await _supabase
          .from('sales_orders')
          .select('id, customer_phone, final_amount, order_date')
          .eq('store_id', storeId)
          .gte('order_date', sevenDaysAgo.toIso8601String().split('T')[0])
          .lte('order_date', now.toIso8601String().split('T')[0])
          .eq('order_status', 'completed');

      // Get customers created before 7 days ago (existing customers)
      final existingCustomers = await _supabase
          .from('customers')
          .select('customer_phone')
          .eq('org_id', orgId)
          .lt('created_at', sevenDaysAgo.toIso8601String());

      final existingPhones = <String>{};
      for (var c in existingCustomers) {
        final phone = c['customer_phone'] as String?;
        if (phone != null && phone.isNotEmpty) {
          existingPhones.add(phone);
        }
      }

      int newCustomerOrders = 0;
      int oldCustomerOrders = 0;
      double newCustomerSales = 0;
      double oldCustomerSales = 0;
      final Set<String> newCustomerPhones = {};
      final Set<String> oldCustomerPhones = {};

      for (var row in response) {
        final phone = row['customer_phone'] as String?;
        final amount = (row['final_amount'] as num?)?.toDouble() ?? 0;

        if (phone == null || phone.isEmpty) {
          // Walk-in customer - count as new
          newCustomerOrders++;
          newCustomerSales += amount;
        } else if (existingPhones.contains(phone)) {
          // Existing customer
          oldCustomerOrders++;
          oldCustomerSales += amount;
          oldCustomerPhones.add(phone);
        } else {
          // New customer
          newCustomerOrders++;
          newCustomerSales += amount;
          newCustomerPhones.add(phone);
        }
      }

      debugPrint('📊 Customer comparison: New=$newCustomerOrders (₹$newCustomerSales), Old=$oldCustomerOrders (₹$oldCustomerSales)');

      return CustomerComparisonData(
        newCustomerOrders: newCustomerOrders,
        oldCustomerOrders: oldCustomerOrders,
        newCustomerSales: newCustomerSales,
        oldCustomerSales: oldCustomerSales,
        uniqueNewCustomers: newCustomerPhones.length,
        uniqueOldCustomers: oldCustomerPhones.length,
      );
    } catch (e) {
      debugPrint('❌ Get customer comparison error: $e');
      return CustomerComparisonData.empty();
    }
  }

  /// Get GRN summary for last 7 days
  Future<GrnSummaryData> getGrnSummary(String storeId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 6));

      final response = await _supabase
          .from('inward_headers')
          .select('id, total_amount, received_date, status')
          .eq('store_id', storeId)
          .gte('received_date', sevenDaysAgo.toIso8601String().split('T')[0])
          .lte('received_date', now.toIso8601String().split('T')[0]);

      int totalCount = 0;
      double totalValue = 0;
      int postedCount = 0;
      
      // Daily breakdown
      final Map<String, DailyGrnData> dailyData = {};
      
      // Initialize all 7 days
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        dailyData[dateStr] = DailyGrnData(date: date, count: 0, value: 0);
      }

      for (var row in response) {
        totalCount++;
        final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
        totalValue += amount;
        
        if (row['status'] == 'posted') postedCount++;
        
        final dateStr = row['received_date'] as String;
        if (dailyData.containsKey(dateStr)) {
          dailyData[dateStr]!.count++;
          dailyData[dateStr]!.value += amount;
        }
      }

      final sortedData = dailyData.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      
      final dailyList = sortedData.map((e) => e.value).toList();

      debugPrint('📊 GRN summary: $totalCount GRNs, ₹$totalValue total');

      return GrnSummaryData(
        totalCount: totalCount,
        totalValue: totalValue,
        postedCount: postedCount,
        dailyData: dailyList,
      );
    } catch (e) {
      debugPrint('❌ Get GRN summary error: $e');
      return GrnSummaryData.empty();
    }
  }

  /// Get complete dashboard data
  Future<DashboardData> getDashboardData(String storeId, String orgId) async {
    try {
      final results = await Future.wait([
        getLast7DaysSales(storeId),
        getCustomerComparison(storeId, orgId),
        getGrnSummary(storeId),
      ]);

      return DashboardData(
        salesData: results[0] as Last7DaysSalesData,
        customerData: results[1] as CustomerComparisonData,
        grnData: results[2] as GrnSummaryData,
      );
    } catch (e) {
      debugPrint('❌ Get dashboard data error: $e');
      return DashboardData.empty();
    }
  }
}


// ============ DATA MODELS ============

class DashboardData {
  final Last7DaysSalesData salesData;
  final CustomerComparisonData customerData;
  final GrnSummaryData grnData;

  DashboardData({
    required this.salesData,
    required this.customerData,
    required this.grnData,
  });

  factory DashboardData.empty() => DashboardData(
    salesData: Last7DaysSalesData.empty(),
    customerData: CustomerComparisonData.empty(),
    grnData: GrnSummaryData.empty(),
  );
}

class Last7DaysSalesData {
  final List<DailySalesData> dailyData;
  final double totalSales;
  final int totalOrders;
  final double averageBillValue;

  Last7DaysSalesData({
    required this.dailyData,
    required this.totalSales,
    required this.totalOrders,
    required this.averageBillValue,
  });

  factory Last7DaysSalesData.empty() => Last7DaysSalesData(
    dailyData: [],
    totalSales: 0,
    totalOrders: 0,
    averageBillValue: 0,
  );
}

class DailySalesData {
  final DateTime date;
  double totalSales;
  int orderCount;
  double abv;

  DailySalesData({
    required this.date,
    required this.totalSales,
    required this.orderCount,
    this.abv = 0,
  });

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  String get shortDate => '${date.day}/${date.month}';
}

class CustomerComparisonData {
  final int newCustomerOrders;
  final int oldCustomerOrders;
  final double newCustomerSales;
  final double oldCustomerSales;
  final int uniqueNewCustomers;
  final int uniqueOldCustomers;

  CustomerComparisonData({
    required this.newCustomerOrders,
    required this.oldCustomerOrders,
    required this.newCustomerSales,
    required this.oldCustomerSales,
    required this.uniqueNewCustomers,
    required this.uniqueOldCustomers,
  });

  factory CustomerComparisonData.empty() => CustomerComparisonData(
    newCustomerOrders: 0,
    oldCustomerOrders: 0,
    newCustomerSales: 0,
    oldCustomerSales: 0,
    uniqueNewCustomers: 0,
    uniqueOldCustomers: 0,
  );

  int get totalOrders => newCustomerOrders + oldCustomerOrders;
  double get totalSales => newCustomerSales + oldCustomerSales;
  
  double get newCustomerPercentage => 
      totalOrders > 0 ? (newCustomerOrders / totalOrders) * 100 : 0;
  double get oldCustomerPercentage => 
      totalOrders > 0 ? (oldCustomerOrders / totalOrders) * 100 : 0;
}

class GrnSummaryData {
  final int totalCount;
  final double totalValue;
  final int postedCount;
  final List<DailyGrnData> dailyData;

  GrnSummaryData({
    required this.totalCount,
    required this.totalValue,
    required this.postedCount,
    required this.dailyData,
  });

  factory GrnSummaryData.empty() => GrnSummaryData(
    totalCount: 0,
    totalValue: 0,
    postedCount: 0,
    dailyData: [],
  );
}

class DailyGrnData {
  final DateTime date;
  int count;
  double value;

  DailyGrnData({
    required this.date,
    required this.count,
    required this.value,
  });

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  String get shortDate => '${date.day}/${date.month}';
}
