import 'package:flutter/material.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:email_validator/email_validator.dart';
import 'create_workspace_page.dart';
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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String _status = '';
  bool _isLoading = false;
  bool _show2FASetupPrompt = false;
  String? _emailError;
  SecureStorageService? _storageService;

  @override
  void initState() {
    super.initState();
    _show2FASetupPrompt = widget.show2FASetup;
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      _storageService = await SecureStorageService.create();
    } catch (e) {
      print('Error initializing SecureStorageService: $e');
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
    // Validate username
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _status = 'Please enter your name';
      });
      return;
    }

    // Validate email if 2FA is enabled or prompted
    if (_show2FASetupPrompt || widget.show2FASetup) {
      if (!_validateEmail(_emailController.text.trim())) {
        setState(() {
          _status = _emailError ?? 'Please enter a valid email address';
        });
        return;
      }
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
        print('📝 Username: ${_usernameController.text.trim()}');
        print('📝 Email: ${_emailController.text.trim()}');
        
        if (dbAddress != null) {
          final profileMessage = {
            'type': 'profile',
            'userAddress': key,
            'username': _usernameController.text.trim(),
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
          await prefs.setString('username', _usernameController.text.trim());
          await prefs.setString('email', _emailController.text.trim());
          
          // Store email securely for 2FA
          if (_emailController.text.trim().isNotEmpty && _storageService != null) {
            await _storageService!.storeSecureData('2fa_email', _emailController.text.trim());
            print('Email stored securely for 2FA: ${_emailController.text.trim()}');
          }
          
          setState(() {
            _isLoading = false;
            _status = 'Profile saved successfully to OrbitDB!';
          });
          
          // Show 2FA setup prompt for new users, otherwise go to workspace creation
          if (_show2FASetupPrompt) {
            await _show2FASetupDialog();
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => CreateWorkspacePage(userAddress: widget.address)),
            );
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

  Future<void> _show2FASetupDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Secure Your Account',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security,
                size: 48,
                color: Colors.blue[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'Would you like to enable Two-Factor Authentication (2FA) for enhanced security?',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                '2FA adds an extra layer of security to protect your account from unauthorized access.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => CreateWorkspacePage(userAddress: widget.address)),
                );
              },
              child: const Text('Skip for Now'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateTo2FASetup();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Enable 2FA'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _navigateTo2FASetup() async {
    try {
      final email = _emailController.text.trim();
      
      // Validate email before navigating
      if (!_validateEmail(email)) {
        setState(() {
          _status = _emailError ?? 'Please enter a valid email address';
        });
        return;
      }
      
      // Navigate to 2FA setup if requested, otherwise go to workspace creation
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Setup2FAScreen(
            userId: widget.address,
            preFilledEmail: email,
          ),
        ),
      );
    } catch (e) {
      print('❌ Error saving profile: $e');
      setState(() {
        _status = 'Error navigating to 2FA setup: $e';
      });
    }
  }

  Future<void> _setup2FA() async {
    // Validate username first
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _status = 'Please enter your name before setting up 2FA';
      });
      return;
    }

    final email = _emailController.text.trim();
    
    // Validate email before setting up 2FA
    if (!_validateEmail(email)) {
      setState(() {
        _status = _emailError ?? 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Saving profile and setting up 2FA...';
    });

    try {
      // First, save the profile to OrbitDB (same as _saveProfile but without navigation)
      final key = widget.address.toLowerCase().trim();
      final dbName = 'profile_$key';
      
      print('💾 [2FA Flow] Saving profile before 2FA setup...');
      print('📝 [2FA Flow] Database name: $dbName');
      print('📝 [2FA Flow] Username: ${_usernameController.text.trim()}');
      print('📝 [2FA Flow] Email: $email');
      
      // Create the database first
      final dbAddress = await OrbitDBService.createChatDB(dbName);
      
      if (dbAddress != null) {
        final profileMessage = {
          'type': 'profile',
          'userAddress': key,
          'username': _usernameController.text.trim(),
          'email': email,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        print('📋 [2FA Flow] Profile message to save: $profileMessage');
        
        final result = await OrbitDBService.addMessage(dbAddress, profileMessage);
        
        if (result != null) {
          print('✅ [2FA Flow] Profile saved successfully with hash: $result');
          
          // Verify the save
          print('🔍 [2FA Flow] Verifying profile save...');
          final verifyMessages = await OrbitDBService.getMessages(dbAddress);
          print('📨 [2FA Flow] Retrieved ${verifyMessages.length} messages after save');
          for (var msg in verifyMessages) {
            print('📄 [2FA Flow] Message: type=${msg['type']}, userAddress=${msg['userAddress']}, username=${msg['username']}');
          }
          
          // Also save to SharedPreferences for backward compatibility
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('username', _usernameController.text.trim());
          await prefs.setString('email', email);
          
          // Store email securely for 2FA
          if (email.isNotEmpty && _storageService != null) {
            await _storageService!.storeSecureData('2fa_email', email);
            print('✅ [2FA Flow] Email stored securely for 2FA: $email');
          }
          
          print('✅ [2FA Flow] Profile saved successfully, navigating to 2FA setup...');
          
          setState(() {
            _isLoading = false;
            _status = 'Profile saved! Setting up 2FA...';
          });
          
          // Now navigate to 2FA setup screen
          // Use pushReplacement so user can't go back to profile setup
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => Setup2FAScreen(
                userId: widget.address,
                preFilledEmail: email,
              ),
            ),
          );
        } else {
          print('❌ [2FA Flow] Failed to save profile message');
          setState(() {
            _isLoading = false;
            _status = 'Error saving profile. Please try again.';
          });
        }
      } else {
        print('❌ [2FA Flow] Failed to create profile database');
        setState(() {
          _isLoading = false;
          _status = 'Error creating profile database. Please try again.';
        });
      }
    } catch (e) {
      print('❌ [2FA Flow] Error saving profile: $e');
      setState(() {
        _isLoading = false;
        _status = 'Error saving profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Profile Setup',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar image
              const CircleAvatar(
                radius: 100,
                backgroundImage: AssetImage('assets/ProfileIcon.png'), // 👈 Your image here
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 24),
              
              // Heading
              const Text(
                'Setup your profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Name Field
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Email Field
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Email (required for 2FA)',
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _emailError != null ? Colors.red : Colors.grey,
                      width: _emailError != null ? 2 : 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _emailError != null ? Colors.red : Colors.grey,
                      width: _emailError != null ? 2 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _emailError != null ? Colors.red : Colors.blue,
                      width: 2,
                    ),
                  ),
                  errorText: _emailError,
                  errorStyle: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
                onChanged: (value) {
                  // Clear error when user starts typing
                  if (_emailError != null && value.isNotEmpty) {
                    setState(() {
                      _emailError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Status Message
              if (_status.isNotEmpty) ...[
                Container(
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
                const SizedBox(height: 16),
              ],

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : const Text('Save'),
                ),
              ),

              // 2FA Setup Option (for existing users)
              if (!_show2FASetupPrompt) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _setup2FA,
                    icon: const Icon(Icons.security, size: 18),
                    label: const Text('Setup 2FA'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
