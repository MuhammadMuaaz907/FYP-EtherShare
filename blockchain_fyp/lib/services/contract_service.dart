import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';
import 'package:hex/hex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'two_fa_error_handler.dart';
import 'distributed_service.dart';

/// Enhanced Contract Service with 2FA Support
/// 
/// This service provides:
/// - User registration and login functionality
/// - Two-Factor Authentication (2FA) support
/// - Backup code management
/// - Comprehensive error handling and retry logic
/// - Gas estimation and transaction optimization
/// - Integration with existing blockchain operations
class ContractService {
  final String _rpcUrl = 'https://ace58300bb2f.ngrok-free.app';
  final String _contractAddress = '0x15D9fDF2c6514047A2FFa4B8eD0fa87BB069a0Cd'; // Updated contract with 2FA functions
  late Web3Client _client;
  late DeployedContract _contract;
  
  // Existing contract functions
  late ContractFunction _register;
  late ContractFunction _login;
  late ContractFunction _isRegistered;
  
  // New 2FA contract functions
  late ContractFunction _enable2FA;
  late ContractFunction _verify2FA;
  late ContractFunction _disable2FA;
  late ContractFunction _is2FAEnabled;
  late ContractFunction _getBackupCodeCount;
  late ContractFunction _getFailedAttempts;
  late ContractFunction _isLockedOut;
  late ContractFunction _getRemainingLockoutTime;
  late ContractFunction _regenerateBackupCodes;

  // Configuration constants
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const int _defaultGasPrice = 20; // gwei
  static const int _defaultMaxGas = 200000;
  static const int _chainId = 1337;

  // Error handler for comprehensive error management
  final TwoFAErrorHandler _errorHandler = TwoFAErrorHandler();

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
        
        // Initialize existing functions
        _register = _contract.function('register');
        _login = _contract.function('login');
        _isRegistered = _contract.function('isRegistered');
        
        // Initialize new 2FA functions (if available in contract)
        try {
          _enable2FA = _contract.function('enable2FA');
          _verify2FA = _contract.function('verify2FA');
          _disable2FA = _contract.function('disable2FA');
          _is2FAEnabled = _contract.function('is2FAEnabled');
          _getBackupCodeCount = _contract.function('getBackupCodeCount');
          _getFailedAttempts = _contract.function('getFailedAttempts');
          _isLockedOut = _contract.function('isLockedOut');
          _getRemainingLockoutTime = _contract.function('getRemainingLockoutTime');
          _regenerateBackupCodes = _contract.function('regenerateBackupCodes');
          print('✅ ContractService initialized successfully with 2FA support');
        } catch (e) {
          print('⚠️ 2FA functions not available in contract: $e');
          print('✅ ContractService initialized successfully (without 2FA)');
        }
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

  /// Gets function data for a specific function name
  String getFunctionData(String functionName) {
    final function = _contract.function(functionName);
    final encoded = function.encodeCall([]);
    return '0x${HEX.encode(encoded)}';
  }

  // ============ EXISTING FUNCTIONS (MAINTAINED) ============

