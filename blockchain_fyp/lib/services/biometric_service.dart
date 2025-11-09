import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'two_fa_error_handler.dart';

class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static final TwoFAErrorHandler _errorHandler = TwoFAErrorHandler();

  /// Check if biometric authentication is available
  static Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      print('Biometric availability check error: $e');
      return false;
    }
  }

  /// Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('Get available biometrics error: $e');
      return [];
    }
  }

  /// Authenticate using biometrics
  static Future<bool> authenticate({
    String? reason,
    String? cancelButton,
    String? goToSettingsButton,
    String? goToSettingsDescription,
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        throw PlatformException(
          code: 'BIOMETRIC_NOT_AVAILABLE',
          message: 'Biometric authentication is not available on this device',
        );
      }

      return await _localAuth.authenticate(
        localizedReason: reason ?? 'Please authenticate to continue',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }

  /// Check if biometric is enrolled
  static Future<bool> isBiometricEnrolled() async {
    try {
      final biometrics = await getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      print('Biometric enrollment check error: $e');
      return false;
    }
  }

  /// Stop biometric authentication
  static Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      print('Stop biometric authentication error: $e');
    }
  }

  // ============ ERROR HANDLING METHODS ============

  /// Check biometric availability with error handling
  static Future<bool> isBiometricAvailableSafe() async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          final isAvailable = await _localAuth.canCheckBiometrics;
          final isDeviceSupported = await _localAuth.isDeviceSupported();
          
          if (!isDeviceSupported) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.deviceCompatibility,
                severity: ErrorSeverity.low,
                recoverable: false,
                retryable: false,
                originalError: 'Device not supported',
              ),
              'Your device does not support biometric authentication',
              'isBiometricAvailable',
            );
          }

          if (!isAvailable) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Biometric not available',
              ),
              'Biometric authentication is not available on this device',
              'isBiometricAvailable',
            );
          }

          return isAvailable && isDeviceSupported;
        } catch (e) {
          if (e is PlatformException) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: true,
                originalError: e,
              ),
              'Failed to check biometric availability: ${e.message}',
              'isBiometricAvailable',
            );
          }
          rethrow;
        }
      },
      'isBiometricAvailable',
      retryable: true,
      customErrorMessage: 'Failed to check biometric availability',
    );
  }

  /// Get available biometric types with error handling
  static Future<List<BiometricType>> getAvailableBiometricsSafe() async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          final biometrics = await _localAuth.getAvailableBiometrics();
          
          if (biometrics.isEmpty) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'No biometrics available',
              ),
              'No biometric authentication methods are available',
              'getAvailableBiometrics',
            );
          }

          return biometrics;
        } catch (e) {
          if (e is PlatformException) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: true,
                originalError: e,
              ),
              'Failed to get available biometrics: ${e.message}',
              'getAvailableBiometrics',
            );
          }
          rethrow;
        }
      },
      'getAvailableBiometrics',
      retryable: true,
      customErrorMessage: 'Failed to get available biometric types',
    );
  }

  /// Authenticate with comprehensive error handling
  static Future<bool> authenticateSafe({required String reason}) async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          // Validate reason
          if (reason.isEmpty) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.authentication,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Empty reason',
              ),
              'Authentication reason cannot be empty',
              'authenticate',
            );
          }

          // Check availability first
          final isAvailable = await isBiometricAvailableSafe();
          if (!isAvailable) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: false,
                originalError: 'Biometric not available',
              ),
              'Biometric authentication is not available',
              'authenticate',
            );
          }

          // Perform authentication
          final result = await _localAuth.authenticate(
            localizedReason: reason,
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );

          if (!result) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.authentication,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: true,
                originalError: 'Authentication failed',
              ),
              'Biometric authentication failed. Please try again.',
              'authenticate',
            );
          }

          return result;
        } catch (e) {
          if (e is PlatformException) {
            String errorMessage;
            ErrorType errorType;
            bool retryable = true;

            switch (e.code) {
              case 'NotAvailable':
                errorMessage = 'Biometric authentication is not available on this device';
                errorType = ErrorType.deviceCompatibility;
                retryable = false;
                break;
              case 'NotEnrolled':
                errorMessage = 'No biometric data is enrolled. Please set up biometric authentication in your device settings.';
                errorType = ErrorType.biometric;
                retryable = false;
                break;
              case 'LockedOut':
                errorMessage = 'Biometric authentication is temporarily locked. Please try again later.';
                errorType = ErrorType.rateLimit;
                retryable = true;
                break;
              case 'PermanentlyLockedOut':
                errorMessage = 'Biometric authentication is permanently locked. Please use an alternative authentication method.';
                errorType = ErrorType.biometric;
                retryable = false;
                break;
              case 'UserCancel':
                errorMessage = 'Authentication was cancelled by user';
                errorType = ErrorType.authentication;
                retryable = true;
                break;
              case 'AuthenticationFailed':
                errorMessage = 'Biometric authentication failed. Please try again.';
                errorType = ErrorType.authentication;
                retryable = true;
                break;
              case 'SystemCancel':
                errorMessage = 'Authentication was cancelled by the system';
                errorType = ErrorType.authentication;
                retryable = true;
                break;
              case 'PasscodeNotSet':
                errorMessage = 'No passcode is set on this device. Please set up a passcode first.';
                errorType = ErrorType.deviceCompatibility;
                retryable = false;
                break;
              case 'FingerprintNotAvailable':
                errorMessage = 'Fingerprint authentication is not available on this device';
                errorType = ErrorType.deviceCompatibility;
                retryable = false;
                break;
              case 'FaceIDNotAvailable':
                errorMessage = 'Face ID authentication is not available on this device';
                errorType = ErrorType.deviceCompatibility;
                retryable = false;
                break;
              case 'TouchIDNotAvailable':
                errorMessage = 'Touch ID authentication is not available on this device';
                errorType = ErrorType.deviceCompatibility;
                retryable = false;
                break;
              default:
                errorMessage = 'Biometric authentication failed: ${e.message}';
                errorType = ErrorType.biometric;
                retryable = true;
            }

            throw TwoFAException(
              ErrorInfo(
                type: errorType,
                severity: ErrorSeverity.medium,
                recoverable: true,
                retryable: retryable,
                originalError: e,
              ),
              errorMessage,
              'authenticate',
            );
          }
          rethrow;
        }
      },
      'authenticate',
      retryable: true,
      customErrorMessage: 'Biometric authentication failed',
    );
  }

  /// Check if biometric is locked out with error handling
  static Future<bool> isBiometricLockedOutSafe() async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          final biometrics = await _localAuth.getAvailableBiometrics();
          return biometrics.isEmpty;
        } catch (e) {
          if (e is PlatformException && e.code == 'LockedOut') {
            return true;
          }
          return false;
        }
      },
      'isBiometricLockedOut',
      retryable: false,
      customErrorMessage: 'Failed to check biometric lockout status',
    );
  }

  /// Get biometric authentication status with error handling
  static Future<Map<String, dynamic>> getBiometricStatusSafe() async {
    return await _errorHandler.handle2FAError(
      () async {
        try {
          final isAvailable = await isBiometricAvailableSafe();
          final biometrics = await getAvailableBiometricsSafe();
          final isLockedOut = await isBiometricLockedOutSafe();

          return {
            'isAvailable': isAvailable,
            'availableBiometrics': biometrics.map((e) => e.toString()).toList(),
            'isLockedOut': isLockedOut,
            'canCheckBiometrics': await _localAuth.canCheckBiometrics,
            'isDeviceSupported': await _localAuth.isDeviceSupported(),
          };
        } catch (e) {
          throw TwoFAException(
            ErrorInfo(
              type: ErrorType.biometric,
              severity: ErrorSeverity.medium,
              recoverable: true,
              retryable: true,
              originalError: e,
            ),
            'Failed to get biometric status',
            'getBiometricStatus',
          );
        }
      },
      'getBiometricStatus',
      retryable: true,
      customErrorMessage: 'Failed to get biometric authentication status',
    );
  }

  /// Stop authentication with error handling
  static Future<void> stopAuthenticationSafe() async {
    await _errorHandler.handle2FAError(
      () async {
        try {
          await _localAuth.stopAuthentication();
        } catch (e) {
          if (e is PlatformException) {
            throw TwoFAException(
              ErrorInfo(
                type: ErrorType.biometric,
                severity: ErrorSeverity.low,
                recoverable: true,
                retryable: false,
                originalError: e,
              ),
              'Failed to stop biometric authentication: ${e.message}',
              'stopAuthentication',
            );
          }
          rethrow;
        }
      },
      'stopAuthentication',
      retryable: false,
      customErrorMessage: 'Failed to stop biometric authentication',
    );
  }

  /// Get error statistics
  static Map<String, dynamic> getErrorStatistics() {
    return _errorHandler.getErrorStatistics();
  }

  /// Clear error history
  static void clearErrorHistory() {
    _errorHandler.clearErrorHistory();
  }

  /// Dispose resources
  static void dispose() {
    _errorHandler.dispose();
  }
}
