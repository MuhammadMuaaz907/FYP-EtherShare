import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'two_fa_error_handler.dart';

/// Comprehensive Email OTP Service for secure authentication
/// 
/// This service provides:
/// - 6-digit OTP generation with 5-minute expiration
/// - SMTP email sending with Gmail, SendGrid, or custom servers
/// - Secure OTP storage with encryption
/// - OTP validation with expiration checking
/// - Rate limiting (max 3 OTPs per hour per email)
/// - Professional email templates with HTML design
/// - Graceful error handling and retry mechanisms
/// - Network timeout handling
/// - Comprehensive logging and monitoring
/// - Support for multiple email providers
class EmailOTPService {
  // OTP Configuration
  static const int _otpLength = 6;
  static const Duration _otpExpiration = Duration(minutes: 5);
  static const int _maxOtpAttemptsPerHour = 3;
  static const Duration _rateLimitWindow = Duration(hours: 1);
  
  // Email Configuration
  // IMPORTANT: Use a verified sender email from SendGrid
  // For testing, use your verified SendGrid sender email
  // For production, use your domain email (e.g., noreply@yourdomain.com)
  static const String _defaultFromEmail = 'muhammadmuaaz907@gmail.com'; // Change this to your verified sender
  static const String _defaultFromName = 'EtherShare';
  
  // Storage configuration
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  
  // Storage keys
  static const String _otpAttemptsKey = 'email_otp_attempts_';
  static const String _otpDataKey = 'email_otp_data_';
  
  // SMTP Configuration
  String? _smtpUsername;
  String? _smtpPassword;
  String? _smtpHost;
  int? _smtpPort;
  
  // Error handler
  final TwoFAErrorHandler _errorHandler = TwoFAErrorHandler();
  
  // Active OTPs cache
  final Map<String, _OTPData> _activeOtpCache = {};
  Timer? _cacheCleanupTimer;
  
  EmailOTPService._();
  
  static Future<EmailOTPService> create() async {
    final service = EmailOTPService._();
    await service._initialize();
    return service;
  }
  
  /// Initialize the email OTP service
  Future<void> _initialize() async {
    try {
      _startCacheCleanup();
      print('EmailOTPService initialized successfully');
    } catch (e) {
      print('EmailOTPService initialization error: $e');
      rethrow;
    }
  }
  
