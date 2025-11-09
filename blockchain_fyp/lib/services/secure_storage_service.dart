import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'two_fa_error_handler.dart';

/// Comprehensive Secure Storage Service for 2FA and sensitive data
/// 
/// This service provides:
/// - Encrypted storage using flutter_secure_storage
/// - TOTP secret management with proper encryption
/// - Backup codes with expiration tracking
/// - 2FA settings and configuration storage
/// - Data migration support for future updates
/// - Graceful error handling and recovery
/// - Cross-platform security (Android/iOS)
class SecureStorageService {
  // Storage configuration with platform-specific security
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  // Storage keys with versioning for migration support
  static const String _versionKey = 'storage_version';
  static const String _totpSecretKey = 'totp_secret_v2';
  static const String _biometricEnabledKey = 'biometric_enabled_v2';
  static const String _backupCodesKey = 'backup_codes_v2';
  static const String _backupCodesExpiryKey = 'backup_codes_expiry_v2';
  static const String _user2FAStatusKey = 'user_2fa_status_v2';
  static const String _lastBackupCodeUsedKey = 'last_backup_code_used_v2';
  static const String _totpAlgorithmKey = 'totp_algorithm_v2';
  static const String _timeWindowToleranceKey = 'time_window_tolerance_v2';
  static const String _lastTimeSyncKey = 'last_time_sync_v2';
  static const String _timeOffsetKey = 'time_offset_v2';
  
  // Current storage version for migration
  static const int _currentVersion = 2;
  
  // Backup code expiration (30 days)
  static const Duration _backupCodeExpiration = Duration(days: 30);

  // Error handler for comprehensive error management
  final TwoFAErrorHandler _errorHandler = TwoFAErrorHandler();

  SecureStorageService._();

  static Future<SecureStorageService> create() async {
    final service = SecureStorageService._();
    await service._initialize();
    return service;
  }

  /// Initialize the secure storage service with migration support
  Future<void> _initialize() async {
    try {
      await _checkAndMigrateData();
      print('SecureStorageService initialized successfully');
    } catch (e) {
      print('SecureStorageService initialization error: $e');
      rethrow;
    }
  }

  /// Check storage version and migrate data if necessary
  Future<void> _checkAndMigrateData() async {
    try {
      final versionString = await _storage.read(key: _versionKey);
      final currentVersion = int.tryParse(versionString ?? '0') ?? 0;
      
      if (currentVersion < _currentVersion) {
        print('Migrating storage from version $currentVersion to $_currentVersion');
        await _migrateData(currentVersion);
        await _storage.write(key: _versionKey, value: _currentVersion.toString());
        print('Data migration completed');
      }
    } catch (e) {
      print('Data migration error: $e');
      // Continue without migration - fresh install
    }
  }

  /// Migrate data from older versions
  Future<void> _migrateData(int fromVersion) async {
    try {
      if (fromVersion < 2) {
        // Migrate from version 1 to 2
        await _migrateFromV1ToV2();
      }
    } catch (e) {
      print('Migration from version $fromVersion failed: $e');
      throw Exception('Data migration failed: $e');
    }
  }

  /// Migrate from version 1 to version 2
  Future<void> _migrateFromV1ToV2() async {
    try {
      // Migrate old keys to new versioned keys
      final oldKeys = [
        'totp_secret',
        'biometric_enabled',
        'backup_codes',
        'user_2fa_status',
      ];
      
      final newKeys = [
        _totpSecretKey,
        _biometricEnabledKey,
        _backupCodesKey,
        _user2FAStatusKey,
      ];
      
      for (int i = 0; i < oldKeys.length; i++) {
        final oldValue = await _storage.read(key: oldKeys[i]);
        if (oldValue != null) {
          await _storage.write(key: newKeys[i], value: oldValue);
          await _storage.delete(key: oldKeys[i]);
        }
      }
      
      print('Migration from v1 to v2 completed');
    } catch (e) {
      print('Migration from v1 to v2 error: $e');
      rethrow;
    }
  }

  /// Store TOTP secret securely with validation
  Future<void> storeTOTPSecret(String secret) async {
    try {
      if (secret.isEmpty) {
        throw ArgumentError('TOTP secret cannot be empty');
      }
      
      // Validate secret format (basic check)
      if (secret.length < 16) {
        throw ArgumentError('TOTP secret is too short');
      }
      
      await _storage.write(key: _totpSecretKey, value: secret);
      print('TOTP secret stored successfully');
    } catch (e) {
      print('Store TOTP secret error: $e');
      rethrow;
    }
  }

