# Technologies Used and Their Purpose - FYP Report

## Table Format for FYP Report

| Technology | Version | Purpose |
|------------|---------|---------|
| **FRONTEND TECHNOLOGIES** | | |
| Flutter Framework | SDK >=2.19.0 | Cross-platform mobile application development framework enabling single codebase for Android, iOS, Web, Windows, Linux, and macOS |
| Dart Programming Language | 2.19.0+ | Primary programming language for Flutter application with strong typing and async/await support |
| Provider | ^6.0.5 | State management solution for managing application-wide state and reactive UI updates |
| Web3Dart | ^2.7.2 | Ethereum blockchain integration library for connecting to Ethereum network and interacting with smart contracts |
| WalletConnect Flutter V2 | ^2.2.5 | Cryptocurrency wallet connectivity for secure wallet-based authentication |
| HTTP | ^1.2.2 | HTTP client for making REST API calls to backend server |
| Dio | ^5.8.0+1 | Advanced HTTP client with interceptors, file uploads, and better error handling |
| File Picker | ^8.0.7 | Enables users to select files from device storage |
| Image Picker | ^1.0.7 | Allows users to capture or select images from camera/gallery |
| Shared Preferences | ^2.3.2 | Local key-value storage for user preferences and settings |
| SQLite (sqflite) | ^2.3.0 | Local relational database for offline data storage and P2P message synchronization |
| Flutter Secure Storage | ^9.0.0 | Encrypted local storage for sensitive data like private keys and authentication tokens |
| Local Auth | ^2.1.7 | Biometric authentication (fingerprint, face recognition) for additional security |
| Crypto | ^3.0.3 | Cryptographic functions for SHA-256 hashing and secure random number generation |
| OTP | ^3.2.0 | Time-based One-Time Password (TOTP) generation for 2FA authentication |
| Mailer | ^6.0.1 | Email sending functionality for OTP codes via email |
| Connectivity Plus | ^5.0.2 | Network connectivity monitoring for detecting online/offline status |
| Mongo Dart | ^0.10.3 | Direct MongoDB connection from Flutter (optional alternative to HTTP API) |
| Path Provider | ^2.1.2 | Access to device file system paths for file storage management |
| Open File | ^3.3.2 | Opens files with default system applications |
| Share Plus | ^7.2.1 | Native sharing functionality for files, messages, or links |
| URL Launcher | ^6.3.0 | Opens URLs in browser or external apps |
| Record | ^5.1.2 | Audio recording functionality for voice messages |
| Audio Players | ^6.0.0 | Plays audio files and voice messages |
| Permission Handler | ^11.3.1 | Manages runtime permissions for camera, storage, microphone |
| Flutter Dotenv | ^5.1.0 | Environment variable management for configuration and API keys |
| App Links | ^3.4.2 | Deep linking support for custom URL schemes |
| Get It | ^7.7.0 | Dependency injection container for service management |
| UUID | ^4.2.1 | Generates unique identifiers for messages, workspaces, channels |
| Hex | ^0.2.0 | Hexadecimal encoding/decoding for blockchain addresses and hashes |
| **BACKEND TECHNOLOGIES** | | |
| Node.js | Latest | JavaScript runtime environment for server-side development with asynchronous, event-driven architecture |
| Express.js | ^4.18.2 | Web application framework for creating RESTful API endpoints and handling HTTP requests |
| MongoDB | Latest | NoSQL document database for distributed data storage with horizontal scalability |
| Mongoose | ^8.0.3 | Object Data Modeling library for MongoDB with schema definition and validation |
| Web3.js | ^4.16.0 | Ethereum JavaScript library for backend blockchain interaction and transaction validation |
| WebSocket (ws) | ^8.17.1 | Real-time bidirectional communication for P2P messaging and live updates |
| CORS | ^2.8.5 | Cross-Origin Resource Sharing middleware for secure cross-domain communication |
| Multer | ^1.4.5-lts.1 | File upload middleware for handling multipart/form-data file uploads |
| JSON Web Token | ^9.0.2 | Stateless authentication mechanism for securing API endpoints |
| Bcrypt.js | ^2.4.3 | Password hashing library for secure password storage with salt rounds |
| Express Validator | ^7.0.1 | Request validation middleware for input data validation and sanitization |
| Joi | ^17.11.0 | Schema validation library for complex data structure validation |
| UUID | ^10.0.0 | Generates unique identifiers for database records |
| Dotenv | ^16.3.1 | Environment variable management for configuration and sensitive data |
| Nodemon | ^3.0.2 | Development tool for automatic server restart on file changes |
| Net Module | ^1.0.2 | TCP networking module for P2P communication and direct node-to-node connections |
| **BLOCKCHAIN TECHNOLOGIES** | | |
| Ethereum Blockchain | Latest | Decentralized blockchain platform for smart contracts and immutable ledger |
| Solidity | ^0.8.0 | Smart contract programming language for implementing blockchain-based authentication |
| Truffle Framework | Latest | Development framework for Ethereum smart contracts compilation, deployment, and testing |
| Ganache | Latest | Local Ethereum blockchain for development and testing with pre-funded test accounts |
| Smart Contract (UserAuth.sol) | v2 | Blockchain-based user authentication contract with 2FA functionality and rate limiting |
| Web3 Integration | Latest | Connects application to Ethereum network for smart contract interaction |
| **DATABASE TECHNOLOGIES** | | |
| MongoDB | Latest | Primary distributed database storing users, workspaces, channels, messages, files with hash chains |
| SQLite (sqflite) | ^2.3.0 | Local relational database for mobile devices enabling offline functionality |
| **NETWORKING & COMMUNICATION** | | |
| HTTP/HTTPS Protocol | - | RESTful API communication between frontend and backend |
| TCP/IP Protocol | - | Direct peer-to-peer communication for device-to-device messaging |
| WebSocket Protocol | - | Real-time bidirectional communication for live updates |
| P2P Architecture | - | Direct device-to-device communication enabling offline messaging |
| **SECURITY TECHNOLOGIES** | | |
| Two-Factor Authentication (2FA) | - | Additional security layer with TOTP and backup codes |
| Biometric Authentication | - | Fingerprint and face recognition using device-native APIs |
| SHA-256 Hashing | - | Cryptographic hashing for hash chains and data integrity |
| JWT Tokens | - | Stateless authentication tokens for API security |
| Bcrypt Hashing | - | Secure password storage with salt rounds |
| Encrypted Storage | - | Secure local storage for sensitive data using platform-specific secure storage |
| **DEVELOPMENT TOOLS** | | |
| Git | Latest | Source code version control and collaboration |
| NPM | Latest | Node.js package manager for dependency management |
| Pub | Latest | Dart/Flutter package manager for dependency management |
| Postman/Thunder Client | Latest | API testing and development tool |
| MongoDB Compass | Latest | MongoDB database management GUI |
| Cloudflare Tunnel | Latest | Exposes local server to internet for remote testing |