  /// Start periodic cache cleanup
  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _cleanupExpiredOtps();
    });
  }
  
  /// Configure SMTP server
  /// 
  /// Examples:
  /// - Gmail: smtpHost='smtp.gmail.com', smtpPort=587
  /// - SendGrid: smtpHost='smtp.sendgrid.net', smtpPort=587
  /// - Custom: Provide your SMTP server details
  Future<void> configureSMTP({
    required String username,
    required String password,
    required String host,
    int? port,
    bool useSecure = true,
  }) async {
    _smtpUsername = username;
    _smtpPassword = password;
    _smtpHost = host;
    _smtpPort = port ?? (useSecure ? 587 : 25);
    
    print('SMTP configured: $host');
  }
  
  /// Generate a random 6-digit OTP code
  String _generateOTP() {
    final random = Random.secure();
    final otp = StringBuffer();
    
    for (int i = 0; i < _otpLength; i++) {
      otp.write(random.nextInt(10));
    }
    
    return otp.toString();
  }
  
  /// Validate email format
  bool _isValidEmail(String email) {
    return EmailValidator.validate(email);
  }
  
  /// Check rate limiting for email
  Future<bool> _checkRateLimit(String email) async {
    try {
      final attemptsKey = _otpAttemptsKey + email;
      final attemptsJson = await _storage.read(key: attemptsKey);
      
      if (attemptsJson == null) {
        // First attempt
        await _storage.write(
          key: attemptsKey,
          value: jsonEncode({
            'count': 1,
            'firstAttempt': DateTime.now().toIso8601String(),
          }),
        );
        return true;
      }
      
      final attemptsData = jsonDecode(attemptsJson) as Map<String, dynamic>;
      final firstAttempt = DateTime.parse(attemptsData['firstAttempt'] as String);
      final count = attemptsData['count'] as int;
      final timeElapsed = DateTime.now().difference(firstAttempt);
      
      if (timeElapsed > _rateLimitWindow) {
        // Reset count - window expired
        await _storage.write(
          key: attemptsKey,
          value: jsonEncode({
            'count': 1,
            'firstAttempt': DateTime.now().toIso8601String(),
          }),
        );
        return true;
      }
      
      if (count >= _maxOtpAttemptsPerHour) {
        // Rate limit exceeded
        return false;
      }
      
      // Increment count
      await _storage.write(
        key: attemptsKey,
        value: jsonEncode({
          'count': count + 1,
          'firstAttempt': attemptsData['firstAttempt'],
        }),
      );
      return true;
    } catch (e) {
      print('Rate limit check error: $e');
      return true; // Allow on error to not block users
    }
  }
  
  /// Record OTP attempt
  Future<void> _recordOtpAttempt(String email, int count) async {
    try {
      final attemptsKey = _otpAttemptsKey + email;
      await _storage.write(
        key: attemptsKey,
        value: jsonEncode({
          'count': count,
          'firstAttempt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      print('Record OTP attempt error: $e');
    }
  }
  
  /// Store OTP data securely
  Future<void> _storeOtpData(String email, String otp) async {
    try {
      final otpData = _OTPData(
        otp: otp,
        email: email,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(_otpExpiration),
        attempts: 0,
      );
      
      _activeOtpCache[email] = otpData;
      
      final otpKey = _otpDataKey + email;
      await _storage.write(
        key: otpKey,
        value: jsonEncode({
          'otp': otp,
          'email': email,
          'createdAt': DateTime.now().toIso8601String(),
          'expiresAt': DateTime.now().add(_otpExpiration).toIso8601String(),
          'attempts': 0,
        }),
      );
      
      print('OTP stored for $email');
    } catch (e) {
      print('Store OTP data error: $e');
      rethrow;
    }
  }
  
  /// Retrieve OTP data
  Future<_OTPData?> _getOtpData(String email) async {
    try {
      // Check cache first
      if (_activeOtpCache.containsKey(email)) {
        final cached = _activeOtpCache[email]!;
        if (DateTime.now().isBefore(cached.expiresAt)) {
          return cached;
        } else {
          _activeOtpCache.remove(email);
        }
      }
      
      // Check storage
      final otpKey = _otpDataKey + email;
      final otpDataJson = await _storage.read(key: otpKey);
      
      if (otpDataJson == null) return null;
      
      final otpData = jsonDecode(otpDataJson) as Map<String, dynamic>;
      final createdAt = DateTime.parse(otpData['createdAt'] as String);
      final expiresAt = DateTime.parse(otpData['expiresAt'] as String);
      
      final data = _OTPData(
        otp: otpData['otp'] as String,
        email: otpData['email'] as String,
        createdAt: createdAt,
        expiresAt: expiresAt,
        attempts: otpData['attempts'] as int,
      );
      
      if (DateTime.now().isAfter(expiresAt)) {
        return null; // Expired
      }
      
      _activeOtpCache[email] = data;
      return data;
    } catch (e) {
      print('Get OTP data error: $e');
      return null;
    }
  }
  
  /// Cleanup expired OTPs
  void _cleanupExpiredOtps() {
    final now = DateTime.now();
    _activeOtpCache.removeWhere((email, otpData) => now.isAfter(otpData.expiresAt));
    
    debugPrint('Cleaned up expired OTPs. Active: ${_activeOtpCache.length}');
  }
  
  /// Get email HTML template
  String _getEmailTemplate({
    required String otpCode,
    required String userName,
  }) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your Verification Code</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background-color: #f5f5f5;
      margin: 0;
      padding: 0;
    }
    .container {
      max-width: 600px;
      margin: 40px auto;
      background-color: #ffffff;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    }
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      padding: 40px 20px;
      text-align: center;
      border-radius: 8px 8px 0 0;
    }
    .header h1 {
      color: #ffffff;
      margin: 0;
      font-size: 28px;
      font-weight: 600;
    }
    .content {
      padding: 40px 30px;
    }
    .greeting {
      font-size: 18px;
      color: #333333;
      margin-bottom: 20px;
    }
    .message {
      font-size: 16px;
      color: #666666;
      line-height: 1.6;
      margin-bottom: 30px;
    }
    .otp-container {
      text-align: center;
      margin: 30px 0;
    }
    .otp-code {
      display: inline-block;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: #ffffff;
      font-size: 32px;
      font-weight: bold;
      padding: 20px 40px;
      border-radius: 8px;
      letter-spacing: 8px;
      font-family: 'Courier New', monospace;
    }
    .otp-label {
      font-size: 14px;
      color: #999999;
      margin-top: 10px;
    }
    .validity {
      background-color: #fff4e6;
      border-left: 4px solid #ff9800;
      padding: 15px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .validity p {
      margin: 0;
      font-size: 14px;
      color: #e65100;
    }
    .security-note {
      background-color: #f5f5f5;
      border-left: 4px solid #4caf50;
      padding: 15px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .security-note p {
      margin: 0;
      font-size: 14px;
      color: #2e7d32;
    }
    .footer {
      text-align: center;
      padding: 30px;
      background-color: #f9f9f9;
      border-radius: 0 0 8px 8px;
      color: #999999;
      font-size: 12px;
    }
    .footer p {
      margin: 5px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔐 Verify Your Account</h1>
    </div>
    <div class="content">
      <div class="greeting">Hello $userName,</div>
      <div class="message">
        You've requested to verify your account. Use the verification code below to complete the process.
      </div>
      <div class="otp-container">
        <div class="otp-code">$otpCode</div>
        <div class="otp-label">Your 6-digit verification code</div>
      </div>
      <div class="validity">
        <p>⏰ This code will expire in 5 minutes for security reasons.</p>
      </div>
      <div class="security-note">
        <p>🔒 Security Alert: Never share this code with anyone. EtherShare staff will never ask for this code.</p>
      </div>
      <div class="message">
        If you didn't request this code, please ignore this email or contact support if you're concerned.
      </div>
    </div>
    <div class="footer">
      <p><strong>EtherShare Security Team</strong></p>
      <p>This is an automated email. Please do not reply.</p>
      <p>© 2024 EtherShare. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''';
  }
  
  /// Get email plain text template
  String _getEmailPlainText({
    required String otpCode,
    required String userName,
  }) {
    return '''
Verify Your Account

Hello $userName,

You've requested to verify your account. Use the verification code below to complete the process.

Your Verification Code: $otpCode

This code will expire in 5 minutes for security reasons.

Security Alert: Never share this code with anyone. EtherShare staff will never ask for this code.

If you didn't request this code, please ignore this email or contact support if you're concerned.

Best regards,
EtherShare Security Team

This is an automated email. Please do not reply.
© 2024 EtherShare. All rights reserved.
''';
  }
  
  /// Create SMTP server configuration
  SmtpServer _createSmtpServer() {
    if (_smtpHost == null || _smtpUsername == null || _smtpPassword == null) {
      throw Exception('SMTP not configured. Please call configureSMTP() first.');
    }
    
    // Try to detect provider
    final host = _smtpHost!.toLowerCase();
    
    if (host.contains('gmail')) {
      return gmail(_smtpUsername!, _smtpPassword!);
    } else if (host.contains('sendgrid')) {
      return SmtpServer(
        'smtp.sendgrid.net',
        username: _smtpUsername,
        password: _smtpPassword,
        port: 587,
      );
    } else {
      // Custom SMTP server
      return SmtpServer(
        _smtpHost!,
        username: _smtpUsername,
        password: _smtpPassword,
        port: _smtpPort ?? 587,
      );
    }
  }
  
  /// Send OTP via email
  /// 
  /// Returns true if OTP was sent successfully, false otherwise
  Future<bool> sendOTP({
    required String email,
    String? userName,
    int? maxRetries,
    Duration? timeout,
  }) async {
    return await _errorHandler.handle2FAError(
      () async {
        // Validate email
        if (!_isValidEmail(email)) {
          throw Exception('Invalid email format');
        }
        
        // Check rate limit
        final canSend = await _checkRateLimit(email);
        if (!canSend) {
          throw Exception('Too many OTP requests. Please try again in 1 hour.');
        }
        
        // Generate OTP
        final otp = _generateOTP();
        print('Generated OTP for $email: $otp');
        
        // Store OTP securely
        await _storeOtpData(email, otp);
        
        // Send email with retry mechanism
        final success = await _sendEmailWithRetry(
          to: email,
          otp: otp,
          userName: userName ?? 'User',
          maxRetries: maxRetries ?? 3,
          timeout: timeout ?? const Duration(seconds: 30),
        );
        
        if (success) {
          await _recordOtpAttempt(email, 1);
          print('OTP email sent successfully to $email');
        }
        
        return success;
      },
      'sendOTP',
      retryable: true,
      customErrorMessage: 'Failed to send verification email',
    );
  }
  
  /// Send email with retry mechanism
  Future<bool> _sendEmailWithRetry({
    required String to,
    required String otp,
    required String userName,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    Exception? lastException;
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Create SMTP server
        final smtpServer = _createSmtpServer();
        
        // Create email message
        final message = Message()
          ..from = Address(_smtpUsername ?? _defaultFromEmail, _defaultFromName)
          ..recipients.add(to)
          ..subject = 'Your EtherShare Verification Code'
          ..html = _getEmailTemplate(otpCode: otp, userName: userName)
          ..text = _getEmailPlainText(otpCode: otp, userName: userName);
        
        // Send email with timeout
        await send(message, smtpServer).timeout(timeout);
        
        print('Email sent successfully to $to (attempt ${attempt + 1})');
        return true;
      } on TimeoutException catch (e) {
        lastException = e;
        print('Email send timeout (attempt ${attempt + 1}): $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      } on MailerException catch (e) {
        lastException = e;
        print('Email send error (attempt ${attempt + 1}): $e');
        if (attempt < maxRetries - 1 && _shouldRetry(e)) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        } else {
          throw Exception('Failed to send email: ${e.message}');
        }
      } catch (e) {
        lastException = Exception('Unexpected error: $e');
        print('Unexpected email error (attempt ${attempt + 1}): $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }
    
    throw Exception('Failed to send email after $maxRetries attempts: $lastException');
  }
  
  /// Check if error is retryable
  bool _shouldRetry(MailerException error) {
    // Don't retry on authentication errors
    if (error.toString().contains('authentication')) return false;
    
    // Don't retry on invalid recipient errors
    if (error.toString().contains('recipient')) return false;
    
    // Retry on network or server errors
    return error.toString().contains('network') ||
           error.toString().contains('timeout') ||
           error.toString().contains('server');
  }
  
  /// Verify OTP code
  /// 
  /// Returns true if OTP is valid and not expired, false otherwise
  Future<bool> verifyOTP({
    required String email,
    required String code,
  }) async {
    return await _errorHandler.handle2FAError(
      () async {
        // Validate input
        if (code.length != _otpLength) {
          print('Invalid OTP length: ${code.length} (expected: $_otpLength)');
          return false;
        }
        
        if (!_isValidEmail(email)) {
          throw Exception('Invalid email format');
        }
        
        // Get OTP data
        final otpData = await _getOtpData(email);
        
        if (otpData == null) {
          print('No OTP found for $email');
          return false;
        }
        
        // Check expiration
        if (DateTime.now().isAfter(otpData.expiresAt)) {
          print('OTP expired for $email');
          await _clearOtpData(email);
          return false;
        }
        
        // Check attempts
        if (otpData.attempts >= 3) {
          print('Too many OTP verification attempts for $email');
          return false;
        }
        
        // Update attempts
        otpData.attempts++;
        await _storeOtpData(email, otpData.otp);
        
        // Verify code
        if (otpData.otp == code) {
          print('OTP verified successfully for $email');
          await _clearOtpData(email);
          return true;
        }
        
        print('Invalid OTP code for $email');
        return false;
      },
      'verifyOTP',
      retryable: false,
      customErrorMessage: 'Failed to verify OTP code',
    );
  }
  
  /// Clear OTP data after successful verification
  Future<void> _clearOtpData(String email) async {
    try {
      _activeOtpCache.remove(email);
      
      final otpKey = _otpDataKey + email;
      await _storage.delete(key: otpKey);
      
      print('Cleared OTP data for $email');
    } catch (e) {
      print('Clear OTP data error: $e');
    }
  }
  
  /// Check if OTP is still valid
  Future<bool> isOTPValid(String email) async {
    try {
      final otpData = await _getOtpData(email);
      
      if (otpData == null) return false;
      
      if (DateTime.now().isAfter(otpData.expiresAt)) {
        return false;
      }
      
      return otpData.attempts < 3;
    } catch (e) {
      print('Check OTP validity error: $e');
      return false;
    }
  }
  
  /// Get remaining time for OTP
  Duration getRemainingTime(String email) {
    try {
      final otpData = _activeOtpCache[email];
      
      if (otpData == null) return Duration.zero;
      
      final remaining = otpData.expiresAt.difference(DateTime.now());
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      return Duration.zero;
    }
  }
  
  /// Resend OTP (generates new OTP)
  Future<bool> resendOTP({
    required String email,
    String? userName,
  }) async {
    // Clear old OTP
    await _clearOtpData(email);
    
    // Send new OTP
    return await sendOTP(
      email: email,
      userName: userName,
    );
  }
  
  /// Get OTP statistics for an email
  Future<Map<String, dynamic>> getOtpStats(String email) async {
    try {
      final otpData = await _getOtpData(email);
      final attemptsKey = _otpAttemptsKey + email;
      final attemptsJson = await _storage.read(key: attemptsKey);
      
      if (otpData == null) {
        return {
          'hasActiveOtp': false,
          'attemptsCount': 0,
          'remainingTime': 0,
        };
      }
      
      final attemptsCount = attemptsJson != null
          ? (jsonDecode(attemptsJson) as Map<String, dynamic>)['count'] as int
          : 0;
      
      final remaining = getRemainingTime(email).inSeconds;
      
      return {
        'hasActiveOtp': true,
        'attemptsCount': otpData.attempts,
        'remainingTime': remaining,
        'otpRequests': attemptsCount,
        'expiresAt': otpData.expiresAt.toIso8601String(),
      };
    } catch (e) {
      print('Get OTP stats error: $e');
      return {
        'hasActiveOtp': false,
        'attemptsCount': 0,
        'remainingTime': 0,
      };
    }
  }
  
  /// Test email configuration
  Future<bool> testEmailConfiguration() async {
    try {
      final smtpServer = _createSmtpServer();
      
      final testMessage = Message()
        ..from = Address(_smtpUsername ?? _defaultFromEmail, _defaultFromName)
        ..recipients.add(_smtpUsername ?? _defaultFromEmail)
        ..subject = 'EtherShare Email Configuration Test'
        ..text = 'This is a test email from EtherShare Email OTP Service.';
      
      await send(testMessage, smtpServer).timeout(const Duration(seconds: 30));
      
      print('Email configuration test successful');
      return true;
    } catch (e) {
      print('Email configuration test failed: $e');
      return false;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _cacheCleanupTimer?.cancel();
    _activeOtpCache.clear();
    _errorHandler.dispose();
  }
}

/// OTP data class
class _OTPData {
  final String otp;
  final String email;
  final DateTime createdAt;
  final DateTime expiresAt;
  int attempts;
  
  _OTPData({
    required this.otp,
    required this.email,
    required this.createdAt,
    required this.expiresAt,
    this.attempts = 0,
  });
}

