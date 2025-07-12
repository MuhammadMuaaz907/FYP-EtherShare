import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';
import 'package:hex/hex.dart';

class ContractService {
  final String _rpcUrl = 'https://6a632f7d419e.ngrok-free.app';
  final String _contractAddress = '0x023bd7D5F48a36AcA66313B67127f7947Aa059FD';
  late Web3Client _client;
  late DeployedContract _contract;
  late ContractFunction _register;
  late ContractFunction _login;
  late ContractFunction _isRegistered;

  String get contractAddress => _contractAddress;

  ContractService._();

  static Future<ContractService> create() async {
    final service = ContractService._();
    await service._init();
    return service;
  }

  Future<void> _init() async {
    try {
      _client = Web3Client(_rpcUrl, Client());
      final abiString = await rootBundle.loadString('assets/contract_abi.json');
      final abiJson = jsonDecode(abiString) as Map<String, dynamic>;
      final abi = abiJson['abi'] as List<dynamic>;
      _contract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(abi), 'UserAuth'),
        EthereumAddress.fromHex(_contractAddress),
      );
      _register = _contract.function('register');
      _login = _contract.function('login');
      _isRegistered = _contract.function('isRegistered');
      await testRegisterAndLogin();
    } catch (e) {
      print('ContractService init error: $e');
      rethrow;
    }
  }

  String getFunctionData(String functionName) {
    final function = _contract.function(functionName);
    final encoded = function.encodeCall([]);
    return '0x${HEX.encode(encoded)}';
  }

  Future<String> register(String privateKey) async {
    try {
      final credentials = EthPrivateKey.fromHex(privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey);
      final sender = await credentials.extractAddress();
      final nonce = await _client.getTransactionCount(sender);
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _register,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, 20),
          maxGas: 200000,
        ),
        chainId: 1337,
      );
      return txHash;
    } catch (e) {
      print('Register error: $e');
      rethrow;
    }
  }

  Future<String> login(String privateKey) async {
    try {
      final credentials = EthPrivateKey.fromHex(privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey);
      final sender = await credentials.extractAddress();
      final nonce = await _client.getTransactionCount(sender);
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _login,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, 20),
          maxGas: 200000,
        ),
        chainId: 1337,
      );
      return txHash;
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  Future<String> registerWithAddress(String address) async {
    try {
      final nonce = await _client.getTransactionCount(EthereumAddress.fromHex(address));
      final txHash = await _client.sendTransaction(
        EthPrivateKey.fromHex('0x192ff8ad181ad785b2c4cfe40079fbba085d3eead3f9dddbd0898228262b4dd3'),
        Transaction.callContract(
          contract: _contract,
          function: _register,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, 20),
          maxGas: 200000,
        ),
        chainId: 1337,
      );
      return txHash;
    } catch (e) {
      print('Register with address error: $e');
      rethrow;
    }
  }

  Future<String> loginWithAddress(String address) async {
    try {
      final nonce = await _client.getTransactionCount(EthereumAddress.fromHex(address));
      final txHash = await _client.sendTransaction(
        EthPrivateKey.fromHex('0x192ff8ad181ad785b2c4cfe40079fbba085d3eead3f9dddbd0898228262b4dd3'),
        Transaction.callContract(
          contract: _contract,
          function: _login,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, 20),
          maxGas: 200000,
        ),
        chainId: 1337,
      );
      return txHash;
    } catch (e) {
      print('Login with address error: $e');
      rethrow;
    }
  }

  Future<bool> isRegistered(String address) async {
    const maxRetries = 3;
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        print('Calling isRegistered for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _isRegistered,
          params: [EthereumAddress.fromHex(address)],
        );
        print('isRegistered result: $result');
        return result[0] as bool;
      } catch (e) {
        print('IsRegistered error (Attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount >= maxRetries) {
          throw Exception('Failed to check registration after $maxRetries attempts: $e');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw Exception('Failed to check registration after $maxRetries attempts');
  }

  Future<void> testRegisterAndLogin() async {
    try {
      final privateKey = '0x192ff8ad181ad785b2c4cfe40079fbba085d3eead3f9dddbd0898228262b4dd3';
      final address = EthPrivateKey.fromHex(privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey).address.hex;
      final isUserRegistered = await isRegistered(address);
      print('Test isRegistered: $isUserRegistered');
      if (!isUserRegistered) {
        final txHash = await register(privateKey);
        print('Test register transaction: $txHash');
      }
      final txHash = await login(privateKey);
      print('Test login transaction: $txHash');
    } catch (e) {
      print('Test register/login error: $e');
    }
  }
}