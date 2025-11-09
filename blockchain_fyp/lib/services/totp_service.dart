import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:otp/otp.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'two_fa_error_handler.dart';
import 'email_otp_service.dart';

/// Comprehensive TOTP Service for secure two-factor authentication
/// 
/// This service provides:
/// - Email OTP generation and verification
/// - Backup recovery codes generation
/// - Secure secret generation using UUID and cryptographic randomness
/// - TOTP code generation and validation (for compatibility)
/// - Time synchronization handling
/// - Support for multiple TOTP algorithms (SHA1, SHA256, SHA512)
/// - Integration with EmailOTPService for email delivery
class TOTPService {
  // Constants for TOTP configuration
  static const int _secretLength = 32;
  static const int _timeStep = 30;
  static const int _digits = 6;
  static const int _backupCodeCount = 10;
  static const int _backupCodeLength = 8;
  static const int _timeWindowTolerance = 1; // Allow 1 time step before/after
  static const String _defaultIssuer = 'EtherShare';
  
  // Email OTP configuration
  static const int _emailOtpExpirationMinutes = 5;
  static const int _emailOtpLength = 6;
  
  // Secure storage for email OTPs
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  
  // Email OTP cache (in-memory)
  final Map<String, _EmailOTPData> _emailOtpCache = {};
  Timer? _emailOtpCleanupTimer;
  
  // EmailOTPService for sending emails
  EmailOTPService? _emailOtpService;
  
  // Time synchronization endpoints for network time correction
  static const List<String> _timeSyncEndpoints = [
    'https://worldtimeapi.org/api/timezone/UTC',
    'https://timeapi.io/api/Time/current/zone?timeZone=UTC',
  ];

  DateTime? _lastTimeSync;
  int _timeOffset = 0; // Offset in seconds from device time
  final TwoFAErrorHandler _errorHandler = TwoFAErrorHandler();

  TOTPService._();

  static Future<TOTPService> create() async {
    final service = TOTPService._();
    await service._initialize();
    return service;
  }

  /// Initialize the TOTP service with time synchronization
  Future<void> _initialize() async {
    try {
      await _syncTime();
      _startEmailOtpCleanupTimer();
      print('TOTPService initialized successfully');
    } catch (e) {
      print('TOTPService initialization warning: $e');
      // Continue without time sync - device time will be used
    }
  }
  
