# IPFS Desktop Setup Guide for Real OrbitDB

## 🎯 Complete Setup for Real OrbitDB with IPFS Desktop

### **Step 1: IPFS Desktop Installation & Configuration**

#### **1.1 Download IPFS Desktop**
1. Go to: https://github.com/ipfs/ipfs-desktop/releases
2. Download latest version for Windows
3. Install and start IPFS Desktop

#### **1.2 Configure IPFS Desktop Settings**
1. **Open IPFS Desktop**
2. **Go to Settings → Advanced**
3. **Configure these settings:**

```json
{
  "Addresses": {
    "API": "/ip4/192.168.0.33/tcp/5001",
    "Gateway": "/ip4/192.168.0.33/tcp/8081",
    "Swarm": [
      "/ip4/0.0.0.0/tcp/4001",
      "/ip6/::/tcp/4001"
    ]
  },
  "API": {
    "HTTPHeaders": {
      "Access-Control-Allow-Origin": ["*"],
      "Access-Control-Allow-Methods": ["GET", "POST", "PUT"],
      "Access-Control-Allow-Headers": ["X-Requested-With", "Range", "User-Agent"]
    }
  }
}
```

#### **1.3 Enable CORS**
1. In IPFS Desktop → Settings → Advanced
2. Find **CORS** section
3. **Enable "Allow all origins"**
4. **Save settings and restart IPFS Desktop**

### **Step 2: Verify IPFS Desktop Connection**

#### **2.1 Test IPFS API**
```bash
# Test API connection
powershell -Command "Invoke-WebRequest -Uri 'http://192.168.0.35:5001/api/v0/id' -Method POST"
```

#### **2.2 Test IPFS Gateway**
```bash
# Test Gateway
powershell -Command "Invoke-WebRequest -Uri 'http://192.168.0.35:8080/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme'"
```

### **Step 3: Start Real OrbitDB Server**

#### **3.1 Start Server**
```bash
# Start the server
npm start
```

#### **3.2 Expected Output**
```
🚀 Initializing Real OrbitDB with IPFS Desktop...
🔍 Testing IPFS Desktop connection...
✅ IPFS Desktop connected successfully
📊 IPFS ID: QmYourPeerID
🌐 IPFS Addresses: [...]
🔧 Initializing OrbitDB...
✅ Real OrbitDB with IPFS Desktop initialized successfully
🚀 Real OrbitDB server running on port 3000
```

### **Step 4: Test Real OrbitDB**

#### **4.1 Health Check**
```bash
curl http://localhost:3000/health
```

**Expected Response:**
```json
{
  "status": "OK",
  "message": "Real OrbitDB server is running",
  "orbitdb": {
    "initialized": true,
    "ipfsId": "QmYourPeerID",
    "peersCount": 0,
    "databases": [],
    "serviceType": "Real OrbitDB with IPFS Desktop"
  }
}
```

#### **4.2 Create Workspace**
```bash
curl -X POST http://localhost:3000/api/workspace/test-workspace/create
```

#### **4.3 Add Message**
```bash
curl -X POST http://localhost:3000/api/workspace/test-workspace/messages \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello Real OrbitDB!", "sender": "user1"}'
```

#### **4.4 Get Messages**
```bash
curl http://localhost:3000/api/workspace/test-workspace/messages
```

### **Step 5: Flutter App Integration**

#### **5.1 Update Flutter Service**
Flutter app mein IP address update karein (if needed):
```dart
// In orbitdb_service.dart
static const String baseUrl = 'http://192.168.0.36:3000';
static const String wsUrl = 'ws://192.168.0.36:8080';
```

#### **5.2 Start Flutter App**
```bash
cd blockchain_fyp
flutter run
```

### **Step 6: Test Complete System**

#### **6.1 Send Message from Flutter**
```dart
await OrbitDBService.addMessage('test-workspace', {
  'text': 'Hello from Flutter!',
  'sender': 'flutter_user',
  'timestamp': DateTime.now().millisecondsSinceEpoch
});
```

