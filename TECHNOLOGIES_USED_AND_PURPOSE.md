# Technologies Used and Their Purpose - EtherShare FYP Report

## Project Overview
**EtherShare** is a Blockchain-Based Secure File Sharing and Communication System that combines distributed and decentralized architectures to provide secure, tamper-proof file sharing and messaging capabilities.

---

## 1. FRONTEND TECHNOLOGIES

### 1.1 Flutter Framework
**Version:** SDK >=2.19.0 <3.0.0  
**Purpose:**
- Cross-platform mobile application development framework
- Enables single codebase for Android, iOS, Web, Windows, Linux, and macOS
- Provides Material Design UI components for consistent user experience
- Handles platform-specific adaptations automatically

### 1.2 Dart Programming Language
**Purpose:**
- Primary programming language for Flutter application
- Provides strong typing, async/await support for asynchronous operations
- Enables efficient state management and reactive programming

### 1.3 Provider Package (^6.0.5)
**Purpose:**
- State management solution for Flutter
- Manages application-wide state (user authentication, workspace data, messages)
- Implements dependency injection pattern for service management
- Enables reactive UI updates when data changes

### 1.4 Web3Dart Package (^2.7.2)
**Purpose:**
- Ethereum blockchain integration library for Dart/Flutter
- Connects to Ethereum network (local Ganache or testnet)
- Interacts with smart contracts deployed on blockchain
- Handles transaction signing, gas estimation, and contract function calls
- Enables blockchain-based user authentication and data integrity

### 1.5 WalletConnect Flutter V2 (^2.2.5)
**Purpose:**
- Integrates cryptocurrency wallet connectivity
- Allows users to connect MetaMask or other Web3 wallets
- Enables secure wallet-based authentication
- Facilitates blockchain transaction signing without exposing private keys

### 1.6 HTTP Package (^1.2.2)
**Purpose:**
- HTTP client for making REST API calls to backend server
- Handles GET, POST, PUT, DELETE requests
- Manages request/response serialization
- Supports timeout and error handling

### 1.7 Dio Package (^5.8.0+1)
**Purpose:**
- Advanced HTTP client with interceptors and request cancellation
- Handles file uploads and downloads
- Provides better error handling and retry mechanisms
- Supports request/response transformation

### 1.8 File Picker (^8.0.7)
**Purpose:**
- Enables users to select files from device storage
- Supports multiple file types (documents, images, videos)
- Provides cross-platform file selection interface

### 1.9 Image Picker (^1.0.7)
**Purpose:**
- Allows users to capture or select images from camera/gallery
- Handles image compression and format conversion
- Provides camera and gallery access permissions

### 1.10 Shared Preferences (^2.3.2)
**Purpose:**
- Local key-value storage for simple data persistence
- Stores user preferences, settings, and configuration
- Provides lightweight persistent storage solution

### 1.11 SQLite (sqflite ^2.3.0)
**Purpose:**
- Local relational database for offline data storage
- Stores messages, channels, workspaces locally
- Enables offline functionality when server is unavailable
- Provides fast local data access
- Supports P2P message synchronization

### 1.12 Flutter Secure Storage (^9.0.0)
**Purpose:**
- Encrypted local storage for sensitive data
- Stores private keys, authentication tokens securely
- Uses platform-specific secure storage (Keychain on iOS, Keystore on Android)
- Protects sensitive user credentials

### 1.13 Local Auth (^2.1.7)
**Purpose:**
- Biometric authentication (fingerprint, face recognition)
- Provides additional security layer for user authentication
- Enables 2FA with biometric verification
- Uses device-native biometric APIs

### 1.14 Crypto Package (^3.0.3)
**Purpose:**
- Cryptographic functions for data security
- Implements SHA-256 hashing for chain integrity
- Generates secure random numbers for tokens
- Provides encryption/decryption capabilities

### 1.15 OTP Package (^3.2.0)
**Purpose:**
- Time-based One-Time Password (TOTP) generation
- Implements 2FA authentication codes
- Generates and validates 6-digit authentication codes
- Supports Google Authenticator compatible codes

### 1.16 Mailer Package (^6.0.1)
**Purpose:**
- Email sending functionality
- Sends OTP codes via email for 2FA
- Handles email delivery and error management
- Supports SMTP configuration

### 1.17 Connectivity Plus (^5.0.2)
**Purpose:**
- Network connectivity monitoring
- Detects online/offline status
- Switches between server and local storage modes
- Enables hybrid storage service functionality

### 1.18 Mongo Dart (^0.10.3)
**Purpose:**
- Direct MongoDB connection from Flutter (optional)
- Alternative to HTTP API for database access
- Enables direct database queries when needed

