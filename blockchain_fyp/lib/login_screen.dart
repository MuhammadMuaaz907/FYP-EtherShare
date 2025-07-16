import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ProfileSetup.dart';
import 'services/contract_service.dart';
import 'private_key_login_screen.dart';

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
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => ProfileSetupScreen(address: address)),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: Image.asset(
                      'assets/chat_illustration.png',
                      height: 230,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.only(top: 50),
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
                            onPressed:  _connectToMetaMask,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Continue with MetaMask 🦊'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const PrivateKeyLoginScreen()),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 