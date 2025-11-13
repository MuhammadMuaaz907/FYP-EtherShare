import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import '../services/email_otp_service.dart';
import '../services/secure_storage_service.dart';
import '../services/biometric_service.dart';
import '../services/orbitdb_service.dart';
import '../services/invite_link_manager.dart';
import '../services/invite_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../home_screen.dart';
import '../workspace_home_page.dart';
import 'accept_invite_screen.dart';

/// Comprehensive 2FA Verification Screen with Email OTP
/// 
/// This screen provides:
/// - Email OTP code verification with validation
/// - Biometric authentication option
/// - Backup code verification
/// - Rate limiting and security features
/// - Integration with existing login flow
/// - Proper error handling and user feedback
class Verify2FAScreen extends StatefulWidget {
  final String userId;
  final String userAddress;
  final String? userEmail; // Added for email display

  const Verify2FAScreen({
    super.key,
    required this.userId,
    required this.userAddress,
    this.userEmail,
  });

  @override
  State<Verify2FAScreen> createState() => _Verify2FAScreenState();
}

class _Verify2FAScreenState extends State<Verify2FAScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _animationController;
  late AnimationController _successController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Services
  EmailOTPService? _emailOtpService;
  SecureStorageService? _storageService;

  // State variables
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _backupCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _status = '';
  int _remainingTime = 300; // 5 minutes for email OTP
  int _attemptCount = 0;
  bool _isLocked = false;
  DateTime? _lockoutUntil;
  bool _verificationSuccess = false;
  Timer? _countdownTimer;
  String _userEmail = '';
  bool _canResend = false;
  int _currentStep = 0; // 0 = biometric, 1 = OTP, 2 = backup code

  // Rate limiting constants
  static const int _maxAttempts = 3;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    try {
      // Initialize services
      _emailOtpService = await EmailOTPService.create();
      _storageService = await SecureStorageService.create();

      // Check biometric availability and settings
      _biometricAvailable = await BiometricService.isBiometricAvailable();
      _biometricEnabled = await _storageService!.isBiometricEnabled();

      // Check if 2FA is enabled
      final is2FAEnabled = await _storageService!.isUser2FAEnabled();
      if (!is2FAEnabled) {
        // Skip 2FA verification if not enabled
        _navigateToHome();
        return;
      }

      // Get user email from storage or parameter
      _userEmail = widget.userEmail ?? await _getStoredEmail() ?? '';
      
      // Configure SMTP via environment variables (see .env.example)
      final username = dotenv.env['SMTP_USERNAME'] ?? '';
      final password = dotenv.env['SMTP_PASSWORD'] ?? '';
      final host = dotenv.env['SMTP_HOST'] ?? '';
      final portStr = dotenv.env['SMTP_PORT'] ?? '';
      final useSecureStr = dotenv.env['SMTP_SECURE'] ?? 'true';

      if (username.isEmpty || password.isEmpty || host.isEmpty || portStr.isEmpty) {
        throw Exception('SMTP configuration missing. Define SMTP_USERNAME, SMTP_PASSWORD, SMTP_HOST, SMTP_PORT in .env');
      }

      final port = int.tryParse(portStr) ?? 587;
      final useSecure = useSecureStr.toLowerCase() != 'false';

      await _emailOtpService!.configureSMTP(
        username: username,
        password: password,
        host: host,
        port: port,
        useSecure: useSecure,
      );
      
      // DO NOT SEND OTP automatically - only when user navigates to OTP screen
      
      setState(() {
        _isLoading = false;
        _status = ''; // No status message on biometric screen
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error initializing verification: $e';
      });
    }
  }

  /// Get stored email from secure storage
  Future<String?> _getStoredEmail() async {
    try {
      final email = await _storageService!.getSecureData('2fa_email');
      return email;
    } catch (e) {
      print('Error getting stored email: $e');
      return null;
    }
  }

  /// Start countdown timer for email OTP
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _remainingTime = 300; // 5 minutes
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _verificationSuccess) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  /// Format time for display (MM:SS)
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Mask email for display (e.g., user@example.com -> u***@ex***.com)
  String _maskEmail(String email) {
    if (email.isEmpty) return '';
    
    final parts = email.split('@');
    if (parts.length != 2) return email;
    
    final localPart = parts[0];
    final domainPart = parts[1];
    
    final maskedLocal = localPart.length > 1 
        ? '${localPart[0]}${'*' * (localPart.length - 1)}'
        : localPart;
    
    final domainParts = domainPart.split('.');
    if (domainParts.length >= 2) {
      final maskedDomain = domainParts[0].length > 2
          ? '${domainParts[0].substring(0, 2)}${'*' * (domainParts[0].length - 2)}'
          : domainParts[0];
      return '$maskedLocal@$maskedDomain.${domainParts.last}';
    }
    
    return '$maskedLocal@$domainPart';
  }

  /// Verify email OTP code
  Future<void> _verifyTOTPCode() async {
    if (_codeController.text.isEmpty) {
      setState(() => _status = 'Please enter a verification code');
      return;
    }

    if (_isLocked && _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final remainingTime = _lockoutUntil!.difference(DateTime.now()).inMinutes;
      setState(() => _status = 'Too many failed attempts. Please try again in $remainingTime minutes.');
      return;
    } else if (_isLocked) {
      // Reset lockout if time has passed
      setState(() {
        _isLocked = false;
        _attemptCount = 0;
        _lockoutUntil = null;
      });
    }

    setState(() => _isLoading = true);

    try {
      if (_userEmail.isEmpty) {
        setState(() {
          _isLoading = false;
          _status = 'Email not found. Please setup 2FA first.';
        });
        return;
      }

      final isValid = await _emailOtpService!.verifyOTP(
        email: _userEmail,
        code: _codeController.text,
      );
      
      if (isValid) {
        await _handleSuccessfulVerification();
      } else {
        await _handleFailedAttempt();
      }
    } catch (e) {
      await _handleFailedAttempt();
      setState(() {
        _isLoading = false;
        _status = 'Error verifying code: $e';
      });
    }
  }

  /// Ensure SMTP is configured
  Future<void> _ensureSMTPConfigured() async {
    try {
      // Check if dotenv is initialized
      if (!dotenv.isInitialized) {
        // Try to load .env file from assets (for mobile) or root (for web/desktop)
        try {
          await dotenv.load(fileName: '.env');
        } catch (e1) {
          // Try loading from assets as fallback
          try {
            await dotenv.load(fileName: 'assets/.env');
          } catch (e2) {
            throw Exception(
              'Environment file (.env) not found or could not be loaded.\n\n'
              'Please create a .env file in the blockchain_fyp directory with:\n\n'
              'SMTP_USERNAME=your_email@gmail.com\n'
              'SMTP_PASSWORD=your_app_password\n'
              'SMTP_HOST=smtp.gmail.com\n'
              'SMTP_PORT=587\n'
              'SMTP_SECURE=true\n\n'
              'After creating .env, ensure it is listed in pubspec.yaml assets section,\n'
              'then restart your app with: flutter clean && flutter run\n\n'
              'Error: $e1'
            );
          }
        }
      }
      
      // Try to configure SMTP from environment variables
      final username = dotenv.env['SMTP_USERNAME'] ?? '';
      final password = dotenv.env['SMTP_PASSWORD'] ?? '';
      final host = dotenv.env['SMTP_HOST'] ?? '';
      final portStr = dotenv.env['SMTP_PORT'] ?? '';
      final useSecureStr = dotenv.env['SMTP_SECURE'] ?? 'true';

      if (username.isEmpty || password.isEmpty || host.isEmpty || portStr.isEmpty) {
        throw Exception(
          'SMTP configuration is missing.\n\n'
          'Please create a .env file in the blockchain_fyp directory with the following:\n\n'
          'SMTP_USERNAME=your_email@gmail.com\n'
          'SMTP_PASSWORD=your_app_password\n'
          'SMTP_HOST=smtp.gmail.com\n'
          'SMTP_PORT=587\n'
          'SMTP_SECURE=true\n\n'
          'For Gmail, you need to use an App Password, not your regular password.'
        );
      }

      final port = int.tryParse(portStr) ?? 587;
      final useSecure = useSecureStr.toLowerCase() != 'false';

      await _emailOtpService!.configureSMTP(
        username: username,
        password: password,
        host: host,
        port: port,
        useSecure: useSecure,
      );
    } catch (e) {
      throw Exception('Failed to configure SMTP: $e');
    }
  }

  /// Resend OTP via email
  Future<void> _resendOTP() async {
    if (_userEmail.isEmpty) {
      setState(() => _status = 'Email not found');
      return;
    }

    if (!_canResend) {
      setState(() => _status = 'Please wait before requesting a new code');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      // Ensure SMTP is configured before resending OTP
      await _ensureSMTPConfigured();
      
      final resent = await _emailOtpService!.resendOTP(
        email: _userEmail,
        userName: widget.userId,
      );

      if (resent) {
        setState(() {
          _status = 'New code sent! Check your email.';
          _codeController.clear();
          _startCountdownTimer();
        });
      } else {
        setState(() => _status = 'Failed to resend code');
      }
    } catch (e) {
      setState(() => _status = 'Error resending code: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyBackupCode() async {
    if (_backupCodeController.text.isEmpty) {
      setState(() => _status = 'Please enter a backup code');
      return;
    }

    if (_isLocked && _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final remainingTime = _lockoutUntil!.difference(DateTime.now()).inMinutes;
      setState(() => _status = 'Too many failed attempts. Please try again in $remainingTime minutes.');
      return;
    } else if (_isLocked) {
      // Reset lockout if time has passed
      setState(() {
        _isLocked = false;
        _attemptCount = 0;
        _lockoutUntil = null;
      });
    }

    setState(() => _isLoading = true);

    try {
      final success = await _storageService!.useBackupCode(_backupCodeController.text);
      
      if (success) {
        await _handleSuccessfulVerification();
      } else {
        await _handleFailedAttempt();
        setState(() {
          _isLoading = false;
          _status = 'Invalid backup code. Please try again.';
        });
        _backupCodeController.clear();
      }
    } catch (e) {
      await _handleFailedAttempt();
      setState(() {
        _isLoading = false;
        _status = 'Error verifying backup code: $e';
      });
    }
  }

  Future<void> _authenticateWithBiometric() async {
    if (!_biometricAvailable || !_biometricEnabled) {
      setState(() => _status = 'Biometric authentication is not available. Please use OTP verification.');
      // Automatically switch to OTP screen if biometric is not available
      Future.delayed(const Duration(seconds: 1), () {
        _goToOTPScreen();
      });
      return;
    }

    if (_isLocked && _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final remainingTime = _lockoutUntil!.difference(DateTime.now()).inMinutes;
      setState(() => _status = 'Too many failed attempts. Please try again in $remainingTime minutes.');
      // Switch to OTP as fallback
      Future.delayed(const Duration(seconds: 1), () {
        _goToOTPScreen();
      });
      return;
    } else if (_isLocked) {
      // Reset lockout if time has passed
      setState(() {
        _isLocked = false;
        _attemptCount = 0;
        _lockoutUntil = null;
      });
    }

    setState(() => _isLoading = true);

    try {
      final isAuthenticated = await BiometricService.authenticate(
        reason: 'Authenticate to verify your identity',
      );

      if (isAuthenticated) {
        await _handleSuccessfulVerification();
      } else {
        await _handleFailedAttempt();
        setState(() {
          _isLoading = false;
          _status = 'Biometric authentication failed. Please use OTP verification.';
        });
        // Switch to OTP screen as fallback
        Future.delayed(const Duration(seconds: 1), () {
          _goToOTPScreen();
        });
      }
    } catch (e) {
      print('⚠️ Biometric authentication error: $e');
      // If biometric fails due to FragmentActivity issue, gracefully fallback to OTP
      if (e.toString().contains('FragmentActivity') || e.toString().contains('no_fragment_activity')) {
        setState(() {
          _isLoading = false;
          _status = 'Biometric authentication unavailable. Switching to OTP verification...';
        });
        // Automatically switch to OTP screen
        Future.delayed(const Duration(seconds: 1), () {
          _goToOTPScreen();
        });
      } else {
        await _handleFailedAttempt();
        setState(() {
          _isLoading = false;
          _status = 'Biometric authentication error. Please use OTP verification.';
        });
        // Switch to OTP screen as fallback
        Future.delayed(const Duration(seconds: 1), () {
          _goToOTPScreen();
        });
      }
    }
  }

  Future<void> _handleSuccessfulVerification() async {
    setState(() {
      _verificationSuccess = true;
      _isLoading = false;
      _status = 'Verification successful!';
    });

    // Play success animation
    _successController.forward();

    // Wait for animation and navigate
    await Future.delayed(const Duration(milliseconds: 1500));
    _navigateToHome();
  }

  Future<void> _handleFailedAttempt() async {
    _attemptCount++;
    
    if (_attemptCount >= _maxAttempts) {
      _isLocked = true;
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
      setState(() {
        _isLoading = false;
        _status = 'Too many failed attempts. Please try again in 5 minutes.';
      });
    } else {
      final remainingAttempts = _maxAttempts - _attemptCount;
      setState(() {
        _isLoading = false;
        _status = 'Invalid code. $remainingAttempts attempts remaining.';
      });
      _codeController.clear();
    }
  }

  Future<void> _navigateToHome() async {
    if (mounted) {
      try {
        // Fetch workspace details from OrbitDB
        String workspaceName = 'YourWorkspace';
        String channelName = 'general';
        
        try {
          final key = widget.userAddress.toLowerCase().trim();
          final dbName = 'workspace_$key';
          final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
          
          if (dbAddress != null) {
            final messages = await OrbitDBService.getMessages(dbAddress);
            
            // Find workspace message for this user
            for (var message in messages) {
              if (message['type'] == 'workspace' && message['userAddress'] == key) {
                final workspaceDetails = jsonDecode(message['workspaceDetails']);
                workspaceName = workspaceDetails['workspaceName'] ?? workspaceName;
                channelName = workspaceDetails['channelName'] ?? channelName;
                break;
              }
            }
          }
        } catch (e) {
          print('Error fetching workspace details: $e');
        }
        
        // Save login session to persistent storage
        await OrbitDBService.saveLoginSession(widget.userAddress, workspaceName, channelName);
        
        // Check for pending invites
        final pendingInvite = await InviteLinkManager.instance.consumePendingInvite();
        
        if (pendingInvite != null) {
          final resolved = await InviteService.resolveInvite(pendingInvite);
          if (resolved != null && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => AcceptInviteScreen(
                  invite: resolved,
                  userAddress: widget.userAddress,
                  onComplete: () async {
                    await InviteLinkManager.instance.clearPendingInvite();
                  },
                ),
              ),
            );
            return;
          }
        }
        
        // Navigate to workspace home page
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TeamHomePage(
                workspaceName: workspaceName,
                channelName: channelName,
              ),
            ),
          );
        }
      } catch (e) {
        print('Error navigating to workspace: $e');
        // Fallback to home screen if workspace navigation fails
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    }
  }

  void _goToOTPScreen() async {
    setState(() {
      _currentStep = 1;
      _animationController.reset();
      _animationController.forward();
    });
    
    // SEND OTP when user navigates to OTP screen
    if (_userEmail.isNotEmpty) {
      setState(() => _isLoading = true);
      
      try {
        // Ensure SMTP is configured before sending OTP
        await _ensureSMTPConfigured();
        
        print('Sending OTP to $_userEmail');
        final sent = await _emailOtpService!.sendOTP(
          email: _userEmail,
          userName: widget.userId,
        );
        
        if (sent) {
          print('OTP sent successfully to $_userEmail');
          _startCountdownTimer();
          setState(() {
            _status = 'We sent a code to your email';
            _isLoading = false;
          });
        } else {
          setState(() {
            _status = 'Failed to send OTP. Please try again.';
            _isLoading = false;
          });
        }
      } catch (e) {
        print('Error sending OTP: $e');
        setState(() {
          _status = 'Error sending OTP: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _goToBackupCodeScreen() {
    setState(() {
      _currentStep = 2;
      _animationController.reset();
      _animationController.forward();
    });
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 32),
        const Text(
          'Verify Your Identity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Complete your login with two-factor authentication',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Address: ${widget.userAddress.substring(0, 6)}...${widget.userAddress.substring(widget.userAddress.length - 4)}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBiometricSection() {
    if (!_biometricAvailable) {
      return const SizedBox.shrink();
    }

    // If biometric is available but not enabled, show a message
    if (!_biometricEnabled) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange),
        ),
        child: Column(
          children: [
            Icon(
              Icons.fingerprint,
              size: 48,
              color: Colors.orange[700],
            ),
            const SizedBox(height: 12),
            const Text(
              'Biometric Authentication',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can enable biometric authentication in 2FA settings for quicker access',
              style: TextStyle(fontSize: 14, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.blue[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue[200]!, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.fingerprint,
              size: 56,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Quick Biometric Login',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use your fingerprint or face ID\nfor instant authentication',
            style: TextStyle(fontSize: 15, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _authenticateWithBiometric,
              icon: const Icon(Icons.fingerprint, size: 28),
              label: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Authenticate with Biometric',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _goToOTPScreen,
            child: const Text(
              'Or enter OTP code instead',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTOTPCodeSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.email,
                color: Colors.blue[700],
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Email Verification',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _userEmail.isNotEmpty 
                ? 'We sent a code to your email\n${_maskEmail(_userEmail)}'
                : 'Enter the 6-digit code from your email',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          
          // Code Input Field
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue[700]!,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onSubmitted: (_) => _verifyTOTPCode(),
          ),
          
          const SizedBox(height: 16),
          
          // Timer Display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _remainingTime <= 60 
                  ? Colors.red[50] 
                  : Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _remainingTime <= 60 
                    ? Colors.red[200]! 
                    : Colors.blue[200]!,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer,
                  size: 16,
                  color: _remainingTime <= 60 
                      ? Colors.red[600] 
                      : Colors.blue[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Code expires in ${_formatTime(_remainingTime)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _remainingTime <= 60 
                        ? Colors.red[700] 
                        : Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Resend OTP button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Didn\'t receive code? ',
                style: TextStyle(color: Colors.grey[600]),
              ),
              TextButton(
                onPressed: _isLoading || !_canResend ? null : _resendOTP,
                child: Text(
                  _canResend ? 'Resend OTP' : 'Resend in ${_formatTime(_remainingTime)}',
                  style: TextStyle(
                    color: _canResend ? Colors.blue[700] : Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Verify Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyTOTPCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Verify Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Use Backup Code Link
          TextButton(
            onPressed: _goToBackupCodeScreen,
            child: const Text(
              'Use Backup Code Instead',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCodeSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.backup,
                color: Colors.orange[700],
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Backup Code',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter your backup code to complete verification',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 24),
          
          // Backup Code Input Field
          TextField(
            controller: _backupCodeController,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: 'Enter backup code',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.orange[300]!, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.orange[700]!,
                  width: 2,
                ),
              ),
            ),
            onSubmitted: (_) => _verifyBackupCode(),
          ),
          
          const SizedBox(height: 20),
          
          // Verify Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyBackupCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Verify Backup Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage() {
    if (_status.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _status.contains('successful') || _status.contains('Verification')
            ? Colors.green[100]
            : _status.contains('attempts') || _status.contains('failed')
                ? Colors.red[100]
                : Colors.blue[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _status.contains('successful') || _status.contains('Verification')
              ? Colors.green[300]!
              : _status.contains('attempts') || _status.contains('failed')
                  ? Colors.red[300]!
                  : Colors.blue[300]!,
        ),
      ),
      child: Text(
        _status,
        style: TextStyle(
          color: _status.contains('successful') || _status.contains('Verification')
              ? Colors.green[800]
              : _status.contains('attempts') || _status.contains('failed')
                  ? Colors.red[800]
                  : Colors.blue[800],
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSuccessAnimation() {
    if (!_verificationSuccess) return const SizedBox.shrink();

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          children: [
            Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green[600],
            ),
            const SizedBox(height: 16),
            Text(
              'Verification Successful!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Redirecting to home screen...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF00163A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00163A),
        foregroundColor: Colors.white,
        title: const Text('Two-Factor Authentication'),
        elevation: 0,
        automaticallyImplyLeading: false, // Prevent back navigation
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    
                    if (_verificationSuccess) ...[
                      _buildSuccessAnimation(),
                    ] else if (_currentStep == 0) ...[
                      // Step 1: Biometric Screen
                      _buildBiometricSection(),
                    ] else if (_currentStep == 1) ...[
                      // Step 2: OTP Screen
                      _buildTOTPCodeSection(),
                    ] else if (_currentStep == 2) ...[
                      // Step 3: Backup Code Screen
                      _buildBackupCodeSection(),
                    ],
                    
                    _buildStatusMessage(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animationController.dispose();
    _successController.dispose();
    _codeController.dispose();
    _backupCodeController.dispose();
    super.dispose();
  }
}