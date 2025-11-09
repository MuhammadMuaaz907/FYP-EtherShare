import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/email_otp_service.dart';
import '../services/secure_storage_service.dart';
import '../services/biometric_service.dart';
import '../create_workspace_page.dart'; // For workspace creation after 2FA setup
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Comprehensive 2FA Setup Screen with Email OTP
/// 
/// This screen provides:
/// - Email-based 2FA setup with OTP verification
/// - Email input with pre-filled profile email
/// - OTP code input with countdown timer
/// - Resend OTP functionality with rate limiting
/// - Backup codes generation and display
/// - Success navigation to CreateWorkspacePage (workspace management flow)
/// - Integration with EmailOTPService and SecureStorageService
class Setup2FAScreen extends StatefulWidget {
  final String userId;
  final String? preFilledEmail;

  const Setup2FAScreen({
    super.key,
    required this.userId,
    this.preFilledEmail,
  });

  @override
  State<Setup2FAScreen> createState() => _Setup2FAScreenState();
}

class _Setup2FAScreenState extends State<Setup2FAScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _animationController;
  late AnimationController _progressController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Services
  EmailOTPService? _emailOtpService;
  SecureStorageService? _storageService;

  // State variables
  int _currentStep = 0;
  String _userEmail = '';
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  List<String> _backupCodes = [];
  String _status = '';
  bool _codeVerified = false;
  int _remainingTime = 300; // 5 minutes in seconds
  bool _otpSent = false;
  Timer? _countdownTimer;
  bool _canResend = false;

  // Text controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  // Step titles
  final List<String> _stepTitles = [
    'Enter Email',
    'Verify OTP',
    'Backup Codes',
    'Complete Setup',
  ];

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

    _progressController = AnimationController(
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

    _animationController.forward();
    _progressController.forward();
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    try {
      // Initialize services
      _emailOtpService = await EmailOTPService.create();
      _storageService = await SecureStorageService.create();

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

      // Check biometric availability
      _biometricAvailable = await BiometricService.isBiometricAvailable();

      // Pre-fill email if provided
      if (widget.preFilledEmail != null && widget.preFilledEmail!.isNotEmpty) {
        _emailController.text = widget.preFilledEmail!;
        _userEmail = widget.preFilledEmail!;
      }

      // Generate backup codes
      _backupCodes = _generateBackupCodes();
      print('Generated ${_backupCodes.length} backup codes');

      setState(() {
        _isLoading = false;
        _status = '2FA setup initialized successfully';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error initializing 2FA: $e';
      });
    }
  }

  /// Generate backup codes
  List<String> _generateBackupCodes() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final codes = <String>[];
    
    for (int i = 0; i < 10; i++) {
      final code = (random + i * 1000).toString().substring(0, 8);
      codes.add(code.toUpperCase());
    }
    
    return codes;
  }

  /// Start countdown timer for OTP
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _remainingTime = 300; // 5 minutes
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
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

  /// Send OTP to email
  Future<void> _sendOTP() async {
    if (_emailController.text.isEmpty) {
      setState(() => _status = 'Please enter your email address');
      return;
    }

    // Validate email format
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)) {
      setState(() => _status = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      // Ensure SMTP is configured before sending OTP
      await _ensureSMTPConfigured();
      
      final sent = await _emailOtpService!.sendOTP(
        email: _emailController.text,
        userName: widget.userId,
      );

      if (sent) {
        setState(() {
          _otpSent = true;
          _userEmail = _emailController.text;
          _status = 'OTP sent successfully! Check your email.';
        });
        _startCountdownTimer();
        _nextStep();
      } else {
        setState(() => _status = 'Failed to send OTP. Please try again.');
      }
    } catch (e) {
      setState(() => _status = 'Error sending OTP: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Verify OTP code
  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) {
      setState(() => _status = 'Please enter a valid 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      final verified = await _emailOtpService!.verifyOTP(
        email: _userEmail,
        code: _otpController.text,
      );

      if (verified) {
        setState(() {
          _codeVerified = true;
          _status = 'OTP verified successfully!';
        });
        _countdownTimer?.cancel();
        _nextStep();
      } else {
        setState(() {
          _status = 'Invalid OTP code. Please try again.';
          _otpController.clear();
        });
      }
    } catch (e) {
      setState(() => _status = 'Error verifying OTP: $e');
    } finally {
      setState(() => _isLoading = false);
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

  /// Resend OTP
  Future<void> _resendOTP() async {
    if (!_canResend) {
      setState(() => _status = 'Please wait before requesting a new OTP');
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
        setState(() => _status = 'New OTP sent! Check your email.');
        _otpController.clear();
        _startCountdownTimer();
      } else {
        setState(() => _status = 'Failed to resend OTP');
      }
    } catch (e) {
      setState(() => _status = 'Error resending OTP: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _nextStep() {
    if (_currentStep < _stepTitles.length - 1) {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _enable2FA() async {
    setState(() => _isLoading = true);

    try {
      // Store backup codes
      await _storageService!.storeBackupCodes(_backupCodes);
      print('Backup codes stored successfully (${_backupCodes.length} codes)');

      // Store biometric preference
      await _storageService!.setBiometricEnabled(_biometricEnabled);
      print('Biometric enabled status set to: $_biometricEnabled');
      
      // If biometric is enabled, verify it's enrolled on device
      if (_biometricEnabled) {
        final isEnrolled = await BiometricService.isBiometricEnrolled();
        if (!isEnrolled) {
          setState(() {
            _isLoading = false;
            _status = 'Please set up biometric authentication in your device settings first';
          });
          return;
        }
        print('Biometric verification confirmed - user has biometrics enrolled');
      }

      // Store email-based 2FA info
      await _storageService!.storeSecureData('2fa_email', _userEmail);

      // Enable 2FA
      await _storageService!.setUser2FAStatus(true);
      print('User 2FA status set to: true');

      setState(() {
        _isLoading = false;
        _status = '2FA enabled successfully!';
      });

      // Show success dialog
      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error enabling 2FA: $e';
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600], size: 28),
            const SizedBox(width: 12),
            const Text(
              'Setup Complete!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Two-factor authentication has been successfully enabled for your account.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.popUntil(context, (route) => route.isFirst); // Pop all routes
              // Navigate to workspace creation page after 2FA setup
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => CreateWorkspacePage(userAddress: widget.userId)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_stepTitles.length, (index) {
              final isActive = index <= _currentStep;
              final isCompleted = index < _currentStep;
              
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCompleted 
                            ? Colors.green[600]
                            : isActive 
                                ? Colors.blue[700]
                                : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                    if (index < _stepTitles.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isCompleted ? Colors.green[600] : Colors.grey[300],
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            _stepTitles[_currentStep],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildEmailStep();
      case 1:
        return _buildOTPVerificationStep();
      case 2:
        return _buildBackupCodesStep();
      case 3:
        return _buildCompletionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEmailStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.email, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Enter Email',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter your email address to receive the verification code. This email will be used for two-factor authentication.',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isLoading && !_otpSent,
            decoration: InputDecoration(
              labelText: 'Email Address',
              hintText: 'user@example.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading || _otpSent ? null : _sendOTP,
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
                      'Send OTP',
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

  Widget _buildOTPVerificationStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Verify OTP',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Enter the 6-digit code sent to $_userEmail',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 20),
          
          // Countdown Timer
          if (_remainingTime > 0 && !_codeVerified)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Code expires in: ${_formatTime(_remainingTime)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 20),
          
          // OTP Input
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            enabled: !_isLoading && !_codeVerified,
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
                borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Resend OTP
          if (!_codeVerified) ...[
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
          ],
          
          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading || _codeVerified ? null : _previousStep,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading || _codeVerified ? null : _verifyOTP,
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
                      : Text(
                          _codeVerified ? 'Verified ✓' : 'Verify',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCodesStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.backup, color: Colors.orange[700], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Backup Codes',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Save these backup codes in a secure location. You can use them to access your account if you lose access to your email.',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            height: 250,
            child: ListView.builder(
              itemCount: _backupCodes.length,
              itemBuilder: (context, index) {
                final code = _backupCodes[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _copyToClipboard(code),
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy code',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _previousStep,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('I\'ve Saved Them'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[600], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Complete Setup',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Review your 2FA settings and complete the setup:',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 20),
          
          // Settings Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                _buildSettingRow('Email 2FA', 'Enabled', Icons.email),
                _buildSettingRow('Backup Codes', '${_backupCodes.length} codes', Icons.backup),
                if (_biometricAvailable)
                  _buildSettingRow('Biometric Auth', _biometricEnabled ? 'Enabled' : 'Disabled', Icons.fingerprint),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Biometric Option
          if (_biometricAvailable) ...[
            SwitchListTile(
              title: const Text('Enable Biometric Authentication'),
              subtitle: const Text('Use fingerprint or face ID for quick access'),
              value: _biometricEnabled,
              onChanged: (value) {
                setState(() {
                  _biometricEnabled = value;
                });
              },
              activeColor: Colors.blue[700],
            ),
            const SizedBox(height: 20),
          ],
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _enable2FA,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
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
                      'Enable 2FA',
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

  Widget _buildSettingRow(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
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
        title: const Text('Setup Two-Factor Authentication'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildProgressIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildStepContent(),
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _status.contains('successful') || _status.contains('verified')
                                  ? Colors.green[100]
                                  : Colors.red[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _status.contains('successful') || _status.contains('verified')
                                    ? Colors.green[300]!
                                    : Colors.red[300]!,
                              ),
                            ),
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: _status.contains('successful') || _status.contains('verified')
                                    ? Colors.green[800]
                                    : Colors.red[800],
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _progressController.dispose();
    _countdownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}
