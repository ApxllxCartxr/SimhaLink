import 'package:flutter/foundation.dart';

/// Production-ready error handling and logging system
/// Note: Crashlytics can be added later for full production deployment
class AppLogger {
  /// Log error with optional details and stack trace
  static void logError(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
    bool fatal = false,
  ]) {
    // Debug console output
    if (kDebugMode) {
      print('🚨 ERROR: $message');
      if (error != null) print('Details: $error');
      if (stackTrace != null) print('Stack: $stackTrace');
    }
    
    // TODO: Add Firebase Crashlytics in production
    // FirebaseCrashlytics.instance.recordError(error ?? message, stackTrace, fatal: fatal);
  }
  
  /// Log informational messages
  static void logInfo(String message) {
    if (kDebugMode) {
      print('ℹ️ INFO: $message');
    }
  }
  
  /// Log warning messages
  static void logWarning(String message, [dynamic details]) {
    if (kDebugMode) {
      print('⚠️ WARNING: $message');
      if (details != null) print('Details: $details');
    }
  }
  
  /// Log critical events that should be monitored
  static void logCritical(String message, [dynamic error, StackTrace? stackTrace]) {
    logError(message, error, stackTrace, true);
  }
}
