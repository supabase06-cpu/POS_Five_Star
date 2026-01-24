import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  StreamSubscription? _userStreamSubscription;
  Timer? _connectivityTimer;
  bool _isConnected = false;
  String? _currentUserId;
  
  // Callback for when user data changes
  Function()? onUserDataChanged;
  
  bool get isConnected => _isConnected;
  
  // Initialize realtime connection with user stream
  Future<void> initialize({String? userId}) async {
    _currentUserId = userId;
    
    // Check connectivity immediately on init
    await _checkConnectivity();
    
    try {
      if (userId != null && _isConnected) {
        _userStreamSubscription = _supabase
            .from('app_users')
            .stream(primaryKey: ['id'])
            .eq('id', userId)
            .listen((List<Map<String, dynamic>> data) {
              if (data.isNotEmpty) {
                _handleUserChange(data.first);
              }
              // Connection is working
              if (!_isConnected) {
                _isConnected = true;
                debugPrint('✅ Realtime connected');
                notifyListeners();
              }
            }, onError: (error) {
              debugPrint('❌ Realtime error: $error');
              if (_isConnected) {
                _isConnected = false;
                notifyListeners();
              }
            });
        
        debugPrint('✅ Realtime connected');
      }
      
      // Start connectivity check timer
      _startConnectivityCheck();
    } catch (e) {
      debugPrint('❌ Realtime init error: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  /// Start periodic connectivity check
  void _startConnectivityCheck() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _checkConnectivity();
    });
  }
  
  /// Check if actually connected to internet
  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      
      if (online != _isConnected) {
        _isConnected = online;
        if (online) {
          debugPrint('🌐 Realtime: Back online');
        } else {
          debugPrint('📴 Realtime: Went offline');
        }
        notifyListeners();
      }
    } catch (_) {
      if (_isConnected) {
        _isConnected = false;
        debugPrint('📴 Realtime: Went offline');
        notifyListeners();
      }
    }
  }
  
  /// Force connectivity check (can be called from outside)
  Future<bool> checkConnectivityNow() async {
    await _checkConnectivity();
    return _isConnected;
  }
  
  void _handleUserChange(Map<String, dynamic> userData) {
    if (onUserDataChanged != null) {
      onUserDataChanged!();
    }
    notifyListeners();
  }
  
  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    _userStreamSubscription = null;
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    _isConnected = false;
    _currentUserId = null;
    onUserDataChanged = null;
    super.dispose();
  }
  
  Future<void> reconnect({String? userId}) async {
    _userStreamSubscription?.cancel();
    _userStreamSubscription = null;
    _isConnected = false;
    await initialize(userId: userId ?? _currentUserId);
  }
}
