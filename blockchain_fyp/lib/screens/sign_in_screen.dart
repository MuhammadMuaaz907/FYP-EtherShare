import 'dart:async';
import 'dart:io';
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
      // Normalize address to lowercase for consistent database lookups
      final address = credentials.address.hex.toLowerCase();
      
      print('🔐 Starting sign-in process for address: $address');
      
      // Step 1: Check if user exists in backend database first (primary check)
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      _safeSetState(() {
        _status = 'Verifying account...';
      });
      
      // Step 1: Check backend server health first
      _safeSetState(() {
        _status = 'Connecting to server...';
      });
      
      bool backendReachable = false;
      try {
        print('🔍 Checking backend server health...');
        backendReachable = await DistributedService.checkHealth().timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            print('⏱️ Backend health check timed out');
            return false;
          },
        ).catchError((e) {
          print('⚠️ Backend health check error: $e');
          return false;
        });
        
        if (backendReachable) {
          print('✅ Backend server is reachable');
        } else {
          print('❌ Backend server is unreachable');
        }
      } catch (e) {
        print('❌ Error checking backend health: $e');
        backendReachable = false;
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      // Step 2: Check backend database if server is reachable
      Map<String, dynamic>? backendProfile;
      bool isNetworkError = false;
      
      if (backendReachable) {
        try {
          print('🔍 Checking backend database for address: $address');
          _safeSetState(() {
            _status = 'Verifying account...';
          });
          
          backendProfile = await DistributedService.getUserProfile(address).timeout(
            const Duration(seconds: 6),
            onTimeout: () {
              print('⏱️ Backend profile check timed out');
              return null;
            },
          ).catchError((e) {
            print('⚠️ Backend profile check error: $e');
            // Check if it's a network error
            if (e is SocketException || e.toString().contains('SocketException') || 
                e.toString().contains('No route to host') || 
                e.toString().contains('Connection refused')) {
              isNetworkError = true;
            }
            return null;
          });
          
          if (backendProfile != null) {
            print('✅ Backend profile found:');
            print('   - Address: ${backendProfile['address']}');
            print('   - Username: ${backendProfile['username']}');
            print('   - Email: ${backendProfile['email']}');
            print('   - First Name: ${backendProfile['firstName'] ?? "N/A"}');
            print('   - Last Name: ${backendProfile['lastName'] ?? "N/A"}');
            print('   - All keys: ${backendProfile.keys.toList()}');
          } else {
            print('❌ Backend profile not found for address: $address');
            if (isNetworkError) {
              print('⚠️ Network error detected during profile fetch');
            }
          }
        } catch (e) {
          print('❌ Error checking backend profile: $e');
          backendProfile = null;
          if (e is SocketException || e.toString().contains('SocketException') || 
              e.toString().contains('No route to host')) {
            isNetworkError = true;
          }
        }
      } else {
        // Backend is not reachable - this is a network/server issue
        print('❌ Backend server is not reachable - cannot verify profile');
        isNetworkError = true;
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      // Step 3: Handle different scenarios
      if (backendProfile != null) {
        // User exists in backend database - proceed with sign-in
        print('✅ User found in backend database - proceeding with sign-in');
        // Continue to profile/workspace check below
      } else if (isNetworkError || !backendReachable) {
        // Backend is unreachable - show error and don't redirect to profile setup
        print('❌ Backend server unreachable - cannot verify account');
        _isProcessing = false;
        _safeSetState(() {
          _status = 'Cannot connect to server. Please check:\n1. Backend server is running\n2. Device and PC are on same network\n3. Firewall allows port 3000';
          _isLoading = false;
        });
        return;
      } else {
        // Backend is reachable but user doesn't exist - check blockchain as fallback
        _safeSetState(() {
          _status = 'Checking blockchain registration...';
        });
        
        final isRegistered = await contractService.isRegistered(address).timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        ).catchError((e) {
          print('⚠️ Blockchain check error: $e');
          return false;
        });
        
        if (!mounted) {
          _isProcessing = false;
          return;
        }
        
        if (!isRegistered) {
          // User doesn't exist anywhere - need to sign up
          _isProcessing = false;
          _safeSetState(() {
            _status = 'Account not found. Please sign up first.';
            _isLoading = false;
          });
          return;
        } else {
          // User exists on blockchain but not in backend - incomplete setup
          print('⚠️ User registered on blockchain but profile not in backend database');
          _isProcessing = false;
          _safeSetState(() {
            _status = 'You are already signed up. Please complete your profile setup.';
            _isLoading = false;
          });
          
          // Navigate to profile setup after a short delay
          await Future.delayed(const Duration(milliseconds: 1500));
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
      }
      
      // Step 2: User exists in backend - check profile completeness and workspace membership
      _safeSetState(() {
        _status = 'Loading your workspace...';
      });
      
      // Since user exists in backend, check if profile is complete
      bool hasCompleteProfile = false;
      bool hasWorkspaceMembership = false;
      List<Map<String, dynamic>> userWorkspaces = [];
      
      // Check profile completeness from backend data
      // backendProfile is guaranteed to be non-null here since we're in the "exists" branch
      final username = backendProfile['username']?.toString().trim();
      final email = backendProfile['email']?.toString().trim();
      
      // Profile is complete if username and email exist and are not empty
      // firstName, lastName, designation are optional but username and email are required
      hasCompleteProfile = username != null && 
                          username.isNotEmpty && 
                          email != null && 
                          email.isNotEmpty;
      
      print('📋 Profile completeness check:');
      print('   - Username: "${username ?? "MISSING"}" (length: ${username != null ? username.length : 0})');
      print('   - Email: "${email ?? "MISSING"}" (length: ${email != null ? email.length : 0})');
      print('   - First Name: ${backendProfile['firstName'] ?? "optional"}');
      print('   - Last Name: ${backendProfile['lastName'] ?? "optional"}');
      print('   - Username is not null: ${username != null}');
      print('   - Username is not empty: ${username != null && username.isNotEmpty}');
      print('   - Email is not null: ${email != null}');
      print('   - Email is not empty: ${email != null && email.isNotEmpty}');
      print('   - Result: ${hasCompleteProfile ? "✅ COMPLETE" : "❌ INCOMPLETE"}');
      
      // Check workspace membership (user can be creator OR member)
      try {
        print('🔍 Checking workspace membership for: $address');
        userWorkspaces = await DistributedService.getUserWorkspaces(address).timeout(
          const Duration(seconds: 6),
          onTimeout: () {
            print('⏱️ Workspace check timed out');
            return <Map<String, dynamic>>[];
          },
        ).catchError((e) {
          print('⚠️ Workspace check error: $e');
          return <Map<String, dynamic>>[];
        });
        
        hasWorkspaceMembership = userWorkspaces.isNotEmpty;
        
        if (hasWorkspaceMembership) {
          print('✅ User has workspace membership: ${userWorkspaces.length} workspace(s)');
          for (var ws in userWorkspaces) {
            print('   - Workspace: ${ws['name'] ?? ws['workspaceName'] ?? "Unknown"} (ID: ${ws['workspace_id'] ?? ws['workspaceId']})');
            print('     Keys: ${ws.keys.toList()}');
          }
        } else {
          print('⚠️ User has no workspace membership (empty array returned)');
        }
      } catch (e) {
        print('❌ Error checking workspace membership: $e');
        print('   Error type: ${e.runtimeType}');
        hasWorkspaceMembership = false;
        userWorkspaces = [];
      }
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      print('🔍 Sign In Debug Summary:');
      print('  - Backend Profile: ✅ EXISTS');
      print('  - hasCompleteProfile: ${hasCompleteProfile ? "✅ YES" : "❌ NO"}');
      print('  - hasWorkspaceMembership: ${hasWorkspaceMembership ? "✅ YES" : "❌ NO"}');
      print('  - Workspace Count: ${userWorkspaces.length}');
      print('  - Next Action: ${hasCompleteProfile && hasWorkspaceMembership ? "→ Proceed to 2FA/Workspace Home" : hasCompleteProfile ? "→ Create Workspace" : "→ Complete Profile"}');
      
      // Step 3: Handle incomplete profile/workspace
      if (!hasCompleteProfile) {
        print('❌ DECISION: User exists but profile incomplete - redirecting to profile setup');
        print('   Reason: Username="${username ?? "null"}", Email="${email ?? "null"}"');
        _isProcessing = false;
        _safeSetState(() {
          _status = 'Completing profile setup...';
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
      
      if (!hasWorkspaceMembership) {
        print('❌ DECISION: User profile complete but no workspace membership - redirecting to workspace creation');
        _isProcessing = false;
        _safeSetState(() {
          _status = 'Creating workspace...';
          _isLoading = false;
        });
        
        // Navigate to workspace creation screen
        if (mounted) {
          // Import and navigate to workspace creation screen
          // For now, redirect to profile setup which will lead to workspace creation
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(
                address: address,
                show2FASetup: false, // Don't show 2FA setup, just complete profile if needed
              ),
            ),
          );
        }
        return;
      }
      
      print('✅ DECISION: Profile complete AND workspace membership exists - proceeding to 2FA check');
      
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
          // Use backendProfile we already fetched - no need to fetch again
          final userEmail = backendProfile['email']?.toString();
          
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
        return;
      }
      
      // Step 6: Complete login and navigate to workspace
      print('✅ 2FA not enabled - redirecting to workspace');
      _safeSetState(() {
        _status = 'Sign in successful! Loading workspace...';
        _isLoading = false;
      });
      
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      
      String workspaceName = 'YourWorkspace';
      String channelName = 'general';
      
      // Use workspaces we already fetched in Step 2 (no need to fetch again)
      if (userWorkspaces.isNotEmpty) {
        // Get first workspace (user's primary workspace)
        final workspace = userWorkspaces.first;
        workspaceName = workspace['name'] ?? 
                       workspace['workspaceName'] ?? 
                       'YourWorkspace';
        // Default channel is always "general" for all workspaces
        channelName = 'general';
        print('✅ Using workspace: $workspaceName, channel: $channelName');
        print('   Workspace ID: ${workspace['workspace_id'] ?? workspace['workspaceId']}');
      } else {
        // Fallback: Fetch again if somehow workspaces list is empty
        print('⚠️ Workspaces list empty, fetching again...');
        try {
          final workspaces = await DistributedService.getUserWorkspaces(address).timeout(
            const Duration(seconds: 6),
            onTimeout: () => [],
          ).catchError((e) {
            print('⚠️ Error fetching workspace details: $e');
            return <Map<String, dynamic>>[];
          });
          
          if (workspaces.isNotEmpty) {
            workspaceName = workspaces.first['name'] ?? 
                           workspaces.first['workspaceName'] ?? 
                           'YourWorkspace';
            channelName = 'general';
            print('✅ Found workspace: $workspaceName, channel: $channelName');
          } else {
            print('⚠️ No workspaces found, using defaults');
          }
        } catch (e) {
          print('⚠️ Error fetching workspace details: $e');
          // Continue with defaults
        }
      }
      
      // Save login session to database for persistence
      await SessionService.saveLoginSession(address, workspaceName, channelName);
      print('✅ Login session saved: $address -> $workspaceName / $channelName');
      
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

