class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final String? organizationId;
  final String role;
  final bool isActive;
  final DateTime? lastLogin;
  final List<String> permissions;
  final OrganizationInfo? organization;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.organizationId,
    required this.role,
    required this.isActive,
    this.lastLogin,
    required this.permissions,
    this.organization,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'],
      organizationId: json['org_id'],
      role: json['role_key'] ?? 'cashier',
      isActive: json['is_active'] ?? false,
      lastLogin: json['last_login_at'] != null 
        ? DateTime.parse(json['last_login_at']) 
        : null,
      permissions: List<String>.from(json['permissions'] ?? []),
      organization: json['organization'] != null 
        ? OrganizationInfo.fromJson(json['organization']) 
        : null,
    );
  }

  bool hasPermission(String permission) {
    return permissions.contains(permission) || permissions.contains('all');
  }

  // Updated POS access logic to work with your permission format
  bool get canAccessPOS {
    // Check for explicit pos_access permission
    if (hasPermission('pos_access')) return true;
    
    // Check for billing permissions (which indicates POS access)
    if (permissions.any((p) => p.startsWith('billing.') && p.endsWith('.true'))) return true;
    
    // Admin and manager roles should have POS access
    if (role == 'org_admin' || role == 'admin' || role == 'manager') return true;
    
    return false;
  }
  
  bool get canProcessPayments => hasPermission('process_payments') || 
    permissions.any((p) => p.startsWith('billing.') && p.endsWith('.true'));
  bool get canViewReports => hasPermission('view_reports') || 
    permissions.any((p) => p.startsWith('reports.') && p.endsWith('.true'));
  bool get canManageInventory => hasPermission('manage_inventory') || 
    permissions.any((p) => p.startsWith('inventory.') && p.endsWith('.true'));
  bool get canManageUsers => hasPermission('manage_users') || role == 'org_admin' || role == 'admin';
  bool get isManager => role == 'manager' || role == 'admin';
  bool get isAdmin => role == 'admin';
}

class OrganizationInfo {
  final String id;
  final String name;
  final String subscriptionStatus;
  final DateTime? subscriptionExpiryDate;
  final String planType;
  final bool isActive;
  final int maxUsers;
  final int currentUsers;
  final List<String> features;

  OrganizationInfo({
    required this.id,
    required this.name,
    required this.subscriptionStatus,
    this.subscriptionExpiryDate,
    required this.planType,
    required this.isActive,
    required this.maxUsers,
    required this.currentUsers,
    required this.features,
  });

  factory OrganizationInfo.fromJson(Map<String, dynamic> json) {
    return OrganizationInfo(
      id: json['id'] ?? '',
      name: json['org_name'] ?? '',
      subscriptionStatus: json['subscription_tier'] ?? 'basic',
      subscriptionExpiryDate: null, // You'll need to join with subscriptions table for this
      planType: json['subscription_tier'] ?? 'basic',
      isActive: json['is_active'] ?? false,
      maxUsers: 5, // Default, you can get this from subscriptions table
      currentUsers: 0, // You'll need to count from app_users table
      features: [], // You can define features based on subscription_tier
    );
  }

  bool get hasActiveSubscription {
    if (subscriptionStatus != 'active') return false;
    if (subscriptionExpiryDate == null) return true;
    return DateTime.now().isBefore(subscriptionExpiryDate!);
  }

  bool get canAddMoreUsers => currentUsers < maxUsers;
  
  bool hasFeature(String feature) {
    return features.contains(feature);
  }

  String get subscriptionStatusMessage {
    switch (subscriptionStatus) {
      case 'active':
        if (subscriptionExpiryDate != null) {
          final daysLeft = subscriptionExpiryDate!.difference(DateTime.now()).inDays;
          if (daysLeft <= 7) {
            return 'Subscription expires in $daysLeft days';
          }
        }
        return 'Active subscription';
      case 'expired':
        return 'Subscription has expired';
      case 'cancelled':
        return 'Subscription cancelled';
      case 'suspended':
        return 'Account suspended';
      default:
        return 'No active subscription';
    }
  }
}