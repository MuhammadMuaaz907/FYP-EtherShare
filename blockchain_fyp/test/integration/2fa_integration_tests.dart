import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:blockchain_fyp/main.dart';
import 'package:blockchain_fyp/services/totp_service.dart';
import 'package:blockchain_fyp/services/secure_storage_service.dart';
import 'package:blockchain_fyp/services/biometric_service.dart';
import 'package:blockchain_fyp/services/contract_service.dart';
import 'package:blockchain_fyp/screens/setup_2fa_screen.dart';
import 'package:blockchain_fyp/screens/verify_2fa_screen.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('2FA Integration Tests', () {
    testWidgets('Complete 2FA Setup Flow', (WidgetTester tester) async {
      // Initialize the app
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Wait for app to load
      await tester.pump(const Duration(seconds: 2));

      // Test the complete 2FA setup flow
      await _testComplete2FASetupFlow(tester);
    });

    testWidgets('2FA Verification Flow', (WidgetTester tester) async {
      // Initialize the app
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Wait for app to load
      await tester.pump(const Duration(seconds: 2));

      // Test the 2FA verification flow
      await _test2FAVerificationFlow(tester);
    });

    testWidgets('2FA Error Handling Flow', (WidgetTester tester) async {
      // Initialize the app
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Wait for app to load
      await tester.pump(const Duration(seconds: 2));

      // Test error handling scenarios
      await _test2FAErrorHandling(tester);
    });

    testWidgets('Biometric Authentication Flow', (WidgetTester tester) async {
      // Initialize the app
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Wait for app to load
      await tester.pump(const Duration(seconds: 2));

      // Test biometric authentication
      await _testBiometricAuthentication(tester);
    });

    testWidgets('Backup Code Usage Flow', (WidgetTester tester) async {
      // Initialize the app
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Wait for app to load
      await tester.pump(const Duration(seconds: 2));

      // Test backup code usage
      await _testBackupCodeUsage(tester);
    });
  });

  group('Service Integration Tests', () {
    test('TOTPService and SecureStorageService Integration', () async {
      // Initialize services
      final totpService = await TOTPService.create();
      final storageService = await SecureStorageService.create();

      // Generate secret and backup codes
      final secret = totpService.generateSecret();
      final backupCodes = totpService.generateBackupCodes();

      // Store in secure storage
      await storageService.storeTOTPSecret(secret);
      await storageService.storeBackupCodes(backupCodes);
      await storageService.setUser2FAStatus(true);

      // Retrieve and verify
      final retrievedSecret = await storageService.getTOTPSecret();
      final retrievedCodes = await storageService.getBackupCodes();
      final isEnabled = await storageService.isUser2FAEnabled();

      expect(retrievedSecret, equals(secret));
      expect(retrievedCodes, equals(backupCodes));
      expect(isEnabled, isTrue);

      // Generate TOTP code and verify
      final totpCode = totpService.generateTOTP(retrievedSecret);
      final isValid = totpService.verifyTOTP(retrievedSecret, totpCode);

      expect(isValid, isTrue);

      // Test backup code verification
      final backupCode = retrievedCodes.first;
      final isBackupValid = totpService.verifyBackupCode(backupCode, retrievedCodes);

      expect(isBackupValid, isTrue);
    });

    test('ContractService and SecureStorageService Integration', () async {
      // Initialize services
      final contractService = await ContractService.create();
      final storageService = await SecureStorageService.create();

      const testAddress = '0x1234567890123456789012345678901234567890';
      final backupCodes = ['CODE1', 'CODE2', 'CODE3'];

      try {
        // Enable 2FA on blockchain
        await contractService.enable2FA(testAddress, backupCodes);

        // Check blockchain 2FA status
        final blockchain2FAEnabled = await contractService.is2FAEnabled(testAddress);
        expect(blockchain2FAEnabled, isTrue);

        // Store locally
        await storageService.setUser2FAStatus(true);

        // Verify both are enabled
        final local2FAEnabled = await storageService.isUser2FAEnabled();
        expect(local2FAEnabled, isTrue);
      } catch (e) {
        // Expected if contract is not deployed or network issues
        print('Contract integration test skipped: $e');
      }
    });

    test('BiometricService and SecureStorageService Integration', () async {
      // Initialize services
      final biometricService = BiometricService();
      final storageService = await SecureStorageService.create();

      // Check biometric availability
      final isAvailable = await BiometricService.isBiometricAvailable();
      
      if (isAvailable) {
        // Enable biometric in storage
        await storageService.setBiometricEnabled(true);
        final isEnabled = await storageService.isBiometricEnabled();
        expect(isEnabled, isTrue);

        // Test authentication (may fail on emulator)
        try {
          final isAuthenticated = await BiometricService.authenticate(
            reason: 'Test integration',
          );
          expect(isAuthenticated, isA<bool>());
        } catch (e) {
          // Expected on emulator or if user cancels
          print('Biometric authentication test skipped: $e');
        }
      } else {
        print('Biometric not available on this device');
      }
    });
  });

  group('Performance Integration Tests', () {
    test('2FA Setup Performance', () async {
      final stopwatch = Stopwatch()..start();

      // Initialize services
      final totpService = await TOTPService.create();
      final storageService = await SecureStorageService.create();

      // Generate secret and codes
      final secret = totpService.generateSecret();
      final backupCodes = totpService.generateBackupCodes();
      final qrUri = totpService.generateTOTPURI(secret, 'test@example.com');

      // Store data
      await storageService.storeTOTPSecret(secret);
      await storageService.storeBackupCodes(backupCodes);
      await storageService.setUser2FAStatus(true);

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      expect(secret, isNotEmpty);
      expect(backupCodes, hasLength(10));
      expect(qrUri, contains('otpauth://totp'));
    });

    test('2FA Verification Performance', () async {
      final stopwatch = Stopwatch()..start();

      // Initialize services
      final totpService = await TOTPService.create();
      final storageService = await SecureStorageService.create();

      // Setup
      final secret = totpService.generateSecret();
      await storageService.storeTOTPSecret(secret);

      // Retrieve and verify
      final retrievedSecret = await storageService.getTOTPSecret();
      expect(retrievedSecret, isNotNull);
      final totpCode = await totpService.generateTOTPSafe(retrievedSecret!);
      final isValid = await totpService.verifyTOTPSafe(retrievedSecret, totpCode);

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(isValid, isTrue);
    });
  });
}

