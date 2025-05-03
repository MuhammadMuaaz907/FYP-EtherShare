import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/contract_service.dart';

void main() {
  GetIt.I.registerSingletonAsync<Web3App>(() async {
    final app = await Web3App.createInstance(
      projectId: '1f976613b40ddd232f1339e8ae5f1634', // Replace with your WalletConnect Project ID
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
  final TextEditingController _privateKeyController = TextEditingController();
  String _status = '';
  bool _isLoading = false;
  String? _connectedAddress;
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
      });
      print('Init Error: $e');
    }
  }

  Future<void> _connectToMetaMask() async {
    if (_web3App == null) {
      setState(() {
        _status = 'WalletConnect not initialized';
      });
      return;
    }

    try {
      print('Starting WalletConnect connection...');
      _connectResponse = await _web3App!.connect(
        requiredNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:1337'], // Ganache chain ID
            methods: ['eth_sign', 'eth_signTransaction', 'eth_sendTransaction'],
            events: ['accountsChanged', 'chainChanged'],
          ),
        },
      );
      print('Connect response received: ${_connectResponse?.uri}');

      // Launch MetaMask with raw wc: URI
      final wcUri = _connectResponse!.uri.toString();
      print('WalletConnect URI: $wcUri');
      final uri = Uri.parse(wcUri);
      print('Parsed URI: $uri');
      final canLaunch = await canLaunchUrl(uri);
      print('Can Launch URL: $canLaunch');
      if (canLaunch) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('Launched MetaMask with URI');
      } else {
        setState(() {
          _status = 'Cannot launch MetaMask. Is it installed?';
        });
        return;
      }

      _sessionData = await _connectResponse!.session.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('WalletConnect session timed out');
        },
      );
      print('Session data: ${_sessionData?.namespaces}');

      if (_sessionData!.namespaces['eip155']!.accounts.isNotEmpty) {
        final account = _sessionData!.namespaces['eip155']!.accounts[0];
        final address = account.split(':').last;
        setState(() {
          _connectedAddress = address;
          _status = 'Connected to MetaMask: $_connectedAddress';
        });
      } else {
        setState(() {
          _status = 'Failed to connect to MetaMask: No accounts found';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error connecting to MetaMask: $e';
      });
      print('Connect Error: $e');
    }
  }

  Future<void> _register(ContractService? contractService) async {
    if (contractService == null) {
      setState(() {
        _status = 'Contract service not initialized';
        _isLoading = false;
      });
      return;
    }

    if (_connectedAddress == null) {
      setState(() {
        _status = 'Please connect to MetaMask';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      final privateKey = _privateKeyController.text.trim();
      if (privateKey.isEmpty) {
        setState(() {
          _status = 'Please enter a private key';
          _isLoading = false;
        });
        return;
      }

      final txHash = await contractService.register(privateKey);
      if (txHash.isNotEmpty) {
        setState(() {
          _status = 'Registered successfully! Tx: $txHash';
        });
      } else {
        setState(() {
          _status = 'Registration failed';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _login(ContractService? contractService) async {
    if (contractService == null) {
      setState(() {
        _status = 'Contract service not initialized';
        _isLoading = false;
      });
      return;
    }

    if (_connectedAddress == null) {
      setState(() {
        _status = 'Please connect to MetaMask';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      final privateKey = _privateKeyController.text.trim();
      if (privateKey.isEmpty) {
        setState(() {
          _status = 'Please enter a private key';
          _isLoading = false;
        });
        return;
      }

      final isRegistered = await contractService.isRegistered(_connectedAddress!);
      if (!isRegistered) {
        setState(() {
          _status = 'User not registered';
          _isLoading = false;
        });
        return;
      }

      final txHash = await contractService.login(privateKey);
      if (txHash.isNotEmpty) {
        setState(() {
          _status = 'Logged in successfully! Tx: $txHash';
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        });
      } else {
        setState(() {
          _status = 'Login failed';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contractService = Provider.of<ContractService?>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FYP Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: contractService == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _connectToMetaMask,
                    child: const Text('Connect to MetaMask'),
                  ),
                  const SizedBox(height: 20),
                  if (_connectedAddress != null)
                    Text(
                      'Connected Address: $_connectedAddress',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _privateKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Private Key (Temporary)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () => _register(contractService),
                              child: const Text('Register'),
                            ),
                            ElevatedButton(
                              onPressed: () => _login(contractService),
                              child: const Text('Login'),
                            ),
                          ],
                        ),
                  const SizedBox(height: 20),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
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
      ),
      body: const Center(
        child: Text('Welcome to the Secure File Sharing System!'),
      ),
    );
  }
}