### 1.19 Path Provider (^2.1.2)
**Purpose:**
- Access to device file system paths
- Gets application documents directory
- Manages file storage locations
- Provides cross-platform path handling

### 1.20 Open File (^3.3.2)
**Purpose:**
- Opens files with default system applications
- Handles file viewing and editing
- Supports various file types (PDF, images, documents)

### 1.21 Share Plus (^7.2.1)
**Purpose:**
- Native sharing functionality
- Shares files, messages, or links via system share dialog
- Integrates with other apps on device

### 1.22 URL Launcher (^6.3.0)
**Purpose:**
- Opens URLs in browser or external apps
- Handles deep linking and app links
- Launches external applications

### 1.23 Record Package (^5.1.2)
**Purpose:**
- Audio recording functionality
- Records voice messages for communication
- Handles audio file format conversion

### 1.24 Audio Players (^6.0.0)
**Purpose:**
- Plays audio files and voice messages
- Handles audio playback controls
- Supports multiple audio formats

### 1.25 Permission Handler (^11.3.1)
**Purpose:**
- Manages runtime permissions
- Requests camera, storage, microphone permissions
- Handles permission status checking

### 1.26 Flutter Dotenv (^5.1.0)
**Purpose:**
- Environment variable management
- Loads configuration from .env files
- Stores API keys, backend URLs securely
- Separates development and production configurations

### 1.27 App Links (^3.4.2)
**Purpose:**
- Deep linking support
- Handles custom URL schemes
- Enables app-to-app communication

### 1.28 Get It (^7.7.0)
**Purpose:**
- Dependency injection container
- Manages service instances (singleton pattern)
- Provides centralized service access
- Simplifies dependency management

### 1.29 UUID (^4.2.1)
**Purpose:**
- Generates unique identifiers
- Creates unique IDs for messages, workspaces, channels
- Ensures data uniqueness across distributed system

### 1.30 Hex Package (^0.2.0)
**Purpose:**
- Hexadecimal encoding/decoding
- Converts blockchain addresses and hashes
- Handles Ethereum address formatting

---

## 2. BACKEND TECHNOLOGIES

### 2.1 Node.js
**Purpose:**
- JavaScript runtime environment for server-side development
- Enables asynchronous, event-driven server architecture
- Handles concurrent connections efficiently
- Provides access to system resources and network operations

### 2.2 Express.js (^4.18.2)
**Purpose:**
- Web application framework for Node.js
- Creates RESTful API endpoints
- Handles HTTP requests and responses
- Provides middleware for authentication, validation, error handling
- Routes API requests to appropriate handlers

### 2.3 MongoDB (via Mongoose ^8.0.3)
**Purpose:**
- NoSQL document database for distributed data storage
- Stores users, workspaces, messages, channels, files
- Implements blockchain-like ledger system
- Maintains hash chains for data integrity
- Provides horizontal scalability for distributed system
- Supports replica sets for high availability

### 2.4 Mongoose ODM
**Purpose:**
- Object Data Modeling library for MongoDB
- Defines data schemas and models
- Provides data validation and type casting
- Handles database connections and transactions
- Implements middleware for data transformation

### 2.5 Web3.js (^4.16.0)
**Purpose:**
- Ethereum JavaScript library for backend
- Interacts with Ethereum blockchain from server
- Validates blockchain transactions
- Monitors smart contract events
- Handles gas estimation and transaction management

### 2.6 WebSocket (ws ^8.17.1)
**Purpose:**
- Real-time bidirectional communication
- Enables P2P messaging between nodes
- Provides persistent connections for live updates
- Handles TCP socket communication for distributed nodes

### 2.7 CORS (^2.8.5)
**Purpose:**
- Cross-Origin Resource Sharing middleware
- Allows frontend to access backend API from different origins
- Configures allowed origins, methods, and headers
- Enables secure cross-domain communication

### 2.8 Multer (^1.4.5-lts.1)
**Purpose:**
- File upload middleware for Express
- Handles multipart/form-data for file uploads
- Manages file storage and metadata
- Processes file uploads to server

### 2.9 JSON Web Token (jsonwebtoken ^9.0.2)
**Purpose:**
- Stateless authentication mechanism
- Generates and validates JWT tokens
- Secures API endpoints
- Enables session management without server-side storage

### 2.10 Bcrypt.js (^2.4.3)
**Purpose:**
- Password hashing library
- Securely hashes user passwords
- Implements salt rounds for password security
- Prevents password exposure in database

### 2.11 Express Validator (^7.0.1)
**Purpose:**
- Request validation middleware
- Validates input data before processing
- Prevents invalid data from entering system
- Provides sanitization and error messages

