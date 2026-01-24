import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all users for organization
  Future<List<AppUser>> getUsers(String orgId, {String? searchQuery, String? roleFilter, bool? activeOnly}) async {
    try {
      debugPrint('🔍 Fetching users for org: $orgId');
      
      var query = _supabase
          .from('app_users')
          .select('*, stores(store_name)')
          .eq('org_id', orgId);

      if (activeOnly == true) {
        query = query.eq('is_active', true);
      }

      if (roleFilter != null && roleFilter.isNotEmpty) {
        query = query.eq('role_key', roleFilter);
      }

      final response = await query.order('full_name');
      
      List<AppUser> users = response.map<AppUser>((u) => AppUser.fromMap(u)).toList();
      
      // Apply search filter locally for better flexibility
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        users = users.where((u) =>
            u.fullName.toLowerCase().contains(lowerQuery) ||
            u.username.toLowerCase().contains(lowerQuery) ||
            u.email.toLowerCase().contains(lowerQuery) ||
            (u.phone?.contains(searchQuery) ?? false) ||
            (u.employeeCode?.toLowerCase().contains(lowerQuery) ?? false)
        ).toList();
      }

      debugPrint('📦 Users loaded: ${users.length}');
      return users;
    } catch (e) {
      debugPrint('❌ Get users error: $e');
      return [];
    }
  }

  /// Get user by ID
  Future<AppUser?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('app_users')
          .select('*, stores(store_name)')
          .eq('id', userId)
          .single();
      
      return AppUser.fromMap(response);
    } catch (e) {
      debugPrint('❌ Get user error: $e');
      return null;
    }
  }

  /// Get available roles
  Future<List<Role>> getRoles() async {
    try {
      final response = await _supabase
          .from('roles')
          .select()
          .eq('is_active', true)
          .order('level');
      
      return response.map<Role>((r) => Role.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Get roles error: $e');
      return [];
    }
  }

  /// Get user statistics for org
  Future<UserStats> getUserStats(String orgId) async {
    try {
      final response = await _supabase
          .from('app_users')
          .select('id, is_active, role_key, last_login_at')
          .eq('org_id', orgId);

      int totalUsers = response.length;
      int activeUsers = 0;
      int inactiveUsers = 0;
      int recentlyActive = 0;
      final Map<String, int> roleCount = {};

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      for (var row in response) {
        if (row['is_active'] == true) {
          activeUsers++;
        } else {
          inactiveUsers++;
        }

        final roleKey = row['role_key'] as String? ?? 'unknown';
        roleCount[roleKey] = (roleCount[roleKey] ?? 0) + 1;

        final lastLogin = row['last_login_at'] as String?;
        if (lastLogin != null) {
          final loginDate = DateTime.tryParse(lastLogin);
          if (loginDate != null && loginDate.isAfter(sevenDaysAgo)) {
            recentlyActive++;
          }
        }
      }

      return UserStats(
        totalUsers: totalUsers,
        activeUsers: activeUsers,
        inactiveUsers: inactiveUsers,
        recentlyActive: recentlyActive,
        roleCount: roleCount,
      );
    } catch (e) {
      debugPrint('❌ Get user stats error: $e');
      return UserStats.empty();
    }
  }

  /// Toggle user active status
  Future<bool> toggleUserStatus(String userId, bool isActive) async {
    try {
      await _supabase
          .from('app_users')
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      
      debugPrint('✅ User status updated: $userId -> $isActive');
      return true;
    } catch (e) {
      debugPrint('❌ Toggle user status error: $e');
      return false;
    }
  }
}

// ============ DATA MODELS ============

class AppUser {
  final String id;
  final String orgId;
  final String? storeId;
  final String? storeName;
  final String username;
  final String email;
  final String fullName;
  final String? employeeCode;
  final String? phone;
  final String roleKey;
  final String? profileImageUrl;
  final DateTime? dateOfBirth;
  final DateTime? dateOfJoining;
  final String? emergencyContact;
  final bool isActive;
  final DateTime? lastLoginAt;
  final bool forcePasswordChange;
  final int failedLoginAttempts;
  final DateTime? accountLockedUntil;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.orgId,
    this.storeId,
    this.storeName,
    required this.username,
    required this.email,
    required this.fullName,
    this.employeeCode,
    this.phone,
    required this.roleKey,
    this.profileImageUrl,
    this.dateOfBirth,
    this.dateOfJoining,
    this.emergencyContact,
    required this.isActive,
    this.lastLoginAt,
    this.forcePasswordChange = false,
    this.failedLoginAttempts = 0,
    this.accountLockedUntil,
    required this.permissions,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      orgId: map['org_id'] as String,
      storeId: map['store_id'] as String?,
      storeName: map['stores']?['store_name'] as String?,
      username: map['username'] as String,
      email: map['email'] as String,
      fullName: map['full_name'] as String,
      employeeCode: map['employee_code'] as String?,
      phone: map['phone'] as String?,
      roleKey: map['role_key'] as String,
      profileImageUrl: map['profile_image_url'] as String?,
      dateOfBirth: map['date_of_birth'] != null ? DateTime.tryParse(map['date_of_birth']) : null,
      dateOfJoining: map['date_of_joining'] != null ? DateTime.tryParse(map['date_of_joining']) : null,
      emergencyContact: map['emergency_contact'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      lastLoginAt: map['last_login_at'] != null ? DateTime.tryParse(map['last_login_at']) : null,
      forcePasswordChange: map['force_password_change'] as bool? ?? false,
      failedLoginAttempts: map['failed_login_attempts'] as int? ?? 0,
      accountLockedUntil: map['account_locked_until'] != null ? DateTime.tryParse(map['account_locked_until']) : null,
      permissions: (map['permissions'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(map['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  String get roleDisplayName {
    switch (roleKey) {
      case 'super_admin': return 'Super Admin';
      case 'org_admin': return 'Org Admin';
      case 'store_manager': return 'Store Manager';
      case 'cashier': return 'Cashier';
      case 'kitchen_staff': return 'Kitchen Staff';
      default: return roleKey.replaceAll('_', ' ').toUpperCase();
    }
  }

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.substring(0, fullName.length >= 2 ? 2 : 1).toUpperCase();
  }

  bool get isLocked => accountLockedUntil != null && accountLockedUntil!.isAfter(DateTime.now());
}

class Role {
  final String id;
  final String roleKey;
  final String roleName;
  final String? description;
  final int level;
  final bool isSystemRole;
  final bool isActive;

  Role({
    required this.id,
    required this.roleKey,
    required this.roleName,
    this.description,
    required this.level,
    this.isSystemRole = false,
    this.isActive = true,
  });

  factory Role.fromMap(Map<String, dynamic> map) {
    return Role(
      id: map['id'] as String,
      roleKey: map['role_key'] as String,
      roleName: map['role_name'] as String,
      description: map['description'] as String?,
      level: map['level'] as int,
      isSystemRole: map['is_system_role'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

class UserStats {
  final int totalUsers;
  final int activeUsers;
  final int inactiveUsers;
  final int recentlyActive;
  final Map<String, int> roleCount;

  UserStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.inactiveUsers,
    required this.recentlyActive,
    required this.roleCount,
  });

  factory UserStats.empty() => UserStats(
    totalUsers: 0,
    activeUsers: 0,
    inactiveUsers: 0,
    recentlyActive: 0,
    roleCount: {},
  );
}
