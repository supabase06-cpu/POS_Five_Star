import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionMonitorService {
  static final SessionMonitorService _instance = SessionMonitorService._internal();
  factory SessionMonitorService() => _instance;
  SessionMonitorService._internal();

  Timer? _sessionTimer;
  Timer? _subscriptionTimer;
  Function? onSessionExpired;
  Function? onSubscriptionExpired;
  
  static const String _lastActivityKey = 'last_activity';
  static const String _subscriptionCacheKey = 'subscription_cache';
  static const String _lastSubscriptionCheckKey = 'last_subscription_check';

  /// Initialize session monitoring
  void startSessionMonitoring({
    Function? onExpired,
    Function? onSubscriptionExpired,
  }) {
    this.onSessionExpired = onExpired;
    this.onSubscriptionExpired = onSubscriptionExpired;
    
    _updateLastActivity();
    _startSessionTimer();
    _startSubscriptionTimer();
    
    debugPrint('🔐 Session monitoring started');
  }

  /// Stop session monitoring
  void stopSessionMonitoring() {
    _sessionTimer?.cancel();
    _subscriptionTimer?.cancel();
    debugPrint('🔐 Session monitoring stopped');
  }

  /// Update last activity timestamp
  void updateActivity() {
    _updateLastActivity();
  }

  /// Start the session timer that checks every minute
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkSessionExpiry();
    });
  }

  /// Start the subscription timer that checks every hour
  void _startSubscriptionTimer() {
    _subscriptionTimer?.cancel();
    _subscriptionTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkSubscriptionStatus();
    });
  }

  /// Update last activity timestamp
  Future<void> _updateLastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Check if session should be expired (daily 2AM-3AM auto logout)
  Future<void> _checkSessionExpiry() async {
    final now = DateTime.now();
    
    // Check if current time is between 2AM and 3AM
    if (now.hour >= 2 && now.hour < 3) {
      final prefs = await SharedPreferences.getInstance();
      final lastActivityMs = prefs.getInt(_lastActivityKey) ?? 0;
      final lastActivity = DateTime.fromMillisecondsSinceEpoch(lastActivityMs);
      
      // If last activity was before today's 2AM, force logout
      final today2AM = DateTime(now.year, now.month, now.day, 2, 0, 0);
      
      if (lastActivity.isBefore(today2AM)) {
        debugPrint('🔐 Auto logout triggered - Daily session reset (2AM-3AM)');
        onSessionExpired?.call();
        return;
      }
    }
    
    // Also check for 24-hour inactivity (backup check)
    final prefs = await SharedPreferences.getInstance();
    final lastActivityMs = prefs.getInt(_lastActivityKey) ?? 0;
    final lastActivity = DateTime.fromMillisecondsSinceEpoch(lastActivityMs);
    final hoursSinceActivity = now.difference(lastActivity).inHours;
    
    if (hoursSinceActivity >= 24) {
      debugPrint('🔐 Auto logout triggered - 24 hours of inactivity');
      onSessionExpired?.call();
    }
  }

  /// Check subscription status
  Future<void> _checkSubscriptionStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get user's org_id from metadata or profile
      final orgId = await _getUserOrgId();
      if (orgId == null) return;

      // Check if we need to refresh subscription data
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastSubscriptionCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check subscription every 6 hours or on first run
      if (now - lastCheck < (6 * 60 * 60 * 1000) && lastCheck > 0) {
        // Use cached data if recent
        final cachedData = prefs.getString(_subscriptionCacheKey);
        if (cachedData != null) {
          final subscription = jsonDecode(cachedData);
          _validateSubscription(subscription);
          return;
        }
      }

      // Fetch fresh subscription data
      final subscription = await _fetchSubscriptionData(orgId);
      if (subscription != null) {
        // Cache the subscription data
        await prefs.setString(_subscriptionCacheKey, jsonEncode(subscription));
        await prefs.setInt(_lastSubscriptionCheckKey, now);
        
        _validateSubscription(subscription);
      }
      
    } catch (e) {
      debugPrint('❌ Error checking subscription: $e');
      // On error, use cached data if available
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_subscriptionCacheKey);
      if (cachedData != null) {
        final subscription = jsonDecode(cachedData);
        _validateSubscription(subscription);
      }
    }
  }

  /// Get user's organization ID
  Future<String?> _getUserOrgId() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      // Try to get from user metadata first
      final orgId = user.userMetadata?['org_id'] as String?;
      if (orgId != null) return orgId;

      // Fallback: Query user profile
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('organization_id')
          .eq('user_id', user.id)
          .single();

      return response['organization_id'] as String?;
    } catch (e) {
      debugPrint('❌ Error getting org_id: $e');
      return null;
    }
  }

  /// Fetch subscription data from database
  Future<Map<String, dynamic>?> _fetchSubscriptionData(String orgId) async {
    try {
      final response = await Supabase.instance.client
          .from('subscriptions')
          .select('*')
          .eq('org_id', orgId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching subscription: $e');
      return null;
    }
  }

  /// Validate subscription and trigger actions if needed
  void _validateSubscription(Map<String, dynamic> subscription) {
    try {
      final status = subscription['status'] as String?;
      final expiryDateStr = subscription['expiry_date'] as String?;
      final gracePeriodDays = subscription['grace_period_days'] as int? ?? 7;
      
      if (expiryDateStr == null) return;
      
      final expiryDate = DateTime.parse(expiryDateStr);
      final now = DateTime.now();
      final graceEndDate = expiryDate.add(Duration(days: gracePeriodDays));
      
      debugPrint('🔐 Subscription check: Status=$status, Expiry=$expiryDateStr, Grace ends=${graceEndDate.toIso8601String()}');
      
      // Check if subscription is expired beyond grace period
      if (now.isAfter(graceEndDate)) {
        debugPrint('🔐 Subscription expired beyond grace period');
        onSubscriptionExpired?.call();
        return;
      }
      
      // Check if subscription is inactive
      if (status != 'active') {
        debugPrint('🔐 Subscription is not active: $status');
        onSubscriptionExpired?.call();
        return;
      }
      
      // Check if we're in grace period (expired but within grace)
      if (now.isAfter(expiryDate) && now.isBefore(graceEndDate)) {
        final daysLeft = graceEndDate.difference(now).inDays;
        debugPrint('⚠️ Subscription in grace period: $daysLeft days left');
        // Could show warning here, but don't logout yet
      }
      
    } catch (e) {
      debugPrint('❌ Error validating subscription: $e');
    }
  }

  /// Get subscription info for display
  Future<Map<String, dynamic>?> getSubscriptionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_subscriptionCacheKey);
      
      if (cachedData != null) {
        return jsonDecode(cachedData) as Map<String, dynamic>;
      }
      
      // If no cache, try to fetch fresh data
      final orgId = await _getUserOrgId();
      if (orgId != null) {
        return await _fetchSubscriptionData(orgId);
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error getting subscription info: $e');
      return null;
    }
  }

  /// Check subscription on login
  Future<bool> validateSubscriptionOnLogin() async {
    try {
      final orgId = await _getUserOrgId();
      if (orgId == null) return false;

      final subscription = await _fetchSubscriptionData(orgId);
      if (subscription == null) {
        debugPrint('🔐 No subscription found for org: $orgId');
        return false;
      }

      // Cache the subscription data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subscriptionCacheKey, jsonEncode(subscription));
      await prefs.setInt(_lastSubscriptionCheckKey, DateTime.now().millisecondsSinceEpoch);

      final status = subscription['status'] as String?;
      final expiryDateStr = subscription['expiry_date'] as String?;
      final gracePeriodDays = subscription['grace_period_days'] as int? ?? 7;
      
      if (expiryDateStr == null || status != 'active') {
        debugPrint('🔐 Invalid subscription: status=$status, expiry=$expiryDateStr');
        return false;
      }
      
      final expiryDate = DateTime.parse(expiryDateStr);
      final now = DateTime.now();
      final graceEndDate = expiryDate.add(Duration(days: gracePeriodDays));
      
      // Allow login if within grace period
      if (now.isAfter(graceEndDate)) {
        debugPrint('🔐 Subscription expired beyond grace period');
        return false;
      }
      
      debugPrint('✅ Subscription valid for login');
      return true;
      
    } catch (e) {
      debugPrint('❌ Error validating subscription on login: $e');
      return false;
    }
  }

  /// Clear cached subscription data (call on logout)
  Future<void> clearSubscriptionCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_subscriptionCacheKey);
    await prefs.remove(_lastSubscriptionCheckKey);
    debugPrint('🔐 Subscription cache cleared');
  }
}