### 2.12 Joi (^17.11.0)
**Purpose:**
- Schema validation library
- Validates complex data structures
- Provides detailed validation error messages
- Ensures data integrity at API level

### 2.13 UUID (^10.0.0)
**Purpose:**
- Generates unique identifiers on backend
- Creates unique IDs for database records
- Ensures data uniqueness in distributed system

### 2.14 Dotenv (^16.3.1)
**Purpose:**
- Environment variable management
- Loads configuration from .env files
- Stores sensitive data (database URLs, API keys)
- Separates development and production settings

### 2.15 Nodemon (^3.0.2)
**Purpose:**
- Development tool for automatic server restart
- Monitors file changes and restarts server
- Improves development workflow efficiency

### 2.16 Net Module (^1.0.2)
**Purpose:**
- TCP networking module
- Creates TCP server for P2P communication
- Handles direct node-to-node connections
- Manages socket connections and data transmission

---

## 3. BLOCKCHAIN TECHNOLOGIES

### 3.1 Ethereum Blockchain
**Purpose:**
- Decentralized blockchain platform for smart contracts
- Provides immutable ledger for user authentication
- Ensures data integrity and tamper-proof records
- Enables trustless user registration and login

### 3.2 Solidity Programming Language
**Version:** ^0.8.0  
**Purpose:**
- Smart contract programming language
- Implements UserAuth contract for blockchain-based authentication
- Defines 2FA functionality on blockchain
- Creates immutable authentication logic

### 3.3 Truffle Framework
**Purpose:**
- Development framework for Ethereum smart contracts
- Compiles Solidity contracts
- Manages contract deployment
- Provides testing framework for smart contracts
- Handles contract migration and versioning

### 3.4 Ganache (Local Blockchain)
**Purpose:**
- Local Ethereum blockchain for development
- Provides test accounts with pre-funded Ether
- Enables rapid development and testing
- Simulates blockchain network without gas costs
- Runs on localhost:7545

### 3.5 Smart Contract: UserAuth.sol
**Purpose:**
- Blockchain-based user authentication contract
- Manages user registration on blockchain
- Implements 2FA functionality with backup codes
- Provides rate limiting and account lockout
- Emits events for authentication activities
- Ensures immutable authentication records

### 3.6 Web3 Integration
**Purpose:**
- Connects application to Ethereum network
- Enables interaction with smart contracts
- Handles transaction signing and submission
- Manages gas estimation and transaction fees
- Monitors blockchain events

---

## 4. DATABASE TECHNOLOGIES

### 4.1 MongoDB
**Purpose:**
- Primary distributed database for server-side storage
- Stores users, workspaces, channels, messages, files
- Implements blockchain-like ledger system with hash chains
- Maintains node registry for distributed system
- Provides horizontal scalability
- Supports replica sets for high availability

**Collections:**
- `users`: User profiles and authentication data
- `workspaces`: Workspace information and members
- `channels`: Channel data and settings
- `messages`: Message content with hash chain
- `files`: File metadata and storage information
- `nodes`: Distributed node registry with chain positions
- `ledgers`: Blockchain-like transaction blocks
- `peers`: P2P peer information

### 4.2 SQLite (via sqflite)
**Purpose:**
- Local relational database for mobile devices
- Stores messages, channels, workspaces offline
- Enables offline functionality
- Provides fast local data access
- Supports P2P message synchronization
- Maintains local cache of server data

---

## 5. NETWORKING & COMMUNICATION

### 5.1 HTTP/HTTPS Protocol
**Purpose:**
- RESTful API communication between frontend and backend
- Standard request/response protocol
- Supports JSON data exchange
- Enables stateless client-server communication

### 5.2 TCP/IP Protocol
**Purpose:**
- Direct peer-to-peer communication
- Enables device-to-device messaging
- Provides reliable data transmission
- Supports real-time communication
- Handles P2P node connections

### 5.3 WebSocket Protocol
**Purpose:**
- Real-time bidirectional communication
- Enables live updates without polling
- Supports persistent connections
- Handles real-time messaging

### 5.4 P2P (Peer-to-Peer) Architecture
**Purpose:**
- Direct device-to-device communication
- Enables offline messaging capabilities
- Reduces server dependency
- Provides decentralized communication
- Supports distributed file sharing

---

## 6. SECURITY TECHNOLOGIES

### 6.1 Two-Factor Authentication (2FA)
**Purpose:**
- Additional security layer for user authentication
- Implements TOTP (Time-based One-Time Password)
- Provides backup codes for account recovery
- Reduces risk of unauthorized access

### 6.2 Biometric Authentication
**Purpose:**
- Fingerprint and face recognition authentication
- Uses device-native biometric APIs
- Provides convenient and secure authentication
- Enhances user experience

