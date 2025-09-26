import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';
import 'package:hex/hex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './orbitdb_service.dart';

class ContractService {
  final String _rpcUrl = 'https://20d9ab0b49d1.ngrok-free.app';
  final String _contractAddress = '0xa8FD94cD7f4Ee4513E938106911E56770d73CCf1';
  late Web3Client _client;
  late DeployedContract _contract;
  late ContractFunction _register;
  late ContractFunction _login;
  late ContractFunction _isRegistered;

  String get contractAddress => _contractAddress;

  ContractService._();

  // Dummy constructor for fallback when initialization fails
  ContractService.dummy() {
    print('⚠️ Using dummy ContractService - blockchain features disabled');
  }

  static Future<ContractService> create() async {
    final service = ContractService._();
    await service._init();
    return service;
  }

  Future<void> _init() async {
    try {
      print('🔄 Initializing ContractService...');
      
      // Initialize Web3Client with timeout
      _client = Web3Client(_rpcUrl, Client());
      
      // Load contract ABI with error handling
      String abiString;
      try {
        abiString = await rootBundle.loadString('assets/contract_abi.json');
      } catch (e) {
        print('⚠️ Could not load contract ABI: $e');
        // Create a minimal ABI for basic functionality
        abiString = '{"abi": []}';
      }
      
      final abiJson = jsonDecode(abiString) as Map<String, dynamic>;
      final abi = abiJson['abi'] as List<dynamic>;
      
      if (abi.isNotEmpty) {
        _contract = DeployedContract(
          ContractAbi.fromJson(jsonEncode(abi), 'UserAuth'),
          EthereumAddress.fromHex(_contractAddress),
        );
        _register = _contract.function('register');
        _login = _contract.function('login');
        _isRegistered = _contract.function('isRegistered');
        print('✅ ContractService initialized successfully');
      } else {
        print('⚠️ Contract ABI is empty, using fallback mode');
        // Initialize with dummy functions for fallback
        _contract = DeployedContract(
          ContractAbi.fromJson('[]', 'UserAuth'),
          EthereumAddress.fromHex(_contractAddress),
        );
      }
    } catch (e) {
      print('❌ Error initializing ContractService: $e');
      // Don't rethrow to prevent app crash
      print('⚠️ ContractService will run in fallback mode');
    }
  }

  String getFunctionData(String functionName) {
    final function = _contract.function(functionName);
    final encoded = function.encodeCall([]);
    return '0x${HEX.encode(encoded)}';
  }

  Future<String> register(String privateKey) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: register called');
      return 'dummy_tx_hash';
    }
    
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
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: login called');
      return 'dummy_tx_hash';
    }
    
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
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: registerWithAddress called');
      return 'dummy_tx_hash';
    }
    
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
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: loginWithAddress called');
      return 'dummy_tx_hash';
    }
    
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
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: isRegistered called');
      return false;
    }
    
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

  // workspaceDbAddress is now set to the actual OrbitDB address in OrbitDBService.

  Future<bool> doesWorkspaceExist(String address) async {
    try {
      final key = address.toLowerCase().trim();
      // Create workspace database name for this user
      final dbName = 'workspace_$key';
      
      // First try to get existing database
      String? dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      if (dbAddress != null) {
        print('🔍 Checking workspace in database: $dbAddress');
        // Get messages from the workspace database
        final messages = await OrbitDBService.getMessages(dbAddress);
        print('📨 Retrieved ${messages.length} messages from workspace database');
        
        // Check if there's a workspace message for this user
        for (var message in messages) {
          print('🔍 Checking message: ${message['type']} for user: ${message['userAddress']}');
          if (message['type'] == 'workspace' && message['userAddress'] == key) {
            print('📋 Found workspace data: ${message['workspaceDetails']}');
            print('✅ Workspace found for user: $key');
            return true;
          }
        }
      } else {
        print('❌ Workspace database not found for user: $key');
      }
      
      print('❌ No workspace found for user: $key');
      return false;
    } catch (e) {
      print('Error checking workspace existence: $e');
      return false;
    }
  }

  // Check if user has completed profile setup - Now uses OrbitDB instead of local storage
  Future<bool> hasCompletedProfile(String address) async {
    try {
      final key = address.toLowerCase().trim();
      final dbName = 'profile_$key';
      
      // First try to get existing database
      String? dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      if (dbAddress != null) {
        print('🔍 Checking profile in database: $dbAddress');
        final messages = await OrbitDBService.getMessages(dbAddress);
        print('📨 Retrieved ${messages.length} messages from profile database');
        
        // Find profile message for this user
        for (var message in messages) {
          print('🔍 Checking message: ${message['type']} for user: ${message['userAddress']}');
          if (message['type'] == 'profile' && message['userAddress'] == key) {
            final username = message['username'];
            final email = message['email'];
            
            print('📋 Found profile data - Username: $username, Email: $email');
            
            if (username != null && username.isNotEmpty && email != null && email.isNotEmpty) {
              print('✅ Profile completed for user: $address');
              return true;
            }
          }
        }
      } else {
        print('❌ Profile database not found for user: $address');
      }
      
      print('❌ Profile not completed for user: $address');
      return false;
    } catch (e) {
      print('Error checking profile completion: $e');
      return false;
    }
  }

  // Helper method to get existing database
  Future<String?> _getExistingDatabase(String dbName) async {
    try {
      // Use consistent database addressing
      return await OrbitDBService.getConsistentDatabaseAddress(dbName);
    } catch (e) {
      print('Error getting existing database: $e');
      return null;
    }
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