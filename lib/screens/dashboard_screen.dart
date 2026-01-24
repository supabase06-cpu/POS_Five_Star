import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/dashboard_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  
  DashboardData? _dashboardData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final storeId = authProvider.userProfile?.organizationId;
    final orgId = authProvider.userProfile?.organizationId;

    if (storeId == null || orgId == null) {
      setState(() {
        _error = 'Store not configured';
        _isLoading = false;
      });
      return;
    }

    final data = await _dashboardService.getDashboardData(storeId, orgId);
    
    if (mounted) {
      setState(() {
        _dashboardData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: Colors.red[600])))
                    : _buildDashboardContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      color: Colors.orange[600],
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.dashboard, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh',
          ),
          const DebugButton(),
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    if (_dashboardData == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards Row
          _buildSummaryCards(),
          const SizedBox(height: 20),
          // Charts Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sales Chart
              Expanded(
                flex: 3,
                child: _buildSalesChart(),
              ),
              const SizedBox(width: 20),
              // Customer Comparison
              Expanded(
                flex: 2,
                child: _buildCustomerComparison(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // GRN Section
          _buildGrnSection(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final sales = _dashboardData!.salesData;
    final grn = _dashboardData!.grnData;
    final customers = _dashboardData!.customerData;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Sales (7 Days)',
            '₹${_formatAmount(sales.totalSales)}',
            Icons.trending_up,
            Colors.green,
            '${sales.totalOrders} orders',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            'Average Bill Value',
            '₹${_formatAmount(sales.averageBillValue)}',
            Icons.receipt_long,
            Colors.blue,
            'Per order average',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            'GRN Value (7 Days)',
            '₹${_formatAmount(grn.totalValue)}',
            Icons.inventory_2,
            Colors.orange,
            '${grn.totalCount} GRNs',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            'New Customers',
            '${customers.uniqueNewCustomers}',
            Icons.person_add,
            Colors.purple,
            '₹${_formatAmount(customers.newCustomerSales)} sales',
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSalesChart() {
    final sales = _dashboardData!.salesData;
    
    if (sales.dailyData.isEmpty) {
      return _buildEmptyChartCard('Sales Comparison', 'No sales data available');
    }

    final maxSales = sales.dailyData.map((d) => d.totalSales).reduce((a, b) => a > b ? a : b);
    final double maxY = maxSales > 0 ? (maxSales * 1.2) : 1000.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.bar_chart, color: Colors.green[600], size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Last 7 Days Sales',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Total: ₹${_formatAmount(sales.totalSales)}',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 280,
            child: Stack(
              children: [
                BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (group) => Colors.grey[800]!,
                        tooltipPadding: const EdgeInsets.all(8),
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final day = sales.dailyData[group.x.toInt()];
                          return BarTooltipItem(
                            '${day.dayName} ${day.shortDate}\n₹${_formatAmount(day.totalSales)}\n${day.orderCount} orders\nABV: ₹${_formatAmount(day.abv)}',
                            const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < sales.dailyData.length) {
                              final day = sales.dailyData[index];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      day.dayName,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      day.shortDate,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox();
                          },
                          reservedSize: 40,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 60,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '₹${_formatCompact(value)}',
                              style: TextStyle(color: Colors.grey[500], fontSize: 10),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 5,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey[200]!,
                        strokeWidth: 1,
                      ),
                    ),
                    barGroups: sales.dailyData.asMap().entries.map((entry) {
                      final index = entry.key;
                      final day = entry.value;
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: day.totalSales,
                            color: Colors.green[400],
                            width: 28,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maxY,
                              color: Colors.grey[100],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                // Overlay text values on top of bars
                Positioned.fill(
                  child: CustomPaint(
                    painter: BarValuesPainter(
                      salesData: sales.dailyData,
                      maxY: maxY,
                      chartWidth: 280,
                      leftPadding: 60,
                      bottomPadding: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ABV Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: sales.dailyData.map((day) {
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        day.dayName,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${_formatIndianNumber(day.abv.round())}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                      Text(
                        'ABV',
                        style: TextStyle(fontSize: 8, color: Colors.blue[400]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerComparison() {
    final customers = _dashboardData!.customerData;
    
    if (customers.totalOrders == 0) {
      return _buildEmptyChartCard('Customer Analysis', 'No customer data available');
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.people, color: Colors.purple[600], size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'New vs Returning',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(
                    value: customers.newCustomerOrders.toDouble(),
                    title: '${customers.newCustomerPercentage.toStringAsFixed(0)}%',
                    color: Colors.purple[400],
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  PieChartSectionData(
                    value: customers.oldCustomerOrders.toDouble(),
                    title: '${customers.oldCustomerPercentage.toStringAsFixed(0)}%',
                    color: Colors.blue[400],
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend
          _buildCustomerLegendItem(
            'New Customers',
            Colors.purple[400]!,
            customers.newCustomerOrders,
            customers.newCustomerSales,
          ),
          const SizedBox(height: 12),
          _buildCustomerLegendItem(
            'Returning Customers',
            Colors.blue[400]!,
            customers.oldCustomerOrders,
            customers.oldCustomerSales,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total Orders', '${customers.totalOrders}'),
                Container(width: 1, height: 30, color: Colors.grey[300]),
                _buildStatItem('Total Sales', '₹${_formatAmount(customers.totalSales)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerLegendItem(String label, Color color, int orders, double sales) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              Text(
                '$orders orders • ₹${_formatAmount(sales)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }


  Widget _buildGrnSection() {
    final grn = _dashboardData!.grnData;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.inventory_2, color: Colors.orange[600], size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'GRN Summary (Last 7 Days)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${grn.totalCount} GRNs • ₹${_formatAmount(grn.totalValue)}',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (grn.dailyData.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'No GRN data for this period',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                // GRN Stats
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildGrnStatCard(
                          'Total GRNs',
                          '${grn.totalCount}',
                          Icons.receipt_long,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildGrnStatCard(
                          'Total Value',
                          '₹${_formatAmount(grn.totalValue)}',
                          Icons.currency_rupee,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildGrnStatCard(
                          'Posted',
                          '${grn.postedCount}',
                          Icons.check_circle,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Daily GRN Chart
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 120,
                    child: _buildGrnDailyChart(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGrnStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrnDailyChart() {
    final grn = _dashboardData!.grnData;
    
    if (grn.dailyData.isEmpty) return const SizedBox();

    final maxValue = grn.dailyData.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final double maxY = maxValue > 0 ? (maxValue * 1.2) : 1000.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Colors.grey[800]!,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = grn.dailyData[group.x.toInt()];
              return BarTooltipItem(
                '${day.dayName}\n${day.count} GRNs\n₹${_formatAmount(day.value)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < grn.dailyData.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      grn.dailyData[index].dayName,
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 24,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: grn.dailyData.asMap().entries.map((entry) {
          final index = entry.key;
          final day = entry.value;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: day.value,
                color: Colors.orange[400],
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyChartCard(String title, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 40),
          Icon(Icons.bar_chart, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == 0) return '0';
    return _formatIndianNumber(amount.round());
  }

  String _formatCompact(double value) {
    if (value >= 10000000) { // 1 crore
      return '${_formatIndianNumber((value / 10000000).round())}Cr';
    } else if (value >= 100000) { // 1 lakh
      return '${_formatIndianNumber((value / 100000).round())}L';
    } else if (value >= 1000) {
      return '${_formatIndianNumber((value / 1000).round())}K';
    }
    return _formatIndianNumber(value.round());
  }

  String _formatIndianNumber(int number) {
    if (number == 0) return '0';
    
    String numStr = number.toString();
    String result = '';
    
    // Handle negative numbers
    bool isNegative = false;
    if (numStr.startsWith('-')) {
      isNegative = true;
      numStr = numStr.substring(1);
    }
    
    int length = numStr.length;
    
    if (length <= 3) {
      result = numStr;
    } else if (length <= 5) {
      // For 4-5 digits: 12,345
      result = numStr.substring(0, length - 3) + ',' + numStr.substring(length - 3);
    } else if (length <= 7) {
      // For 6-7 digits: 12,34,567
      result = numStr.substring(0, length - 5) + ',' + 
               numStr.substring(length - 5, length - 3) + ',' + 
               numStr.substring(length - 3);
    } else {
      // For 8+ digits: 1,23,45,678
      String lastThree = numStr.substring(length - 3);
      String remaining = numStr.substring(0, length - 3);
      
      result = lastThree;
      
      while (remaining.length > 2) {
        result = remaining.substring(remaining.length - 2) + ',' + result;
        remaining = remaining.substring(0, remaining.length - 2);
      }
      
      if (remaining.isNotEmpty) {
        result = remaining + ',' + result;
      }
    }
    
    return isNegative ? '-$result' : result;
  }
}

class BarValuesPainter extends CustomPainter {
  final List<DailySalesData> salesData;
  final double maxY;
  final double chartWidth;
  final double leftPadding;
  final double bottomPadding;

  BarValuesPainter({
    required this.salesData,
    required this.maxY,
    required this.chartWidth,
    required this.leftPadding,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final chartHeight = size.height - bottomPadding;
    final chartAreaWidth = size.width - leftPadding;
    final barSpacing = chartAreaWidth / salesData.length;

    for (int i = 0; i < salesData.length; i++) {
      final day = salesData[i];
      if (day.totalSales > 0) {
        // Calculate bar top position
        final barHeight = (day.totalSales / maxY) * chartHeight;
        final barTop = chartHeight - barHeight;
        
        // Calculate x position for center of bar
        final barCenterX = leftPadding + (i * barSpacing) + (barSpacing / 2);
        
        // Position text slightly above the bar
        final textY = barTop - 20;
        
        textPainter.text = TextSpan(
          text: '₹${_formatIndianNumberForChart(day.totalSales.round())}',
          style: TextStyle(
            color: Colors.green[700],
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        );
        
        textPainter.layout();
        
        // Center the text horizontally
        final textX = barCenterX - (textPainter.width / 2);
        
        canvas.drawRect(
          Rect.fromLTWH(
            textX - 4,
            textY - 2,
            textPainter.width + 8,
            textPainter.height + 4,
          ),
          Paint()
            ..color = Colors.white.withOpacity(0.9)
            ..style = PaintingStyle.fill,
        );
        
        textPainter.paint(canvas, Offset(textX, textY));
      }
    }
  }

  String _formatIndianNumberForChart(int number) {
    if (number == 0) return '0';
    
    String numStr = number.toString();
    String result = '';
    int length = numStr.length;
    
    if (length <= 3) {
      result = numStr;
    } else if (length == 4) {
      // 1234 -> 1,234
      result = '${numStr[0]},${numStr.substring(1)}';
    } else if (length == 5) {
      // 12345 -> 12,345
      result = '${numStr.substring(0, 2)},${numStr.substring(2)}';
    } else if (length == 6) {
      // 123456 -> 1,23,456
      result = '${numStr[0]},${numStr.substring(1, 3)},${numStr.substring(3)}';
    } else if (length == 7) {
      // 1234567 -> 12,34,567
      result = '${numStr.substring(0, 2)},${numStr.substring(2, 4)},${numStr.substring(4)}';
    } else if (length == 8) {
      // 12345678 -> 1,23,45,678
      result = '${numStr[0]},${numStr.substring(1, 3)},${numStr.substring(3, 5)},${numStr.substring(5)}';
    } else {
      // For larger numbers, use a simple approach
      List<String> parts = [];
      String temp = numStr;
      
      // Add last 3 digits
      parts.insert(0, temp.substring(temp.length - 3));
      temp = temp.substring(0, temp.length - 3);
      
      // Add groups of 2 digits
      while (temp.length > 2) {
        parts.insert(0, temp.substring(temp.length - 2));
        temp = temp.substring(0, temp.length - 2);
      }
      
      // Add remaining digits
      if (temp.isNotEmpty) {
        parts.insert(0, temp);
      }
      
      result = parts.join(',');
    }
    
    return result;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
