import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/contract_service.dart';
import '../services/session_service.dart';
import '../services/distributed_service.dart';
import '../ProfileSetup.dart';
import 'package:web3dart/web3dart.dart';
import '../workspace_home_page.dart';
import '../services/secure_storage_service.dart';
import 'verify_2fa_screen.dart';
import '../screens/sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _privateKeyController = TextEditingController();
  final FocusNode _privateKeyFocusNode = FocusNode();
  String _status = '';
  bool _isLoading = false;
  bool _isProcessing = false; // Prevent multiple simultaneous sign-in attempts

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  /// Safely updates state only if widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _signIn() async {
    // Prevent multiple simultaneous calls
    if (_isProcessing) {
      print('⚠️ Sign-in already in progress, ignoring duplicate call');
      return;
    }

    final privateKey = _privateKeyController.text.trim();
    
    if (privateKey.isEmpty) {
      _safeSetState(() {
        _status = 'Please enter your private key';
      });
      return;
    }

    // Validate private key format
    if (privateKey.length < 64) {
      _safeSetState(() {
        _status = 'Invalid private key format';
        _isLoading = false;
      });
      return;
    }

    // Set processing flag and loading state
    _isProcessing = true;
    _safeSetState(() {
      _isLoading = true;
      _status = 'Signing in...';
    });

    final contractService = Provider.of<ContractService?>(context, listen: false);
    if (contractService == null) {
      _isProcessing = false;
      _safeSetState(() {
        _status = 'Contract service not initialized';
        _isLoading = false;
      });
      return;
    }

    try {
      // Validate and extract address from private key
      final credentials = EthPrivateKey.fromHex(
        privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey,
      );
      final address = credentials.address.hex;
      
      print('🔐 Starting sign-in process for address: $address');
      
      // Step 1: Check registration with timeout
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      _safeSetState(() {
        _status = 'Verifying account...';
      });
      
      final isRegistered = await contractService.isRegistered(address).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('Connection timeout. Please check your network connection.');
        },
      );
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      if (!isRegistered) {
        _isProcessing = false;
        _safeSetState(() {
          _status = 'Account not found. Please sign up first.';
          _isLoading = false;
        });
        return;
      }
      
      // Step 2: Check profile and workspace in parallel for better performance
      _safeSetState(() {
        _status = 'Checking profile...';
      });
      
      bool hasProfile = false;
      bool workspaceExists = false;
      
      // Run profile and workspace checks in parallel
      try {
        final results = await Future.wait<bool>([
          contractService.hasCompletedProfile(address).timeout(
            const Duration(seconds: 8),
            onTimeout: () => false,
          ).catchError((e) {
            print('⚠️ Profile check error: $e');
            return false;
          }),
          contractService.doesWorkspaceExist(address).timeout(
            const Duration(seconds: 8),
            onTimeout: () => false,
          ).catchError((e) {
            print('⚠️ Workspace check error: $e');
            return false;
          }),
        ]);
        
        hasProfile = results[0];
        workspaceExists = results[1];
      } catch (e) {
        print('⚠️ Error checking profile/workspace: $e');
        hasProfile = false;
        workspaceExists = false;
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      print('🔍 Sign In Debug Info:');
      print('  - isRegistered: $isRegistered');
      print('  - hasProfile: $hasProfile');
      print('  - workspaceExists: $workspaceExists');
      
      // Step 3: Handle incomplete profile/workspace
      if (!hasProfile || !workspaceExists) {
        print('⚠️ User registered but profile/workspace incomplete');
        _isProcessing = false;
        _safeSetState(() {
          _status = 'Completing setup...';
          _isLoading = false;
        });
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(
                address: address,
                show2FASetup: true,
              ),
            ),
          );
        }
        return;
      }
      
      // Step 4: Check 2FA status
      _safeSetState(() {
        _status = 'Checking security settings...';
      });
      
      SecureStorageService? storageService;
      bool is2FAEnabled = false;
      try {
        storageService = await SecureStorageService.create();
        is2FAEnabled = await storageService.isUser2FAEnabled();
        print('🔐 2FA Status: ${is2FAEnabled ? "ENABLED" : "DISABLED"}');
      } catch (e) {
        print('⚠️ Error checking 2FA status: $e');
        is2FAEnabled = false;
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      // Step 5: Handle 2FA or direct login
      if (is2FAEnabled) {
        print('🔐 2FA is enabled - navigating to verification screen');
        _isProcessing = false;
        _safeSetState(() {
          _status = '2FA verification required...';
          _isLoading = false;
        });
        
        if (mounted) {
          String? userEmail;
          try {
            final profile = await DistributedService.getUserProfile(address).timeout(
              const Duration(seconds: 8),
              onTimeout: () => null,
            ).catchError((e) {
              print('⚠️ Error fetching user email: $e');
              return null;
            });
            userEmail = profile?['email']?.toString();
          } catch (e) {
            print('⚠️ Error fetching user email: $e');
          }
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => Verify2FAScreen(
                  userId: address,
                  userAddress: address,
                  userEmail: userEmail,
                ),
              ),
            );
          }
        }
        return;
      }
      
      // Step 6: Complete login and navigate to workspace
      print('✅ 2FA not enabled - redirecting to workspace');
      _safeSetState(() {
        _status = 'Sign in successful! Redirecting...';
        _isLoading = false;
      });
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      String workspaceName = 'YourWorkspace';
      String channelName = 'general';
      
      try {
        final workspaces = await DistributedService.getUserWorkspaces(address).timeout(
          const Duration(seconds: 8),
          onTimeout: () => [],
        ).catchError((e) {
          print('⚠️ Error fetching workspace details: $e');
          return <Map<String, dynamic>>[];
        });
        
        if (workspaces.isNotEmpty) {
          workspaceName = workspaces.first['name']?.toString() ?? 'YourWorkspace';
          channelName = workspaces.first['defaultChannel']?.toString() ?? 'general';
        }
      } catch (e) {
        print('⚠️ Error fetching workspace details: $e');
      }
      
      await SessionService.saveLoginSession(address, workspaceName, channelName);
      
      if (mounted) {
        _isProcessing = false;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeamHomePage(
              workspaceName: workspaceName,
              channelName: channelName,
            ),
          ),
        );
      } else {
        _isProcessing = false;
      }
      
    } catch (e) {
      print('❌ Sign in error: $e');
      _isProcessing = false;
      
      String errorMessage = 'Sign in failed. Please try again.';
      if (e is TimeoutException) {
        errorMessage = 'Connection timeout. Please check your network and try again.';
      } else if (e.toString().contains('Invalid private key') || 
                 e.toString().contains('Invalid hex')) {
        errorMessage = 'Invalid private key format. Please check and try again.';
      } else if (e.toString().contains('Connection')) {
        errorMessage = 'Network error. Please check your connection.';
      }
      
      _safeSetState(() {
        _status = errorMessage;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _isProcessing = false; // Reset processing flag
    _privateKeyController.dispose();
    _privateKeyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: true,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  width: 100,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  alignment: AlignmentDirectional(0, -1),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 140,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                              topLeft: Radius.circular(0),
                              topRight: Radius.circular(0),
                            ),
                          ),
                          alignment: AlignmentDirectional(-1, 0),
                          child: Align(
                            alignment: AlignmentDirectional(-1, -1),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.black,
                                  size: 24,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional(0, -1),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 20),
                                    child: Text(
                                      'Welcome Back',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                            fontFamily: 'Inter',
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.bold,
                                          ) ?? const TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.0,
                                          ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    child: TextFormField(
                                      controller: _privateKeyController,
                                      focusNode: _privateKeyFocusNode,
                                      autofocus: true,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: 'Private Key',
                                        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontFamily: 'Inter',
                                              letterSpacing: 0.0,
                                            ) ?? const TextStyle(
                                              fontSize: 14,
                                              letterSpacing: 0.0,
                                            ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE0E0E0),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0xFF0F365F),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.red,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.red,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF5F5F5),
                                      ),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontFamily: 'Inter',
                                            letterSpacing: 0.0,
                                          ) ?? const TextStyle(
                                            fontSize: 14,
                                            letterSpacing: 0.0,
                                          ),
                                    ),
                                  ),
                                ),
                                if (_status.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                    child: Text(
                                      _status,
                                      style: TextStyle(
                                        color: _status.contains('Error') || 
                                               _status.contains('failed') ||
                                               _status.contains('timeout') ||
                                               _status.contains('not found')
                                            ? Colors.red
                                            : _status.contains('successful') || 
                                              _status.contains('Redirecting')
                                                ? Colors.green
                                                : Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                    height: 44,
                                    child: FilledButton(
                                      onPressed: (_isLoading || _isProcessing) ? null : _signIn,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F365F),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
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
                                              'Sign In',
                                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                    fontFamily: 'Inter',
                                                    color: Colors.white,
                                                    letterSpacing: 0.0,
                                                  ) ?? const TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    letterSpacing: 0.0,
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional(0, -1),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 12),
                                    child: RichText(
                                      textScaler: MediaQuery.of(context).textScaler,
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Don\'t have an account? ',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  fontFamily: 'Inter',
                                                  letterSpacing: 0.0,
                                                ) ?? const TextStyle(
                                                  fontSize: 14,
                                                  letterSpacing: 0.0,
                                                ),
                                          ),
                                          TextSpan(
                                            text: ' Sign Up here',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF0F365F),
                                                  letterSpacing: 0.0,
                                                ) ?? const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF0F365F),
                                                  letterSpacing: 0.0,
                                                ),
                                            mouseCursor: SystemMouseCursors.click,
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () {
                                                Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => const SignUpScreen(),
                                                  ),
                                                );
                                              },
                                          ),
                                        ],
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontFamily: 'Inter',
                                              letterSpacing: 0.0,
                                            ) ?? const TextStyle(
                                              fontSize: 14,
                                              letterSpacing: 0.0,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isDesktop(context))
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        'https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=1380&q=80',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F365F),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          );
                        },
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
}