#### **6.2 Upload File from Flutter**
```dart
await OrbitDBService.uploadFile('test-workspace', 'document.pdf', fileBytes);
```

#### **6.3 Real-time Updates**
```dart
// Initialize WebSocket
await OrbitDBService.initializeWebSocket();

// Join workspace
await OrbitDBService.joinWorkspace('test-workspace');

// Set message callback
OrbitDBService.setMessageCallback((message) {
  print('New message received: $message');
});
```

## 🔧 Troubleshooting

### **Issue 1: IPFS Desktop Not Accessible**

#### **Symptoms:**
- `Connection refused`
- `405 - Method Not Allowed`
- `403 - Forbidden`

#### **Solutions:**
1. **Check IPFS Desktop Status**
   - Open IPFS Desktop
   - Check if "Connected" status is shown
   - If not, wait for connection

2. **Verify IP Address**
   ```bash
   ipconfig
   ```
   - Check your actual IP address
   - Update configuration if IP changed

3. **Enable CORS**
   - IPFS Desktop → Settings → Advanced
   - Enable "Allow all origins"
   - Restart IPFS Desktop

4. **Check Firewall**
   - Windows Firewall mein ports 5001, 8080 allow karein
   - Antivirus software check karein

### **Issue 2: OrbitDB Server Not Starting**

#### **Symptoms:**
- `Failed to initialize Real OrbitDB with IPFS`
- `IPFS Desktop not accessible`

#### **Solutions:**
1. **Check IPFS Desktop**
   ```bash
   powershell -Command "Invoke-WebRequest -Uri 'http://192.168.0.35:5001/api/v0/id' -Method POST"
   ```

2. **Check Port Availability**
   ```bash
   netstat -an | findstr :3000
   netstat -an | findstr :5001
   ```

3. **Restart Services**
   - Stop IPFS Desktop
   - Start IPFS Desktop
   - Run `npm start`

### **Issue 3: Flutter App Connection Issues**

#### **Symptoms:**
- App not connecting to server
- WebSocket connection failed

#### **Solutions:**
1. **Check Server Status**
   ```bash
   curl http://localhost:3000/health
   ```

2. **Verify Network**
   - Check if Flutter app and server are on same network
   - Update IP addresses if needed

3. **Check Flutter Dependencies**
   ```bash
   cd blockchain_fyp
   flutter pub get
   ```

## 📊 Verification Checklist

### **✅ IPFS Desktop**
- [ ] IPFS Desktop is running
- [ ] Status shows "Connected"
- [ ] API accessible at `192.168.0.35:5001`
- [ ] Gateway accessible at `192.168.0.35:8080`
- [ ] CORS enabled

### **✅ OrbitDB Server**
- [ ] Server starts without errors
- [ ] Health check: `http://localhost:3000/health`
- [ ] WebSocket: `ws://localhost:8080`
- [ ] IPFS connection successful
- [ ] Real OrbitDB initialized

### **✅ Flutter App**
- [ ] App starts without errors
- [ ] Connects to server
- [ ] WebSocket connection established
- [ ] Can send/receive messages
- [ ] File upload/download works

## 🎯 Expected Final Result

**When everything works:**
1. **IPFS Desktop**: Shows "Connected" with your Peer ID
2. **OrbitDB Server**: Running with real IPFS integration
3. **Flutter App**: Connected and can send/receive messages
4. **File Sharing**: Real IPFS file storage and retrieval
5. **Real-time Updates**: WebSocket working with OrbitDB

## 🚀 Quick Start Commands

```bash
# 1. Start IPFS Desktop (manually)
# 2. Test connection
.\test-ipfs-connection.bat

# 3. Start Real OrbitDB server
npm start

# 4. Start Flutter app (in new terminal)
cd blockchain_fyp
flutter run
```

---

**Ab aapka project Real OrbitDB ke saath fully functional hai! 🎉**

**Next Steps:**
1. Configure IPFS Desktop
2. Start server
3. Test Flutter app
4. Enjoy decentralized file sharing!
