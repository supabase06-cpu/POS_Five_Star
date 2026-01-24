import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/session_monitor_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final SessionMonitorService _sessionMonitor = SessionMonitorService();
  
  User? _user;
  UserProfile? _userProfile;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  final Completer<void> _initCompleter = Completer<void>();
  
  User? get user => _user;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null && _userProfile != null;
  
  AuthProvider(this._supabase) {
    _initializeAuth();
  }
  
  Future<void> waitForInitialization() async {
    if (_isInitialized) return;
    await _initCompleter.future;
  }
  
  Future<void> _initializeAuth() async {
    try {
      _user = _supabase.auth.currentUser;
      
      if (_user != null) {
        debugPrint('🔐 Session found, loading profile...');
        await _loadUserProfile();
      } else {
        debugPrint('🔐 No session');
      }
      
      _supabase.auth.onAuthStateChange.listen((data) {
        _user = data.session?.user;
        if (_user != null) {
          _loadUserProfile();
        } else {
          _userProfile = null;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('❌ Auth init error: $e');
    } finally {
      _isInitialized = true;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }
  
  Future<void> reloadUserProfile() async {
    if (_user != null) {
      await _loadUserProfile();
    }
  }
  
  Future<void> signIn(String email, String password, bool rememberMe) async {
    _setLoading(true);
    _clearError();
    
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        _user = response.user;
        await _loadUserProfile();
        
        if (_userProfile == null) {
          throw Exception('User profile not found');
        }
        
        if (!_userProfile!.isActive) {
          await signOut();
          throw Exception('Your account has been deactivated.');
        }
        
        if (_userProfile!.organization != null) {
          final org = _userProfile!.organization!;
          if (!org.isActive) {
            await signOut();
            throw Exception('Your organization is inactive.');
          }
          if (!org.hasActiveSubscription) {
            await signOut();
            throw Exception('Subscription expired.');
          }
        }
        
        if (!_userProfile!.canAccessPOS) {
          await signOut();
          throw Exception('No POS access permission.');
        }
        
        // Check subscription on login
        final subscriptionValid = await _sessionMonitor.validateSubscriptionOnLogin();
        if (!subscriptionValid) {
          await signOut();
          throw Exception('Subscription expired or invalid.');
        }
        
        await _updateLastLogin();
        
        // Start session monitoring after successful login
        _sessionMonitor.startSessionMonitoring(
          onExpired: () async {
            debugPrint('🔐 Session expired - auto logout');
            await signOut();
          },
          onSubscriptionExpired: () async {
            debugPrint('🔐 Subscription expired - auto logout');
            await signOut();
          },
        );
        
        if (rememberMe) {
          await _saveCredentials(email, password);
        } else {
          await _clearSavedCredentials();
        }
        
        debugPrint('✅ Login successful: ${_userProfile!.fullName}');
      }
    } on AuthException catch (e) {
      _setError(_getAuthErrorMessage(e.message));
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }
  
  Future<void> signOut() async {
    _setLoading(true);
    _clearError();
    
    try {
      // Stop session monitoring
      _sessionMonitor.stopSessionMonitoring();
      
      // Clear subscription cache
      await _sessionMonitor.clearSubscriptionCache();
      
      await _supabase.auth.signOut();
      _user = null;
      _userProfile = null;
      debugPrint('✅ Logged out');
    } catch (e) {
      _setError('Error signing out.');
    } finally {
      _setLoading(false);
    }
  }
  
  Future<void> _loadUserProfile() async {
    if (_user == null) return;
    
    try {
      final userResponse = await _supabase
          .from('app_users')
          .select('*')
          .eq('id', _user!.id)
          .single();
      
      final profileData = Map<String, dynamic>.from(userResponse);
      profileData['organization'] = null;
      
      _userProfile = UserProfile.fromJson(profileData);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Profile load error: $e');
      await signOut();
      _setError('User profile not found.');
    }
  }
  
  Future<void> _updateLastLogin() async {
    if (_user == null) return;
    
    try {
      await _supabase
          .from('app_users')
          .update({'last_login_at': DateTime.now().toIso8601String()})
          .eq('id', _user!.id);
    } catch (e) {
      // Silent fail
    }
  }
  
  String _getAuthErrorMessage(String error) {
    switch (error.toLowerCase()) {
      case 'invalid login credentials':
        return 'Invalid email or password.';
      case 'email not confirmed':
        return 'Please confirm your email.';
      case 'too many requests':
        return 'Too many attempts. Please wait.';
      default:
        return 'Login failed.';
    }
  }
  
  bool hasPermission(String permission) {
    return _userProfile?.hasPermission(permission) ?? false;
  }
  
  bool get canProcessPayments => _userProfile?.canProcessPayments ?? false;
  bool get canViewReports => _userProfile?.canViewReports ?? false;
  bool get canManageInventory => _userProfile?.canManageInventory ?? false;
  bool get canManageUsers => _userProfile?.canManageUsers ?? false;
  bool get isManager => _userProfile?.isManager ?? false;
  bool get isAdmin => _userProfile?.isAdmin ?? false;
  
  OrganizationInfo? get organization => _userProfile?.organization;
  bool get hasActiveSubscription => true;
  String get subscriptionStatus => 'Active';
  
  Future<Map<String, String?>> getSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'email': prefs.getString('saved_email'),
        'password': prefs.getString('saved_password')
      };
    } catch (e) {
      return {'email': null, 'password': null};
    }
  }
  
  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      await prefs.setString('saved_password', password);
    } catch (e) {}
  }
  
  Future<void> _clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    } catch (e) {}
  }
  
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }
  
  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  void clearError() {
    _clearError();
  }
  
  /// Update user activity (call this on user interactions)
  void updateActivity() {
    if (isAuthenticated) {
      _sessionMonitor.updateActivity();
    }
  }
  
  /// Get subscription info for display
  Future<Map<String, dynamic>?> getSubscriptionInfo() async {
    return await _sessionMonitor.getSubscriptionInfo();
  }
}
