# 📱 Two Device Setup Guide - MobileA to MobileB Communication

## 🎯 **Goal:**
Enable smooth communication between MobileA and MobileB, both when server is ON and OFF.

---

## ✅ **What's Fixed:**

1. ✅ **HybridStorageService auto-initializes** after login
2. ✅ **P2P server starts automatically** on port 8080
3. ✅ **Peer connections tracked** by user address
4. ✅ **Auto-connects** when sending messages
5. ✅ **Works offline** - no server needed for P2P

---

## 📋 **Step-by-Step Setup:**

### **Step 1: Get Device IP Addresses**

**On MobileA:**
1. Connect to same WiFi network as MobileB
2. Open app and login
3. Check logs for: `✅ P2P TCP server started on [IP]:8080`
4. Note your IP address (e.g., `192.168.1.1`)

**On MobileB:**
1. Connect to same WiFi network as MobileA
2. Open app and login
3. Check logs for: `✅ P2P TCP server started on [IP]:8080`
4. Note your IP address (e.g., `192.168.1.2`)

---

### **Step 2: Share Peer Information**

**Option A: Manual Entry (Current)**
- MobileA user: Note MobileB's IP (192.168.1.2)
- MobileB user: Note MobileA's IP (192.168.1.1)

**Option B: Automatic (Future Enhancement)**
- System will auto-discover peers from server
- QR code sharing for peer info

---

### **Step 3: Add Peer Information**

**On MobileA:**
```dart
// This happens automatically when sending message
// But you can also manually add:
await HybridStorageService.instance.savePeer(
  userAddress: '0xMobileB...', // MobileB's wallet address
  ipAddress: '192.168.1.2',    // MobileB's IP
  port: 8080,
);
```

**On MobileB:**
```dart
await HybridStorageService.instance.savePeer(
  userAddress: '0xMobileA...', // MobileA's wallet address
  ipAddress: '192.168.1.1',    // MobileA's IP
  port: 8080,
);
```

---

### **Step 4: Send Messages**

**MobileA sends to MobileB:**
1. Open direct message with MobileB user
2. Type message and send
3. System automatically:
   - Checks SQLite for MobileB's peer info
   - Connects to MobileB (192.168.1.2:8080)
   - Sends message via P2P TCP
   - Saves to SQLite
   - Syncs to MongoDB (if server online)

**MobileB receives:**
1. Message arrives via P2P TCP
2. Saved to SQLite automatically
3. Displayed in UI
4. Synced to MongoDB (if server online)

---

## 🔄 **How It Works:**

### **When Server is ON:**
```
MobileA → Message → SQLite (local)
                → P2P TCP → MobileB → SQLite (local)
                → MongoDB (server) → Sync
```

### **When Server is OFF:**
```
MobileA → Message → SQLite (local)
                → P2P TCP → MobileB → SQLite (local)
                → Queue for sync (when server back)
```

---

## 🧪 **Testing Scenarios:**

### **Test 1: Server ON - First Message**
1. ✅ Start backend server
2. ✅ MobileA and MobileB login
3. ✅ MobileA sends first message to MobileB
4. ✅ System auto-connects and sends via P2P
5. ✅ Message arrives on MobileB
6. ✅ Message synced to MongoDB

### **Test 2: Server OFF - Communication**
1. ✅ Turn off backend server
2. ✅ MobileA and MobileB login
3. ✅ MobileA sends message to MobileB
4. ✅ Message arrives via P2P (no server needed!)
5. ✅ Message saved to SQLite on both devices
6. ✅ Turn on server - messages sync automatically

### **Test 3: Old Messages Display**
1. ✅ Turn off backend server
2. ✅ MobileA opens chat with MobileB
3. ✅ Should see old messages from SQLite
4. ✅ Can send new messages via P2P

---

## 🐛 **Troubleshooting:**

### **Issue: Messages not arriving**
**Check:**
1. ✅ Both devices on same WiFi network
2. ✅ P2P server started (check logs)
3. ✅ IP addresses correct
4. ✅ Firewall allows port 8080
5. ✅ Peer info saved in SQLite

**Solution:**
```dart
// Check P2P status
final p2pInfo = HybridStorageService.instance.getMyP2PInfo();
print('My IP: ${p2pInfo?['ip_address']}');
print('My Port: ${p2pInfo?['port']}');

// Check peer info
final peer = await HybridStorageService.instance.getPeer('0xMobileB...');
print('Peer IP: ${peer?['ip_address']}');
print('Peer Port: ${peer?['port']}');
```

### **Issue: Connection fails**
**Check:**
1. ✅ IP addresses are correct
2. ✅ Port 8080 is not blocked
3. ✅ Devices on same network
4. ✅ P2P server is running

**Solution:**
- Try manual connection:
```dart
await HybridStorageService.instance.connectToPeer(
  ipAddress: '192.168.1.2',
  port: 8080,
  userAddress: '0xMobileB...',
);
```

---

## 📊 **Logs to Check:**

**On MobileA:**
```
✅ Hybrid Storage initialized - P2P ready
✅ P2P TCP server started on 192.168.1.1:8080
🔗 Connecting to peer: 192.168.1.2:8080
✅ Connected to peer: 192.168.1.2:8080
📤 Sending message to 0xMobileB... via peerId: 192.168.1.2:8080
✅ Message sent via P2P to 0xMobileB...
```

**On MobileB:**
```
✅ Hybrid Storage initialized - P2P ready
✅ P2P TCP server started on 192.168.1.2:8080
📡 New P2P connection: 192.168.1.1:xxxxx
✅ Handshake completed with 0xMobileA...
📨 Received P2P message from 192.168.1.1:xxxxx: message
✅ Message received and saved: [message_id]
```

---

## ✅ **Status: READY**

All fixes applied:
- ✅ Auto-initialization after login
- ✅ Peer connection tracking
- ✅ Auto-connect on message send
- ✅ Works server ON/OFF
- ✅ Old messages display from SQLite

**Ready to test with your two devices!** 🚀

---

## 💡 **Quick Test:**

1. **MobileA:** Login → Note IP (e.g., 192.168.1.1)
2. **MobileB:** Login → Note IP (e.g., 192.168.1.2)
3. **MobileA:** Send message to MobileB
4. **Result:** Message should arrive via P2P! ✅

