# 2FA Implementation Test Suite

This comprehensive test suite validates the Two-Factor Authentication (2FA) implementation for the EtherShare blockchain application.

## Test Structure

```
test/
├── 2fa_tests.dart                    # Main unit and widget tests
├── test_config.dart                  # Test configuration and utilities
├── integration/
│   └── 2fa_integration_tests.dart    # Integration tests
├── mocks/
│   └── blockchain_mock_tests.dart    # Mock tests for blockchain
├── error_handling/
│   └── error_handling_tests.dart     # Error handling tests
└── performance/
    └── performance_tests.dart        # Performance tests
```

## Test Categories

### 1. Unit Tests (`2fa_tests.dart`)
- **TOTPService Tests**: Secret generation, code validation, QR generation
- **BiometricService Tests**: Availability check, authentication
- **SecureStorageService Tests**: Encryption, storage, retrieval
- **Widget Tests**: Setup2FAScreen, Verify2FAScreen, QRCodeWidget
- **Error Handling**: Invalid inputs, edge cases
- **Performance**: QR generation, biometric auth

### 2. Integration Tests (`integration/2fa_integration_tests.dart`)
- **Complete 2FA Setup Flow**: End-to-end setup process
- **2FA Verification Flow**: TOTP and backup code verification
- **Service Integration**: Cross-service functionality
- **Performance Integration**: Multi-service performance
- **Error Recovery**: Network failures, service unavailability

### 3. Mock Tests (`mocks/blockchain_mock_tests.dart`)
- **ContractService Mocks**: Blockchain interaction simulation
- **Service Integration Mocks**: Cross-service mock testing
- **Error Scenario Mocks**: Network errors, contract failures
- **Edge Case Mocks**: Invalid data, rate limiting
- **Performance Mocks**: Fast/slow operation simulation

### 4. Error Handling Tests (`error_handling/error_handling_tests.dart`)
- **TOTPService Errors**: Invalid secrets, codes, URIs
- **BiometricService Errors**: Unavailable hardware, cancellation
- **SecureStorageService Errors**: Invalid keys, values, operations
- **ContractService Errors**: Network, contract, gas issues
- **Edge Cases**: Empty data, special characters, limits

### 5. Performance Tests (`performance/performance_tests.dart`)
- **TOTPService Performance**: Secret generation, code verification
- **SecureStorageService Performance**: Data storage, retrieval
- **BiometricService Performance**: Availability checks, authentication
- **QRCodeWidget Performance**: Rendering, large data handling
- **ContractService Performance**: Gas estimation, contract calls
- **Memory Performance**: Leak detection, large data handling
- **Concurrent Performance**: Parallel operation handling

## Running Tests

### Prerequisites
```bash
# Install dependencies
flutter pub get

# Generate mocks (if needed)
flutter packages pub run build_runner build
```

### Run All Tests
```bash
flutter test
```

### Run Specific Test Suites
```bash
# Unit and widget tests
flutter test test/2fa_tests.dart

# Integration tests
flutter test integration_test/2fa_integration_tests.dart

# Mock tests
flutter test test/mocks/blockchain_mock_tests.dart

# Error handling tests
flutter test test/error_handling/error_handling_tests.dart

# Performance tests
flutter test test/performance/performance_tests.dart
```

### Run Tests with Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## Test Configuration

### Performance Thresholds
- Secret Generation: < 1000ms for 100 operations
- TOTP Generation: < 2000ms for 1000 operations
- TOTP Verification: < 2000ms for 1000 operations
- QR URI Generation: < 1000ms for 100 operations
- Data Storage: < 10000ms for 100 operations
- Data Retrieval: < 5000ms for 100 operations
- QR Code Rendering: < 2000ms for single render

### Test Data
- Test User ID: `test_user_123`
- Test Address: `0x1234567890123456789012345678901234567890`
- Test Secret: `TEST_SECRET_KEY_123456789`
- Test Backup Codes: `BACKUP01`, `BACKUP02`, etc.
- Test TOTP Code: `123456`

## Test Scenarios

### 1. Happy Path Tests
- Successful 2FA setup with QR code generation
- Successful TOTP code verification
- Successful backup code usage
- Successful biometric authentication
- Successful 2FA disable

