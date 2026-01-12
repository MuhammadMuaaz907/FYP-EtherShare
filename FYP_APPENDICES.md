# APPENDICES

---

## Appendix A: Project Mapping with Work Packages (WPs)

In this project, we focused on two key work packages (WPs) to ensure a structured and impactful approach:

### WP1: Blockchain Integration - Hash Chain Integrity - Security

•	Our software relies heavily on blockchain technology and cryptographic hash chain algorithms to ensure data integrity and security.
•	We use hash chain verification (SHA-256) to detect tampering and maintain blockchain-like data integrity.
•	The project demands deep understanding of cryptography, blockchain concepts, and secure data storage.

### WP6: Diverse Stakeholders

•	The project is designed with organizations, teams, and individuals as the primary audience, ensuring secure communication and file sharing.
•	It considers a broad range of user needs to create an intuitive and secure interface for workspace collaboration.
•	Stakeholders include developers, security experts, team managers, and end-users who contribute to refining the application.

### Conclusion

By aligning with these WPs, we ensure our software is technically correct, secure, and impactful for the intended audience.

---

## Appendix B: Project Mapping with Sustainable Development Goals (SDGs)

Our project contributes to the United Nations Sustainable Development Goals (SDGs) by addressing key global challenges:

### SDG-4: Quality Education

•	Our application provides secure communication and file sharing among organizations and individuals by integrating blockchain technology and hash chain algorithms to create a more secure environment.
•	It enables secure collaboration for educational institutions, allowing students and teachers to share resources safely.
•	The offline mode and P2P communication make it accessible even in areas with limited internet connectivity.

### SDG-9: Industry, Innovation and Infrastructure

•	The project fosters innovation by integrating blockchain technology, decentralized storage, and peer-to-peer communication features.
•	It contributes to resilient digital infrastructure with hybrid storage (MongoDB + SQLite) and P2P networking capabilities.
•	The hash chain integrity system demonstrates innovative application of cryptographic techniques for data security.

### Conclusion

By addressing these SDGs, our project helps create a more secure, innovative, and technologically advanced future for communication and collaboration.

---

## Appendix C: Questionnaire Used for the Survey

### Introduction

We created this survey to learn about the challenges users face when trying to communicate securely and share files in a team environment. Their feedback helped us design the "EtherShare" blockchain-based secure file sharing and communication application.

### Who Took the Survey?

•	Software developers and IT professionals
•	Team managers and project coordinators
•	Security experts and system administrators
•	End-users who require secure communication and file sharing

### Questions We Asked:

•	Do you use any secure communication tools for team collaboration?
•	How comfortable are you with blockchain-based authentication?
•	What difficulties do you face when trying to ensure data integrity in shared files?
•	Would you prefer server-based or peer-to-peer (P2P) communication for messaging?
•	What features would you like in an app that provides secure file sharing with blockchain technology?
•	How important is it for the app to provide offline functionality and data synchronization?
•	What security features (2FA, biometric authentication, hash chain integrity) are most important to you?
•	How valuable is peer-to-peer communication for reducing server dependency?

### What We Learned:

•	Most users preferred blockchain-based authentication for enhanced security.
•	Many found data integrity verification (hash chain) very important for trust.
•	Offline functionality and P2P communication were considered valuable features.
•	Two-Factor Authentication (2FA) was highly requested for additional security.
•	Real-time messaging with integrity verification was considered essential.

---

## Appendix D: Coding

### Python/Node.js Backend Implementation:

This section contains essential code snippets used for implementing the hash chain integrity system and blockchain integration for secure data storage.

### Hash Chain Implementation:

**File:** `backend/services/hashChainService.js`

```javascript
// Calculate SHA-256 hash for data integrity
static calculateHash(data) {
  return crypto.createHash('sha256').update(data).digest('hex');
}

// Add hash chain fields to documents
static async addHashFields(collection, document, filter) {
  const lastDoc = await collection.find(filter).sort({timestamp: -1}).limit(1).toArray();
  let previousHash = lastDoc.length > 0 ? lastDoc[0].current_hash : "0";
  const dataString = JSON.stringify(sortObjectKeys(document));
  const currentHash = this.calculateHash(dataString + previousHash);
  document.previous_hash = previousHash;
  document.current_hash = currentHash;
  return document;
}

// Verify chain integrity
static verifyChainIntegrity(documents) {
  let expectedHash = "0";
  for (const doc of documents) {
    if (doc.previous_hash !== expectedHash) return {valid: false};
    const calculatedHash = this.calculateHash(JSON.stringify(doc) + doc.previous_hash);
    if (calculatedHash !== doc.current_hash) return {valid: false};
    expectedHash = doc.current_hash;
  }
  return {valid: true};
}
```

### Message API Endpoint:

**File:** `backend/routes/messages.js`

```javascript
// Add message with hash chain integrity
router.post('/', async (req, res) => {
  const messageData = createMessageData(req.body);
  await HashChainService.addHashFields(messagesCollection, messageData, filter);
  await messagesCollection.insertOne(messageData);
  return res.json({success: true, data: messageData});
});

// Get messages with integrity verification
router.get('/channel/:workspaceId/:channelId', async (req, res) => {
  const messages = await messagesCollection.find(filter).sort({timestamp: 1}).toArray();
  const integrity = HashChainService.verifyChainIntegrity(messages);
  if (!integrity.valid) return res.json({success: false, chainBroken: true});
  return res.json({success: true, data: messages});
});
```

### Flutter Frontend Service:

**File:** `blockchain_fyp/lib/services/distributed_service.dart`

