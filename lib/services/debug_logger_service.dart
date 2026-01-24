import 'package:flutter/foundation.dart';

enum LogType { api, log }

class LogEntry {
  final String id;
  final LogType type;
  final DateTime timestamp;
  final String title;
  final String? request;
  final String? response;
  final String? error;
  final int? statusCode;
  final Duration? duration;

  LogEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.title,
    this.request,
    this.response,
    this.error,
    this.statusCode,
    this.duration,
  });
}

class DebugLoggerService extends ChangeNotifier {
  static final DebugLoggerService _instance = DebugLoggerService._internal();
  factory DebugLoggerService() => _instance;
  DebugLoggerService._internal();

  static const bool isDeveloperMode = true; // Set to false in production

  final List<LogEntry> _apiLogs = [];
  final List<LogEntry> _appLogs = [];
  int _logCounter = 0;

  List<LogEntry> get apiLogs => List.unmodifiable(_apiLogs);
  List<LogEntry> get appLogs => List.unmodifiable(_appLogs);

  // Log API request/response
  void logApi({
    required String title,
    String? request,
    String? response,
    String? error,
    int? statusCode,
    Duration? duration,
  }) {
    if (!isDeveloperMode) return;
    
    final entry = LogEntry(
      id: '${++_logCounter}',
      type: LogType.api,
      timestamp: DateTime.now(),
      title: title,
      request: request,
      response: response,
      error: error,
      statusCode: statusCode,
      duration: duration,
    );
    
    _apiLogs.insert(0, entry);
    if (_apiLogs.length > 100) _apiLogs.removeLast();
    notifyListeners();
  }

  // Log general app logs
  void log(String message, {String? details}) {
    if (!isDeveloperMode) return;
    
    final entry = LogEntry(
      id: '${++_logCounter}',
      type: LogType.log,
      timestamp: DateTime.now(),
      title: message,
      response: details,
    );
    
    _appLogs.insert(0, entry);
    if (_appLogs.length > 100) _appLogs.removeLast();
    notifyListeners();
    
    // Also print to console
    debugPrint('📝 $message${details != null ? '\n$details' : ''}');
  }

  void clearApiLogs() {
    _apiLogs.clear();
    notifyListeners();
  }

  void clearAppLogs() {
    _appLogs.clear();
    notifyListeners();
  }

  void clearAll() {
    _apiLogs.clear();
    _appLogs.clear();
    notifyListeners();
  }
}