### 6.3 Cryptographic Hashing (SHA-256)
**Purpose:**
- Creates hash chains for data integrity
- Ensures tamper-proof data storage
- Detects unauthorized data modifications
- Implements blockchain-like immutability

### 6.4 JWT (JSON Web Tokens)
**Purpose:**
- Stateless authentication tokens
- Secures API endpoints
- Enables session management
- Prevents unauthorized API access

### 6.5 Password Hashing (Bcrypt)
**Purpose:**
- Secure password storage
- Implements salt rounds for security
- Prevents password exposure
- Protects user credentials

### 6.6 Encrypted Storage
**Purpose:**
- Secure local storage for sensitive data
- Protects private keys and tokens
- Uses platform-specific secure storage
- Prevents data exposure

---

## 7. DEVELOPMENT & DEPLOYMENT TOOLS

### 7.1 Git Version Control
**Purpose:**
- Source code version control
- Tracks code changes and history
- Enables collaboration
- Manages code branches and releases

### 7.2 NPM (Node Package Manager)
**Purpose:**
- Manages Node.js dependencies
- Installs and updates packages
- Handles package versioning
- Resolves dependency conflicts

### 7.3 Pub Package Manager (Dart)
**Purpose:**
- Manages Flutter/Dart dependencies
- Installs Flutter packages
- Handles package versioning
- Resolves dependency conflicts

### 7.4 Postman/Thunder Client
**Purpose:**
- API testing and development
- Tests backend endpoints
- Validates API responses
- Documents API functionality

### 7.5 MongoDB Compass
**Purpose:**
- MongoDB database management GUI
- Visualizes database collections
- Enables data inspection and editing
- Provides query interface

### 7.6 Cloudflare Tunnel (Optional)
**Purpose:**
- Exposes local server to internet
- Enables remote device testing
- Provides secure tunnel for development
- Allows testing without port forwarding

---

## 8. ARCHITECTURAL PATTERNS

### 8.1 Hybrid Storage Architecture
**Purpose:**
- Combines server (MongoDB) and local (SQLite) storage
- Enables offline functionality
- Provides data redundancy
- Supports seamless online/offline transitions

### 8.2 Distributed System Architecture
**Purpose:**
- Multiple nodes in network
- Blockchain-like node chain
- Hash chain for integrity
- Immutable data records

### 8.3 P2P Communication Architecture
**Purpose:**
- Direct device-to-device communication
- Reduces server load
- Enables offline messaging
- Provides decentralized communication

### 8.4 Service-Oriented Architecture (SOA)
**Purpose:**
- Modular service design
- Separation of concerns
- Reusable service components
- Easy maintenance and testing

### 8.5 Singleton Pattern
**Purpose:**
- Single instance of services
- Centralized service management
- Efficient resource usage
- Consistent state management

---

## 9. DATA INTEGRITY & VERIFICATION

### 9.1 Hash Chain Implementation
**Purpose:**
- Links data blocks using cryptographic hashes
- Ensures data integrity and immutability
- Detects tampering and unauthorized modifications
- Implements blockchain-like verification

### 9.2 Chain Integrity Verification
**Purpose:**
- Validates hash chain continuity
- Detects broken chains
- Ensures data consistency
- Prevents data corruption

### 9.3 Gas Calculation System
**Purpose:**
- Simulates blockchain gas fees
- Tracks transaction costs
- Implements time-based gas calculation
- Provides blockchain-like transaction metrics

---

## 10. FILE HANDLING

### 10.1 File Upload System
**Purpose:**
- Handles file uploads to server
- Stores files in MongoDB or file system
- Manages file metadata
- Supports multiple file types

### 10.2 File Download System
**Purpose:**
- Downloads files from server
- Caches files locally
- Provides offline file access
- Handles file sharing

### 10.3 File Storage
**Purpose:**
- Server-side file storage (MongoDB GridFS or file system)
- Local file caching
- File metadata management
- File access control

---

## SUMMARY

This project utilizes a comprehensive technology stack combining:
- **Frontend:** Flutter/Dart for cross-platform mobile development
- **Backend:** Node.js/Express for RESTful API server
- **Blockchain:** Ethereum/Solidity for decentralized authentication
- **Database:** MongoDB (distributed) + SQLite (local) for hybrid storage
- **Networking:** HTTP, TCP, WebSocket for various communication needs
- **Security:** 2FA, biometrics, encryption, hashing for data protection
- **Architecture:** Hybrid distributed + decentralized system with P2P capabilities

The combination of these technologies enables EtherShare to provide secure, tamper-proof, and decentralized file sharing and communication capabilities with both online and offline functionality.


