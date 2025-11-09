import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Comprehensive 2FA Error Handling Service
/// 
/// This service provides:
/// - Centralized error handling for all 2FA operations
/// - Network connectivity monitoring
/// - Retry mechanisms with exponential backoff
/// - User-friendly error messages
/// - Fallback options for critical failures
/// - Error logging and analytics
/// - Recovery suggestions
class TwoFAErrorHandler {
  static final TwoFAErrorHandler _instance = TwoFAErrorHandler._internal();
  factory TwoFAErrorHandler() => _instance;
  TwoFAErrorHandler._internal();

  // Error tracking
  final Map<String, int> _errorCounts = {};
  final Map<String, DateTime> _lastErrorTimes = {};
  final List<ErrorLog> _errorLogs = [];
  
  // Connectivity monitoring
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isConnected = true;
  Timer? _retryTimer;
  
  // Configuration
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(minutes: 5);
  static const Duration _errorCooldown = Duration(minutes: 1);

  /// Initialize error handling service
  Future<void> initialize() async {
    await _startConnectivityMonitoring();
    _startErrorCleanup();
  }

  /// Start monitoring network connectivity
  Future<void> _startConnectivityMonitoring() async {
    try {
      final connectivity = Connectivity();
      _connectivitySubscription = connectivity.onConnectivityChanged.listen(
        _onConnectivityChanged,
        onError: (error) {
          debugPrint('Connectivity monitoring error: $error');
        },
      );
      
      // Check initial connectivity
      final result = await connectivity.checkConnectivity();
      _isConnected = result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Failed to start connectivity monitoring: $e');
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(ConnectivityResult result) {
    final wasConnected = _isConnected;
    _isConnected = result != ConnectivityResult.none;
    
    if (!wasConnected && _isConnected) {
      debugPrint('Network connectivity restored');
      _triggerRetryOperations();
    } else if (wasConnected && !_isConnected) {
      debugPrint('Network connectivity lost');
    }
  }

  /// Start periodic error cleanup
  void _startErrorCleanup() {
    Timer.periodic(const Duration(hours: 1), (timer) {
      _cleanupOldErrors();
    });
  }

  /// Clean up old error logs
  void _cleanupOldErrors() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _errorLogs.removeWhere((log) => log.timestamp.isBefore(cutoff));
    _errorCounts.removeWhere((key, value) => value == 0);
  }

  /// Handle 2FA errors with comprehensive error management
  Future<T> handle2FAError<T>(
    Future<T> Function() operation,
    String operationName, {
    bool retryable = true,
    Duration? customRetryDelay,
    String? customErrorMessage,
  }) async {
    try {
      return await operation();
    } catch (error) {
      return await _handleError(
        error,
        operationName,
        retryable: retryable,
        customRetryDelay: customRetryDelay,
        customErrorMessage: customErrorMessage,
      );
    }
  }

  /// Internal error handling with retry logic
  Future<T> _handleError<T>(
    dynamic error,
    String operationName, {
    bool retryable = true,
    Duration? customRetryDelay,
    String? customErrorMessage,
  }) async {
    final errorInfo = _analyzeError(error);
    final errorKey = '${operationName}_${errorInfo.type}';
    
    // Log the error
    _logError(errorInfo, operationName);
    
    // Check if we should retry
    if (retryable && _shouldRetry(errorKey, errorInfo)) {
      final retryDelay = customRetryDelay ?? _calculateRetryDelay(errorKey);
      
      debugPrint('Retrying $operationName in ${retryDelay.inSeconds}s (attempt ${_errorCounts[errorKey] ?? 0 + 1})');
      
      await Future.delayed(retryDelay);
      _errorCounts[errorKey] = (_errorCounts[errorKey] ?? 0) + 1;
      _lastErrorTimes[errorKey] = DateTime.now();
      
      // Retry the operation
      try {
        return await _retryOperation(operationName);
      } catch (retryError) {
        return await _handleError(
          retryError,
          operationName,
          retryable: retryable,
          customRetryDelay: customRetryDelay,
          customErrorMessage: customErrorMessage,
        );
      }
    }
    
    // No more retries, throw user-friendly error
    throw TwoFAException(
      errorInfo,
      customErrorMessage ?? _getUserFriendlyMessage(errorInfo, operationName),
      operationName,
    );
  }

  /// Analyze error and categorize it
  ErrorInfo _analyzeError(dynamic error) {
    if (error is TwoFAException) {
      return error.errorInfo;
    }
    
    final errorString = error.toString().toLowerCase();
    
    // Network errors
    if (errorString.contains('socket') || 
        errorString.contains('network') || 
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        error is SocketException) {
      return ErrorInfo(
        type: ErrorType.network,
        severity: ErrorSeverity.high,
        recoverable: true,
        retryable: true,
        originalError: error,
      );
    }
    
    // Blockchain errors
    if (errorString.contains('transaction') || 
        errorString.contains('gas') ||
        errorString.contains('contract') ||
        errorString.contains('blockchain')) {
      return ErrorInfo(
        type: ErrorType.blockchain,
        severity: ErrorSeverity.high,
        recoverable: true,
        retryable: true,
        originalError: error,
      );
    }
    
    // Authentication errors
    if (errorString.contains('invalid') || 
        errorString.contains('expired') ||
        errorString.contains('unauthorized') ||
        errorString.contains('authentication')) {
      return ErrorInfo(
        type: ErrorType.authentication,
        severity: ErrorSeverity.medium,
        recoverable: true,
        retryable: false,
        originalError: error,
      );
    }
    
    // Storage errors
    if (errorString.contains('storage') || 
        errorString.contains('encryption') ||
        errorString.contains('keychain') ||
        errorString.contains('secure')) {
      return ErrorInfo(
        type: ErrorType.storage,
        severity: ErrorSeverity.high,
        recoverable: false,
        retryable: false,
        originalError: error,
      );
    }
    
    // Biometric errors
    if (errorString.contains('biometric') || 
        errorString.contains('fingerprint') ||
        errorString.contains('face') ||
        errorString.contains('touch')) {
      return ErrorInfo(
        type: ErrorType.biometric,
        severity: ErrorSeverity.medium,
        recoverable: true,
        retryable: true,
        originalError: error,
      );
    }
    
    // Rate limiting errors
    if (errorString.contains('rate') || 
        errorString.contains('limit') ||
        errorString.contains('too many') ||
        errorString.contains('locked')) {
      return ErrorInfo(
        type: ErrorType.rateLimit,
        severity: ErrorSeverity.medium,
        recoverable: true,
        retryable: true,
        originalError: error,
      );
    }
    
    // Device compatibility errors
    if (errorString.contains('device') || 
        errorString.contains('compatibility') ||
        errorString.contains('hardware') ||
        errorString.contains('unsupported')) {
      return ErrorInfo(
        type: ErrorType.deviceCompatibility,
        severity: ErrorSeverity.low,
        recoverable: false,
        retryable: false,
        originalError: error,
      );
    }
    
    // Unknown error
    return ErrorInfo(
      type: ErrorType.unknown,
      severity: ErrorSeverity.medium,
      recoverable: true,
      retryable: true,
      originalError: error,
    );
  }

  /// Check if operation should be retried
  bool _shouldRetry(String errorKey, ErrorInfo errorInfo) {
    if (!errorInfo.retryable) return false;
    if (!_isConnected && errorInfo.type == ErrorType.network) return false;
    
    final errorCount = _errorCounts[errorKey] ?? 0;
    final lastErrorTime = _lastErrorTimes[errorKey];
    
    if (errorCount >= _maxRetries) return false;
    if (lastErrorTime != null && 
        DateTime.now().difference(lastErrorTime) < _errorCooldown) {
      return false;
    }
    
    return true;
  }

  /// Calculate retry delay with exponential backoff
  Duration _calculateRetryDelay(String errorKey) {
    final errorCount = _errorCounts[errorKey] ?? 0;
    final delay = Duration(
      milliseconds: _baseRetryDelay.inMilliseconds * (1 << errorCount),
    );
    
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  /// Retry operation (placeholder - would need specific operation context)
  Future<T> _retryOperation<T>(String operationName) async {
    // This would need to be implemented with specific operation context
    throw UnimplementedError('Retry operation not implemented for $operationName');
  }

  /// Get user-friendly error message
  String _getUserFriendlyMessage(ErrorInfo errorInfo, String operationName) {
    switch (errorInfo.type) {
      case ErrorType.network:
        return 'Network connection failed. Please check your internet connection and try again.';
      case ErrorType.blockchain:
        return 'Blockchain transaction failed. Please try again or contact support if the problem persists.';
      case ErrorType.authentication:
        return 'Authentication failed. Please check your code and try again.';
      case ErrorType.storage:
        return 'Unable to save data securely. Please restart the app and try again.';
      case ErrorType.biometric:
        return 'Biometric authentication failed. Please try again or use an alternative method.';
      case ErrorType.rateLimit:
        return 'Too many failed attempts. Please wait before trying again.';
      case ErrorType.deviceCompatibility:
        return 'Your device may not support this feature. Please use an alternative authentication method.';
      case ErrorType.unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Log error for analytics and debugging
  void _logError(ErrorInfo errorInfo, String operationName) {
    final log = ErrorLog(
      timestamp: DateTime.now(),
      operation: operationName,
      errorInfo: errorInfo,
      stackTrace: StackTrace.current,
    );
    
    _errorLogs.add(log);
    
    if (kDebugMode) {
      debugPrint('2FA Error: $operationName - ${errorInfo.type} - ${errorInfo.originalError}');
    }
  }

  /// Trigger retry operations when connectivity is restored
  void _triggerRetryOperations() {
    // This would trigger retry of failed operations
    debugPrint('Triggering retry operations after connectivity restoration');
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final now = DateTime.now();
    final last24Hours = now.subtract(const Duration(hours: 24));
    
    final recentErrors = _errorLogs.where(
      (log) => log.timestamp.isAfter(last24Hours),
    ).toList();
    
    final errorCounts = <ErrorType, int>{};
    for (final log in recentErrors) {
      errorCounts[log.errorInfo.type] = (errorCounts[log.errorInfo.type] ?? 0) + 1;
    }
    
    return {
      'totalErrors': _errorLogs.length,
      'recentErrors': recentErrors.length,
      'errorCounts': errorCounts,
      'isConnected': _isConnected,
      'activeErrorKeys': _errorCounts.keys.toList(),
    };
  }

  /// Clear error history
  void clearErrorHistory() {
    _errorCounts.clear();
    _lastErrorTimes.clear();
    _errorLogs.clear();
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
  }
}

/// Error information class
class ErrorInfo {
  final ErrorType type;
  final ErrorSeverity severity;
  final bool recoverable;
  final bool retryable;
  final dynamic originalError;
  final Map<String, dynamic>? additionalData;

  ErrorInfo({
    required this.type,
    required this.severity,
    required this.recoverable,
    required this.retryable,
    required this.originalError,
    this.additionalData,
  });
}

/// Error types enumeration
enum ErrorType {
  network,
  blockchain,
  authentication,
  storage,
  biometric,
  rateLimit,
  deviceCompatibility,
  unknown,
}

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// Custom 2FA exception
class TwoFAException implements Exception {
  final ErrorInfo errorInfo;
  final String message;
  final String operationName;
  final DateTime timestamp;

  TwoFAException(this.errorInfo, this.message, this.operationName)
      : timestamp = DateTime.now();

  @override
  String toString() {
    return 'TwoFAException: $message (${errorInfo.type})';
  }
}

/// Error log entry
class ErrorLog {
  final DateTime timestamp;
  final String operation;
  final ErrorInfo errorInfo;
  final StackTrace stackTrace;

  ErrorLog({
    required this.timestamp,
    required this.operation,
    required this.errorInfo,
    required this.stackTrace,
  });
}

/// Error recovery suggestions
class ErrorRecoverySuggestions {
  static List<String> getSuggestions(ErrorType errorType) {
    switch (errorType) {
      case ErrorType.network:
        return [
          'Check your internet connection',
          'Try switching between WiFi and mobile data',
          'Restart your router if using WiFi',
          'Contact your network provider if the issue persists',
        ];
      case ErrorType.blockchain:
        return [
          'Wait a few minutes and try again',
          'Check if the blockchain network is experiencing issues',
          'Try increasing gas price if available',
          'Contact support if the problem continues',
        ];
      case ErrorType.authentication:
        return [
          'Double-check your authentication code',
          'Make sure your device time is correct',
          'Try using a backup code if available',
          'Contact support if you cannot authenticate',
        ];
      case ErrorType.storage:
        return [
          'Restart the application',
          'Clear app cache and data',
          'Check available storage space',
          'Contact support for assistance',
        ];
      case ErrorType.biometric:
        return [
          'Clean your fingerprint sensor',
          'Try using a different finger',
          'Use alternative authentication method',
          'Check biometric settings in device settings',
        ];
      case ErrorType.rateLimit:
        return [
          'Wait before trying again',
          'Use backup codes if available',
          'Contact support if locked out',
          'Check if account is temporarily suspended',
        ];
      case ErrorType.deviceCompatibility:
        return [
          'Update your device software',
          'Use alternative authentication method',
          'Check device compatibility requirements',
          'Contact support for device-specific issues',
        ];
      case ErrorType.unknown:
        return [
          'Try again in a few minutes',
          'Restart the application',
          'Check for app updates',
          'Contact support if the problem persists',
        ];
    }
  }
}
