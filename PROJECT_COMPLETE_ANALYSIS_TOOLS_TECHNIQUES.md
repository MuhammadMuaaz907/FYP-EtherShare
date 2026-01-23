# EtherShare - Complete Project Analysis: Tools & Techniques

**Blockchain-Based Secure File Sharing and Communication System**

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Frontend/Mobile Technologies](#frontendmobile-technologies)
3. [Blockchain Technologies](#blockchain-technologies)
4. [Backend Technologies](#backend-technologies)
5. [Database Technologies](#database-technologies)
6. [Security Technologies](#security-technologies)
7. [P2P & Networking Technologies](#p2p--networking-technologies)
8. [File & Media Handling](#file--media-handling)
9. [Development Tools](#development-tools)
10. [Architecture Patterns & Techniques](#architecture-patterns--techniques)

---

## 🎯 Project Overview

**EtherShare** ek comprehensive blockchain-based secure communication system hai jo multiple advanced technologies use karta hai:

- **Blockchain Authentication** (Ethereum Smart Contracts)
- **Two-Factor Authentication (2FA)**
- **Hash Chain Integrity Verification**
- **End-to-End Encryption (AES-256)**
- **Peer-to-Peer (P2P) Messaging**
- **Hybrid Storage System** (Local + Cloud)
- **Distributed System Architecture**

---

## 📱 Frontend/Mobile Technologies

### **Flutter Framework**
- **Version**: Flutter SDK >=2.19.0 <3.0.0
- **Purpose**: Cross-platform mobile app development
- **Platforms Supported**: Android, iOS, Web, Windows, Linux, macOS
- **Language**: Dart

### **State Management**
- **Provider** (^6.0.5)
  - State management solution
  - Dependency injection
  - Reactive programming pattern

### **Dependency Injection**
- **get_it** (^7.7.0)
  - Service locator pattern
  - Singleton management
  - Service registration

### **UI/UX Libraries**
- **url_launcher** (^6.3.0) - Deep linking, external URLs
- **app_links** (^3.4.2) - Deep linking support (`ethershare://invite?workspace=...`)
- **share_plus** (^7.2.1) - Share functionality
- **permission_handler** (^11.3.1) - Runtime permissions

---

## ⛓️ Blockchain Technologies

### **Smart Contract Development**
- **Solidity** (^0.8.0)
  - Smart contract language
  - UserAuth contract implementation
  - 2FA functionality on-chain

### **Blockchain Development Tools**
- **Truffle Framework**
  - Smart contract compilation
  - Migration management
  - Network configuration
  - Contract deployment

### **Web3 Libraries**

#### **Flutter (Dart)**
- **web3dart** (^2.7.2)
  - Ethereum blockchain interaction
  - Contract function calls
  - Transaction signing
  - Gas estimation
  - Event listening

#### **Node.js (Backend)**
- **web3** (^4.16.0)
  - Backend blockchain operations
  - Contract interaction from server
  - Event monitoring

### **Wallet Integration**
- **walletconnect_flutter_v2** (^2.2.5)
  - MetaMask integration
  - Wallet connection
  - Transaction signing via external wallets
  - Cross-platform wallet support

### **Blockchain Utilities**
- **hex** (^0.2.0) - Hexadecimal encoding/decoding
- **ffi** (^2.1.0) - Foreign Function Interface for native calls

### **Blockchain Network**
- **Ganache / Local Ethereum Node**
  - Development blockchain
  - Port: 7545
  - Network ID: * (any)
  - RPC URL: ngrok tunnel (for mobile access)

---

## 🔧 Backend Technologies

### **Runtime & Framework**
- **Node.js**
  - JavaScript runtime
  - Event-driven architecture
  - Non-blocking I/O

- **Express.js** (^4.18.2)
  - Web application framework
  - RESTful API endpoints
  - Middleware support
  - Route handling

### **Backend Libraries**

#### **Core Dependencies**
- **cors** (^2.8.5) - Cross-Origin Resource Sharing
- **dotenv** (^16.3.1) - Environment variables management
- **uuid** (^10.0.0) - Unique identifier generation

#### **Validation & Security**
- **express-validator** (^7.0.1) - Request validation
- **joi** (^17.11.0) - Schema validation
- **jsonwebtoken** (^9.0.2) - JWT token generation/verification
- **bcryptjs** (^2.4.3) - Password hashing

#### **File Handling**
- **multer** (^1.4.5-lts.1) - File upload middleware
  - Multipart/form-data handling
  - File storage management

#### **Networking**
- **ws** (^8.17.1) - WebSocket server
  - Real-time communication
  - Bidirectional messaging
- **net** (^1.0.2) - TCP server implementation
  - P2P TCP communication
  - Socket management

### **Development Tools**
- **nodemon** (^3.0.2) - Auto-restart on file changes

### **Backend Architecture**
- **MVC Pattern**: Routes, Models, Services separation
- **Middleware Pattern**: Authentication, validation, error handling
- **Service Layer**: Business logic separation

---

## 💾 Database Technologies

### **NoSQL Database**
- **MongoDB**
  - Document-based storage
  - Flexible schema
  - Distributed system support

- **Mongoose** (^8.0.3)
  - MongoDB ODM (Object Document Mapper)
  - Schema definition
  - Model validation
  - Query building

### **SQL Database (Local)**
- **SQLite** (via **sqflite** ^2.3.0)
  - Local relational database
  - Offline data storage
  - Fast local queries
  - Lightweight embedded database

### **Database Models**
- **Users** - User authentication data
- **Workspaces** - Team workspaces
- **Channels** - Communication channels
- **Messages** - Chat messages with hash chain
- **Files** - File metadata and storage
- **Nodes** - Distributed system nodes
- **Ledger** - Hash chain ledger entries
- **Peers** - P2P peer information

---

## 🔐 Security Technologies

### **Encryption**
- **AES-256-CBC Encryption**
  - **Library**: `encrypt` (^5.0.3)
  - **Mode**: CBC (Cipher Block Chaining)
  - **Key Size**: 256 bits
  - **IV**: Random 16-byte IV per message
  - **Padding**: PKCS7
  - **Purpose**: End-to-end message encryption

- **crypto** (^3.0.3) - Dart cryptography library
  - Hash functions (SHA-256)
  - Random number generation
  - Cryptographic utilities

### **Secure Storage**
- **flutter_secure_storage** (^9.0.0)
  - Encrypted keychain (iOS)
  - Encrypted keystore (Android)
  - Secure credential storage
  - Encryption key storage

- **shared_preferences** (^2.3.2)
  - Non-sensitive data storage
  - User preferences
  - App settings

### **Two-Factor Authentication (2FA)**

#### **TOTP (Time-based One-Time Password)**
- **otp** (^3.2.0) - TOTP generation/verification
  - RFC 6238 compliant
  - 6-digit codes
  - 30-second time windows

#### **Email OTP**
- **mailer** (^6.0.1) - SMTP email sending
  - Gmail SMTP integration
  - OTP email delivery
  - Email validation

- **email_validator** (^2.1.17) - Email format validation

#### **Biometric Authentication**
- **local_auth** (^2.1.7)
  - Fingerprint authentication
  - Face ID / Face unlock
  - Biometric security

### **Hash Chain Integrity**
- **SHA-256 Hashing**
  - Message integrity verification
  - Chain linking (`previous_hash` → `current_hash`)
  - Tamper detection
  - Blockchain-like structure

### **Security Patterns**
- **Zero-Knowledge Architecture**: Server never sees plaintext
- **Client-Side Encryption**: Encryption happens on device
- **Rate Limiting**: Failed attempt tracking
- **Lockout Mechanism**: Account protection after failed attempts
- **Backup Codes**: Recovery mechanism for 2FA

---

## 🌐 P2P & Networking Technologies

### **P2P Communication**
- **Dart ServerSocket / Socket**
  - TCP server implementation
  - Direct device-to-device communication
  - Port: 8080 (configurable)
  - IPv4 network support

### **Network Utilities**
- **connectivity_plus** (^5.0.2)
  - Network connectivity checking
  - Online/offline detection
  - Network type detection

### **HTTP Client**
- **http** (^1.2.2) - Basic HTTP client
- **dio** (^5.8.0+1) - Advanced HTTP client
  - Request/response interceptors
  - Timeout handling
  - Error handling
  - File upload/download

### **Backend URL Management**
- **flutter_dotenv** (^5.1.0)
  - Environment variable loading
  - Configuration management
  - Backend URL configuration

### **Cloudflare Tunnel**
- Public URL generation
- Firewall bypass
- Remote access without port forwarding

---

## 📁 File & Media Handling

### **File Selection**
- **file_picker** (^8.0.7)
  - File selection from device
  - Multiple file types support
  - Cross-platform file access

### **Image Handling**
- **image_picker** (^1.0.7)
  - Camera access
  - Gallery selection
  - Image cropping/editing

### **Audio Handling**
- **record** (^5.1.2)
  - Audio recording
  - Voice message support
  - Recording format control

- **audioplayers** (^6.0.0)
  - Audio playback
  - Voice message playback
  - Media controls

### **File Operations**
- **open_file** (^3.3.2) - Open files with system default app
- **open_file_macos** (^0.0.1) - macOS file opening
- **path_provider** (^2.1.2) - File system paths
- **path** (^1.8.3) - Path manipulation utilities

---

## 🛠️ Development Tools

### **Version Control**
- **Git** - Source code versioning

### **Package Management**
- **npm** / **package.json** - Node.js dependencies
- **pubspec.yaml** - Flutter/Dart dependencies
- **package-lock.json** - Dependency locking

### **Build Tools**
- **Truffle** - Smart contract compilation
- **Flutter Build System** - App compilation
- **CMake** (Windows/Linux) - Native compilation

### **Testing**
- **flutter_test** - Unit testing
- **integration_test** - Integration testing
- **mockito** (^5.4.4) - Mocking framework
- **build_runner** (^2.4.7) - Code generation

### **Code Quality**
- **flutter_lints** (^4.0.0) - Linting rules
- **ESLint** (implicit) - JavaScript linting

### **Scripts & Automation**
- **PowerShell Scripts** (.ps1)
  - `start-mongodb.ps1` - MongoDB startup
  - `start-server.ps1` - Backend server startup
  - `fix-firewall.ps1` - Firewall configuration
  - `allow-port-3000.ps1` - Port access

- **Batch Scripts** (.bat)
  - `quick-start.bat` - Quick project setup

---

## 🏗️ Architecture Patterns & Techniques

### **Design Patterns**

#### **Singleton Pattern**
- `ContractService` - Single blockchain connection
- `P2PService` - Single P2P server instance
- `HybridStorageService` - Single storage manager
- `DistributedService` - Single backend connection

#### **Service Locator Pattern**
- `get_it` for dependency injection
- Centralized service management

#### **Repository Pattern**
- `SQLiteService` - Data access abstraction
- `HybridStorageService` - Storage abstraction

#### **Observer Pattern**
- Provider for state management
- Callbacks for P2P events
- Stream subscriptions

### **Architecture Techniques**

#### **Hybrid Storage Architecture**
- **SQLite** (Local): Fast, offline access
- **MongoDB** (Server): Authoritative, sync across devices
- **Sync Strategy**: Local-first, server sync when online

#### **Hash Chain Technique**
- **Blockchain-like Structure**: Each message linked to previous
- **Integrity Verification**: SHA-256 hash chain
- **Tamper Detection**: Hash mismatch detection
- **Version Support**: Hash version 1 & 2 (legacy & new)

#### **Zero-Knowledge Architecture**
- **Client-Side Encryption**: Messages encrypted before sending
- **Server Blindness**: Server never sees plaintext
- **Payload Hash**: Integrity without plaintext access

#### **P2P Architecture**
- **TCP Server**: Each device runs server
- **Peer Discovery**: Backend-assisted or manual
- **Direct Communication**: Device-to-device without server
- **Fallback**: Server relay when P2P unavailable

#### **Distributed System Architecture**
- **Node Management**: Multiple backend nodes
- **Ledger System**: Distributed hash chain
- **Consensus**: Hash chain verification
- **Node Registration**: Dynamic node addition

### **Error Handling Techniques**
- **Retry Logic**: Automatic retry with exponential backoff
- **Error Wrapping**: Comprehensive error messages
- **Graceful Degradation**: Fallback mechanisms
- **Exception Handling**: Controlled exceptions

### **Concurrency Management**
- **Async/Await**: Non-blocking operations
- **Streams**: Reactive data flow
- **Locks**: Prevent concurrent sync operations
- **Atomic Operations**: Hash chain updates

### **Security Techniques**
- **Rate Limiting**: Failed attempt tracking
- **Lockout Mechanism**: Temporary account lock
- **Backup Codes**: 2FA recovery
- **Secure Key Storage**: Hardware-backed storage
- **Random IV**: Unique per message encryption

---

## 📊 Technology Summary Table

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| **Frontend** | Flutter | >=2.19.0 | Cross-platform app |
| **State Management** | Provider | ^6.0.5 | State management |
| **Blockchain (Flutter)** | web3dart | ^2.7.2 | Ethereum interaction |
| **Blockchain (Node)** | web3 | ^4.16.0 | Backend blockchain ops |
| **Smart Contracts** | Solidity | ^0.8.0 | Contract language |
| **Wallet** | WalletConnect | ^2.2.5 | Wallet integration |
| **Backend** | Node.js + Express | ^4.18.2 | REST API |
| **Database (NoSQL)** | MongoDB + Mongoose | ^8.0.3 | Server storage |
| **Database (SQL)** | SQLite (sqflite) | ^2.3.0 | Local storage |
| **Encryption** | AES-256-CBC | encrypt ^5.0.3 | Message encryption |
| **Secure Storage** | flutter_secure_storage | ^9.0.0 | Key storage |
| **2FA** | TOTP + Email OTP | otp ^3.2.0 | Authentication |
| **Biometric** | local_auth | ^2.1.7 | Biometric auth |
| **P2P** | Dart TCP | Native | Direct messaging |
| **HTTP Client** | dio | ^5.8.0+1 | API calls |
| **File Handling** | file_picker | ^8.0.7 | File selection |
| **Media** | image_picker, record | ^1.0.7, ^5.1.2 | Media handling |

---

## 🔄 Data Flow Architecture

```
[User Action]
    ↓
[Flutter UI]
    ↓
[Service Layer]
    ├── ContractService → [Ethereum Blockchain]
    ├── DistributedService → [Node.js Backend] → [MongoDB]
    ├── HybridStorageService
    │   ├── SQLiteService → [SQLite Local DB]
    │   └── P2PService → [TCP Direct Connection]
    └── AESCryptoService → [Encryption/Decryption]
    ↓
[Storage/Network]
```

---

## 🎓 Key Techniques Used

1. **Blockchain Integration**: Smart contract interaction, transaction signing
2. **Hash Chain Verification**: Message integrity using linked hashes
3. **End-to-End Encryption**: Client-side AES-256 encryption
4. **P2P Networking**: Direct device-to-device TCP communication
5. **Hybrid Storage**: Local-first with server sync
6. **Offline Support**: SQLite-based offline functionality
7. **Distributed System**: Multi-node backend architecture
8. **Zero-Knowledge**: Server never sees plaintext
9. **2FA Implementation**: TOTP, Email OTP, Biometric
10. **Real-time Sync**: Background sync with conflict resolution

---

## 📝 Notes

- **Development Environment**: Windows 10, PowerShell
- **Blockchain Network**: Local Ganache (port 7545)
- **Backend Port**: 3000
- **P2P Port**: 8080
- **Database**: MongoDB (server), SQLite (local)
- **Tunnel**: Cloudflare Tunnel for remote access

---

**Document Created**: January 23, 2026  
**Project**: EtherShare - FYP  
**Version**: 1.0.0
