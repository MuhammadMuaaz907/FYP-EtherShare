# 🌐 Decentralized P2P System - Implementation Guide

## ✅ Implementation Complete

The decentralized P2P system has been successfully implemented with the following components:

### **1. SQLite Service** (`lib/services/sqlite_service.dart`)
- ✅ Local database with all tables (users, workspaces, messages, members, files, peers)
- ✅ Chain integrity support (previous_hash, current_hash)
- ✅ Full CRUD operations matching MongoDB interface
- ✅ Offline-first storage

### **2. P2P Service** (`lib/services/p2p_service.dart`)
- ✅ TCP server (listens for incoming connections)
- ✅ TCP client (connects to other devices)
- ✅ Direct device-to-device messaging
- ✅ Peer connection management
- ✅ Message acknowledgment system
- ✅ Ping/pong heartbeat

### **3. Hybrid Storage Service** (`lib/services/hybrid_storage_service.dart`)
- ✅ Dual storage: SQLite (local) + MongoDB (server)
- ✅ Automatic sync when server is online
- ✅ Offline mode support
- ✅ P2P messaging integration
- ✅ Background sync timer

---

## 🚀 How to Use

### **Step 1: Initialize Hybrid Storage**

After user logs in, initialize the hybrid storage service:

```dart
import 'services/hybrid_storage_service.dart';

// After user login, get user address
final userAddress = '0x...'; // User's wallet address

// Initialize hybrid storage
await HybridStorageService.instance.initialize(
  userAddress: userAddress,
);
```

### **Step 2: Use Hybrid Storage Instead of DistributedService**

Replace `DistributedService` calls with `HybridStorageService`:

#### **Before:**
```dart
// Save profile
await DistributedService.saveUserProfile(
  address: address,
  username: username,
  email: email,
);

// Send message
await DistributedService.addMessage(
  workspaceId: workspaceId,
  senderAddress: senderAddress,
  receiverAddress: receiverAddress,
  messageText: messageText,
);
```

#### **After:**
```dart
// Save profile (works offline too!)
await HybridStorageService.instance.saveUserProfile(
  address: address,
  username: username,
  email: email,
);

// Send message (tries P2P first, then server)
await HybridStorageService.instance.addMessage(
  workspaceId: workspaceId,
  senderAddress: senderAddress,
  receiverAddress: receiverAddress,
  messageText: messageText,
);
```

### **Step 3: Connect to Peers**

#### **Method 1: Connect by IP Address**
```dart
await HybridStorageService.instance.connectToPeer(
  ipAddress: '192.168.1.2',
  port: 8080,
  userAddress: '0x...', // Optional
);
```

#### **Method 2: Connect by User Address**
```dart
// First, save peer info
await HybridStorageService.instance.savePeer(
  userAddress: '0x...',
  ipAddress: '192.168.1.2',
  port: 8080,
);

// Then connect
await HybridStorageService.instance.connectToPeerByAddress('0x...');
```

### **Step 4: Get P2P Info**

Display your P2P connection info to share with others:

```dart
final p2pInfo = HybridStorageService.instance.getMyP2PInfo();
if (p2pInfo != null) {
  print('My IP: ${p2pInfo['ip_address']}');
  print('My Port: ${p2pInfo['port']}');
  print('My Address: ${p2pInfo['user_address']}');
  
  // Share this info with other users via QR code or manual entry
}
```

---

## 📱 Example: Direct Messaging Flow

### **UserA (192.168.1.1) wants to message UserB (192.168.1.2)**

1. **UserA saves UserB's peer info:**
```dart
await HybridStorageService.instance.savePeer(
  userAddress: '0xUserB...',
  ipAddress: '192.168.1.2',
  port: 8080,
);
```

2. **UserA sends message:**
```dart
await HybridStorageService.instance.addMessage(
  workspaceId: '',
  senderAddress: '0xUserA...',
  receiverAddress: '0xUserB...',
  messageText: 'Hello UserB!',
);
```

3. **System automatically:**
   - Saves to SQLite (local)
   - Tries P2P connection to UserB
   - Sends message via TCP
   - If server online, syncs to MongoDB

4. **UserB receives message:**
   - Message arrives via TCP
   - Saved to SQLite automatically
   - If server online, synced to MongoDB

---

## 🔧 Integration Points

### **Update main.dart**

Add hybrid storage initialization after user login:

```dart
// In login_screen.dart or after successful login
final userAddress = '0x...'; // Get from login

// Initialize hybrid storage
await HybridStorageService.instance.initialize(
  userAddress: userAddress,
);
```

### **Update Pages Using DistributedService**

Replace in these files:
- `lib/ProfileSetup.dart`
- `lib/direct_message_page.dart`
- `lib/channel_page.dart`
- `lib/workspace_home_page.dart`
- `lib/workspace_preview_page.dart`

Change:
```dart
// OLD
import 'services/distributed_service.dart';
DistributedService.saveUserProfile(...)

// NEW
import 'services/hybrid_storage_service.dart';
HybridStorageService.instance.saveUserProfile(...)
```

---

## 🌐 Network Configuration

### **Local Network (LAN)**
- Devices on same WiFi network
- Use local IP addresses (192.168.x.x)
- Port 8080 (default, configurable)

### **Internet (Future)**
- Requires NAT traversal
- May need relay server
- Currently supports LAN only

---

## 📊 How It Works

### **Online Mode (Server Available)**
```
UserA → SQLite (local) → MongoDB (server)
UserA → P2P TCP → UserB → SQLite (local) → MongoDB (server)
```

### **Offline Mode (Server Down)**
```
UserA → SQLite (local)
UserA → P2P TCP → UserB → SQLite (local)
(Sync to MongoDB when server comes back online)
```

---

## ✅ Testing

### **Test 1: Offline Messaging**
1. Turn off backend server
2. UserA and UserB on same network
3. UserA sends message to UserB
4. Message should arrive via P2P
5. Check SQLite database

### **Test 2: Sync**
1. Send messages while offline
2. Turn on backend server
3. Wait 30 seconds (sync timer)
4. Check MongoDB for synced messages

### **Test 3: Peer Discovery**
1. UserA starts app
2. UserB starts app
3. UserA connects to UserB by IP
4. Verify connection status

---

## 🐛 Troubleshooting

### **P2P Connection Fails**
- Check firewall settings (port 8080)
- Verify devices on same network
- Check IP addresses are correct
- Ensure P2P server is running

### **Messages Not Syncing**
- Check server is online: `HybridStorageService.instance.isServerOnline()`
- Check sync timer is running
- Check SQLite for unsynced messages

### **SQLite Errors**
- Check database path permissions
- Verify sqflite package installed
- Check database version

---

## 📝 Next Steps

1. ✅ **Update UI Pages** - Replace DistributedService with HybridStorageService
2. ✅ **Add Peer Discovery UI** - Show connected peers
3. ✅ **Add QR Code Sharing** - Share P2P info via QR
4. ✅ **Add Connection Status** - Show online/offline status
5. ✅ **Test on Real Devices** - Test P2P on actual devices

---

## 🎯 Key Features

- ✅ **Offline Support** - Works without server
- ✅ **P2P Messaging** - Direct device-to-device
- ✅ **Auto Sync** - Syncs when server available
- ✅ **Chain Integrity** - Maintains blockchain-like chain
- ✅ **Peer Management** - Track and connect to peers
- ✅ **Dual Storage** - SQLite + MongoDB

---

**Status:** ✅ Ready for Integration
**Next:** Update UI pages to use HybridStorageService