  /// Retrieve TOTP secret with error handling
  Future<String?> getTOTPSecret() async {
    try {
      final secret = await _storage.read(key: _totpSecretKey);
      if (secret != null) {
        print('TOTP secret retrieved successfully');
      }
      return secret;
    } catch (e) {
      print('Get TOTP secret error: $e');
      return null;
    }
  }

  /// Store biometric enabled status
  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
      print('Biometric enabled status set to: $enabled');
    } catch (e) {
      print('Set biometric enabled error: $e');
      rethrow;
    }
  }

  /// Check if biometric is enabled
  Future<bool> isBiometricEnabled() async {
    try {
      final value = await _storage.read(key: _biometricEnabledKey);
      final enabled = value == 'true';
      print('Biometric enabled status: $enabled');
      return enabled;
    } catch (e) {
      print('Get biometric enabled error: $e');
      return false;
    }
  }

  /// Store backup codes with expiration tracking
  Future<void> storeBackupCodes(List<String> codes) async {
    try {
      if (codes.isEmpty) {
        throw ArgumentError('Backup codes list cannot be empty');
      }
      
      // Validate backup codes format
      for (final code in codes) {
        if (code.length != 8) {
          throw ArgumentError('Invalid backup code length: ${code.length}');
        }
      }
      
      final codesJson = jsonEncode({
        'codes': codes,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(_backupCodeExpiration).toIso8601String(),
      });
      
      await _storage.write(key: _backupCodesKey, value: codesJson);
      print('Backup codes stored successfully (${codes.length} codes)');
    } catch (e) {
      print('Store backup codes error: $e');
      rethrow;
    }
  }

  /// Retrieve backup codes with expiration check
  Future<List<String>> getBackupCodes() async {
    try {
      final codesJson = await _storage.read(key: _backupCodesKey);
      if (codesJson == null || codesJson.isEmpty) {
        return [];
      }
      
      final data = jsonDecode(codesJson) as Map<String, dynamic>;
      final expiresAt = DateTime.parse(data['expires_at'] as String);
      
      if (DateTime.now().isAfter(expiresAt)) {
        print('Backup codes have expired, clearing storage');
        await _storage.delete(key: _backupCodesKey);
        return [];
      }
      
      final codes = List<String>.from(data['codes'] as List);
      print('Backup codes retrieved successfully (${codes.length} codes)');
      return codes;
    } catch (e) {
      print('Get backup codes error: $e');
      return [];
    }
  }

  /// Check if backup codes are expired
  Future<bool> areBackupCodesExpired() async {
    try {
      final codesJson = await _storage.read(key: _backupCodesKey);
      if (codesJson == null) return true;
      
      final data = jsonDecode(codesJson) as Map<String, dynamic>;
      final expiresAt = DateTime.parse(data['expires_at'] as String);
      
      return DateTime.now().isAfter(expiresAt);
    } catch (e) {
      print('Check backup codes expiration error: $e');
      return true;
    }
  }

  /// Mark backup code as used and remove it
  Future<bool> useBackupCode(String code) async {
    try {
      final codes = await getBackupCodes();
      if (!codes.contains(code)) {
        print('Backup code not found: $code');
        return false;
      }
      
      // Remove the used code
      codes.remove(code);
      
      if (codes.isEmpty) {
        // No more backup codes, clear storage
        await _storage.delete(key: _backupCodesKey);
        print('Last backup code used, cleared storage');
      } else {
        // Update storage with remaining codes
        await storeBackupCodes(codes);
        print('Backup code used, ${codes.length} codes remaining');
      }
      
      // Track last used backup code
      await _storage.write(
        key: _lastBackupCodeUsedKey,
        value: DateTime.now().toIso8601String(),
      );
      
      return true;
    } catch (e) {
      print('Use backup code error: $e');
      return false;
    }
  }

  /// Get last backup code usage timestamp
  Future<DateTime?> getLastBackupCodeUsed() async {
    try {
      final timestamp = await _storage.read(key: _lastBackupCodeUsedKey);
      if (timestamp != null) {
        return DateTime.parse(timestamp);
      }
      return null;
    } catch (e) {
      print('Get last backup code used error: $e');
      return null;
    }
  }

  /// Set user 2FA status
  Future<void> setUser2FAStatus(bool enabled) async {
    try {
      await _storage.write(key: _user2FAStatusKey, value: enabled.toString());
      print('User 2FA status set to: $enabled');
    } catch (e) {
      print('Set user 2FA status error: $e');
      rethrow;
    }
  }

  /// Check if user has 2FA enabled
  Future<bool> isUser2FAEnabled() async {
    try {
      final value = await _storage.read(key: _user2FAStatusKey);
      final enabled = value == 'true';
      print('User 2FA status: $enabled');
      return enabled;
    } catch (e) {
      print('Get user 2FA status error: $e');
      return false;
    }
  }

  /// Store TOTP algorithm preference
  Future<void> setTOTPAlgorithm(String algorithm) async {
    try {
      await _storage.write(key: _totpAlgorithmKey, value: algorithm);
      print('TOTP algorithm set to: $algorithm');
    } catch (e) {
      print('Set TOTP algorithm error: $e');
      rethrow;
    }
  }

  /// Get TOTP algorithm preference
  Future<String> getTOTPAlgorithm() async {
    try {
      final algorithm = await _storage.read(key: _totpAlgorithmKey);
      return algorithm ?? 'SHA1'; // Default to SHA1
    } catch (e) {
      print('Get TOTP algorithm error: $e');
      return 'SHA1';
    }
  }

  /// Store time window tolerance
  Future<void> setTimeWindowTolerance(int tolerance) async {
    try {
      await _storage.write(key: _timeWindowToleranceKey, value: tolerance.toString());
      print('Time window tolerance set to: $tolerance');
    } catch (e) {
      print('Set time window tolerance error: $e');
      rethrow;
    }
  }

  /// Get time window tolerance
  Future<int> getTimeWindowTolerance() async {
    try {
      final tolerance = await _storage.read(key: _timeWindowToleranceKey);
      return int.tryParse(tolerance ?? '1') ?? 1; // Default to 1
    } catch (e) {
      print('Get time window tolerance error: $e');
      return 1;
    }
  }

  /// Store time synchronization data
  Future<void> storeTimeSyncData(DateTime lastSync, int timeOffset) async {
    try {
      await _storage.write(key: _lastTimeSyncKey, value: lastSync.toIso8601String());
      await _storage.write(key: _timeOffsetKey, value: timeOffset.toString());
      print('Time sync data stored: offset=${timeOffset}s');
    } catch (e) {
      print('Store time sync data error: $e');
      rethrow;
    }
  }

  /// Get time synchronization data
  Future<Map<String, dynamic>?> getTimeSyncData() async {
    try {
      final lastSync = await _storage.read(key: _lastTimeSyncKey);
      final timeOffset = await _storage.read(key: _timeOffsetKey);
      
      if (lastSync != null && timeOffset != null) {
        return {
          'lastSync': DateTime.parse(lastSync),
          'timeOffset': int.parse(timeOffset),
        };
      }
      return null;
    } catch (e) {
      print('Get time sync data error: $e');
      return null;
    }
  }

  /// Clear all 2FA data
  Future<void> clear2FAData() async {
    try {
      final keys = [
        _totpSecretKey,
        _biometricEnabledKey,
        _backupCodesKey,
        _backupCodesExpiryKey,
        _user2FAStatusKey,
        _lastBackupCodeUsedKey,
        _totpAlgorithmKey,
        _timeWindowToleranceKey,
        _lastTimeSyncKey,
        _timeOffsetKey,
      ];
      
      for (final key in keys) {
        await _storage.delete(key: key);
      }
      
      print('All 2FA data cleared successfully');
    } catch (e) {
      print('Clear 2FA data error: $e');
      rethrow;
    }
  }

  /// Store custom secure data with validation
  Future<void> storeSecureData(String key, String value) async {
    try {
      if (key.isEmpty) {
        throw ArgumentError('Storage key cannot be empty');
      }
      
      await _storage.write(key: key, value: value);
      print('Secure data stored for key: $key');
    } catch (e) {
      print('Store secure data error for key $key: $e');
      rethrow;
    }
  }

  /// Retrieve custom secure data
  Future<String?> getSecureData(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        print('Secure data retrieved for key: $key');
      }
      return value;
    } catch (e) {
      print('Get secure data error for key $key: $e');
      return null;
    }
  }

  /// Delete custom secure data
  Future<void> deleteSecureData(String key) async {
    try {
      await _storage.delete(key: key);
      print('Secure data deleted for key: $key');
    } catch (e) {
      print('Delete secure data error for key $key: $e');
      rethrow;
    }
  }

  /// Get all stored keys (for debugging)
  Future<Map<String, String>> getAllStoredData() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      print('Get all stored data error: $e');
      return {};
    }
  }

  /// Check if storage is available and working
  Future<bool> isStorageAvailable() async {
    try {
      const testKey = 'test_storage_availability';
      const testValue = 'test';
      
      await _storage.write(key: testKey, value: testValue);
      final retrieved = await _storage.read(key: testKey);
      await _storage.delete(key: testKey);
      
      return retrieved == testValue;
    } catch (e) {
      print('Storage availability check failed: $e');
      return false;
    }
  }

  /// Get storage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final allData = await getAllStoredData();
      final backupCodes = await getBackupCodes();
      final is2FAEnabled = await isUser2FAEnabled();
      final biometricEnabled = await isBiometricEnabled();
      final hasTOTPSecret = await getTOTPSecret() != null;
      final backupCodesExpired = await areBackupCodesExpired();
      final lastBackupUsed = await getLastBackupCodeUsed();
      
      return {
        'totalKeys': allData.length,
        'hasTOTPSecret': hasTOTPSecret,
        'is2FAEnabled': is2FAEnabled,
        'isBiometricEnabled': biometricEnabled,
        'backupCodesCount': backupCodes.length,
        'areBackupCodesExpired': backupCodesExpired,
        'lastBackupCodeUsed': lastBackupUsed?.toIso8601String(),
        'storageVersion': _currentVersion,
        'isStorageAvailable': await isStorageAvailable(),
      };
    } catch (e) {
      print('Get storage stats error: $e');
      return {};
    }
  }

  /// Test storage functionality
  Future<void> testStorage() async {
    try {
      print('Testing SecureStorageService...');
      
      // Test basic storage
      const testKey = 'test_key';
      const testValue = 'test_value';
      
      await storeSecureData(testKey, testValue);
      final retrieved = await getSecureData(testKey);
      
      if (retrieved != testValue) {
        throw Exception('Basic storage test failed');
      }
      
      await deleteSecureData(testKey);
      
      // Test 2FA data
      await setUser2FAStatus(true);
      final isEnabled = await isUser2FAEnabled();
      
      if (!isEnabled) {
        throw Exception('2FA status test failed');
      }
      
      // Test backup codes
      final testCodes = ['TEST1234', 'TEST5678'];
      await storeBackupCodes(testCodes);
      final retrievedCodes = await getBackupCodes();
      
      if (retrievedCodes.length != testCodes.length) {
        throw Exception('Backup codes test failed');
      }
      
      // Cleanup
      await clear2FAData();
      
      print('SecureStorageService test completed successfully');
    } catch (e) {
      print('SecureStorageService test failed: $e');
      rethrow;
    }
  }

  // ============ ERROR HANDLING METHODS ============

  /// Store TOTP secret with error handling
  Future<void> storeTOTPSecretSafe(String secret) async {
    await _errorHandler.handle2FAError(
      () async {
        if (secret.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty secret',
            ),
            'Secret key cannot be empty',
            'storeTOTPSecret',
          );
        }

        await storeTOTPSecret(secret);
      },
      'storeTOTPSecret',
      retryable: true,
      customErrorMessage: 'Failed to store TOTP secret securely',
    );
  }

  /// Get TOTP secret with error handling
  Future<String?> getTOTPSecretSafe() async {
    return await _errorHandler.handle2FAError(
      () => getTOTPSecret(),
      'getTOTPSecret',
      retryable: true,
      customErrorMessage: 'Failed to retrieve TOTP secret',
    );
  }

  /// Store backup codes with error handling
  Future<void> storeBackupCodesSafe(List<String> codes) async {
    await _errorHandler.handle2FAError(
      () async {
        if (codes.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty backup codes',
            ),
            'Backup codes cannot be empty',
            'storeBackupCodes',
          );
        }

        // Validate backup code format
        for (final code in codes) {
          if (code.length != 8 || !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.storage,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Invalid backup code format',
              ),
              'Backup codes must be 8 characters and contain only uppercase letters and numbers',
              'storeBackupCodes',
            );
          }
        }

        await storeBackupCodes(codes);
      },
      'storeBackupCodes',
      retryable: true,
      customErrorMessage: 'Failed to store backup codes securely',
    );
  }

  /// Get backup codes with error handling
  Future<List<String>> getBackupCodesSafe() async {
    return await _errorHandler.handle2FAError(
      () => getBackupCodes(),
      'getBackupCodes',
      retryable: true,
      customErrorMessage: 'Failed to retrieve backup codes',
    );
  }

  /// Use backup code with error handling
  Future<bool> useBackupCodeSafe(String code) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (code.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty backup code',
            ),
            'Backup code cannot be empty',
            'useBackupCode',
          );
        }

        if (code.length != 8 || !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.authentication,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Invalid backup code format',
            ),
            'Backup code must be 8 characters and contain only uppercase letters and numbers',
            'useBackupCode',
          );
        }

        return await useBackupCode(code);
      },
      'useBackupCode',
      retryable: false,
      customErrorMessage: 'Failed to use backup code',
    );
  }

  /// Set user 2FA status with error handling
  Future<void> setUser2FAStatusSafe(bool enabled) async {
    await _errorHandler.handle2FAError(
      () => setUser2FAStatus(enabled),
      'setUser2FAStatus',
      retryable: true,
      customErrorMessage: 'Failed to update 2FA status',
    );
  }

  /// Check if user 2FA is enabled with error handling
  Future<bool> isUser2FAEnabledSafe() async {
    return await _errorHandler.handle2FAError(
      () => isUser2FAEnabled(),
      'isUser2FAEnabled',
      retryable: true,
      customErrorMessage: 'Failed to check 2FA status',
    );
  }

  /// Set biometric enabled status with error handling
  Future<void> setBiometricEnabledSafe(bool enabled) async {
    await _errorHandler.handle2FAError(
      () => setBiometricEnabled(enabled),
      'setBiometricEnabled',
      retryable: true,
      customErrorMessage: 'Failed to update biometric settings',
    );
  }

  /// Check if biometric is enabled with error handling
  Future<bool> isBiometricEnabledSafe() async {
    return await _errorHandler.handle2FAError(
      () => isBiometricEnabled(),
      'isBiometricEnabled',
      retryable: true,
      customErrorMessage: 'Failed to check biometric settings',
    );
  }

  /// Store secure data with error handling
  Future<void> storeSecureDataSafe(String key, String value) async {
    await _errorHandler.handle2FAError(
      () async {
        if (key.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty key',
            ),
            'Storage key cannot be empty',
            'storeSecureData',
          );
        }

        if (value.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty value',
            ),
            'Storage value cannot be empty',
            'storeSecureData',
          );
        }

        await storeSecureData(key, value);
      },
      'storeSecureData',
      retryable: true,
      customErrorMessage: 'Failed to store data securely',
    );
  }

  /// Get secure data with error handling
  Future<String?> getSecureDataSafe(String key) async {
    return await _errorHandler.handle2FAError(
      () async {
        if (key.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty key',
            ),
            'Storage key cannot be empty',
            'getSecureData',
          );
        }

        return await getSecureData(key);
      },
      'getSecureData',
      retryable: true,
      customErrorMessage: 'Failed to retrieve data securely',
    );
  }

  /// Delete secure data with error handling
  Future<void> deleteSecureDataSafe(String key) async {
    await _errorHandler.handle2FAError(
      () async {
        if (key.isEmpty) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.storage,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: false,
              originalError: 'Empty key',
            ),
            'Storage key cannot be empty',
            'deleteSecureData',
          );
        }

        await deleteSecureData(key);
      },
      'deleteSecureData',
      retryable: true,
      customErrorMessage: 'Failed to delete data securely',
    );
  }

  /// Clear 2FA data with error handling
  Future<void> clear2FADataSafe() async {
    await _errorHandler.handle2FAError(
      () => clear2FAData(),
      'clear2FAData',
      retryable: true,
      customErrorMessage: 'Failed to clear 2FA data',
    );
  }

  /// Check storage availability with error handling
  Future<bool> isStorageAvailableSafe() async {
    return await _errorHandler.handle2FAError(
      () => isStorageAvailable(),
      'isStorageAvailable',
      retryable: true,
      customErrorMessage: 'Failed to check storage availability',
    );
  }

  /// Get storage statistics with error handling
  Future<Map<String, dynamic>> getStorageStatsSafe() async {
    return await _errorHandler.handle2FAError(
      () => getStorageStats(),
      'getStorageStats',
      retryable: false,
      customErrorMessage: 'Failed to get storage statistics',
    );
  }

  /// Test storage with error handling
  Future<void> testStorageSafe() async {
    await _errorHandler.handle2FAError(
      () => testStorage(),
      'testStorage',
      retryable: true,
      customErrorMessage: 'Storage test failed',
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

  /// Dispose resources
  void dispose() {
    _errorHandler.dispose();
  }
}
