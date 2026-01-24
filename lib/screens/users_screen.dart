import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/user_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_panel.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();
  
  List<AppUser> _users = [];
  List<Role> _roles = [];
  UserStats? _stats;
  bool _isLoading = true;
  String? _selectedRole;
  bool _showActiveOnly = false;
  String? _orgId;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orgId = authProvider.userProfile?.organizationId;
    
    if (_orgId == null) {
      setState(() => _isLoading = false);
      return;
    }

    await Future.wait([
      _loadUsers(),
      _loadRoles(),
      _loadStats(),
    ]);
  }

  Future<void> _loadUsers() async {
    if (_orgId == null) return;
    
    setState(() => _isLoading = true);
    
    final users = await _userService.getUsers(
      _orgId!,
      searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
      roleFilter: _selectedRole,
      activeOnly: _showActiveOnly ? true : null,
    );
    
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRoles() async {
    final roles = await _userService.getRoles();
    if (mounted) {
      setState(() => _roles = roles);
    }
  }

  Future<void> _loadStats() async {
    if (_orgId == null) return;
    final stats = await _userService.getUserStats(_orgId!);
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  Future<void> _toggleUserStatus(AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.isActive ? 'Deactivate User' : 'Activate User'),
        content: Text(
          user.isActive
              ? 'Are you sure you want to deactivate ${user.fullName}? They will not be able to login.'
              : 'Are you sure you want to activate ${user.fullName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: user.isActive ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(user.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _userService.toggleUserStatus(user.id, !user.isActive);
      if (success) {
        _loadUsers();
        _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${user.fullName} has been ${user.isActive ? 'deactivated' : 'activated'}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
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
            child: _isLoading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(),
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
                    child: const Icon(Icons.people, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'User Management',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadUsers();
              _loadStats();
            },
            tooltip: 'Refresh',
          ),
          const DebugButton(),
          const WindowControls(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Stats Cards
          if (_stats != null) _buildStatsRow(),
          const SizedBox(height: 20),
          // Filters and Search
          _buildFiltersRow(),
          const SizedBox(height: 16),
          // Users List
          Expanded(child: _buildUsersList()),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Users',
            '${_stats!.totalUsers}',
            Icons.people,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Active',
            '${_stats!.activeUsers}',
            Icons.check_circle,
            Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Inactive',
            '${_stats!.inactiveUsers}',
            Icons.cancel,
            Colors.red,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Active (7 days)',
            '${_stats!.recentlyActive}',
            Icons.access_time,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildFiltersRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, email, phone...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[400]),
                        onPressed: () {
                          _searchController.clear();
                          _loadUsers();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                if (value.isEmpty || value.length >= 2) {
                  _loadUsers();
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          // Role Filter
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRole,
                  hint: const Text('All Roles'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Roles')),
                    ..._roles.map((role) => DropdownMenuItem(
                      value: role.roleKey,
                      child: Text(role.roleName),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedRole = value);
                    _loadUsers();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Active Only Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _showActiveOnly ? Colors.green[50] : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: _showActiveOnly ? Border.all(color: Colors.green[300]!) : null,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _showActiveOnly,
                  onChanged: (value) {
                    setState(() => _showActiveOnly = value ?? false);
                    _loadUsers();
                  },
                  activeColor: Colors.green,
                ),
                Text(
                  'Active Only',
                  style: TextStyle(
                    color: _showActiveOnly ? Colors.green[700] : Colors.grey[600],
                    fontWeight: _showActiveOnly ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // User Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_users.length} users',
              style: TextStyle(
                color: Colors.blue[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(fontSize: 18, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 50), // Avatar space
                const Expanded(flex: 3, child: Text('User', style: TextStyle(fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('Role', style: TextStyle(fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('Contact', style: TextStyle(fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('Last Login', style: TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 100, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 60), // Actions
              ],
            ),
          ),
          const Divider(height: 1),
          // User Rows
          Expanded(
            child: ListView.separated(
              itemCount: _users.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _buildUserRow(_users[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(AppUser user) {
    return InkWell(
      onTap: () => _showUserDetails(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: user.isActive ? Colors.orange[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: user.profileImageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        user.profileImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            user.initials,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: user.isActive ? Colors.orange[700] : Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: user.isActive ? Colors.orange[700] : Colors.grey[500],
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // User Info
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: user.isActive ? Colors.grey[800] : Colors.grey[500],
                        ),
                      ),
                      if (user.isLocked) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock, size: 14, color: Colors.red[400]),
                      ],
                    ],
                  ),
                  Text(
                    user.email,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.employeeCode != null)
                    Text(
                      'ID: ${user.employeeCode}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
            // Role
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getRoleColor(user.roleKey).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  user.roleDisplayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _getRoleColor(user.roleKey),
                  ),
                ),
              ),
            ),
            // Contact
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user.phone != null)
                    Text(
                      user.phone!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  Text(
                    user.storeName ?? 'All Stores',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            // Last Login
            Expanded(
              flex: 2,
              child: Text(
                user.lastLoginAt != null
                    ? _formatDateTime(user.lastLoginAt!)
                    : 'Never',
                style: TextStyle(
                  fontSize: 12,
                  color: user.lastLoginAt != null ? Colors.grey[600] : Colors.grey[400],
                ),
              ),
            ),
            // Status
            SizedBox(
              width: 100,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isActive ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: user.isActive ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: user.isActive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            SizedBox(
              width: 60,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey[500]),
                onSelected: (value) {
                  if (value == 'toggle') {
                    _toggleUserStatus(user);
                  } else if (value == 'details') {
                    _showUserDetails(user);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18),
                        SizedBox(width: 8),
                        Text('View Details'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          user.isActive ? Icons.block : Icons.check_circle_outline,
                          size: 18,
                          color: user.isActive ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(user.isActive ? 'Deactivate' : 'Activate'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetails(AppUser user) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: user.isActive ? Colors.orange[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: user.isActive ? Colors.orange[700] : Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          user.roleDisplayName,
                          style: TextStyle(color: _getRoleColor(user.roleKey)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: user.isActive ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: user.isActive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _buildDetailRow('Username', user.username),
              _buildDetailRow('Email', user.email),
              if (user.phone != null) _buildDetailRow('Phone', user.phone!),
              if (user.employeeCode != null) _buildDetailRow('Employee Code', user.employeeCode!),
              if (user.storeName != null) _buildDetailRow('Store', user.storeName!),
              if (user.dateOfJoining != null) 
                _buildDetailRow('Joined', _formatDate(user.dateOfJoining!)),
              _buildDetailRow('Last Login', 
                user.lastLoginAt != null ? _formatDateTime(user.lastLoginAt!) : 'Never'),
              const SizedBox(height: 16),
              if (user.permissions.isNotEmpty) ...[
                const Text('Permissions', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: user.permissions.map((p) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                    ),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String roleKey) {
    switch (roleKey) {
      case 'super_admin': return Colors.red[700]!;
      case 'org_admin': return Colors.purple[700]!;
      case 'store_manager': return Colors.blue[700]!;
      case 'cashier': return Colors.green[700]!;
      case 'kitchen_staff': return Colors.orange[700]!;
      default: return Colors.grey[700]!;
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