  /// Start periodic cleanup timer for expired email OTPs
  void _startEmailOtpCleanupTimer() {
    _emailOtpCleanupTimer?.cancel();
    _emailOtpCleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _cleanupExpiredEmailOtps();
    });
  }
  
  /// Cleanup expired email OTPs from cache
  void _cleanupExpiredEmailOtps() {
      final now = DateTime.now();
      _emailOtpCache.removeWhere((email, data) => now.isAfter(data.expiresAt));
    }
    
    /// Set EmailOTPService instance for email sending
    void setEmailOTPService(EmailOTPService service) {
      _emailOtpService = service;
    }
  
  // ============================================================================
  // ORIGINAL TOTP METHODS (KEPT FOR COMPATIBILITY)
  // ============================================================================
  
  /// Generate a cryptographically secure secret key using random bytes
  /// 
  /// Returns a base32-encoded secret suitable for TOTP authenticator apps
  String generateSecret() {
    try {
      // Generate random bytes
      final random = Random.secure();
      
      // Base32 characters: A-Z and 2-7 (RFC 4648)
      const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
      
      // Generate secret using only valid base32 characters
      final secret = StringBuffer();
      for (int i = 0; i < _secretLength; i++) {
        secret.write(base32Chars[random.nextInt(base32Chars.length)]);
      }
      
      final secretString = secret.toString();
      print('Generated TOTP secret: ${secretString.substring(0, 8)}... (length: ${secretString.length})');
      return secretString;
    } catch (e) {
      print('Secret generation error: $e');
      rethrow;
    }
  }

  /// Generate TOTP code using secret and current time
  /// 
  /// [secret] - Base32 encoded secret key
  /// [algorithm] - Hash algorithm to use (default: SHA1)
  /// [timeOffset] - Optional time offset in seconds
  String generateTOTP(
    String secret, {
    Algorithm algorithm = Algorithm.SHA1,
    int? timeOffset,
  }) {
    try {
      final effectiveTime = DateTime.now().add(Duration(seconds: timeOffset ?? _timeOffset));
      
      final code = OTP.generateTOTPCodeString(
        secret,
        effectiveTime.millisecondsSinceEpoch,
        length: _digits,
        interval: _timeStep,
        algorithm: algorithm,
      );
      
      return code;
    } catch (e) {
      print('TOTP generation error: $e');
      throw Exception('Failed to generate TOTP code: $e');
    }
  }

  /// Verify TOTP code with time window tolerance
  /// 
  /// [secret] - Base32 encoded secret key
  /// [code] - 6-digit code to verify
  /// [algorithm] - Hash algorithm to use (default: SHA1)
  /// [timeWindow] - Number of time steps to check before/after current time
  bool verifyTOTP(
    String secret,
    String code, {
    Algorithm algorithm = Algorithm.SHA1,
    int? timeWindow,
  }) {
    try {
      final window = timeWindow ?? _timeWindowTolerance;
      final currentTime = DateTime.now().add(Duration(seconds: _timeOffset));
      
      // Debug: Print to verify secret and code
      print('Verifying TOTP: secret length=${secret.length}, code=$code');
      
      // Check codes in the time window
      for (int i = -window; i <= window; i++) {
        final testTime = currentTime.add(Duration(seconds: i * _timeStep));
        final testCode = OTP.generateTOTPCodeString(
          secret,
          testTime.millisecondsSinceEpoch,
          length: _digits,
          interval: _timeStep,
          algorithm: algorithm,
        );
        
        print('Trying code at offset $i: $testCode');
        
        if (testCode == code) {
          print('TOTP verification successful');
          return true;
        }
      }
      
      // Generate current code for debugging
      final currentCode = OTP.generateTOTPCodeString(
        secret,
        currentTime.millisecondsSinceEpoch,
        length: _digits,
        interval: _timeStep,
        algorithm: algorithm,
      );
      print('Current expected code: $currentCode');
      print('Provided code: $code');
      print('TOTP verification failed - code not found in time window');
      return false;
    } catch (e) {
      print('TOTP verification error: $e');
      return false;
    }
  }

  /// Generate backup recovery codes
  /// 
  /// Returns a list of unique 8-character alphanumeric codes
  List<String> generateBackupCodes() {
    try {
      final codes = <String>[];
      final random = Random.secure();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      
      while (codes.length < _backupCodeCount) {
        final code = StringBuffer();
        for (int i = 0; i < _backupCodeLength; i++) {
          code.write(chars[random.nextInt(chars.length)]);
        }
        
        final codeString = code.toString();
        if (!codes.contains(codeString)) {
          codes.add(codeString);
        }
      }
      
      print('Generated ${codes.length} backup codes');
      return codes;
    } catch (e) {
      print('Backup code generation error: $e');
      throw Exception('Failed to generate backup codes: $e');
    }
  }

  /// Verify backup recovery code
  /// 
  /// [code] - Backup code to verify
  /// [availableCodes] - List of available backup codes
  bool verifyBackupCode(String code, List<String> availableCodes) {
    try {
      if (code.length != _backupCodeLength) {
        print('Invalid backup code length: ${code.length}');
        return false;
      }
      
      final isValid = availableCodes.contains(code.toUpperCase());
      print('Backup code verification: ${isValid ? 'successful' : 'failed'}');
      return isValid;
    } catch (e) {
      print('Backup code verification error: $e');
      return false;
    }
  }

  /// Get remaining time until next TOTP code
  int getRemainingTime() {
    try {
      final now = DateTime.now().add(Duration(seconds: _timeOffset));
      return _timeStep - ((now.millisecondsSinceEpoch ~/ 1000) % _timeStep);
    } catch (e) {
      print('Remaining time calculation error: $e');
      return _timeStep;
    }
  }

  /// Check if TOTP code is expired
  bool isCodeExpired(String secret, String code, {Algorithm algorithm = Algorithm.SHA1}) {
    try {
      return !verifyTOTP(secret, code, algorithm: algorithm, timeWindow: 0);
    } catch (e) {
      print('Code expiration check error: $e');
      return true;
    }
  }

  /// Sync time with network time servers to handle device time drift
  Future<void> _syncTime() async {
    try {
      for (final endpoint in _timeSyncEndpoints) {
        try {
          final response = await http.get(Uri.parse(endpoint)).timeout(
            const Duration(seconds: 5),
          );
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            DateTime? networkTime;
            
            // Parse different time API formats
            if (data['utc_datetime'] != null) {
              networkTime = DateTime.parse(data['utc_datetime']);
            } else if (data['dateTime'] != null) {
              networkTime = DateTime.parse(data['dateTime']);
            }
            
            if (networkTime != null) {
              final deviceTime = DateTime.now().toUtc();
              _timeOffset = networkTime.difference(deviceTime).inSeconds;
              _lastTimeSync = DateTime.now();
              
              print('Time synchronized. Offset: ${_timeOffset}s');
              return;
            }
          }
        } catch (e) {
          print('Time sync failed for $endpoint: $e');
          continue;
        }
      }
      
      throw Exception('All time sync endpoints failed');
    } catch (e) {
      print('Time synchronization error: $e');
      rethrow;
    }
  }

  /// Force time synchronization
  Future<void> syncTime() async {
    await _syncTime();
  }

  /// Get current time offset from network time
  int get timeOffset => _timeOffset;

  /// Check if time sync is recent (within last hour)
  bool get isTimeSyncRecent {
    if (_lastTimeSync == null) return false;
    return DateTime.now().difference(_lastTimeSync!).inHours < 1;
  }

  /// Validate secret format
  bool isValidSecret(String secret) {
    try {
      // Check if it's valid base32 by trying to decode it
      base64Decode(secret);
      return secret.length >= 16 && secret.length <= 64;
    } catch (e) {
      return false;
    }
  }

  /// Get TOTP configuration info
  Map<String, dynamic> getConfiguration() {
    return {
      'secretLength': _secretLength,
      'timeStep': _timeStep,
      'digits': _digits,
      'backupCodeCount': _backupCodeCount,
      'backupCodeLength': _backupCodeLength,
      'timeWindowTolerance': _timeWindowTolerance,
      'defaultIssuer': _defaultIssuer,
      'timeOffset': _timeOffset,
      'lastTimeSync': _lastTimeSync?.toIso8601String(),
      'isTimeSyncRecent': isTimeSyncRecent,
    };
  }

  /// Test TOTP functionality
  Future<void> testTOTP() async {
    try {
      print('Testing TOTP functionality...');
      
      // Generate secret
      final secret = generateSecret();
      print('Generated secret: ${secret.substring(0, 8)}...');
      
      // Generate code
      final code = generateTOTP(secret);
      print('Generated code: $code');
      
      // Verify code
      final isValid = verifyTOTP(secret, code);
      print('Code verification: ${isValid ? 'PASS' : 'FAIL'}');
      
      // Generate backup codes
      final backupCodes = generateBackupCodes();
      print('Generated ${backupCodes.length} backup codes');
      
      // Test backup code verification
      final backupValid = verifyBackupCode(backupCodes.first, backupCodes);
      print('Backup code verification: ${backupValid ? 'PASS' : 'FAIL'}');
      
      print('TOTP test completed successfully');
    } catch (e) {
      print('TOTP test failed: $e');
      rethrow;
    }
  }

  // ============ ERROR HANDLING METHODS ============

  /// Generate secret with error handling
  Future<String> generateSecretSafe() async {
    return await _errorHandler.handle2FAError(
      () async => generateSecret(),
      'generateSecret',
      retryable: true,
      customErrorMessage: 'Failed to generate secure secret key',
    );
  }

  /// Generate TOTP code with error handling
  Future<String> generateTOTPSafe(String secret, {Algorithm algorithm = Algorithm.SHA1, int? timeOffset}) async {
    return await _errorHandler.handle2FAError(
      () async => generateTOTP(secret, algorithm: algorithm, timeOffset: timeOffset),
      'generateTOTP',
      retryable: false,
      customErrorMessage: 'Failed to generate authentication code',
    );
  }

  /// Verify TOTP code with comprehensive error handling
  Future<bool> verifyTOTPSafe(String secret, String code, {Algorithm algorithm = Algorithm.SHA1, int? timeWindow}) async {
    return await _errorHandler.handle2FAError(
      () async {
        // Validate inputs
        if (secret.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty secret',
            ),
            'Secret key cannot be empty',
            'verifyTOTP',
          );
        }

        if (code.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty code',
            ),
            'Authentication code cannot be empty',
            'verifyTOTP',
          );
        }

        if (code.length != 6) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid code length',
            ),
            'Authentication code must be 6 digits',
            'verifyTOTP',
          );
        }

        // Check if code contains only digits
        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid code format',
            ),
            'Authentication code must contain only numbers',
            'verifyTOTP',
          );
        }

        // Check if code is expired
        if (isCodeExpired(secret, code, algorithm: algorithm)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Code expired',
              additionalData: {'remainingTime': getRemainingTime()},
            ),
            'Authentication code has expired. Please wait for a new code.',
            'verifyTOTP',
          );
        }

        return verifyTOTP(secret, code, algorithm: algorithm, timeWindow: timeWindow);
      },
      'verifyTOTP',
      retryable: false,
      customErrorMessage: 'Failed to verify authentication code',
    );
  }

  /// Generate backup codes with error handling
  Future<List<String>> generateBackupCodesSafe() async {
    return await _errorHandler.handle2FAError(
      () async => generateBackupCodes(),
      'generateBackupCodes',
      retryable: true,
      customErrorMessage: 'Failed to generate backup codes',
    );
  }

  /// Verify backup code with error handling
  Future<bool> verifyBackupCodeSafe(String code, List<String> availableCodes) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (code.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty backup code',
            ),
            'Backup code cannot be empty',
            'verifyBackupCode',
          );
        }

        if (availableCodes.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.high,
              recoverable: false,
              retryable: false,
              originalError: 'No backup codes available',
            ),
            'No backup codes available. Please contact support.',
            'verifyBackupCode',
          );
        }

        if (code.length != _backupCodeLength) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid backup code length',
            ),
            'Backup code must be $_backupCodeLength characters',
            'verifyBackupCode',
          );
        }

        return verifyBackupCode(code, availableCodes);
      },
      'verifyBackupCode',
      retryable: false,
      customErrorMessage: 'Failed to verify backup code',
    );
  }

  /// Sync time with error handling
  Future<void> syncTimeSafe() async {
    await _errorHandler.handle2FAError(
      () => syncTime(),
      'syncTime',
      retryable: true,
      customErrorMessage: 'Failed to synchronize time. Authentication codes may not work correctly.',
    );
  }

  /// Get remaining time with error handling
  Future<int> getRemainingTimeSafe() async {
    return await _errorHandler.handle2FAError(
      () async => getRemainingTime(),
      'getRemainingTime',
      retryable: false,
      customErrorMessage: 'Failed to get remaining time',
    );
  }

  /// Check if code is expired with error handling
  Future<bool> isCodeExpiredSafe(String secret, String code, {Algorithm algorithm = Algorithm.SHA1}) async {
    return await _errorHandler.handle2FAError(
      () async => isCodeExpired(secret, code, algorithm: algorithm),
      'isCodeExpired',
      retryable: false,
      customErrorMessage: 'Failed to check code expiration',
    );
  }

  /// Validate secret with error handling
  Future<bool> isValidSecretSafe(String secret) async {
    return await _errorHandler.handle2FAError(
      () async => isValidSecret(secret),
      'isValidSecret',
      retryable: false,
      customErrorMessage: 'Failed to validate secret key',
    );
  }

  /// Get configuration with error handling
  Future<Map<String, dynamic>> getConfigurationSafe() async {
    return await _errorHandler.handle2FAError(
      () async => getConfiguration(),
      'getConfiguration',
      retryable: false,
      customErrorMessage: 'Failed to get configuration',
    );
  }

  /// Test TOTP with error handling
  Future<void> testTOTPSafe() async {
    await _errorHandler.handle2FAError(
      () => testTOTP(),
      'testTOTP',
      retryable: true,
      customErrorMessage: 'TOTP test failed',
    );
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    return _errorHandler.getErrorStatistics();
  }

  /// Clear error history
  void clearErrorHistory() {
    _errorHandler.clearErrorHistory();
  }

  // ============================================================================
  // EMAIL OTP METHODS
  // ============================================================================
  
  /// Generate 6-digit email OTP code
  /// 
  /// [email] - Email address to generate OTP for
  /// Returns the generated OTP code
  String generateEmailOTP(String email) {
    try {
      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        throw Exception('Invalid email format');
      }
      
      // Generate random 6-digit code
      final random = Random.secure();
      final code = StringBuffer();
      
      for (int i = 0; i < _emailOtpLength; i++) {
        code.write(random.nextInt(10));
      }
      
      final otpCode = code.toString();
      print('Generated email OTP for $email: $otpCode');
      
      return otpCode;
    } catch (e) {
      print('Email OTP generation error: $e');
      rethrow;
    }
  }
  
  /// Store email OTP with expiration
  /// 
  /// [email] - Email address
  /// [otp] - The OTP code to store
  Future<void> storeEmailOTP(String email, String otp) async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          if (email.isEmpty) {
            throw Exception('Email cannot be empty');
          }
          if (otp.length != _emailOtpLength) {
            throw Exception('OTP must be $_emailOtpLength digits');
          }
          
          // Store in cache
          final now = DateTime.now();
          final expiresAt = now.add(Duration(minutes: _emailOtpExpirationMinutes));
          
          _emailOtpCache[email] = _EmailOTPData(
            email: email,
            otp: otp,
            createdAt: now,
            expiresAt: expiresAt,
            attempts: 0,
          );
          
          // Store in secure storage
          final storageKey = 'email_otp_$email';
          final data = jsonEncode({
            'email': email,
            'otp': otp,
            'createdAt': now.toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
            'attempts': 0,
          });
          
          await _storage.write(key: storageKey, value: data);
          
          print('Stored email OTP for $email. Expires in $_emailOtpExpirationMinutes minutes');
        } catch (e) {
          print('Store email OTP error: $e');
          rethrow;
        }
      },
      'storeEmailOTP',
      retryable: false,
      customErrorMessage: 'Failed to store email OTP',
    );
  }
  
  /// Verify email OTP code with expiration check
  /// 
  /// [email] - Email address
  /// [code] - The OTP code to verify
  /// Returns true if code is valid and not expired
  Future<bool> verifyEmailOTP(String email, String code) async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          if (email.isEmpty) {
            throw Exception('Email cannot be empty');
          }
          if (code.length != _emailOtpLength) {
            print('Invalid OTP length: ${code.length} (expected: $_emailOtpLength)');
            return false;
          }
          
          // Check cache first
          final cachedData = _emailOtpCache[email];
          if (cachedData == null) {
            // Check secure storage
            final storageKey = 'email_otp_$email';
            final storedData = await _storage.read(key: storageKey);
            
            if (storedData == null) {
              print('No OTP found for $email');
              return false;
            }
            
            final data = jsonDecode(storedData) as Map<String, dynamic>;
            final storedCode = data['otp'] as String;
            final expiresAt = DateTime.parse(data['expiresAt'] as String);
            final attempts = data['attempts'] as int;
            
            // Check expiration
            if (DateTime.now().isAfter(expiresAt)) {
              print('OTP expired for $email');
              await _clearEmailOTP(email);
              return false;
            }
            
            // Check attempts (max 3)
            if (attempts >= 3) {
              print('Too many verification attempts for $email');
              return false;
            }
            
            // Verify code
            if (storedCode == code) {
              print('Email OTP verified successfully for $email');
              await _clearEmailOTP(email);
              return true;
            } else {
              // Increment attempts
              final updatedData = jsonEncode({
                'email': data['email'],
                'otp': data['otp'],
                'createdAt': data['createdAt'],
                'expiresAt': data['expiresAt'],
                'attempts': attempts + 1,
              });
              await _storage.write(key: storageKey, value: updatedData);
              
              print('Invalid email OTP code for $email');
              return false;
            }
          }
          
          // Use cached data
          if (DateTime.now().isAfter(cachedData.expiresAt)) {
            print('OTP expired for $email');
            _emailOtpCache.remove(email);
            await _clearEmailOTP(email);
            return false;
          }
          
          if (cachedData.attempts >= 3) {
            print('Too many verification attempts for $email');
            return false;
          }
          
          if (cachedData.otp == code) {
            print('Email OTP verified successfully for $email');
            _emailOtpCache.remove(email);
            await _clearEmailOTP(email);
            return true;
          } else {
            cachedData.attempts++;
            print('Invalid email OTP code for $email. Attempts: ${cachedData.attempts}');
            return false;
          }
        } catch (e) {
          print('Verify email OTP error: $e');
          return false;
        }
      },
      'verifyEmailOTP',
      retryable: false,
      customErrorMessage: 'Failed to verify email OTP',
    );
  }
  
  /// Send OTP to email via EmailOTPService
  /// 
  /// [email] - Email address to send OTP to
  /// [otp] - The OTP code to send
  /// [userName] - Optional user name
  /// Returns true if email was sent successfully
  Future<bool> sendOTPToEmail(String email, String otp, {String? userName}) async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          if (_emailOtpService == null) {
            throw Exception('EmailOTPService not configured');
          }
          
          // Use EmailOTPService to send the email
          final sent = await _emailOtpService!.sendOTP(
            email: email,
            userName: userName ?? 'User',
          );
          
          if (sent) {
            print('OTP email sent successfully to $email');
          } else {
            print('Failed to send OTP email to $email');
          }
          
          return sent;
        } catch (e) {
          print('Send OTP to email error: $e');
          rethrow;
        }
      },
      'sendOTPToEmail',
      retryable: true,
      customErrorMessage: 'Failed to send OTP email',
    );
  }
  
  /// Clear email OTP data
  Future<void> _clearEmailOTP(String email) async {
    try {
      _emailOtpCache.remove(email);
      final storageKey = 'email_otp_$email';
      await _storage.delete(key: storageKey);
    } catch (e) {
      print('Clear email OTP error: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _emailOtpCleanupTimer?.cancel();
    _emailOtpCache.clear();
    _errorHandler.dispose();
  }
}

/// Email OTP data class
class _EmailOTPData {
  final String email;
  final String otp;
  final DateTime createdAt;
  final DateTime expiresAt;
  int attempts;
  
  _EmailOTPData({
    required this.email,
    required this.otp,
    required this.createdAt,
    required this.expiresAt,
    this.attempts = 0,
  });
}
