import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/contract_service.dart';
import 'ProfileSetup.dart';
import 'package:web3dart/web3dart.dart';

class PrivateKeyLoginScreen extends StatefulWidget {
  const PrivateKeyLoginScreen({super.key});

  @override
  State<PrivateKeyLoginScreen> createState() => _PrivateKeyLoginScreenState();
}

class _PrivateKeyLoginScreenState extends State<PrivateKeyLoginScreen> {
  String _privateKey = '';
  String _status = '';
  bool _isLoading = false;

  Future<void> _loginWithPrivateKey() async {
    if (_privateKey.isEmpty) {
      setState(() {
        _status = 'Please enter a private key';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _status = 'Logging in...';
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
      final isRegistered = await contractService.isRegistered(address);
      if (!isRegistered) {
        await contractService.register(_privateKey);
      }
      await contractService.login(_privateKey);
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
        _status = 'Login error: $e';
        _isLoading = false;
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
          'Login with Private Key',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 350,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  color: const Color(0xFF232B3E),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon
                    Center(
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B4B6B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Heading
                    const Text(
                      'Enter your private key',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Input
                    TextField(
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Private Key',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF2D3754),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        hintText: 'Enter your private key',
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                      onChanged: (value) => _privateKey = value,
                    ),
                    const SizedBox(height: 22),
                    // Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _loginWithPrivateKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Login'),
                    ),
                    const SizedBox(height: 18),
                    // Info text
                    const Text(
                      'We never store your private key.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Optional: Help or info at the bottom
              // const Text(
              //   'Need help? Contact support.',
              //   style: TextStyle(color: Colors.white38, fontSize: 12),
              // ),
            ],
          ),
        ),
      ),
    );
  }
} 