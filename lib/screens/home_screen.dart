import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/realtime_service.dart';
import '../services/offline_sync_service.dart';
import '../services/sales_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';
import 'billing_screen.dart';
import 'products_screen.dart';
import 'inward_screen.dart';
import 'dashboard_screen.dart';
import 'users_screen.dart';
import 'simple_write_off_screen.dart';
import 'printer_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OfflineSyncService _offlineSync = OfflineSyncService();
  final SalesService _salesService = SalesService();
  OfflineSyncStatus _syncStatus = OfflineSyncStatus();
  bool _isInitializing = true;
  Timer? _connectivityTimer;
  
  // Dashboard data
  OrdersSummary? _todaysSummary;
  bool _isDashboardLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeOfflineSync();
    
    // Listen for status changes
    _offlineSync.onStatusChanged = (status) {
      if (mounted) {
        setState(() => _syncStatus = status);
      }
    };

    // Listen for connectivity restoration to trigger immediate sync
    _offlineSync.onConnectivityRestored = () async {
      debugPrint('🔄 Connectivity restored - triggering immediate order sync');
      try {
        await _salesService.syncPendingOrders();
        debugPrint('✅ Immediate order sync completed');
      } catch (e) {
        debugPrint('❌ Immediate order sync failed: $e');
      }
    };

    // Check connectivity every 5 seconds
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectivity();
    });
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final wasOnline = _syncStatus.isOnline;
    final isOnline = await _offlineSync.isOnline();
    
    if (mounted && wasOnline != isOnline) {
      setState(() {
        _syncStatus.isOnline = isOnline;
      });
    }
  }

  Future<void> _initializeOfflineSync() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orgId = authProvider.userProfile?.organizationId;
    final storeId = orgId; // Using org_id as store_id
    
    if (orgId != null && storeId != null) {
      final status = await _offlineSync.initializeOfflineData(orgId, storeId);
      _offlineSync.startBackgroundSync(orgId, storeId);
      
      // Load today's sales data
      await _loadTodaysSales(storeId);
      
      if (mounted) {
        setState(() {
          _syncStatus = status;
          _isInitializing = false;
        });
      }
    } else {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _loadTodaysSales(String storeId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);
      
      final summary = await _salesService.getOrdersByDateRange(storeId, startOfDay, endOfDay);
      
      if (mounted) {
        setState(() {
          _todaysSummary = summary;
          _isDashboardLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading today\'s sales: $e');
      if (mounted) {
        setState(() {
          _isDashboardLoading = false;
        });
      }
    }
  }

  Future<void> _syncNow() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orgId = authProvider.userProfile?.organizationId;
    final storeId = orgId;
    
    if (orgId != null && storeId != null) {
      await _offlineSync.syncNow(orgId, storeId);
    }
  }

  void _showOfflineDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _syncStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _syncStatus.isOnline ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(_syncStatus.isOnline ? 'Ready for Offline' : 'Offline Mode'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.inventory_2, 'Products', '${_syncStatus.productsCount} items loaded'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _buildDetailRow(
                Icons.settings_input_component, 
                'Raw Material Mapping', 
                '${_syncStatus.productsWithMappingCount} of ${_syncStatus.productsCount} products',
                isSubItem: true,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.category, 'Categories', '${_syncStatus.categoriesCount} loaded'),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.people, 'Customers', '${_syncStatus.customersCount} records loaded'),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.image, 'Images', '${_syncStatus.cachedImagesCount} cached'),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.receipt, 'Last Invoice', _syncStatus.lastInvoiceNumber ?? 'N/A'),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.sync, 'Last Sync', _syncStatus.lastSyncText),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _syncStatus.isOnline ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _syncStatus.isOnline ? Icons.check_circle : Icons.info,
                    color: _syncStatus.isOnline ? Colors.green[700] : Colors.orange[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _syncStatus.isOnline 
                          ? 'All data synced. You can work offline anytime.'
                          : 'Working offline. Orders will sync when online.',
                      style: TextStyle(
                        color: _syncStatus.isOnline ? Colors.green[700] : Colors.orange[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_syncStatus.isOnline)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _syncNow();
              },
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Sync Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isSubItem = false}) {
    return Row(
      children: [
        Icon(
          icon, 
          size: isSubItem ? 16 : 20, 
          color: isSubItem ? Colors.grey[500] : Colors.grey[600]
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label, 
                style: TextStyle(
                  fontSize: isSubItem ? 11 : 12, 
                  color: isSubItem ? Colors.grey[500] : Colors.grey[600]
                )
              ),
              Text(
                value, 
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isSubItem ? 13 : 14,
                  color: isSubItem ? Colors.grey[700] : Colors.black87,
                )
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: GestureDetector(
        onTap: () {
          // Update activity on any tap
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          authProvider.updateActivity();
        },
        child: Column(
          children: [
            // Combined header with title bar and app content
            _buildHeader(context),
            // Body content
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56,
      color: Colors.orange[600],
      child: Row(
        children: [
          // Logo and drag area
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  // Simple star logo
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.star,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Five Star Chicken',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Offline Ready Status
          InkWell(
            onTap: _showOfflineDetails,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isInitializing 
                    ? Colors.grey.withOpacity(0.9)
                    : _syncStatus.isReady 
                        ? (_syncStatus.isOnline ? Colors.green.withOpacity(0.9) : Colors.orange.withOpacity(0.9))
                        : Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isInitializing || _syncStatus.isLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else
                    Icon(
                      _syncStatus.isReady 
                          ? (_syncStatus.isOnline ? Icons.cloud_done : Icons.cloud_off)
                          : Icons.cloud_off,
                      size: 14,
                      color: Colors.white,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    _isInitializing 
                        ? 'Loading...'
                        : _syncStatus.isReady 
                            ? (_syncStatus.isOnline ? 'Ready for Offline' : 'Offline Mode')
                            : 'Not Ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_syncStatus.isReady && !_isInitializing) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_syncStatus.productsCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Realtime connection status
          Consumer<RealtimeService>(
            builder: (context, realtimeService, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: realtimeService.isConnected 
                      ? Colors.green.withOpacity(0.9) 
                      : Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      realtimeService.isConnected ? Icons.wifi : Icons.wifi_off,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      realtimeService.isConnected ? 'LIVE' : 'OFFLINE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // User menu
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'logout') {
                    _showLogoutDialog(context, authProvider);
                  }
                },
                offset: const Offset(0, 50),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('Version 1.0.6', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout, size: 20),
                        const SizedBox(width: 8),
                        const Text('Logout'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 16,
                        child: Icon(Icons.person, color: Colors.orange[600], size: 20),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authProvider.userProfile?.fullName ?? 'User',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            authProvider.userProfile?.role.toUpperCase() ?? 'USER',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.8), size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Debug button (developer mode)
          const DebugButton(),
          // Window controls
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final userProfile = authProvider.userProfile;
        final organization = authProvider.organization;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact Hero Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange[600]!,
                      Colors.orange[400]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Compact Profile
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.person, size: 24, color: Colors.orange[600]),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Compact Welcome
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${userProfile?.fullName?.split(' ').first ?? 'User'}!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${userProfile?.role.toUpperCase() ?? 'USER'} • ${organization?.name ?? 'Five Star Chicken'}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Compact Status
                    if (organization != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              organization.planType.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${organization.currentUsers}/${organization.maxUsers} Users',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Two Column Layout: Quick Actions + Dashboard
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side - Quick Actions
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 3,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.orange[600],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 600 ? 4 : 
                                               constraints.maxWidth > 450 ? 3 : 2;
                            
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.1,
                              children: _buildCompactActionCards(context, authProvider, userProfile),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Right Side - Dashboard
                  Expanded(
                    flex: 1,
                    child: _buildDashboardPanel(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Today\'s Dashboard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_isDashboardLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Sales Stats
          _buildDashboardCard(
            'Today\'s Sales',
            '₹${(_todaysSummary?.totalSales ?? 0).toStringAsFixed(0)}',
            Icons.trending_up,
            Colors.green,
            '${_todaysSummary?.totalOrders ?? 0} orders',
          ),
          const SizedBox(height: 10),
          
          _buildDashboardCard(
            'Total Bills',
            '${_todaysSummary?.totalOrders ?? 0}',
            Icons.receipt_long,
            Colors.blue,
            'Orders today',
          ),
          const SizedBox(height: 10),
          
          _buildDashboardCard(
            'Average Bill',
            '₹${_todaysSummary != null && _todaysSummary!.totalOrders > 0 ? (_todaysSummary!.totalSales / _todaysSummary!.totalOrders).toStringAsFixed(0) : '0'}',
            Icons.analytics,
            Colors.purple,
            'Per transaction',
          ),
          const SizedBox(height: 10),
          
          // Payment breakdown
          if (_todaysSummary != null && _todaysSummary!.totalSales > 0) ...[
            _buildDashboardCard(
              'Cash Sales',
              '₹${_todaysSummary!.cashSales.toStringAsFixed(0)}',
              Icons.money,
              Colors.teal,
              '${((_todaysSummary!.cashSales / _todaysSummary!.totalSales) * 100).toStringAsFixed(0)}% of total',
            ),
            const SizedBox(height: 10),
            
            _buildDashboardCard(
              'UPI Sales',
              '₹${_todaysSummary!.upiSales.toStringAsFixed(0)}',
              Icons.qr_code,
              Colors.indigo,
              '${((_todaysSummary!.upiSales / _todaysSummary!.totalSales) * 100).toStringAsFixed(0)}% of total',
            ),
            const SizedBox(height: 10),
          ],
          
          _buildDashboardCard(
            'Products',
            '${_syncStatus.productsCount}',
            Icons.inventory,
            Colors.orange,
            _syncStatus.isOnline ? 'Online' : 'Offline',
          ),
          
          const SizedBox(height: 16),
          
          // Quick Status
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _syncStatus.isOnline ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _syncStatus.isOnline ? Colors.green[200]! : Colors.orange[200]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _syncStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: _syncStatus.isOnline ? Colors.green[600] : Colors.orange[600],
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _syncStatus.isOnline ? 'System Online' : 'Offline Mode',
                    style: TextStyle(
                      color: _syncStatus.isOnline ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCompactActionCards(BuildContext context, AuthProvider authProvider, userProfile) {
    List<Widget> cards = [];
    
    if (authProvider.canProcessPayments || 
        (userProfile?.permissions.any((String p) => p.startsWith('billing.') && p.endsWith('.true')) ?? false)) {
      cards.add(_buildCompactActionCard('Billing', 'Process sales & payments', Icons.point_of_sale, Colors.green,
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BillingScreen()))));
    }
    
    if (authProvider.canManageInventory || 
        (userProfile?.permissions.any((String p) => p.startsWith('inward.') && p.endsWith('.true')) ?? false)) {
      cards.add(_buildCompactActionCard('Inward', 'Manage stock inward', Icons.inventory_2, Colors.teal,
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => const InwardScreen()))));
    }

    if (userProfile?.permissions.any((String p) => p == 'writeoff.store.true') ?? false) {
      cards.add(_buildCompactActionCard('Write Off', 'Manage damaged/expired inventory', Icons.delete_outline, Colors.red,
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SimpleWriteOffScreen()))));
    }
    
    if (authProvider.canViewReports) {
      cards.add(_buildCompactActionCard('Reports', 'View analytics & reports', Icons.analytics, Colors.orange,
        () => _showComingSoon(context)));
    }
    
    if (userProfile?.permissions.any((String p) => p == 'products.store.true') ?? false) {
      cards.add(_buildCompactActionCard('Products', 'Manage product catalog', Icons.inventory, Colors.indigo,
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProductsScreen()))));
    }
    
    cards.add(_buildCompactActionCard('Dashboard', 'View detailed analytics', Icons.dashboard, Colors.purple,
      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardScreen()))));
    
    cards.add(_buildCompactActionCard('Printer', 'Configure POS printers', Icons.print, Colors.brown,
      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PrinterSettingsScreen()))));
    
    if (authProvider.canManageUsers || 
        (userProfile?.permissions.any((String p) => p == 'user_management.store.true') ?? false)) {
      cards.add(_buildCompactActionCard('Users', 'Manage user accounts', Icons.people, Colors.deepPurple,
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UsersScreen()))));
    }
    
    return cards;
  }

  Widget _buildCompactActionCard(String title, String description, IconData icon, Color color, VoidCallback onTap) {
    // Check if user is offline and this is not Billing or Printer
    final bool isOfflineRestricted = !_syncStatus.isOnline && 
                                   title != 'Billing' && 
                                   title != 'Printer';
    
    return Container(
      decoration: BoxDecoration(
        color: isOfflineRestricted ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOfflineRestricted ? Colors.grey[300]! : Colors.grey[200]!
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isOfflineRestricted ? 0.02 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isOfflineRestricted ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: isOfflineRestricted ? null : color.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(18.1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(13.7),
                  decoration: BoxDecoration(
                    color: isOfflineRestricted 
                        ? Colors.grey[300]!.withOpacity(0.5)
                        : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOfflineRestricted ? Icons.lock_outline : icon, 
                    size: 27, 
                    color: isOfflineRestricted ? Colors.grey[500] : color
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isOfflineRestricted ? Colors.grey[500] : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  isOfflineRestricted 
                      ? 'Not Supported for Offline'
                      : description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOfflineRestricted ? Colors.grey[500] : Colors.grey[600],
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feature coming soon!'), backgroundColor: Colors.orange),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              authProvider.signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
