# EtherShare - Blockchain App with 2FA Authentication

A secure blockchain application with comprehensive two-factor authentication (2FA) system.

## ✅ Features

### Two-Factor Authentication (2FA)
- ✅ Email OTP Verification
- ✅ Biometric Authentication (Fingerprint/Face ID)
- ✅ Backup Recovery Codes
- ✅ Multi-step verification flow
- ✅ Secure encrypted storage
- ✅ Rate limiting and security

### Blockchain Integration
- ✅ MetaMask integration
- ✅ Web3 wallet connection
- ✅ Ethereum smart contracts
- ✅ Secure transaction handling

### User Experience
- ✅ Splash screen
- ✅ Profile setup with email validation
- ✅ Professional multi-step UI
- ✅ Smooth animations
- ✅ Error handling

## 📁 Project Structure

```
blockchain_fyp/
├── lib/
│   ├── main.dart                   # Main entry point
│   ├── Splash.dart                 # Splash screen
│   ├── ProfileSetup.dart           # Profile setup screen
│   ├── screens/
│   │   ├── setup_2fa_screen.dart   # 2FA setup
│   │   └── verify_2fa_screen.dart  # 2FA verification
│   └── services/
│       ├── biometric_service.dart      # Biometric auth
│       ├── contract_service.dart       # Blockchain
│       ├── email_otp_service.dart      # Email OTP
│       ├── secure_storage_service.dart # Secure storage
│       ├── totp_service.dart          # TOTP/Backup codes
│       └── two_fa_error_handler.dart  # Error handling
├── assets/                         # Images & resources
└── android/                        # Android configuration
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest)
- Android Studio
- Gmail App Password (for email OTP)

### Installation
```bash
cd blockchain_fyp
flutter pub get
flutter run
```

### Configuration

#### Gmail Setup for OTP
1. Go to Gmail Settings
2. Enable 2-Step Verification
3. Generate App Password: https://myaccount.google.com/apppasswords
4. Use app password in `lib/screens/setup_2fa_screen.dart` and `verify_2fa_screen.dart`

## 🔐 Security Features

- ✅ Encrypted storage (AES-256-GCM)
- ✅ Secure biometric authentication
- ✅ Rate limiting (3 OTP attempts per hour)
- ✅ Backup codes (10 codes)
- ✅ 5-minute OTP expiration
- ✅ Comprehensive error handling
- ✅ Automatic lockout after failures

## 📱 Supported Platforms

- Android ✅ (Main development platform)
- iOS ✅
- Web ✅
- Windows ✅
- Linux ✅
- macOS ✅

## 🔧 Tech Stack

- Flutter 3.x
- Web3dart (Blockchain)
- WalletConnect (Wallet integration)
- Gmail SMTP (Email OTP)
- Local Auth (Biometric)
- Flutter Secure Storage (Encryption)

## 📝 License

MIT License

## 👨‍💻 Developer

Built with ❤️ for secure blockchain authentication
