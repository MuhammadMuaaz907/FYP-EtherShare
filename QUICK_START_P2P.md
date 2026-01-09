# 🚀 Quick Start: Decentralized P2P System

## ✅ **What's Been Implemented**

1. ✅ **SQLite Database** - Local storage (works offline)
2. ✅ **TCP P2P Server/Client** - Direct device-to-device communication
3. ✅ **Hybrid Storage** - SQLite + MongoDB sync

---

## 🎯 **Quick Setup**

### **1. Install Dependencies**
```bash
cd blockchain_fyp
flutter pub get
```

### **2. Initialize After User Login**

Add this to your login screen after successful login:

```dart
import 'services/hybrid_storage_service.dart';

// After user logs in (get userAddress from login)
await HybridStorageService.instance.initialize(
  userAddress: userAddress, // e.g., '0x1234...'
);
```

### **3. Use Hybrid Storage**

Replace `DistributedService` with `HybridStorageService`:

```dart
// OLD
import 'services/distributed_service.dart';
await DistributedService.saveUserProfile(...);

// NEW
import 'services/hybrid_storage_service.dart';
await HybridStorageService.instance.saveUserProfile(...);
```

---

## 📱 **Example: Direct Messaging**

### **UserA (192.168.1.1) → UserB (192.168.1.2)**

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
  messageText: 'Hello!',
);
```

3. **Message automatically:**
   - ✅ Saved to SQLite (local)
   - ✅ Sent via P2P TCP to UserB
   - ✅ Synced to MongoDB (if server online)

---

## 🔍 **Check P2P Status**

```dart
// Get your P2P info
final p2pInfo = HybridStorageService.instance.getMyP2PInfo();
print('My IP: ${p2pInfo?['ip_address']}');
print('My Port: ${p2pInfo?['port']}');

// Check server status
final isOnline = HybridStorageService.instance.isServerOnline();
print('Server: ${isOnline ? "Online" : "Offline"}');
```

---

## ✅ **Testing**

### **Test 1: Offline Messaging**
1. Turn off backend server
2. UserA and UserB on same WiFi
3. UserA sends message to UserB
4. ✅ Message should arrive via P2P

### **Test 2: Sync**
1. Send messages while offline
2. Turn on backend server
3. Wait 30 seconds
4. ✅ Messages should sync to MongoDB

---

## 📚 **Full Documentation**

- `DECENTRALIZED_P2P_ACTION_PLAN.md` - Complete plan
- `DECENTRALIZED_P2P_IMPLEMENTATION_GUIDE.md` - Detailed guide
- `DECENTRALIZED_P2P_SUMMARY.md` - Summary

---

**Ready to use!** 🎉

