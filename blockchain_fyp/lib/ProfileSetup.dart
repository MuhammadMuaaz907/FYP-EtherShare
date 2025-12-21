import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:email_validator/email_validator.dart';
import 'screens/setup_2fa_screen.dart';
import 'services/secure_storage_service.dart';
import 'services/distributed_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String address;
  final bool show2FASetup;

  const ProfileSetupScreen({
    super.key, 
    required this.address,
    this.show2FASetup = false,
  });

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  String _status = '';
  bool _isLoading = false;
  String? _emailError;
  SecureStorageService? _storageService;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadExistingProfile();
  }

  Future<void> _initializeServices() async {
    try {
      _storageService = await SecureStorageService.create();
    } catch (e) {
      print('Error initializing SecureStorageService: $e');
    }
  }

  /// Load existing profile data from Distributed System
  Future<void> _loadExistingProfile() async {
    try {
      final profile = await DistributedService.getUserProfile(widget.address);

      if (profile != null) {
        // Load existing data into controllers
        setState(() {
          _firstNameController.text = profile['firstName']?.toString() ?? '';
          _lastNameController.text = profile['lastName']?.toString() ?? '';
          _emailController.text = profile['email']?.toString() ?? '';
          _designationController.text = profile['designation']?.toString() ?? '';
        });
        print('✅ Loaded existing profile data from MongoDB');
        return;
      }
      
      // Fallback: Try loading from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _firstNameController.text = prefs.getString('firstName') ?? '';
        _lastNameController.text = prefs.getString('lastName') ?? '';
        _emailController.text = prefs.getString('email') ?? '';
        _designationController.text = prefs.getString('designation') ?? '';
      });
    } catch (e) {
      print('⚠️ Error loading existing profile: $e');
    }
  }

  /// Validate email format
  bool _validateEmail(String email) {
    if (email.trim().isEmpty) {
      setState(() {
        _emailError = 'Email is required for 2FA';
      });
      return false;
    }

    if (!EmailValidator.validate(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address';
      });
      return false;
    }

    setState(() {
      _emailError = null;
    });
    return true;
  }

  Future<void> _saveProfile() async {
    // Validate first name
    if (_firstNameController.text.trim().isEmpty) {
      setState(() {
        _status = 'Please enter your first name';
      });
      return;
    }

    // Validate last name
    if (_lastNameController.text.trim().isEmpty) {
      setState(() {
        _status = 'Please enter your last name';
      });
      return;
    }

    // Validate email (required for 2FA)
    if (!_validateEmail(_emailController.text.trim())) {
      setState(() {
        _status = _emailError ?? 'Please enter a valid email address';
      });
      return;
    }
    
    // Check username uniqueness before saving
    final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
    
    // Check if username is already taken
    try {
      final existingProfile = await DistributedService.getUserProfile(widget.address);
      final currentUsername = existingProfile?['username']?.toString() ?? '';
      
      // Only check if username is different from current
      if (currentUsername.toLowerCase() != fullName.toLowerCase()) {
        // Check if username is available
        final testResult = await DistributedService.saveUserProfile(
          address: widget.address,
          username: fullName,
          email: _emailController.text.trim(),
        );
        
        if (testResult['isDuplicate'] == true) {
          setState(() {
            _status = testResult['error'] ?? 'Username "$fullName" is already taken. Please choose a different name.';
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      print('⚠️ Error checking username uniqueness: $e');
      // Continue with save - backend will catch duplicates
    }

    setState(() {
      _isLoading = true;
      _status = 'Saving profile...';
    });

    try {
      // Save profile to MongoDB
      print('💾 Saving profile to MongoDB...');
      print('📝 User address: ${widget.address}');
      print('📝 First Name: ${_firstNameController.text.trim()}');
      print('📝 Last Name: ${_lastNameController.text.trim()}');
      print('📝 Designation: ${_designationController.text.trim()}');
      print('📝 Email: ${_emailController.text.trim()}');
      
      // Combine first and last name for username (backward compatibility)
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      
      // Always save to local storage first (offline support)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', fullName);
      await prefs.setString('firstName', _firstNameController.text.trim());
      await prefs.setString('lastName', _lastNameController.text.trim());
      await prefs.setString('designation', _designationController.text.trim());
      await prefs.setString('email', _emailController.text.trim());
      
      // Store email securely for 2FA
      if (_emailController.text.trim().isNotEmpty && _storageService != null) {
        await _storageService!.storeSecureData('2fa_email', _emailController.text.trim());
        print('✅ Email stored securely for 2FA: ${_emailController.text.trim()}');
      }
      
      print('✅ Profile saved to local storage');
      
      // Try to save to Distributed System (backend)
      final result = await DistributedService.saveUserProfile(
        address: widget.address,
        username: fullName,
        email: _emailController.text.trim(),
      );
      
      if (result['success'] == true) {
        print('✅ Profile saved successfully to MongoDB');
        
        setState(() {
          _isLoading = false;
          _status = 'Profile saved successfully!';
        });
        
        // Navigate to 2FA setup only if show2FASetup is true (onboarding flow)
        if (widget.show2FASetup) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => Setup2FAScreen(
                  userId: widget.address,
                  preFilledEmail: _emailController.text.trim(),
                ),
              ),
            );
          }
        } else {
          // For edit mode, just pop back to profile page
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.pop(context, true); // Return true to indicate success
          }
        }
      } else {
        // Backend save failed, but local save succeeded
        final errorMsg = result['error'] ?? 'Unknown error';
        final isNetworkError = result['isNetworkError'] == true;
        
        print('⚠️ Failed to save profile to MongoDB: $errorMsg');
        print('✅ Profile saved locally - will sync when backend is available');
        
        // Show user-friendly message
        String userMessage;
        if (isNetworkError) {
          userMessage = 'Profile saved locally!\n\n'
              '⚠️ Could not connect to server.\n'
              'Your profile is saved on this device and will sync when the server is available.\n\n'
              'To fix:\n'
              '1. Ensure backend server is running\n'
              '2. Check your network connection\n'
              '3. Verify PC IP address is correct';
        } else {
          userMessage = 'Profile saved locally!\n\n'
              '⚠️ Server error: $errorMsg\n'
              'Your profile is saved on this device.';
        }
        
        // Show dialog with option to continue or retry
        if (mounted) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Profile Saved Locally'),
              content: Text(userMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false), // Retry
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true), // Continue
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          
          if (shouldContinue == true) {
            // User chose to continue - proceed with navigation
            setState(() {
              _isLoading = false;
              _status = 'Profile saved locally';
            });
            
            if (widget.show2FASetup) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Setup2FAScreen(
                      userId: widget.address,
                      preFilledEmail: _emailController.text.trim(),
                    ),
                  ),
                );
              }
            } else {
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) {
                Navigator.pop(context, true);
              }
            }
          } else {
            // User chose to retry - call save again
            setState(() {
              _isLoading = false;
              _status = 'Retrying...';
            });
            await Future.delayed(const Duration(milliseconds: 500));
            await _saveProfile(); // Retry
          }
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error saving profile: $e';
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
          backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F365F),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 25,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Complete Profile',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
              ) ?? const TextStyle(
                color: Colors.white,
              fontSize: 20,
                fontWeight: FontWeight.w600,
            ),
          ),
        centerTitle: false,
        elevation: 0,
      ),
      body: SafeArea(
        top: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Link your Email Section
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F365F),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 8,
                          color: const Color(0x36000000),
                          offset: const Offset(0.0, 4),
                        ),
                      ],
                      borderRadius: BorderRadius.circular(8),
        ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Card(
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                color: const Color(0xFF0F365F),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.email_outlined,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 0, 0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 0, 0),
                                        child: Text(
                                          'Link your Email',
                                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                                fontFamily: 'Inter',
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.bold,
                                              ) ?? const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
        ),
                                        ),
      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 12, 0),
                                        child: Text(
                                          'Enable security by connecting your Email.',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontFamily: 'Inter',
                                                fontSize: 12,
                                                letterSpacing: 0.0,
                                              ) ?? const TextStyle(
                                                fontSize: 12,
                                              ),
                ),
              ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(0, 16, 0, 0),
                            child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                                hintText: 'Email',
                                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'Inter',
                                      letterSpacing: 0.0,
                                    ) ?? const TextStyle(fontSize: 14),
                  enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0F365F),
                                    width: 2,
                    ),
                                  borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0F365F),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                                  borderRadius: BorderRadius.circular(8),
                  ),
                                filled: true,
                                fillColor: const Color(0x4CFEFEFF),
                  errorText: _emailError,
                  ),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Inter',
                                    letterSpacing: 0.0,
                                  ) ?? const TextStyle(fontSize: 14),
                onChanged: (value) {
                  if (_emailError != null && value.isNotEmpty) {
                    setState(() {
                      _emailError = null;
                    });
                  }
                },
              ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              // Your information Section
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      'Your information',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Inter',
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.bold,
                          ) ?? const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              
              // Form Fields
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 16, 0, 0),
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontFamily: 'Inter',
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(fontSize: 14),
                          hintText: ' ',
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFF0F365F),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Inter',
                              letterSpacing: 0.0,
                            ) ?? const TextStyle(fontSize: 14),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 16, 0, 0),
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontFamily: 'Inter',
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(fontSize: 14),
                          hintText: ' ',
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFF0F365F),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Inter',
                              letterSpacing: 0.0,
                            ) ?? const TextStyle(fontSize: 14),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 16, 0, 0),
                      child: TextFormField(
                        controller: _designationController,
                        decoration: InputDecoration(
                          labelText: 'Designation',
                          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontFamily: 'Inter',
                                letterSpacing: 0.0,
                              ) ?? const TextStyle(fontSize: 14),
                          hintText: ' ',
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xFF0F365F),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Inter',
                              letterSpacing: 0.0,
                            ) ?? const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              // Status Message
              if (_status.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _status.contains('successful') 
                        ? Colors.green[100] 
                        : _status.contains('Error') 
                            ? Colors.red[100] 
                            : Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _status.contains('successful') 
                          ? Colors.green[800] 
                          : _status.contains('Error') 
                              ? Colors.red[800] 
                              : Colors.blue[800],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ),
              ],

              // Save Button
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                child: SizedBox(
                  width: 270,
                  height: 50,
                  child: FilledButton(
                  onPressed: _isLoading ? null : _saveProfile,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F365F),
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                            width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                              color: Colors.white,
                          ),
                        )
                        : Text(
                            'Save',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  letterSpacing: 0.0,
                                ) ?? const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _designationController.dispose();
    super.dispose();
  }
}