---

## Detailed Technology Categories

### 1. Frontend Development Stack
The frontend is built using **Flutter** and **Dart**, providing a cross-platform solution that runs on multiple operating systems. The application uses **Provider** for state management, **Web3Dart** for blockchain integration, and various packages for file handling, authentication, and local storage.

### 2. Backend Development Stack
The backend is built using **Node.js** with **Express.js** framework, providing RESTful API endpoints. **MongoDB** with **Mongoose** is used for distributed data storage, while **Web3.js** enables blockchain interaction from the server side.

### 3. Blockchain Integration
The system integrates with **Ethereum blockchain** using **Solidity** smart contracts. **Truffle** framework is used for contract development, and **Ganache** provides a local blockchain for testing. The **UserAuth** smart contract handles blockchain-based authentication.

### 4. Database Architecture
The system uses a **hybrid database approach**: **MongoDB** for distributed server-side storage and **SQLite** for local mobile device storage. This enables both online and offline functionality.

### 5. Networking Architecture
The system implements multiple networking protocols: **HTTP** for RESTful API communication, **TCP/IP** for P2P direct communication, and **WebSocket** for real-time updates.

### 6. Security Implementation
Security is implemented through multiple layers: **2FA** with TOTP, **biometric authentication**, **JWT tokens**, **password hashing** with Bcrypt, **encrypted storage**, and **SHA-256 hash chains** for data integrity.

---

## Technology Selection Justification

1. **Flutter** was chosen for cross-platform development, reducing development time and maintenance costs while providing native performance.

2. **Node.js/Express** was selected for the backend due to JavaScript's ubiquity, excellent async capabilities, and rich ecosystem of packages.

3. **MongoDB** was chosen for its flexibility in handling document-based data, horizontal scalability, and suitability for distributed systems.

4. **Ethereum/Solidity** was selected for blockchain integration due to its maturity, extensive tooling, and smart contract capabilities.

5. **SQLite** was chosen for local storage due to its lightweight nature, reliability, and excellent Flutter support.

6. **Hybrid Architecture** (MongoDB + SQLite) enables both online and offline functionality, providing a seamless user experience.

7. **P2P Communication** reduces server dependency and enables decentralized communication, aligning with blockchain principles.

---

## System Architecture Summary

The EtherShare system combines:
- **Distributed System**: MongoDB-based server with blockchain-like hash chains
- **Decentralized System**: P2P communication with local SQLite storage
- **Blockchain Integration**: Ethereum smart contracts for authentication
- **Hybrid Storage**: Server (MongoDB) + Local (SQLite) for online/offline support

This architecture provides security, reliability, and flexibility for secure file sharing and communication.