### 2. Error Scenarios
- Network connection failures
- Contract execution errors
- Gas estimation failures
- Transaction timeouts
- Invalid address formats
- Contract not deployed
- Insufficient gas
- User transaction rejection

### 3. Edge Cases
- Empty or null input data
- Invalid data formats
- Special characters in data
- Very long data strings
- Maximum rate limiting
- Lockout scenarios
- Expired codes
- Concurrent operations

### 4. Performance Scenarios
- High-volume operations
- Large data handling
- Memory leak detection
- Concurrent execution
- Network latency simulation
- Resource constraint testing

## Mock Services

### ContractService Mock
- `enable2FA()`: Enable 2FA with backup codes
- `verify2FA()`: Verify TOTP or backup codes
- `disable2FA()`: Disable 2FA
- `is2FAEnabled()`: Check 2FA status
- `getBackupCodeCount()`: Get remaining backup codes
- `getFailedAttempts()`: Get failed attempt count
- `isLockedOut()`: Check lockout status
- `getRemainingLockoutTime()`: Get lockout time remaining

### SecureStorageService Mock
- `storeTOTPSecret()`: Store TOTP secret
- `getTOTPSecret()`: Retrieve TOTP secret
- `storeBackupCodes()`: Store backup codes
- `getBackupCodes()`: Retrieve backup codes
- `useBackupCode()`: Use and remove backup code
- `setUser2FAStatus()`: Set 2FA enabled status
- `isUser2FAEnabled()`: Check 2FA status
- `clear2FAData()`: Clear all 2FA data

### TOTPService Mock
- `generateSecret()`: Generate TOTP secret
- `generateTOTP()`: Generate TOTP code
- `verifyTOTP()`: Verify TOTP code
- `generateTOTPURI()`: Generate QR URI
- `generateBackupCodes()`: Generate backup codes
- `verifyBackupCode()`: Verify backup code

## Test Utilities

### TestConfig
- Performance thresholds
- Error scenarios
- Edge case data
- Test constants

### TestUtils
- Data generation
- Performance measurement
- Validation helpers
- Error message creation

### TestDataGenerator
- Random secret generation
- Random backup codes
- Random TOTP codes
- Test QR data

### TestAssertions
- Performance assertions
- Error handling assertions
- Data integrity assertions
- Service availability assertions

## Continuous Integration

### GitHub Actions Example
```yaml
name: 2FA Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter test --coverage
```

## Test Reports

### Coverage Reports
- Line coverage
- Branch coverage
- Function coverage
- Statement coverage

### Performance Reports
- Operation timing
- Memory usage
- Resource consumption
- Concurrent execution metrics

### Error Reports
- Error frequency
- Error types
- Recovery success rates
- Edge case coverage

## Best Practices

### Test Writing
- Use descriptive test names
- Follow AAA pattern (Arrange, Act, Assert)
- Test both success and failure scenarios
- Include edge cases and boundary conditions
- Mock external dependencies
- Use test data generators for consistency

### Test Organization
- Group related tests
- Use meaningful test descriptions
- Separate unit, integration, and performance tests
- Use test fixtures for common setup
- Clean up after tests

### Performance Testing
- Set realistic performance thresholds
- Test under various load conditions
- Monitor memory usage
- Test concurrent operations
- Validate resource cleanup

### Error Testing
- Test all error scenarios
- Validate error messages
- Test error recovery
- Test edge cases
- Test boundary conditions

## Troubleshooting

### Common Issues
1. **Mock generation fails**: Run `flutter packages pub run build_runner build`
2. **Integration tests fail**: Ensure test device/emulator is available
3. **Performance tests fail**: Adjust thresholds based on test environment
4. **Biometric tests fail**: Expected on emulators without biometric hardware
5. **Network tests fail**: Expected when blockchain network is unavailable

### Debug Tips
- Use `flutter test --verbose` for detailed output
- Check test logs for specific failure reasons
- Verify test data and mock configurations
- Ensure all dependencies are properly installed
- Check device/emulator capabilities for integration tests

## Contributing

### Adding New Tests
1. Follow existing test structure
2. Use appropriate test categories
3. Include both positive and negative test cases
4. Add performance thresholds if applicable
5. Update documentation

### Test Maintenance
- Keep tests up to date with code changes
- Review and update performance thresholds
- Add new error scenarios as they're discovered
- Maintain test data consistency
- Update documentation as needed
