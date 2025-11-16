import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:email_validator/email_validator.dart';
import 'screens/setup_2fa_screen.dart';
import 'services/secure_storage_service.dart';
import 'services/orbitdb_service.dart';

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

  /// Load existing profile data from OrbitDB
  Future<void> _loadExistingProfile() async {
    try {
      final key = widget.address.toLowerCase().trim();
      final dbName = 'profile_$key';
      final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);

      if (dbAddress != null) {
        final messages = await OrbitDBService.getMessages(dbAddress);
        
        for (var message in messages) {
          if (message['type'] == 'profile' &&
              message['userAddress']?.toString().toLowerCase() == key) {
            // Load existing data into controllers
            setState(() {
              _firstNameController.text = message['firstName']?.toString() ?? '';
              _lastNameController.text = message['lastName']?.toString() ?? '';
              _emailController.text = message['email']?.toString() ?? '';
              _designationController.text = message['designation']?.toString() ?? '';
            });
            print('✅ Loaded existing profile data');
            return;
          }
        }
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

    setState(() {
      _isLoading = true;
      _status = 'Saving profile...';
    });

    try {
      // Save profile to OrbitDB instead of local storage
      final key = widget.address.toLowerCase().trim();
      final dbName = 'profile_$key';
      
      // Create the database first (this will store the address in cache)
      final dbAddress = await OrbitDBService.createChatDB(dbName);
      
        print('💾 Saving profile to database: $dbAddress');
        print('📝 Database name: $dbName');
        print('📝 User address: $key');
        print('📝 First Name: ${_firstNameController.text.trim()}');
        print('📝 Last Name: ${_lastNameController.text.trim()}');
        print('📝 Designation: ${_designationController.text.trim()}');
        print('📝 Email: ${_emailController.text.trim()}');
        
        if (dbAddress != null) {
          // Combine first and last name for username (backward compatibility)
          final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
          
          final profileMessage = {
            'type': 'profile',
            'userAddress': key,
            'username': fullName,
            'firstName': _firstNameController.text.trim(),
            'lastName': _lastNameController.text.trim(),
            'designation': _designationController.text.trim(),
            'email': _emailController.text.trim(),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          
          print('📋 Profile message to save: $profileMessage');
          print('📋 Profile message keys: ${profileMessage.keys.toList()}');
          
          final result = await OrbitDBService.addMessage(dbAddress, profileMessage);
          
          if (result != null) {
            print('✅ Profile saved successfully with hash: $result');
            print('📌 Database address cached for future use: $dbAddress');
            print('📌 Database name: $dbName');
            
            // Verify the save by immediately reading it back
            print('🔍 Verifying profile save...');
            final verifyMessages = await OrbitDBService.getMessages(dbAddress);
            print('📨 Retrieved ${verifyMessages.length} messages after save');
            for (var msg in verifyMessages) {
              print('📄 Message: type=${msg['type']}, userAddress=${msg['userAddress']}, username=${msg['username']}');
            }
          
          // Also save to SharedPreferences for backward compatibility
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', fullName);
          await prefs.setString('firstName', _firstNameController.text.trim());
          await prefs.setString('lastName', _lastNameController.text.trim());
          await prefs.setString('designation', _designationController.text.trim());
          await prefs.setString('email', _emailController.text.trim());
          
          // Store email securely for 2FA
          if (_emailController.text.trim().isNotEmpty && _storageService != null) {
            await _storageService!.storeSecureData('2fa_email', _emailController.text.trim());
            print('Email stored securely for 2FA: ${_emailController.text.trim()}');
          }
          
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
          print('❌ Failed to save profile message');
          setState(() {
            _isLoading = false;
            _status = 'Error saving profile to OrbitDB';
          });
        }
      } else {
        print('❌ Failed to create profile database');
        setState(() {
          _status = 'Error creating profile database';
          _isLoading = false;
        });
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
