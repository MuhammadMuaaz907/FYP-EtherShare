import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';

class ContractService {
  final String _rpcUrl = 'https://474b-103-84-151-7.ngrok-free.app';
  final String _contractAddress = '0xD89b0BeE22d9d97327a573a1FEbCbcBF85134F14';
  final Web3Client _client;
  final DeployedContract _contract;
  final String _abi;

  ContractService._(this._client, this._contract, this._abi);

  static Future<ContractService> create() async {
    try {
      final client = Web3Client('https://474b-103-84-151-7.ngrok-free.app', Client());
      final abiString = await rootBundle.loadString('assets/contract_abi.json');
      // Parse JSON and extract ABI array
      dynamic abiJson = jsonDecode(abiString);
      if (abiJson is Map<String, dynamic> && abiJson.containsKey('abi')) {
        abiJson = abiJson['abi'];
      }
      if (abiJson is! List) {
        throw Exception('Invalid ABI format: Expected a list');
      }
      final abi = jsonEncode(abiJson); // Convert back to string
      final contract = DeployedContract(
        ContractAbi.fromJson(abi, 'UserAuth'),
        EthereumAddress.fromHex('0xD89b0BeE22d9d97327a573a1FEbCbcBF85134F14'),
      );
      return ContractService._(client, contract, abi);
    } catch (e) {
      print('Error initializing ContractService: $e');
      rethrow;
    }
  }

  Future<bool> isRegistered(String userAddress) async {
    try {
      final function = _contract.function('isRegistered');
      final result = await _client.call(
        contract: _contract,
        function: function,
        params: [EthereumAddress.fromHex(userAddress)],
      );
      return result[0] as bool;
    } catch (e) {
      print('Error checking registration: $e');
      return false;
    }
  }

  Future<String> register(String privateKey) async {
    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final function = _contract.function('register');
      final result = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: function,
          parameters: [],
          maxGas: 5000000,
        ),
        chainId: 5777,
      );
      return result;
    } catch (e) {
      print('Error registering: $e');
      return '';
    }
  }

  Future<String> login(String privateKey) async {
    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final function = _contract.function('login');
      final result = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: function,
          parameters: [],
          maxGas: 5000000,
        ),
        chainId: 5777,
      );
      return result;
    } catch (e) {
      print('Error logging in: $e');
      return '';
    }
  }
}