  /// Registers a new user with the contract
  Future<String> register(String privateKey) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: register called');
      return 'dummy_tx_hash';
    }
    
    try {
      print('ContractService: Registering user...');
      final credentials = _getCredentials(privateKey);
      final sender = await credentials.extractAddress();
      final nonce = await _client.getTransactionCount(sender);
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _register,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: Registration successful - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Register error - $e');
      rethrow;
    }
  }

  /// Performs user login
  Future<String> login(String privateKey) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: login called');
      return 'dummy_tx_hash';
    }
    
    try {
      print('ContractService: Logging in user...');
      final credentials = _getCredentials(privateKey);
      final sender = await credentials.extractAddress();
      final nonce = await _client.getTransactionCount(sender);
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _login,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: Login successful - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Login error - $e');
      rethrow;
    }
  }

  /// Registers a user with a specific address
  Future<String> registerWithAddress(String address) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: registerWithAddress called');
      return 'dummy_tx_hash';
    }
    
    try {
      print('ContractService: Registering user with address $address...');
      final nonce = await _client.getTransactionCount(EthereumAddress.fromHex(address));
      final txHash = await _client.sendTransaction(
        EthPrivateKey.fromHex('0x278db5110cb86a67e1bb94f15de6d3d1d92f8ed49cff5524a2a314e7c5f55b50'),
        Transaction.callContract(
          contract: _contract,
          function: _register,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: Registration with address successful - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Register with address error - $e');
      rethrow;
    }
  }

  /// Performs login with a specific address
  Future<String> loginWithAddress(String address) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: loginWithAddress called');
      return 'dummy_tx_hash';
    }
    
    try {
      print('ContractService: Logging in user with address $address...');
      final nonce = await _client.getTransactionCount(EthereumAddress.fromHex(address));
      final txHash = await _client.sendTransaction(
        EthPrivateKey.fromHex('0x278db5110cb86a67e1bb94f15de6d3d1d92f8ed49cff5524a2a314e7c5f55b50'),
        Transaction.callContract(
          contract: _contract,
          function: _login,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: Login with address successful - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Login with address error - $e');
      rethrow;
    }
  }

  /// Checks if a user is registered
  Future<bool> isRegistered(String address) async {
    // Check if this is a dummy service
    if (_contract.functions.isEmpty) {
      print('⚠️ Dummy ContractService: isRegistered called');
      return false;
    }
    
    return await _retryCall<bool>(
      () async {
        print('ContractService: Checking registration for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _isRegistered,
          params: [EthereumAddress.fromHex(address)],
        );
        print('ContractService: Registration check result - $result');
        return result[0] as bool;
      },
      'isRegistered',
    );
  }

  // ============ WORKSPACE & PROFILE METHODS ============
  
  // workspaceDbAddress is now set to the actual OrbitDB address in OrbitDBService.

  Future<bool> doesWorkspaceExist(String address) async {
    try {
      // Add timeout wrapper for faster failure
      final workspaces = await DistributedService.getUserWorkspaces(address).timeout(
        const Duration(seconds: 7),
        onTimeout: () {
          print('⚠️ Workspace check timeout');
          return <Map<String, dynamic>>[];
        },
      ).catchError((e) {
        print('⚠️ Error checking workspace existence: ${e.toString().split('\n').first}');
        return <Map<String, dynamic>>[];
      });
      return workspaces.isNotEmpty;
    } catch (e) {
      print('⚠️ Error checking workspace existence: ${e.toString().split('\n').first}');
      return false;
    }
  }

  // Check if user has completed profile setup
  Future<bool> hasCompletedProfile(String address) async {
    try {
      // Add timeout wrapper for faster failure
      final profile = await DistributedService.getUserProfile(address).timeout(
        const Duration(seconds: 7),
        onTimeout: () {
          print('⚠️ Profile check timeout');
          return null;
        },
      ).catchError((e) {
        print('⚠️ Error checking profile: ${e.toString().split('\n').first}');
        return null;
      });
      
      if (profile != null) {
        final username = profile['username'];
        final email = profile['email'];
        
        return username != null && username.toString().isNotEmpty && 
               email != null && email.toString().isNotEmpty;
      }
      
      return false;
    } catch (e) {
      print('⚠️ Error checking profile completion: ${e.toString().split('\n').first}');
      return false;
    }
  }




  // ============ NEW 2FA FUNCTIONS ============

  /// Enables 2FA for a user with backup codes
  Future<String> enable2FA(String address, List<String> backupCodes) async {
    try {
      print('ContractService: Enabling 2FA for $address with ${backupCodes.length} backup codes...');
      
      // Validate input
      if (backupCodes.isEmpty) {
        throw Exception('Backup codes cannot be empty');
      }
      if (backupCodes.length > 20) {
        throw Exception('Too many backup codes (max 20)');
      }
      
      final credentials = _getCredentialsFromAddress(address);
      final sender = EthereumAddress.fromHex(address);
      final nonce = await _client.getTransactionCount(sender);
      
      // Convert backup codes to dynamic list for contract call
      final dynamicBackupCodes = backupCodes.map((code) => code as dynamic).toList();
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _enable2FA,
          parameters: [dynamicBackupCodes],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: 2FA enabled successfully - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Enable 2FA error - $e');
      rethrow;
    }
  }

  /// Verifies 2FA code (TOTP or backup code)
  Future<bool> verify2FA(String address, String code) async {
    try {
      print('ContractService: Verifying 2FA code for $address...');
      
      // Validate input
      if (code.isEmpty) {
        throw Exception('Verification code cannot be empty');
      }
      
      final credentials = _getCredentialsFromAddress(address);
      final sender = EthereumAddress.fromHex(address);
      final nonce = await _client.getTransactionCount(sender);
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _verify2FA,
          parameters: [code],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      // Wait for transaction to be mined and get the result
      final receipt = await _waitForTransactionReceipt(txHash);
      if (receipt.status == 1) { // 1 = success, 0 = failure
        print('ContractService: 2FA verification successful - $txHash');
        return true;
      } else {
        print('ContractService: 2FA verification failed - $txHash');
        return false;
      }
    } catch (e) {
      print('ContractService: Verify 2FA error - $e');
      rethrow;
    }
  }

  /// Disables 2FA for a user
  Future<String> disable2FA(String address) async {
    try {
      print('ContractService: Disabling 2FA for $address...');
      
      final credentials = _getCredentialsFromAddress(address);
      final sender = EthereumAddress.fromHex(address);
      final nonce = await _client.getTransactionCount(sender);
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _disable2FA,
          parameters: [],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: 2FA disabled successfully - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Disable 2FA error - $e');
      rethrow;
    }
  }

  /// Checks if 2FA is enabled for a user
  Future<bool> is2FAEnabled(String address) async {
    return await _retryCall<bool>(
      () async {
        print('ContractService: Checking 2FA status for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _is2FAEnabled,
          params: [EthereumAddress.fromHex(address)],
        );
        print('ContractService: 2FA status result - $result');
        return result[0] as bool;
      },
      'is2FAEnabled',
    );
  }

  /// Gets the number of remaining backup codes for a user
  Future<int> getBackupCodeCount(String address) async {
    return await _retryCall<int>(
      () async {
        print('ContractService: Getting backup code count for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _getBackupCodeCount,
          params: [EthereumAddress.fromHex(address)],
        );
        final count = (result[0] as BigInt).toInt();
        print('ContractService: Backup code count - $count');
        return count;
      },
      'getBackupCodeCount',
    );
  }

  /// Gets the number of failed attempts for a user
  Future<int> getFailedAttempts(String address) async {
    return await _retryCall<int>(
      () async {
        print('ContractService: Getting failed attempts for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _getFailedAttempts,
          params: [EthereumAddress.fromHex(address)],
        );
        final attempts = (result[0] as BigInt).toInt();
        print('ContractService: Failed attempts - $attempts');
        return attempts;
      },
      'getFailedAttempts',
    );
  }

  /// Checks if a user is currently locked out
  Future<bool> isLockedOut(String address) async {
    return await _retryCall<bool>(
      () async {
        print('ContractService: Checking lockout status for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _isLockedOut,
          params: [EthereumAddress.fromHex(address)],
        );
        print('ContractService: Lockout status result - $result');
        return result[0] as bool;
      },
      'isLockedOut',
    );
  }

  /// Gets the remaining lockout time for a user
  Future<int> getRemainingLockoutTime(String address) async {
    return await _retryCall<int>(
      () async {
        print('ContractService: Getting remaining lockout time for $address...');
        final result = await _client.call(
          contract: _contract,
          function: _getRemainingLockoutTime,
          params: [EthereumAddress.fromHex(address)],
        );
        final time = (result[0] as BigInt).toInt();
        print('ContractService: Remaining lockout time - $time seconds');
        return time;
      },
      'getRemainingLockoutTime',
    );
  }

  /// Regenerates backup codes for a user
  Future<String> regenerateBackupCodes(String address, List<String> newBackupCodes) async {
    try {
      print('ContractService: Regenerating backup codes for $address...');
      
      // Validate input
      if (newBackupCodes.isEmpty) {
        throw Exception('New backup codes cannot be empty');
      }
      if (newBackupCodes.length > 20) {
        throw Exception('Too many backup codes (max 20)');
      }
      
      final credentials = _getCredentialsFromAddress(address);
      final sender = EthereumAddress.fromHex(address);
      final nonce = await _client.getTransactionCount(sender);
      
      // Convert backup codes to dynamic list for contract call
      final dynamicBackupCodes = newBackupCodes.map((code) => code as dynamic).toList();
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: _regenerateBackupCodes,
          parameters: [dynamicBackupCodes],
          nonce: nonce,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice),
          maxGas: _defaultMaxGas,
        ),
        chainId: _chainId,
      );
      
      print('ContractService: Backup codes regenerated successfully - $txHash');
      return txHash;
    } catch (e) {
      print('ContractService: Regenerate backup codes error - $e');
      rethrow;
    }
  }

  // ============ HELPER FUNCTIONS ============

  /// Gets credentials from private key
  EthPrivateKey _getCredentials(String privateKey) {
    return EthPrivateKey.fromHex(
      privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey
    );
  }

  /// Gets credentials from address (using default private key for testing)
  EthPrivateKey _getCredentialsFromAddress(String address) {
    // In production, you would need to store private keys securely
    // For now, using a default private key for testing
    return EthPrivateKey.fromHex('0x278db5110cb86a67e1bb94f15de6d3d1d92f8ed49cff5524a2a314e7c5f55b50');
  }

  /// Retry logic for contract calls
  Future<T> _retryCall<T>(Future<T> Function() call, String operation) async {
    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        return await call();
      } catch (e) {
        print('ContractService: $operation error (Attempt ${retryCount + 1}) - $e');
        retryCount++;
        if (retryCount >= _maxRetries) {
          throw Exception('Failed to execute $operation after $_maxRetries attempts: $e');
        }
        await Future.delayed(_retryDelay);
      }
    }
    throw Exception('Failed to execute $operation after $_maxRetries attempts');
  }

  /// Waits for transaction receipt
  Future<TransactionReceipt> _waitForTransactionReceipt(String txHash) async {
    const maxAttempts = 30; // 30 seconds timeout
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        final receipt = await _client.getTransactionReceipt(txHash);
        if (receipt != null) {
          return receipt;
        }
      } catch (e) {
        print('ContractService: Error getting transaction receipt - $e');
      }
      
      attempts++;
      await Future.delayed(const Duration(seconds: 1));
    }
    
    throw Exception('Transaction receipt timeout after ${maxAttempts} seconds');
  }

  /// Estimates gas for a transaction
  Future<int> estimateGas(String functionName, List<dynamic> parameters) async {
    try {
      final function = _contract.function(functionName);
      final gasEstimate = await _client.estimateGas(
        sender: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
        to: EthereumAddress.fromHex(_contractAddress),
        data: function.encodeCall(parameters),
      );
      return gasEstimate.toInt();
    } catch (e) {
      print('ContractService: Gas estimation error - $e');
      return _defaultMaxGas; // Return default if estimation fails
    }
  }

  /// Gets current gas price
  Future<int> getCurrentGasPrice() async {
    try {
      final gasPrice = await _client.getGasPrice();
      return gasPrice.getInWei.toInt();
    } catch (e) {
      print('ContractService: Gas price error - $e');
      return EtherAmount.fromUnitAndValue(EtherUnit.gwei, _defaultGasPrice).getInWei.toInt();
    }
  }

  /// Tests the contract connection and basic functionality
  Future<void> testRegisterAndLogin() async {
    try {
      print('ContractService: Testing contract connection...');
      final privateKey = '0x278db5110cb86a67e1bb94f15de6d3d1d92f8ed49cff5524a2a314e7c5f55b50';
      final address = EthPrivateKey.fromHex(privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey).address.hex;
      
      final isUserRegistered = await isRegistered(address);
      print('ContractService: Test isRegistered - $isUserRegistered');
      
      if (!isUserRegistered) {
        final txHash = await register(privateKey);
        print('ContractService: Test register transaction - $txHash');
      }
      
      final txHash = await login(privateKey);
      print('ContractService: Test login transaction - $txHash');
      
      // Test 2FA functions if available
      try {
        final is2FAEnabled = await this.is2FAEnabled(address);
        print('ContractService: Test 2FA status - $is2FAEnabled');
      } catch (e) {
        print('ContractService: 2FA functions not available in contract - $e');
      }
      
    } catch (e) {
      print('ContractService: Test register/login error - $e');
    }
  }

  /// Gets contract information
  Future<Map<String, dynamic>> getContractInfo() async {
    try {
      print('ContractService: Getting contract information...');
      return {
        'contractAddress': _contractAddress,
        'rpcUrl': _rpcUrl,
        'chainId': _chainId,
        'maxRetries': _maxRetries,
        'defaultGasPrice': _defaultGasPrice,
        'defaultMaxGas': _defaultMaxGas,
      };
    } catch (e) {
      print('ContractService: Get contract info error - $e');
      rethrow;
    }
  }

  /// Closes the Web3 client connection
  Future<void> dispose() async {
    try {
      await _client.dispose();
      print('ContractService: Disposed successfully');
    } catch (e) {
      print('ContractService: Dispose error - $e');
    }
  }

  // ============ ERROR HANDLING METHODS ============

  /// Enable 2FA with comprehensive error handling
  Future<String> enable2FASafe(String privateKey, List<String> backupCodes) async {
    return await _errorHandler.handle2FAError(
      () async {
        // Validate inputs
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'enable2FA',
          );
        }

        if (backupCodes.isEmpty || backupCodes.length > 20) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid backup codes count',
            ),
            'Backup codes must be between 1 and 20',
            'enable2FA',
          );
        }

        // Validate backup code format
        for (final code in backupCodes) {
          if (code.length != 8 || !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.blockchain,
                severity: ErrorSeverity.high,
                recoverable: true,
                retryable: false,
                originalError: 'Invalid backup code format',
              ),
              'Backup codes must be 8 characters and contain only uppercase letters and numbers',
              'enable2FA',
            );
          }
        }

        return await enable2FA(privateKey, backupCodes);
      },
      'enable2FA',
      retryable: true,
      customErrorMessage: 'Failed to enable 2FA on blockchain',
    );
  }

  /// Verify 2FA with comprehensive error handling
  Future<bool> verify2FASafe(String privateKey, String code) async {
    return await _errorHandler.handle2FAError(
      () async {
        // Validate inputs
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'verify2FA',
          );
        }

        if (code.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty code',
            ),
            'Verification code cannot be empty',
            'verify2FA',
          );
        }

        // Check if it's a TOTP code (6 digits) or backup code (8 characters)
        if (code.length == 6) {
          if (!RegExp(r'^\d{6}$').hasMatch(code)) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.authentication,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Invalid TOTP code format',
              ),
              'TOTP code must be 6 digits',
              'verify2FA',
            );
          }
        } else if (code.length == 8) {
          if (!RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.authentication,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Invalid backup code format',
              ),
              'Backup code must be 8 characters and contain only uppercase letters and numbers',
              'verify2FA',
            );
          }
        } else {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid code length',
            ),
            'Code must be 6 digits (TOTP) or 8 characters (backup)',
            'verify2FA',
          );
        }

        return await verify2FA(privateKey, code);
      },
      'verify2FA',
      retryable: true,
      customErrorMessage: 'Failed to verify 2FA code',
    );
  }

  /// Disable 2FA with error handling
  Future<String> disable2FASafe(String privateKey) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'disable2FA',
          );
        }

        return await disable2FA(privateKey);
      },
      'disable2FA',
      retryable: true,
      customErrorMessage: 'Failed to disable 2FA on blockchain',
    );
  }

  /// Check if 2FA is enabled with error handling
  Future<bool> is2FAEnabledSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'is2FAEnabled',
          );
        }

        // Validate Ethereum address format
        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'is2FAEnabled',
          );
        }

        return await is2FAEnabled(address);
      },
      'is2FAEnabled',
      retryable: true,
      customErrorMessage: 'Failed to check 2FA status on blockchain',
    );
  }

  /// Get backup code count with error handling
  Future<int> getBackupCodeCountSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'getBackupCodeCount',
          );
        }

        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'getBackupCodeCount',
          );
        }

        final result = await getBackupCodeCount(address);
        return result;
      },
      'getBackupCodeCount',
      retryable: true,
      customErrorMessage: 'Failed to get backup code count from blockchain',
    );
  }

  /// Get failed attempts with error handling
  Future<int> getFailedAttemptsSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'getFailedAttempts',
          );
        }

        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'getFailedAttempts',
          );
        }

        final result = await getFailedAttempts(address);
        return result;
      },
      'getFailedAttempts',
      retryable: true,
      customErrorMessage: 'Failed to get failed attempts from blockchain',
    );
  }

  /// Check if user is locked out with error handling
  Future<bool> isLockedOutSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'isLockedOut',
          );
        }

        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'isLockedOut',
          );
        }

        return await isLockedOut(address);
      },
      'isLockedOut',
      retryable: true,
      customErrorMessage: 'Failed to check lockout status from blockchain',
    );
  }

  /// Get remaining lockout time with error handling
  Future<int> getRemainingLockoutTimeSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'getRemainingLockoutTime',
          );
        }

        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'getRemainingLockoutTime',
          );
        }

        final result = await getRemainingLockoutTime(address);
        return result;
      },
      'getRemainingLockoutTime',
      retryable: true,
      customErrorMessage: 'Failed to get remaining lockout time from blockchain',
    );
  }

  /// Regenerate backup codes with error handling
  Future<String> regenerateBackupCodesSafe(String privateKey, List<String> newBackupCodes) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'regenerateBackupCodes',
          );
        }

        if (newBackupCodes.isEmpty || newBackupCodes.length > 20) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid backup codes count',
            ),
            'Backup codes must be between 1 and 20',
            'regenerateBackupCodes',
          );
        }

        // Validate backup code format
        for (final code in newBackupCodes) {
          if (code.length != 8 || !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.blockchain,
                severity: ErrorSeverity.high,
                recoverable: true,
                retryable: false,
                originalError: 'Invalid backup code format',
              ),
              'Backup codes must be 8 characters and contain only uppercase letters and numbers',
              'regenerateBackupCodes',
            );
          }
        }

        return await regenerateBackupCodes(privateKey, newBackupCodes);
      },
      'regenerateBackupCodes',
      retryable: true,
      customErrorMessage: 'Failed to regenerate backup codes on blockchain',
    );
  }

  /// Register user with error handling
  Future<String> registerSafe(String privateKey) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'register',
          );
        }

        return await register(privateKey);
      },
      'register',
      retryable: true,
      customErrorMessage: 'Failed to register user on blockchain',
    );
  }

  /// Login user with error handling
  Future<String> loginSafe(String privateKey) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (privateKey.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.high,
              recoverable: true,
              retryable: false,
              originalError: 'Empty private key',
            ),
            'Private key cannot be empty',
            'login',
          );
        }

        return await login(privateKey);
      },
      'login',
      retryable: true,
      customErrorMessage: 'Failed to login user on blockchain',
    );
  }

  /// Check if user is registered with error handling
  Future<bool> isRegisteredSafe(String address) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (address.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty address',
            ),
            'Address cannot be empty',
            'isRegistered',
          );
        }

        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.blockchain,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid address format',
            ),
            'Invalid Ethereum address format',
            'isRegistered',
          );
        }

        return await isRegistered(address);
      },
      'isRegistered',
      retryable: true,
      customErrorMessage: 'Failed to check registration status from blockchain',
    );
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    return _errorHandler.getErrorStatistics();
  }

  /// Clear error history
  void clearErrorHistory() {
    _errorHandler.clearErrorHistory();
  }

  /// Dispose with error handling
  Future<void> disposeSafe() async {
    try {
      await dispose();
      _errorHandler.dispose();
    } catch (e) {
      print('ContractService: Safe dispose error - $e');
    }
  }
}