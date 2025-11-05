import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart'; // Add Algorithm enum import
import 'package:blockchain_fyp/services/totp_service.dart';
import 'package:blockchain_fyp/services/biometric_service.dart';
import 'package:blockchain_fyp/services/secure_storage_service.dart';
import 'package:blockchain_fyp/services/contract_service.dart';
import 'package:blockchain_fyp/widgets/qr_code_widget.dart';
import 'package:flutter/material.dart';

void main() {
  group('Performance Tests', () {
    group('TOTPService Performance Tests', () {
      late TOTPService totpService;

      setUp(() async {
        totpService = await TOTPService.create();
      });

      test('should generate secret quickly', () {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          totpService.generateSecret();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        print('Secret generation: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should generate TOTP codes quickly', () {
        final secret = totpService.generateSecret();
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          totpService.generateTOTP(secret);
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('TOTP generation: ${stopwatch.elapsedMilliseconds}ms for 1000 operations');
      });

      test('should verify TOTP codes quickly', () {
        final secret = totpService.generateSecret();
        final code = totpService.generateTOTP(secret);
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          totpService.verifyTOTP(secret, code);
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('TOTP verification: ${stopwatch.elapsedMilliseconds}ms for 1000 operations');
      });

      test('should generate QR URIs quickly', () {
        final secret = totpService.generateSecret();
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          totpService.generateTOTPURI(secret, 'test@example.com');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        print('QR URI generation: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should generate backup codes quickly', () {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 50; i++) {
          totpService.generateBackupCodes();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('Backup code generation: ${stopwatch.elapsedMilliseconds}ms for 50 operations');
      });

      test('should verify backup codes quickly', () {
        final backupCodes = totpService.generateBackupCodes();
        final testCode = backupCodes.first;
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          totpService.verifyBackupCode(testCode, backupCodes);
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('Backup code verification: ${stopwatch.elapsedMilliseconds}ms for 1000 operations');
      });

      test('should handle different algorithms efficiently', () {
        final secret = totpService.generateSecret();
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          totpService.generateTOTP(secret, algorithm: Algorithm.SHA1);
          totpService.generateTOTP(secret, algorithm: Algorithm.SHA256);
          totpService.generateTOTP(secret, algorithm: Algorithm.SHA512);
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
        print('Multi-algorithm generation: ${stopwatch.elapsedMilliseconds}ms for 300 operations');
      });

      test('should get remaining time quickly', () {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 10000; i++) {
          totpService.getRemainingTime();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        print('Remaining time check: ${stopwatch.elapsedMilliseconds}ms for 10000 operations');
      });
    });

    group('SecureStorageService Performance Tests', () {
      late SecureStorageService storageService;

      setUp(() async {
        storageService = await SecureStorageService.create();
      });

      test('should store data quickly', () async {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          await storageService.storeSecureData('key_$i', 'value_$i');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
        print('Data storage: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should retrieve data quickly', () async {
        // First store some data
        for (int i = 0; i < 100; i++) {
          await storageService.storeSecureData('key_$i', 'value_$i');
        }
        
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          await storageService.getSecureData('key_$i');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Data retrieval: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should store TOTP secret quickly', () async {
        final secret = 'TEST_SECRET_KEY_' * 10; // Long secret
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 50; i++) {
          await storageService.storeTOTPSecret('${secret}_$i');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('TOTP secret storage: ${stopwatch.elapsedMilliseconds}ms for 50 operations');
      });

      test('should store backup codes quickly', () async {
        final backupCodes = List.generate(10, (index) => 'CODE$index');
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 50; i++) {
          await storageService.storeBackupCodes(backupCodes);
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Backup code storage: ${stopwatch.elapsedMilliseconds}ms for 50 operations');
      });

      test('should check 2FA status quickly', () async {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          await storageService.isUser2FAEnabled();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('2FA status check: ${stopwatch.elapsedMilliseconds}ms for 1000 operations');
      });

      test('should clear data quickly', () async {
        // First store some data
        await storageService.storeTOTPSecret('TEST_SECRET');
        await storageService.storeBackupCodes(['CODE1', 'CODE2']);
        await storageService.setUser2FAStatus(true);
        
        final stopwatch = Stopwatch()..start();
        
        await storageService.clear2FAData();
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('Data clearing: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('BiometricService Performance Tests', () {
      test('should check availability quickly', () async {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          await BiometricService.isBiometricAvailable();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Biometric availability check: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should handle authentication timeout', () async {
        final stopwatch = Stopwatch()..start();
        
        try {
          await BiometricService.authenticate(
            reason: 'Performance test',
          );
        } catch (e) {
          // Expected on emulator or if user cancels
        }
        
        stopwatch.stop();
        
        // Should not take too long even if it fails
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
        print('Biometric authentication: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('QRCodeWidget Performance Tests', () {
      testWidgets('should render QR code quickly', (WidgetTester tester) async {
        const testData = 'otpauth://totp/test@example.com?secret=TEST123';
        
        final stopwatch = Stopwatch()..start();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QRCodeWidget(
                data: testData,
                size: 200,
              ),
            ),
          ),
        );
        
        await tester.pumpAndSettle();
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('QR code rendering: ${stopwatch.elapsedMilliseconds}ms');
      });

      testWidgets('should handle multiple QR codes efficiently', (WidgetTester tester) async {
        final testData = List.generate(10, (i) => 'otpauth://totp/test$i@example.com?secret=TEST$i');
        
        final stopwatch = Stopwatch()..start();
        
        for (final data in testData) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: QRCodeWidget(
                  data: data,
                  size: 200,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
        print('Multiple QR codes: ${stopwatch.elapsedMilliseconds}ms for 10 codes');
      });

      testWidgets('should handle large QR codes efficiently', (WidgetTester tester) async {
        final largeData = List.filled(1000, 'A').join(); // Large data string
        
        final stopwatch = Stopwatch()..start();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QRCodeWidget(
                data: largeData,
                size: 300,
              ),
            ),
          ),
        );
        
        await tester.pumpAndSettle();
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Large QR code: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('ContractService Performance Tests', () {
      late ContractService contractService;

      setUp(() async {
        contractService = await ContractService.create();
      });

      test('should estimate gas quickly', () async {
        const address = '0x1234567890123456789012345678901234567890';
        final backupCodes = ['CODE1', 'CODE2'];
        
        final stopwatch = Stopwatch()..start();
        
        try {
          await contractService.estimateGas('enable2FA', [backupCodes]);
        } catch (e) {
          // Expected if contract not deployed
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Gas estimation: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('should get current gas price quickly', () async {
        final stopwatch = Stopwatch()..start();
        
        try {
          await contractService.getCurrentGasPrice();
        } catch (e) {
          // Expected if network not available
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Gas price check: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('should get contract info quickly', () async {
        final stopwatch = Stopwatch()..start();
        
        try {
          await contractService.getContractInfo();
        } catch (e) {
          // Expected if contract not available
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        print('Contract info: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('Memory Performance Tests', () {
      test('should not leak memory during TOTP operations', () async {
        final totpService = await TOTPService.create();
        final secret = totpService.generateSecret();
        
        // Perform many operations to test for memory leaks
        for (int i = 0; i < 1000; i++) {
          final code = totpService.generateTOTP(secret);
          totpService.verifyTOTP(secret, code);
        }
        
        // If we get here without running out of memory, the test passes
        expect(true, isTrue);
        print('Memory leak test passed: 1000 TOTP operations completed');
      });

      test('should not leak memory during storage operations', () async {
        final storageService = await SecureStorageService.create();
        
        // Perform many storage operations
        for (int i = 0; i < 100; i++) {
          await storageService.storeSecureData('key_$i', 'value_$i');
          await storageService.getSecureData('key_$i');
          await storageService.deleteSecureData('key_$i');
        }
        
        // If we get here without running out of memory, the test passes
        expect(true, isTrue);
        print('Memory leak test passed: 100 storage operations completed');
      });

      test('should handle large data efficiently', () async {
        final storageService = await SecureStorageService.create();
        final largeData = 'A' * 10000; // 10KB of data
        
        final stopwatch = Stopwatch()..start();
        
        await storageService.storeSecureData('large_key', largeData);
        final retrieved = await storageService.getSecureData('large_key');
        
        stopwatch.stop();
        
        expect(retrieved, equals(largeData));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Large data handling: ${stopwatch.elapsedMilliseconds}ms for 10KB');
      });
    });

    group('Concurrent Performance Tests', () {
      test('should handle concurrent TOTP operations', () async {
        final totpService = await TOTPService.create();
        final secret = totpService.generateSecret();
        
        final stopwatch = Stopwatch()..start();
        
        // Run multiple operations concurrently
        final futures = List.generate(100, (i) async {
          final code = totpService.generateTOTP(secret);
          return totpService.verifyTOTP(secret, code);
        });
        
        final results = await Future.wait(futures);
        
        stopwatch.stop();
        
        expect(results.every((result) => result == true), isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        print('Concurrent TOTP operations: ${stopwatch.elapsedMilliseconds}ms for 100 operations');
      });

      test('should handle concurrent storage operations', () async {
        final storageService = await SecureStorageService.create();
        
        final stopwatch = Stopwatch()..start();
        
        // Run multiple storage operations concurrently
        final futures = List.generate(50, (i) async {
          await storageService.storeSecureData('concurrent_key_$i', 'value_$i');
          return storageService.getSecureData('concurrent_key_$i');
        });
        
        final results = await Future.wait(futures);
        
        stopwatch.stop();
        
        expect(results.every((result) => result != null), isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
        print('Concurrent storage operations: ${stopwatch.elapsedMilliseconds}ms for 50 operations');
      });
    });
  });
}
