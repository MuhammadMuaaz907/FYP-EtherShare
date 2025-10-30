
import 'package:blockchain_fyp/splash.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:hex/hex.dart';
import 'dart:typed_data';
import 'services/contract_service.dart';
import 'services/secure_storage_service.dart';
import 'services/biometric_service.dart';
import 'ProfileSetup.dart';
import 'screens/verify_2fa_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // If .env is missing in non-prod, continue; SMTP init will validate
  }
  GetIt.I.registerSingletonAsync<Web3App>(() async {
    final app = await Web3App.createInstance(
      projectId: '8b3a8acfa9a31912661157c7137ae314',
      metadata: const PairingMetadata(
        name: 'FYP Secure File Sharing',
        description: 'Blockchain-based file sharing app',
        url: 'https://example.com',
        icons: ['https://example.com/icon.png'],
      ),
    );
    return app;
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureProvider<ContractService?>(
      create: (_) async {
        try {
          return await ContractService.create();
        } catch (e) {
          print('FutureProvider error: $e');
          return null;
        }
      },
      initialData: null,
      child: MaterialApp(
        title: 'FYP - Secure File Sharing',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  String _status = '';
  bool _isLoading = false;
  String? _connectedAddress;
  String _privateKey = '';
  Web3App? _web3App;
  ConnectResponse? _connectResponse;
  SessionData? _sessionData;
  late final AnimationController _controller;
  late final Animation<Offset> _pan;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // screen slides from bottom (Offset 0,1) → centre
    _pan = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    // start after first frame for smoothness
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
    _initializeWalletConnect();
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

      print('Connect response received: ${_connectResponse?.uri}');
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
        _status = 'Waiting for MetaMask approval...';
      });

      _sessionData = await _connectResponse!.session.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('WalletConnect session timed out');
        },
      );
      print('Session data: ${_sessionData?.namespaces}');

      if (_sessionData!.namespaces['eip155']!.accounts.isNotEmpty) {
        final account = _sessionData!.namespaces['eip155']!.accounts.firstWhere(
          (acc) => acc.contains('eip155:1337'),
          orElse: () =>
              throw Exception('No account found for chain eip155:1337'),
        );
        final address = account.split(':').last;
        setState(() {
          _connectedAddress = address;
          _status = 'Connected to MetaMask: $_connectedAddress';
        });

        final contractService =
            Provider.of<ContractService?>(context, listen: false);
        if (contractService == null) {
          setState(() {
            _status = 'Contract service not initialized';
            _isLoading = false;
          });
          return;
        }

        try {
          // Switch chain
          print('Requesting chain switch to eip155:1337...');
          await _web3App!
              .request(
            topic: _sessionData!.topic,
            chainId: 'eip155:1337',
            request: SessionRequestParams(
              method: 'wallet_switchEthereumChain',
              params: [
                {'chainId': '0x539'}
              ],
            ),
          )
              .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('Chain switch timed out, continuing anyway...');
              return 'timeout';
            },
          );
          print('Chain switched to eip155:1337');

          // Check registration
          setState(() {
            _status = 'Checking registration status...';
          });
          print('Checking registration for $address...');
          final isRegistered = await contractService.isRegistered(address);
          print('Is registered: $isRegistered');

          if (!isRegistered) {
            setState(() {
              _status = 'Registering user...';
            });
            print('Registering user...');
            final registerTx =
                await contractService.registerWithAddress(address);
            setState(() {
              _status = 'Registration successful: $registerTx';
            });
            await Future.delayed(const Duration(seconds: 3));
          }

          // Login
          setState(() {
            _status = 'Logging in...';
          });
          print('Logging in user...');
          final loginTx = await contractService.loginWithAddress(address);
          setState(() {
            _status = 'Login successful: $loginTx';
            _isLoading = false;
          });

          if (mounted) {
            // Check if 2FA is enabled before navigating
            await _checkAndNavigateWith2FA(context, address);
          }
        } catch (e) {
          print('Transaction Error: $e');
          setState(() {
            _status = 'Transaction Error: $e';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _status = 'Failed to connect to MetaMask: No accounts found';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Connect Error: $e');
      setState(() {
        _status = 'Error connecting to MetaMask: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loginWithPrivateKey() async {
    if (_privateKey.isEmpty) {
      setState(() {
        _status = 'Please enter a private key';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Logging in with private key...';
    });

    final contractService =
        Provider.of<ContractService?>(context, listen: false);
    if (contractService == null) {
      setState(() {
        _status = 'Contract service not initialized';
        _isLoading = false;
      });
      return;
    }

    try {
      final credentials = EthPrivateKey.fromHex(_privateKey.startsWith('0x')
          ? _privateKey.substring(2)
          : _privateKey);
      final address = credentials.address.hex;
      print('Checking registration for $address...');
      final isRegistered = await contractService.isRegistered(address);
      print('Is registered: $isRegistered');
      if (!isRegistered) {
        print('Registering user...');
        final registerTx = await contractService.register(_privateKey);
        print('Registration transaction sent: $registerTx');
      }
      print('Logging in user...');
      final loginTx = await contractService.login(_privateKey);
      print('Login transaction sent: $loginTx');
      setState(() {
        _connectedAddress = address;
        _status = 'Login successful: $loginTx';
        _isLoading = false;
      });
      if (mounted) {
        // Check if 2FA is enabled before navigating
        await _checkAndNavigateWith2FA(context, address);
      }
    } catch (e) {
      print('Private key login error: $e');
      setState(() {
        _status = 'Private key login error: $e';
        _isLoading = false;
      });
    }
  }

  /// Enhanced helper method to check 2FA status and navigate accordingly
  /// 
  /// This method:
  /// - Checks both local storage and blockchain 2FA status
  /// - Handles edge cases (2FA disabled, biometric unavailable, etc.)
  /// - Provides proper error handling and fallback navigation
  /// - Integrates with TOTPService, BiometricService, and SecureStorageService
  Future<void> _checkAndNavigateWith2FA(BuildContext context, String address) async {
    try {
      setState(() {
        _isLoading = true;
        _status = 'Checking 2FA status...';
      });

      // Initialize services
      final storageService = await SecureStorageService.create();
      final contractService = Provider.of<ContractService?>(context, listen: false);
      
      if (contractService == null) {
        throw Exception('Contract service not available');
      }

      // Check local 2FA status
      final local2FAEnabled = await storageService.isUser2FAEnabled();
      
      // Check blockchain 2FA status
      bool blockchain2FAEnabled = false;
      try {
        blockchain2FAEnabled = await contractService.is2FAEnabled(address);
        print('Blockchain 2FA status: $blockchain2FAEnabled');
      } catch (e) {
        print('Error checking blockchain 2FA status: $e');
        // Continue with local status if blockchain check fails
      }

      // Determine if 2FA is enabled (either locally or on blockchain)
      final is2FAEnabled = local2FAEnabled || blockchain2FAEnabled;

      if (is2FAEnabled) {
        // Check if user is locked out
        bool isLockedOut = false;
        int remainingLockoutTime = 0;
        
        try {
          isLockedOut = await contractService.isLockedOut(address);
          if (isLockedOut) {
            remainingLockoutTime = await contractService.getRemainingLockoutTime(address);
            print('User is locked out for $remainingLockoutTime seconds');
          }
        } catch (e) {
          print('Error checking lockout status: $e');
        }

        if (isLockedOut) {
          // Show lockout message and navigate to profile setup
          setState(() {
            _isLoading = false;
            _status = 'Account temporarily locked. Please try again in ${remainingLockoutTime ~/ 60} minutes.';
          });
          
          await Future.delayed(const Duration(seconds: 3));
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileSetupScreen(address: address),
              ),
            );
          }
          return;
        }

        // Check biometric availability
        final biometricAvailable = await BiometricService.isBiometricAvailable();
        final biometricEnabled = await storageService.isBiometricEnabled();
        
        print('Biometric available: $biometricAvailable, enabled: $biometricEnabled');

        // Navigate to 2FA verification screen
        setState(() {
          _isLoading = false;
          _status = '2FA verification required';
        });

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => Verify2FAScreen(
                userId: address,
                userAddress: address,
              ),
            ),
          );
        }
      } else {
        // Check if this is a new user who should be offered 2FA setup
        final isNewUser = !local2FAEnabled && !blockchain2FAEnabled;
        
        setState(() {
          _isLoading = false;
          _status = isNewUser ? 'Welcome! Setting up your profile...' : 'Profile setup';
        });

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(
                address: address,
                show2FASetup: isNewUser, // Pass flag to show 2FA setup option
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error in 2FA check: $e');
      setState(() {
        _isLoading = false;
        _status = 'Error checking security status: $e';
      });
      
      // Fallback to profile setup if 2FA check fails
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileSetupScreen(address: address),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF00163A),
      body: SafeArea(
        child: SlideTransition(
          position: _pan,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  const Text(
                    'Secure\nMessaging app,\nbut made for\nteams.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Right‑aligned illustration
                  Align(
                    alignment: Alignment.centerRight,
                    child: Image.asset(
                      'assets/chat_illustration.png',
                      height: 230,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // White card box
                  Padding(
                    padding: const EdgeInsets.only(top: 50), // thoda neeche
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Get Started',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 8),
                          const Text(
                            'Join thousands of users who trust Ether Share for their private communication.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              _connectToMetaMask();
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Continue with MetaMask 🦊'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  String privateKeyInput = '';
                                  return AlertDialog(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    title: const Text(
                                      'Login with Private Key',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Enter your private key below to continue:',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          obscureText: true,
                                          maxLines: 1,
                                          decoration: InputDecoration(
                                            hintText: 'Enter Private Key',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            prefixIcon:
                                                const Icon(Icons.vpn_key),
                                          ),
                                          onChanged: (val) =>
                                              privateKeyInput = val,
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          Navigator.pop(
                                              context); // close dialog
                                          setState(() {
                                            _privateKey = privateKeyInput;
                                          });
                                          await _loginWithPrivateKey(); // call existing login logic
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue[700],
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Login'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Login with Private Key'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'By continuing, you agree to our Terms of Service and Privacy Policy',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _status.contains('successful')
                                ? Colors.green
                                : Colors.redAccent,
                            fontWeight: FontWeight.w600,
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
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.blue[700],
      ),
      body: const Center(
        child: Text(
          'Welcome to the Secure File Sharing System!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
