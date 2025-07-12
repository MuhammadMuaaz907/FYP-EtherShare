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

void main() {
  GetIt.I.registerSingletonAsync<Web3App>(() async {
    final app = await Web3App.createInstance(
      projectId: '1f976613b40ddd232f1339e8ae5f1634',
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
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _status = '';
  bool _isLoading = false;
  String? _connectedAddress;
  String _privateKey = '';
  Web3App? _web3App;
  ConnectResponse? _connectResponse;
  SessionData? _sessionData;

  @override
  void initState() {
    super.initState();
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
          // Switch chain
          print('Requesting chain switch to eip155:1337...');
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
            final registerTx = await contractService.registerWithAddress(address);
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => ProfileSetupScreen(address: address)),
            );
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

    final contractService = Provider.of<ContractService?>(context, listen: false);
    if (contractService == null) {
      setState(() {
        _status = 'Contract service not initialized';
        _isLoading = false;
      });
      return;
    }

    try {
      final credentials = EthPrivateKey.fromHex(_privateKey.startsWith('0x') ? _privateKey.substring(2) : _privateKey);
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ProfileSetupScreen(address: address)),
        );
      }
    } catch (e) {
      print('Private key login error: $e');
      setState(() {
        _status = 'Private key login error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contractService = Provider.of<ContractService?>(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[900]!, Colors.blue[300]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: contractService == null
              ? const CircularProgressIndicator(color: Colors.white)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'FYP Secure File Sharing',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _connectToMetaMask,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Connect to MetaMask'),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Private Key',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onChanged: (value) => _privateKey = value,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _loginWithPrivateKey,
                        child: const Text('Login with Private Key'),
                      ),
                      const SizedBox(height: 20),
                      if (_status.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _status,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
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

class ProfileSetupScreen extends StatefulWidget {
  final String address;

  const ProfileSetupScreen({super.key, required this.address});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _showPrivateKey = false;
  String? _privateKey;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _privateKey = 'Unable to fetch private key securely. Export from MetaMask.';
  }

  Future<void> _saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', _usernameController.text.trim());
      await prefs.setString('email', _emailController.text.trim());
      setState(() {
        _status = 'Profile saved successfully!';
      });
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _status = 'Error saving profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Setup'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Address: ${widget.address}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Private Key: ',
                  style: TextStyle(fontSize: 16),
                ),
                Expanded(
                  child: Text(
                    _showPrivateKey ? _privateKey! : '••••••••',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: Icon(_showPrivateKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _showPrivateKey = !_showPrivateKey;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Profile Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveProfile,
              child: const Text('Save Profile'),
            ),
            const SizedBox(height: 20),
            if (_status.isNotEmpty)
              Text(
                _status,
                style: TextStyle(
                  color: _status.contains('successfully') ? Colors.green : Colors.red,
                  fontSize: 16,
                ),
              ),
          ],
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