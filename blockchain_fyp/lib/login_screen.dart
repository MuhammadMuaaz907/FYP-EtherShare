import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ProfileSetup.dart';
import 'services/contract_service.dart';
import 'services/session_service.dart';
import 'services/distributed_service.dart';
import 'services/hybrid_storage_service.dart';
import 'workspace_home_page.dart';
import 'dart:convert';
import 'services/invite_link_manager.dart';
import 'services/invite_service.dart';
import 'screens/accept_invite_screen.dart';
import 'services/secure_storage_service.dart';
import 'screens/verify_2fa_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  String _status = '';
  bool _isLoading = false;
  String? _connectedAddress;
  Web3App? _web3App;
  ConnectResponse? _connectResponse;
  SessionData? _sessionData;
  late final AnimationController _controller;
  late final Animation<Offset> _pan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pan = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
    _initializeWalletConnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWalletConnectSession();
    }
  }

  Future<void> _initializeWalletConnect() async {
    try {
      _web3App = await GetIt.I.getAsync<Web3App>();
      setState(() {
        _status = 'WalletConnect initialized';
      });
    } catch (e) {
      setState(() {
        _status = 'WalletConnect initialization failed: $e';
        _isLoading = false;
      });
      print('Init Error: $e');
    }
  }

  Future<void> _checkWalletConnectSession() async {
    if (_connectResponse != null && _sessionData == null) {
      try {
        _sessionData = await _connectResponse!.session.future;
        if (_sessionData != null) {
          final account = _sessionData!.namespaces['eip155']!.accounts.firstWhere(
            (acc) => acc.contains('eip155:1337'),
            orElse: () => throw Exception('No account found for chain eip155:1337'),
          );
          final address = account.split(':').last;
          setState(() {
            _connectedAddress = address;
            _status = 'Connected to MetaMask: $_connectedAddress';
          });

          final contractService = Provider.of<ContractService?>(context, listen: false);
          if (contractService == null) {
            setState(() {
              _status = 'Contract service not initialized';
              _isLoading = false;
            });
            return;
          }

          try {
            await _web3App!.request(
              topic: _sessionData!.topic,
              chainId: 'eip155:1337',
              request: SessionRequestParams(
                method: 'wallet_switchEthereumChain',
                params: [{'chainId': '0x539'}],
              ),
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                print('Chain switch timed out, continuing anyway...');
                return 'timeout';
              },
            );
            setState(() {
              _status = 'Checking registration status...';
            });
            final isRegistered = await contractService.isRegistered(address);
            final hasProfile = await contractService.hasCompletedProfile(address);
            final workspaceExists = await contractService.doesWorkspaceExist(address);
            
            // Debug logging
            print('🔍 Login Debug Info:');
            print('  - isRegistered: $isRegistered');
            print('  - hasProfile: $hasProfile');
            print('  - workspaceExists: $workspaceExists');
            
            // If user is registered, has profile, and has workspace, check 2FA first
            if (isRegistered && hasProfile && workspaceExists) {
              print('✅ All checks passed - checking 2FA status...');
              
              // Check if 2FA is enabled
              SecureStorageService? storageService;
              bool is2FAEnabled = false;
              try {
                storageService = await SecureStorageService.create();
                is2FAEnabled = await storageService.isUser2FAEnabled();
                print('🔐 2FA Status: ${is2FAEnabled ? "ENABLED" : "DISABLED"}');
              } catch (e) {
                print('⚠️ Error checking 2FA status: $e');
              }
              
              // If 2FA is enabled, navigate to verification screen
              if (is2FAEnabled) {
                print('🔐 2FA is enabled - navigating to verification screen');
                setState(() {
                  _status = '2FA verification required...';
                  _isLoading = false;
                });
                
                if (mounted) {
                  // Get user email from MongoDB profile
                  String? userEmail;
                  try {
                    final profile = await DistributedService.getUserProfile(address);
                    if (profile != null) {
                      userEmail = profile['email']?.toString();
                    }
                  } catch (e) {
                    print('Error fetching user email: $e');
                  }
                  
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
              
              // If 2FA is not enabled, proceed to workspace
              print('✅ 2FA not enabled - redirecting to workspace');
              setState(() {
                _status = 'Login successful! Redirecting to workspace...';
                _isLoading = false;
              });
              if (mounted) {
                // Fetch workspace details from MongoDB
              String workspaceName = 'YourWorkspace';
              String channelName = 'general';
              
              try {
                final workspaces = await DistributedService.getUserWorkspaces(address);
                if (workspaces.isNotEmpty) {
                  final firstWorkspace = workspaces.first;
                  workspaceName = firstWorkspace['name'] ?? workspaceName;
                  channelName = 'general'; // Default channel
                }
              } catch (e) {
                print('Error fetching workspace details: $e');
              }
              
              // Save login session
              await SessionService.saveLoginSession(address, workspaceName, channelName);
              
              // Initialize HybridStorageService for P2P communication
              try {
                print('🔄 Initializing Hybrid Storage for P2P...');
                await HybridStorageService.instance.initialize(userAddress: address);
                print('✅ Hybrid Storage initialized - P2P ready');
              } catch (e) {
                print('⚠️ Hybrid Storage init error: $e');
              }

                final pendingInvite =
                    await InviteLinkManager.instance.consumePendingInvite();

                if (pendingInvite != null) {
                  final resolved =
                      await InviteService.resolveInvite(pendingInvite);
                  if (resolved != null && mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AcceptInviteScreen(
                          invite: resolved,
                          userAddress: address,
                          onComplete: () async {
                            await InviteLinkManager.instance.clearPendingInvite();
                          },
                        ),
                      ),
                    );
                    return;
                  }
                }
                
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
              return;
            }
            
            // If user is registered but doesn't have profile or workspace
            if (isRegistered && (!hasProfile || !workspaceExists)) {
              setState(() {
                _status = 'Completing setup...';
                _isLoading = false;
              });
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileSetupScreen(
                    address: address,
                    show2FASetup: true, // Enable 2FA setup flow after profile completion
                  )),
                );
              }
              return;
            }
            
            // If user is not registered, register them
            if (!isRegistered) {
              setState(() {
                _status = 'Registering user...';
              });
              await contractService.registerWithAddress(address);
              await Future.delayed(const Duration(seconds: 2));
            }
            setState(() {
              _status = 'Logging in...';
            });
            await contractService.loginWithAddress(address);
            setState(() {
              _status = 'Login successful!';
              _isLoading = false;
            });
            if (mounted) {
              // No need to save to SharedPreferences - all data is now in OrbitDB
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => ProfileSetupScreen(
                  address: address,
                  show2FASetup: true, // Enable 2FA setup flow after profile completion
                )),
              );
            }
          } catch (e) {
            setState(() {
              _status = 'Transaction Error: $e';
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        setState(() {
          _status = 'Error resuming session: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectToMetaMask() async {
    if (_web3App == null) {
      setState(() {
        _status = 'WalletConnect not initialized';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Connecting to MetaMask...';
    });

    try {
      print('Starting WalletConnect connection...');
      _connectResponse = await _web3App!.connect(
        requiredNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:1337'],
            methods: ['eth_accounts', 'wallet_switchEthereumChain'],
            events: ['accountsChanged', 'chainChanged'],
          ),
        },
      );

      print('Connect response received:  [38;5;2m${_connectResponse?.uri} [0m');
      final wcUri = _connectResponse!.uri.toString();
      print('WalletConnect URI: $wcUri');

      final uri = Uri.parse(wcUri);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        setState(() {
          _status = 'Cannot launch MetaMask. Is it installed?';
          _isLoading = false;
        });
        return;
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);
      print('Launched MetaMask with URI');

      setState(() {
        _status = 'Please approve the connection in MetaMask, then return to the app.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error connecting to MetaMask: $e';
        _isLoading = false;
      });
    }
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
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
          child: SlideTransition(
            position: _pan,
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
                    child: Center(
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height - 
                                MediaQuery.of(context).padding.top - 
                                MediaQuery.of(context).padding.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(25, 10, 0, 0),
                              child: Text(
                                'Secure messaging app, but made for teams',
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
                            padding: EdgeInsetsDirectional.fromSTEB(
                              MediaQuery.of(context).size.width > 600 ? 150 : 0,
                              20,
                              0,
                              0,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/team_illustration.webp',
                                  width: 200,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Fallback to chat illustration if team image fails
                                    return Image.asset(
                                      'assets/chat_illustration.png',
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(32, 40, 32, 32),
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () {
                                  // Keep existing functionality
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Get Started',
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
                                    Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 24),
                                      child: Text(
                                        'Join thousands of users who trust Ether \nShare for their private communication',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontFamily: 'Inter',
                                              letterSpacing: 0.0,
                                            ) ?? const TextStyle(
                                              fontSize: 14,
                                              letterSpacing: 0.0,
                                            ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                      child: SizedBox(
                                        width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                        height: 44,
                                        child: FilledButton(
                                          onPressed: _isLoading ? null : _connectToMetaMask,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F365F),
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                                            elevation: 3,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: Text(
                                            'Continue with MetaMask',
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
                                    Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                      child: SizedBox(
                                        width: MediaQuery.of(context).size.width > 400 ? 370 : double.infinity,
                                        height: 44,
                                        child: FilledButton(
                                          onPressed: _isLoading
                                              ? null
                                              : () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => const SignInScreen(),
                                                    ),
                                                  );
                                                },
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F365F),
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                                            elevation: 3,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: Text(
                                            'Sign in with Private Key',
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
                                    Padding(
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
                                                ..onTap = () async {
                                                  Navigator.push(
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
                                  ],
                                ),
                              ),
                            ),
                          ),
                            ],
                          ),
                        ),
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
      ),
    );
  }
} 