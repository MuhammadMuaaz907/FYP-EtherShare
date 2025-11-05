import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:blockchain_fyp/services/totp_service.dart';
import 'package:blockchain_fyp/services/biometric_service.dart';
import 'package:blockchain_fyp/services/secure_storage_service.dart';
import 'package:blockchain_fyp/services/contract_service.dart';
import 'package:blockchain_fyp/screens/setup_2fa_screen.dart';
import 'package:blockchain_fyp/screens/verify_2fa_screen.dart';
import 'package:blockchain_fyp/widgets/qr_code_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Generate mocks
@GenerateMocks([
  TOTPService,
  BiometricService,
  SecureStorageService,
  ContractService,
])
import '2fa_tests.mocks.dart';

void main() {
  group('TOTPService Unit Tests', () {
    late TOTPService totpService;

    setUp(() async {
      totpService = await TOTPService.create();
    });

    test('should generate valid secret key', () {
      final secret = totpService.generateSecret();
      
      expect(secret, isNotEmpty);
      expect(secret.length, greaterThanOrEqualTo(16));
      expect(secret.length, lessThanOrEqualTo(64));
    });

    test('should generate TOTP code from secret', () {
      final secret = totpService.generateSecret();
      final code = totpService.generateTOTP(secret);
      
      expect(code, isNotEmpty);
      expect(code.length, equals(6));
      expect(int.tryParse(code), isNotNull);
    });

    test('should validate correct TOTP code', () {
      final secret = totpService.generateSecret();
      final code = totpService.generateTOTP(secret);
      
      final isValid = totpService.verifyTOTP(secret, code);
      expect(isValid, isTrue);
    });

    test('should reject invalid TOTP code', () {
      final secret = totpService.generateSecret();
      final invalidCode = '123456';
      
      final isValid = totpService.verifyTOTP(secret, invalidCode);
      expect(isValid, isFalse);
    });

    test('should generate TOTP URI', () {
      final secret = totpService.generateSecret();
      final uri = totpService.generateTOTPURI(secret, 'test@example.com');
      
      expect(uri, contains('otpauth://totp'));
      expect(uri, contains('test@example.com'));
      expect(uri, contains('secret='));
    });

    test('should generate backup codes', () {
      final backupCodes = totpService.generateBackupCodes();
      
      expect(backupCodes, hasLength(10));
      for (final code in backupCodes) {
        expect(code.length, equals(8));
        expect(code, matches(RegExp(r'^[A-Z0-9]+$')));
      }
    });

    test('should verify backup codes', () {
      final backupCodes = totpService.generateBackupCodes();
      final testCode = backupCodes.first;
      
      final isValid = totpService.verifyBackupCode(testCode, backupCodes);
      expect(isValid, isTrue);
    });

    test('should reject invalid backup code', () {
      final backupCodes = totpService.generateBackupCodes();
      final invalidCode = 'INVALID1';
      
      final isValid = totpService.verifyBackupCode(invalidCode, backupCodes);
      expect(isValid, isFalse);
    });

    test('should get remaining time', () {
      final remainingTime = totpService.getRemainingTime();
      
      expect(remainingTime, greaterThanOrEqualTo(0));
      expect(remainingTime, lessThanOrEqualTo(30));
    });

    test('should validate secret format', () {
      final validSecret = totpService.generateSecret();
      final invalidSecret = 'invalid';
      
      expect(totpService.isValidSecret(validSecret), isTrue);
      expect(totpService.isValidSecret(invalidSecret), isFalse);
    });

    test('should handle different algorithms', () {
      final secret = totpService.generateSecret();
      
      final sha1Code = totpService.generateTOTP(secret, algorithm: Algorithm.SHA1);
      final sha256Code = totpService.generateTOTP(secret, algorithm: Algorithm.SHA256);
      final sha512Code = totpService.generateTOTP(secret, algorithm: Algorithm.SHA512);
      
      expect(sha1Code, isNotEmpty);
      expect(sha256Code, isNotEmpty);
      expect(sha512Code, isNotEmpty);
    });
  });

  group('BiometricService Unit Tests', () {
    test('should check biometric availability', () async {
      final isAvailable = await BiometricService.isBiometricAvailable();
      
      expect(isAvailable, isA<bool>());
    });

    test('should authenticate with biometric', () async {
      // Note: This test may fail on emulators without biometric hardware
      try {
        final isAuthenticated = await BiometricService.authenticate(
          reason: 'Test authentication',
        );
        expect(isAuthenticated, isA<bool>());
      } catch (e) {
        // Expected on devices without biometric hardware
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
  });

  group('SecureStorageService Unit Tests', () {
    late SecureStorageService storageService;

    setUp(() async {
      storageService = await SecureStorageService.create();
    });

    test('should store and retrieve TOTP secret', () async {
      const testSecret = 'TEST_SECRET_KEY';
      
      await storageService.storeTOTPSecret(testSecret);
      final retrievedSecret = await storageService.getTOTPSecret();
      
      expect(retrievedSecret, equals(testSecret));
    });

    test('should store and retrieve backup codes', () async {
      final testCodes = ['CODE1', 'CODE2', 'CODE3'];
      
      await storageService.storeBackupCodes(testCodes);
      final retrievedCodes = await storageService.getBackupCodes();
      
      expect(retrievedCodes, equals(testCodes));
    });

    test('should manage 2FA enabled status', () async {
      await storageService.setUser2FAStatus(true);
      final isEnabled = await storageService.isUser2FAEnabled();
      expect(isEnabled, isTrue);
      
      await storageService.setUser2FAStatus(false);
      final isDisabled = await storageService.isUser2FAEnabled();
      expect(isDisabled, isFalse);
    });

    test('should manage biometric enabled status', () async {
      await storageService.setBiometricEnabled(true);
      final isEnabled = await storageService.isBiometricEnabled();
      expect(isEnabled, isTrue);
      
      await storageService.setBiometricEnabled(false);
      final isDisabled = await storageService.isBiometricEnabled();
      expect(isDisabled, isFalse);
    });

    test('should handle backup code usage', () async {
      final testCodes = ['CODE1', 'CODE2', 'CODE3'];
      await storageService.storeBackupCodes(testCodes);
      
      final success = await storageService.useBackupCode('CODE1');
      expect(success, isTrue);
      
      final remainingCodes = await storageService.getBackupCodes();
      expect(remainingCodes, hasLength(2));
      expect(remainingCodes, contains('CODE2'));
      expect(remainingCodes, contains('CODE3'));
    });

    test('should reject invalid backup code', () async {
      final testCodes = ['CODE1', 'CODE2'];
      await storageService.storeBackupCodes(testCodes);
      
      final success = await storageService.useBackupCode('INVALID');
      expect(success, isFalse);
      
      final remainingCodes = await storageService.getBackupCodes();
      expect(remainingCodes, hasLength(2));
    });

    test('should clear 2FA data', () async {
      await storageService.storeTOTPSecret('TEST_SECRET');
      await storageService.storeBackupCodes(['CODE1', 'CODE2']);
      await storageService.setUser2FAStatus(true);
      
      await storageService.clear2FAData();
      
      final secret = await storageService.getTOTPSecret();
      final codes = await storageService.getBackupCodes();
      final isEnabled = await storageService.isUser2FAEnabled();
      
      expect(secret, isNull);
      expect(codes, isEmpty);
      expect(isEnabled, isFalse);
    });

    test('should store and retrieve secure data', () async {
      const key = 'test_key';
      const value = 'test_value';
      
      await storageService.storeSecureData(key, value);
      final retrievedValue = await storageService.getSecureData(key);
      
      expect(retrievedValue, equals(value));
    });

    test('should delete secure data', () async {
      const key = 'test_key';
      const value = 'test_value';
      
      await storageService.storeSecureData(key, value);
      await storageService.deleteSecureData(key);
      
      final retrievedValue = await storageService.getSecureData(key);
      expect(retrievedValue, isNull);
    });

    test('should check storage availability', () async {
      final isAvailable = await storageService.isStorageAvailable();
      expect(isAvailable, isTrue);
    });
  });

  group('QRCodeWidget Widget Tests', () {
    testWidgets('should display QR code with valid data', (WidgetTester tester) async {
      const testData = 'otpauth://totp/test@example.com?secret=TEST123';
      
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
      
      expect(find.byType(QRCodeWidget), findsOneWidget);
    });

    testWidgets('should display error for invalid data', (WidgetTester tester) async {
      const invalidData = '';
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QRCodeWidget(
              data: invalidData,
              size: 200,
            ),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.byType(QRCodeWidget), findsOneWidget);
    });

    testWidgets('should display instruction text', (WidgetTester tester) async {
      const testData = 'otpauth://totp/test@example.com?secret=TEST123';
      const instructionText = 'Scan with your authenticator app';
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QRCodeWidget(
              data: testData,
              size: 200,
              instructionText: instructionText,
            ),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.text(instructionText), findsOneWidget);
    });

    testWidgets('should handle tap interaction', (WidgetTester tester) async {
      const testData = 'otpauth://totp/test@example.com?secret=TEST123';
      bool tapped = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QRCodeWidget(
              data: testData,
              size: 200,
              interactive: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      await tester.tap(find.byType(QRCodeWidget));
      expect(tapped, isTrue);
    });
  });

  group('Setup2FAScreen Widget Tests', () {
    testWidgets('should display setup screen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Setup2FAScreen(
            userId: 'test_user',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.byType(Setup2FAScreen), findsOneWidget);
    });

    testWidgets('should validate form inputs', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Setup2FAScreen(
            userId: 'test_user',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Find and tap continue button
      final continueButton = find.text('Continue');
      if (continueButton.evaluate().isNotEmpty) {
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('should display QR code', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Setup2FAScreen(
            userId: 'test_user',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.byType(QRCodeWidget), findsOneWidget);
    });
  });

  group('Verify2FAScreen Widget Tests', () {
    testWidgets('should display verification screen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Verify2FAScreen(
            userId: 'test_user',
            userAddress: '0x123456789',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.byType(Verify2FAScreen), findsOneWidget);
    });

    testWidgets('should display code input field', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Verify2FAScreen(
            userId: 'test_user',
            userAddress: '0x123456789',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should handle code input', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Verify2FAScreen(
            userId: 'test_user',
            userAddress: '0x123456789',
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      final codeField = find.byType(TextField);
      await tester.enterText(codeField, '123456');
      await tester.pumpAndSettle();
      
      expect(find.text('123456'), findsOneWidget);
    });
  });

  group('Error Handling Tests', () {
    test('TOTPService should handle invalid secret', () {
      final totpService = TOTPService.create();
      
      expect(() => TOTPService().generateTOTP(''), throwsException);
    });

    test('SecureStorageService should handle storage errors', () async {
      final storageService = await SecureStorageService.create();
      
      // Test with invalid data
      await storageService.storeTOTPSecret('');
      final secret = await storageService.getTOTPSecret();
      expect(secret, equals(''));
    });
  });

  group('Edge Case Tests', () {
    test('TOTPService should handle expired codes', () async {
      final totpService = await TOTPService.create();
      final secret = totpService.generateSecret();
      
      // Generate code and wait for it to expire
      final code = totpService.generateTOTP(secret);
      await Future.delayed(const Duration(seconds: 35));
      
      final isValid = totpService.verifyTOTP(secret, code);
      expect(isValid, isFalse);
    });

    test('SecureStorageService should handle empty backup codes', () async {
      final storageService = await SecureStorageService.create();
      
      await storageService.storeBackupCodes([]);
      final codes = await storageService.getBackupCodes();
      expect(codes, isEmpty);
    });
  });

  group('Performance Tests', () {
    test('TOTPService QR generation performance', () {
      final totpService = TOTPService.create();
      final secret = totpService.generateSecret();
      
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 100; i++) {
        totpService.generateTOTPURI(secret, 'test@example.com');
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('SecureStorageService storage performance', () async {
      final storageService = await SecureStorageService.create();
      
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 50; i++) {
        await storageService.storeSecureData('key_$i', 'value_$i');
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