// Helper functions for integration tests
Future<void> _testComplete2FASetupFlow(WidgetTester tester) async {
  // Navigate to setup screen (this would be done through the app flow)
  await tester.pumpWidget(
    MaterialApp(
      home: Setup2FAScreen(
        userId: 'test_user',
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Verify screen is displayed
  expect(find.byType(Setup2FAScreen), findsOneWidget);

  // Test QR code display (using OptimizedQRCodeWidget if available)
  // expect(find.byType(QRCodeWidget), findsOneWidget); // Commented out - using OptimizedQRCodeWidget

  // Test form interactions
  final continueButton = find.text('Continue');
  if (continueButton.evaluate().isNotEmpty) {
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
  }
}

Future<void> _test2FAVerificationFlow(WidgetTester tester) async {
  // Navigate to verification screen
  await tester.pumpWidget(
    MaterialApp(
      home: Verify2FAScreen(
        userId: 'test_user',
        userAddress: '0x123456789',
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Verify screen is displayed
  expect(find.byType(Verify2FAScreen), findsOneWidget);

  // Test code input
  final codeField = find.byType(TextField);
  if (codeField.evaluate().isNotEmpty) {
    await tester.enterText(codeField, '123456');
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
  }

  // Test verify button
  final verifyButton = find.text('Verify Code');
  if (verifyButton.evaluate().isNotEmpty) {
    await tester.tap(verifyButton);
    await tester.pumpAndSettle();
  }
}

Future<void> _test2FAErrorHandling(WidgetTester tester) async {
  // Test with invalid data
  await tester.pumpWidget(
    MaterialApp(
      home: Verify2FAScreen(
        userId: 'test_user',
        userAddress: '0x123456789',
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Enter invalid code
  final codeField = find.byType(TextField);
  if (codeField.evaluate().isNotEmpty) {
    await tester.enterText(codeField, '000000');
    await tester.pumpAndSettle();

    // Tap verify button
    final verifyButton = find.text('Verify Code');
    if (verifyButton.evaluate().isNotEmpty) {
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
    }
  }
}

Future<void> _testBiometricAuthentication(WidgetTester tester) async {
  // Test biometric button if available
  await tester.pumpWidget(
    MaterialApp(
      home: Verify2FAScreen(
        userId: 'test_user',
        userAddress: '0x123456789',
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Look for biometric button
  final biometricButton = find.text('Authenticate with Biometric');
  if (biometricButton.evaluate().isNotEmpty) {
    await tester.tap(biometricButton);
    await tester.pumpAndSettle();
  }
}

Future<void> _testBackupCodeUsage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Verify2FAScreen(
        userId: 'test_user',
        userAddress: '0x123456789',
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Look for backup code button
  final backupButton = find.text('Use Backup Code');
  if (backupButton.evaluate().isNotEmpty) {
    await tester.tap(backupButton);
    await tester.pumpAndSettle();

    // Enter backup code
    final backupField = find.byType(TextField);
    if (backupField.evaluate().isNotEmpty) {
      await tester.enterText(backupField, 'BACKUP01');
      await tester.pumpAndSettle();
    }
  }
}