```dart
// Add message with hash chain
static Future<Map<String, dynamic>> addMessage({
  required String workspaceId,
  required String senderAddress,
  required String messageText,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/api/messages'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'workspaceId': workspaceId,
      'senderAddress': senderAddress,
      'messageText': messageText,
    }),
  );
  return jsonDecode(response.body);
}

// Get channel messages with integrity check
static Future<List<Map<String, dynamic>>> getChannelMessages({
  required String workspaceId,
  required String channelId,
}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/messages/channel/$workspaceId/$channelId')
  );
  final data = jsonDecode(response.body);
  if (data['chainBroken'] == true) throw ChainBrokenException('Chain integrity compromised');
  return List<Map<String, dynamic>>.from(data['data']);
}
```

### Smart Contract - User Authentication:

**File:** `contracts/UserAuth.sol`

```solidity
// Register new user on blockchain
function register() external {
  require(!users[msg.sender].isRegistered, "User already registered");
  users[msg.sender] = User({
    userAddress: msg.sender,
    isRegistered: true,
    is2FAEnabled: false,
    registrationTime: block.timestamp
  });
  emit UserRegistered(msg.sender);
}

// Login user
function login() external {
  require(users[msg.sender].isRegistered, "User not registered");
  emit UserLoggedIn(msg.sender);
}

// Enable 2FA
function enable2FA(string[] memory codes) external {
  require(users[msg.sender].isRegistered, "User not registered");
  users[msg.sender].is2FAEnabled = true;
  backupCodes[msg.sender] = codes;
  emit TwoFAEnabled(msg.sender);
}
```

### P2P Service Implementation:

**File:** `blockchain_fyp/lib/services/p2p_service.dart`

```dart
// Start P2P server for direct device-to-device communication
Future<void> startServer(String userAddress) async {
  _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
  _serverSocket!.listen((Socket socket) {
    socket.listen((data) {
      final message = jsonDecode(utf8.decode(data));
      _handleMessage(socket, message);
    });
  });
}

// Send message via P2P
Future<bool> sendMessage({
  required String receiverAddress,
  required String messageText,
}) async {
  final socket = _connections[receiverAddress];
  if (socket == null) return false;
  socket.add(utf8.encode(jsonEncode({
    'type': 'message',
    'sender_address': _myAddress,
    'receiver_address': receiverAddress,
    'message_text': messageText,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  })));
  return true;
}
```

---

## Appendix E: User Manual

### About This Guide

This guide will show you how to use the EtherShare application, which helps users communicate securely and share files using blockchain technology and hash chain integrity verification.

### What You Need

•	An Android phone or tablet (Android 6.0 or newer) or iOS device (iOS 12.0 or newer)
•	Internet connection (for initial setup and online features)
•	MetaMask or compatible Web3 wallet (for blockchain authentication)

### How to Install the App

1.	Download the app from the Google Play Store or App Store.
2.	Allow necessary permissions (storage, network access, camera for file sharing).
3.	Open the app and connect your wallet (MetaMask recommended).
4.	Register your account on the blockchain and create your profile.

### How to Use the App

#### Opening the App

•	When you open the app, connect your wallet (MetaMask) for blockchain authentication.
•	If you're new, register your Ethereum address on the blockchain.
•	Complete your profile setup (username, email, optional 2FA).

#### Creating a Workspace

•	Tap the "+" button or "Create Workspace" option.
•	Enter workspace name and description.
•	Confirm the transaction in your wallet.
•	Your workspace is created with hash chain integrity.

#### Creating and Joining Channels

•	Open a workspace and tap "+" next to "Channels".
•	Enter channel name and select type (Public or Private).
•	To join a channel, tap on it (public) or accept invite (private).

#### Sending Messages

•	Open a channel or direct message.
•	Type your message in the input field.
•	Tap send button.
•	Message is stored with hash chain integrity verification.

#### Sharing Files

•	Tap attachment icon (paperclip) in message input.
•	Select file from gallery, files, or camera.
•	Add optional message and tap send.
•	File uploads securely and is shared with hash chain verification.

#### Using Offline Mode

•	When internet connection is lost, app automatically switches to offline mode.
•	View previously loaded messages and cached files.
•	Compose messages (they queue for sync when online).
•	Use P2P communication if on same network with other users.

#### Enabling 2FA (Two-Factor Authentication)

•	Go to Settings > Security > Enable 2FA.
•	Choose method: Email OTP, TOTP (authenticator app), or Biometric.
•	Complete setup and save backup codes securely.
•	Use 2FA code or biometric when logging in.

### Troubleshooting & FAQs

#### What if I cannot connect my wallet?

•	Make sure MetaMask or your wallet app is installed and unlocked.
•	Try disconnecting and reconnecting the wallet.
•	Restart the application and try again.

#### What if messages are not sending?

•	Check your internet connection.
•	Verify you are a member of the workspace/channel.
•	Try refreshing the channel or restarting the app.

#### What if I see "Chain Broken" error?

•	This indicates data integrity has been compromised.
•	Messages in broken chain are hidden for security.
•	Contact workspace administrator for assistance.

#### What if P2P communication is not working?

•	Verify both users are on the same network (WiFi/LAN).
•	Check P2P is enabled in Settings > P2P Settings.
•	Check firewall settings on your device.
•	Use server-based messaging as alternative.

#### What if files are not uploading?

•	Check file size (may be too large).
•	Verify file type is supported.
•	Check internet connection and try again.

#### How do I enable offline mode?

•	Offline mode activates automatically when internet is unavailable.
•	Previously loaded messages and files are accessible.
•	New messages queue for sync when connection is restored.
