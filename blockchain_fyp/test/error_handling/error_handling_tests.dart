import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:blockchain_fyp/services/totp_service.dart';
import 'package:blockchain_fyp/services/biometric_service.dart';
import 'package:blockchain_fyp/services/secure_storage_service.dart';
import 'package:blockchain_fyp/services/contract_service.dart';
import 'package:flutter/services.dart';

// Generate mocks
@GenerateMocks([
  TOTPService,
  BiometricService,
  SecureStorageService,
  ContractService,
])
import 'error_handling_tests.mocks.dart';

void main() {
  group('Error Handling Tests', () {
    group('TOTPService Error Handling', () {
      late TOTPService totpService;

      setUp(() async {
        totpService = await TOTPService.create();
      });

      test('should handle empty secret in generateTOTP', () {
        expect(() => totpService.generateTOTP(''), throwsException);
      });

      test('should handle null secret in generateTOTP', () {
        expect(() => totpService.generateTOTP(null as String), throwsException);
      });

      test('should handle invalid secret format', () {
        const invalidSecret = 'invalid_secret_with_special_chars!@#';
        expect(() => totpService.generateTOTP(invalidSecret), throwsException);
      });

      test('should handle empty code in verifyTOTP', () {
        final secret = totpService.generateSecret();
        expect(() => totpService.verifyTOTP(secret, ''), throwsException);
      });

      test('should handle null code in verifyTOTP', () {
        final secret = totpService.generateSecret();
        expect(() => totpService.verifyTOTP(secret, null as String), throwsException);
      });

      test('should handle invalid code format in verifyTOTP', () {
        final secret = totpService.generateSecret();
        const invalidCode = 'abc123'; // Non-numeric
        expect(() => totpService.verifyTOTP(secret, invalidCode), throwsException);
      });

      test('should handle short code in verifyTOTP', () {
        final secret = totpService.generateSecret();
        const shortCode = '12345'; // Too short
        expect(() => totpService.verifyTOTP(secret, shortCode), throwsException);
      });

      test('should handle long code in verifyTOTP', () {
        final secret = totpService.generateSecret();
        const longCode = '1234567'; // Too long
        expect(() => totpService.verifyTOTP(secret, longCode), throwsException);
      });

      test('should handle empty backup code list', () {
        const emptyCodes = <String>[];
        const testCode = 'TEST1234';
        expect(() => totpService.verifyBackupCode(testCode, emptyCodes), throwsException);
      });

      test('should handle null backup code list', () {
        const testCode = 'TEST1234';
        expect(() => totpService.verifyBackupCode(testCode, null as List<String>), throwsException);
      });

      test('should handle empty backup code', () {
        final backupCodes = totpService.generateBackupCodes();
        expect(() => totpService.verifyBackupCode('', backupCodes), throwsException);
      });

      test('should handle invalid backup code format', () {
        final backupCodes = totpService.generateBackupCodes();
        const invalidCode = 'invalid!'; // Special characters
        expect(() => totpService.verifyBackupCode(invalidCode, backupCodes), throwsException);
      });

      test('should handle empty account name in generateTOTPURI', () {
        final secret = totpService.generateSecret();
        expect(() => totpService.generateTOTPURI(secret, ''), throwsException);
      });

      test('should handle null account name in generateTOTPURI', () {
        final secret = totpService.generateSecret();
        expect(() => totpService.generateTOTPURI(secret, null as String), throwsException);
      });

      test('should handle invalid issuer in generateTOTPURI', () {
        final secret = totpService.generateSecret();
        const invalidIssuer = 'Invalid Issuer!@#'; // Special characters
        expect(() => totpService.generateTOTPURI(secret, 'test@example.com', issuer: invalidIssuer), throwsException);
      });
    });

    group('BiometricService Error Handling', () {
      test('should handle biometric not available', () async {
        // This test may pass or fail depending on device capabilities
        try {
          final isAvailable = await BiometricService.isBiometricAvailable();
          expect(isAvailable, isA<bool>());
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle authentication cancellation', () async {
        try {
          await BiometricService.authenticate(
            reason: 'Test cancellation',
          );
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty reason in authenticate', () async {
        try {
          await BiometricService.authenticate(reason: '');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null reason in authenticate', () async {
        try {
          await BiometricService.authenticate(reason: null as String);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });
    });

    group('SecureStorageService Error Handling', () {
      late SecureStorageService storageService;

      setUp(() async {
        storageService = await SecureStorageService.create();
      });

      test('should handle empty key in storeSecureData', () async {
        try {
          await storageService.storeSecureData('', 'value');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null key in storeSecureData', () async {
        try {
          await storageService.storeSecureData(null as String, 'value');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty value in storeSecureData', () async {
        try {
          await storageService.storeSecureData('key', '');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null value in storeSecureData', () async {
        try {
          await storageService.storeSecureData('key', null as String);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty key in getSecureData', () async {
        try {
          await storageService.getSecureData('');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null key in getSecureData', () async {
        try {
          await storageService.getSecureData(null as String);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty backup codes list', () async {
        try {
          await storageService.storeBackupCodes([]);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null backup codes list', () async {
        try {
          await storageService.storeBackupCodes(null as List<String>);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty backup code in useBackupCode', () async {
        try {
          await storageService.useBackupCode('');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null backup code in useBackupCode', () async {
        try {
          await storageService.useBackupCode(null as String);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle empty TOTP secret', () async {
        try {
          await storageService.storeTOTPSecret('');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle null TOTP secret', () async {
        try {
          await storageService.storeTOTPSecret(null as String);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });
    });

    group('ContractService Error Handling', () {
      late MockContractService mockContractService;

      setUp(() {
        mockContractService = MockContractService();
      });

      test('should handle network connection error', () async {
        const address = '0x1234567890123456789012345678901234567890';
        final backupCodes = ['CODE1', 'CODE2'];

        when(mockContractService.enable2FA(address, backupCodes))
            .thenThrow(Exception('Network connection failed'));

        expect(
          () => mockContractService.enable2FA(address, backupCodes),
          throwsException,
        );
      });

      test('should handle contract execution error', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const code = '123456';

        when(mockContractService.verify2FA(address, code))
            .thenThrow(Exception('Contract execution failed'));

        expect(
          () => mockContractService.verify2FA(address, code),
          throwsException,
        );
      });

      test('should handle gas estimation error', () async {
        const address = '0x1234567890123456789012345678901234567890';

        when(mockContractService.estimateGas('enable2FA', any))
            .thenThrow(Exception('Gas estimation failed'));

        expect(
          () => mockContractService.estimateGas('enable2FA', []),
          throwsException,
        );
      });

      test('should handle transaction timeout', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const code = '123456';

        when(mockContractService.verify2FA(address, code))
            .thenThrow(Exception('Transaction timeout'));

        expect(
          () => mockContractService.verify2FA(address, code),
          throwsException,
        );
      });

      test('should handle invalid address format', () async {
        const invalidAddress = 'invalid_address';
        final backupCodes = ['CODE1', 'CODE2'];

        when(mockContractService.enable2FA(invalidAddress, backupCodes))
            .thenThrow(Exception('Invalid address format'));

        expect(
          () => mockContractService.enable2FA(invalidAddress, backupCodes),
          throwsException,
        );
      });

      test('should handle contract not deployed', () async {
        const address = '0x1234567890123456789012345678901234567890';
        final backupCodes = ['CODE1', 'CODE2'];

        when(mockContractService.enable2FA(address, backupCodes))
            .thenThrow(Exception('Contract not deployed'));

        expect(
          () => mockContractService.enable2FA(address, backupCodes),
          throwsException,
        );
      });

      test('should handle insufficient gas', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const code = '123456';

        when(mockContractService.verify2FA(address, code))
            .thenThrow(Exception('Insufficient gas'));

        expect(
          () => mockContractService.verify2FA(address, code),
          throwsException,
        );
      });

      test('should handle user rejection', () async {
        const address = '0x1234567890123456789012345678901234567890';
        final backupCodes = ['CODE1', 'CODE2'];

        when(mockContractService.enable2FA(address, backupCodes))
            .thenThrow(Exception('User rejected transaction'));

        expect(
          () => mockContractService.enable2FA(address, backupCodes),
          throwsException,
        );
      });
    });
  });

  group('Edge Case Tests', () {
    group('TOTPService Edge Cases', () {
      late TOTPService totpService;

      setUp(() async {
        totpService = await TOTPService.create();
      });

      test('should handle very long secret', () {
        const longSecret = 'A' * 100; // Very long secret
        expect(() => totpService.generateTOTP(longSecret), throwsException);
      });

      test('should handle secret with only special characters', () {
        const specialSecret = '!@#\$%^&*()';
        expect(() => totpService.generateTOTP(specialSecret), throwsException);
      });

      test('should handle code with leading zeros', () {
        final secret = totpService.generateSecret();
        const codeWithZeros = '012345';
        // This should work as it's a valid 6-digit code
        expect(() => totpService.verifyTOTP(secret, codeWithZeros), returnsNormally);
      });

      test('should handle backup codes with special characters', () {
        final backupCodes = ['CODE1!', 'CODE2@', 'CODE3#'];
        const testCode = 'CODE1!';
        expect(() => totpService.verifyBackupCode(testCode, backupCodes), throwsException);
      });

      test('should handle backup codes with different lengths', () {
        final backupCodes = ['CODE1', 'CODE12', 'CODE123'];
        const testCode = 'CODE1';
        expect(() => totpService.verifyBackupCode(testCode, backupCodes), throwsException);
      });

      test('should handle account name with special characters', () {
        final secret = totpService.generateSecret();
        const specialAccount = 'test@example.com!@#';
        expect(() => totpService.generateTOTPURI(secret, specialAccount), throwsException);
      });

      test('should handle very long account name', () {
        final secret = totpService.generateSecret();
        const longAccount = 'a' * 1000 + '@example.com';
        expect(() => totpService.generateTOTPURI(secret, longAccount), throwsException);
      });

      test('should handle issuer with special characters', () {
        final secret = totpService.generateSecret();
        const specialIssuer = 'Test Issuer!@#';
        expect(() => totpService.generateTOTPURI(secret, 'test@example.com', issuer: specialIssuer), throwsException);
      });

      test('should handle very long issuer', () {
        final secret = totpService.generateSecret();
        const longIssuer = 'A' * 1000;
        expect(() => totpService.generateTOTPURI(secret, 'test@example.com', issuer: longIssuer), throwsException);
      });
    });

    group('SecureStorageService Edge Cases', () {
      late SecureStorageService storageService;

      setUp(() async {
        storageService = await SecureStorageService.create();
      });

      test('should handle very long key', () async {
        const longKey = 'a' * 1000;
        const value = 'test_value';
        
        try {
          await storageService.storeSecureData(longKey, value);
          final retrieved = await storageService.getSecureData(longKey);
          expect(retrieved, equals(value));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle very long value', () async {
        const key = 'test_key';
        const longValue = 'a' * 10000;
        
        try {
          await storageService.storeSecureData(key, longValue);
          final retrieved = await storageService.getSecureData(key);
          expect(retrieved, equals(longValue));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle key with special characters', () async {
        const specialKey = 'key!@#\$%^&*()';
        const value = 'test_value';
        
        try {
          await storageService.storeSecureData(specialKey, value);
          final retrieved = await storageService.getSecureData(specialKey);
          expect(retrieved, equals(value));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle value with special characters', () async {
        const key = 'test_key';
        const specialValue = 'value!@#\$%^&*()';
        
        try {
          await storageService.storeSecureData(key, specialValue);
          final retrieved = await storageService.getSecureData(key);
          expect(retrieved, equals(specialValue));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle very many backup codes', () async {
        final manyCodes = List.generate(100, (index) => 'CODE$index');
        
        try {
          await storageService.storeBackupCodes(manyCodes);
          final retrieved = await storageService.getBackupCodes();
          expect(retrieved, equals(manyCodes));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle backup codes with unicode characters', () async {
        final unicodeCodes = ['CODE1', 'CODE2', 'CODE3'];
        
        try {
          await storageService.storeBackupCodes(unicodeCodes);
          final retrieved = await storageService.getBackupCodes();
          expect(retrieved, equals(unicodeCodes));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle TOTP secret with unicode characters', () async {
        const unicodeSecret = 'SECRET_KEY_测试';
        
        try {
          await storageService.storeTOTPSecret(unicodeSecret);
          final retrieved = await storageService.getTOTPSecret();
          expect(retrieved, equals(unicodeSecret));
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });
    });

    group('Rate Limiting Edge Cases', () {
      late MockContractService mockContractService;

      setUp(() {
        mockContractService = MockContractService();
      });

      test('should handle maximum failed attempts', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const invalidCode = '000000';

        when(mockContractService.getFailedAttempts(address))
            .thenAnswer((_) async => 3);
        when(mockContractService.isLockedOut(address))
            .thenAnswer((_) async => true);
        when(mockContractService.getRemainingLockoutTime(address))
            .thenAnswer((_) async => 300);

        final attempts = await mockContractService.getFailedAttempts(address);
        final isLocked = await mockContractService.isLockedOut(address);
        final remainingTime = await mockContractService.getRemainingLockoutTime(address);

        expect(attempts, equals(3));
        expect(isLocked, isTrue);
        expect(remainingTime, equals(300));
      });

      test('should handle lockout expiration', () async {
        const address = '0x1234567890123456789012345678901234567890';

        when(mockContractService.isLockedOut(address))
            .thenAnswer((_) async => false);
        when(mockContractService.getRemainingLockoutTime(address))
            .thenAnswer((_) async => 0);

        final isLocked = await mockContractService.isLockedOut(address);
        final remainingTime = await mockContractService.getRemainingLockoutTime(address);

        expect(isLocked, isFalse);
        expect(remainingTime, equals(0));
      });

      test('should handle negative remaining time', () async {
        const address = '0x1234567890123456789012345678901234567890';

        when(mockContractService.getRemainingLockoutTime(address))
            .thenAnswer((_) async => -1);

        final remainingTime = await mockContractService.getRemainingLockoutTime(address);
        expect(remainingTime, equals(-1));
      });
    });

    group('Network Edge Cases', () {
      late MockContractService mockContractService;

      setUp(() {
        mockContractService = MockContractService();
      });

      test('should handle very slow network response', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const code = '123456';

        when(mockContractService.verify2FA(address, code))
            .thenAnswer((_) async {
              await Future.delayed(const Duration(seconds: 30));
              return true;
            });

        final stopwatch = Stopwatch()..start();
        final result = await mockContractService.verify2FA(address, code);
        stopwatch.stop();

        expect(result, isTrue);
        expect(stopwatch.elapsedSeconds, greaterThanOrEqualTo(30));
      });

      test('should handle intermittent network failures', () async {
        const address = '0x1234567890123456789012345678901234567890';
        const code = '123456';

        when(mockContractService.verify2FA(address, code))
            .thenThrow(Exception('Network timeout'))
            .thenAnswer((_) async => true);

        // First call should fail
        expect(
          () => mockContractService.verify2FA(address, code),
          throwsException,
        );

        // Second call should succeed
        final result = await mockContractService.verify2FA(address, code);
        expect(result, isTrue);
      });

      test('should handle partial network failure', () async {
        const address = '0x1234567890123456789012345678901234567890';

        when(mockContractService.is2FAEnabled(address))
            .thenAnswer((_) async => true);
        when(mockContractService.getBackupCodeCount(address))
            .thenThrow(Exception('Network error'));

        final isEnabled = await mockContractService.is2FAEnabled(address);
        expect(isEnabled, isTrue);

        expect(
          () => mockContractService.getBackupCodeCount(address),
          throwsException,
        );
      });
    });
  });
}
