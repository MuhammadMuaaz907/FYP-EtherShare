# Complete Setup Guide - Real OrbitDB with IPFS Desktop

## 🚨 Error Analysis & Solutions

### **Problem 1: PowerShell Command Execution**
**Error**: `test-ipfs-connection.bat : The term 'test-ipfs-connection.bat' is not recognized`

**Solution**: PowerShell mein current directory se scripts run karne ke liye `.\` prefix use karna zaroori hai.

### **Problem 2: IPFS API Access Issues**
**Error**: `405 - Method Not Allowed` aur `403 - Forbidden`

**Solution**: IPFS Desktop mein CORS settings enable karni hongi aur proper API access configure karna hoga.

---

## 🛠️ Complete Step-by-Step Setup

### **Step 1: IPFS Desktop Configuration**

#### **1.1 Download & Install IPFS Desktop**
1. Go to: https://github.com/ipfs/ipfs-desktop/releases
2. Download latest version for Windows
3. Install and start IPFS Desktop

#### **1.2 Configure IPFS Desktop Settings**
1. Open IPFS Desktop
2. Go to **Settings** → **Advanced**
3. Configure these settings:

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

#### **1.3 Enable CORS in IPFS Desktop**
1. In IPFS Desktop, go to **Settings** → **Advanced**
2. Find **CORS** section
3. Enable **Allow all origins**
4. Save settings and restart IPFS Desktop

### **Step 2: Project Setup**

#### **2.1 Install Dependencies**
```bash
# In project directory
npm install
```

#### **2.2 Test IPFS Connection**
```bash
# Windows PowerShell
.\test-ipfs-connection.bat

# Or manually test
Invoke-WebRequest -Uri "http://192.168.0.33:5001/api/v0/id" -Method POST
```

#### **2.3 Start OrbitDB Server**
```bash
# Windows PowerShell
.\start-with-ipfs-desktop.bat

# Or manually
npm start
```

### **Step 3: Flutter App Setup**

#### **3.1 Update Flutter Dependencies**
```bash
cd blockchain_fyp
flutter pub get
```

#### **3.2 Configure Flutter App**
Flutter app mein IP address update karein (if needed):
```dart
// In orbitdb_service.dart
static const String baseUrl = 'http://192.168.0.36:3000';
static const String wsUrl = 'ws://192.168.0.36:8080';
```

#### **3.3 Start Flutter App**
```bash
cd blockchain_fyp
flutter run
```

---

## 🔧 Troubleshooting Guide

### **Issue 1: IPFS Desktop Not Accessible**

#### **Symptoms:**
- `405 - Method Not Allowed`
- `403 - Forbidden`
- Connection refused

#### **Solutions:**
1. **Check IPFS Desktop Status**
   - Open IPFS Desktop
   - Check if "Connected" status is shown
   - If not, wait for connection

2. **Verify IP Address**
   - Check your actual IP address: `ipconfig`
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
- `OrbitDB server is not running`
- Port already in use
- IPFS connection failed

#### **Solutions:**
1. **Check Port Availability**
   ```bash
   netstat -an | findstr :3000
   netstat -an | findstr :8080
   ```

2. **Kill Conflicting Processes**
   ```bash
   taskkill /F /IM node.exe
   taskkill /F /IM ipfs.exe
   ```

3. **Restart Services**
   - Stop IPFS Desktop
   - Start IPFS Desktop
   - Run `npm start`

### **Issue 3: Flutter App Connection Issues**

#### **Symptoms:**
- App not connecting to server
- WebSocket connection failed
- API calls failing

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
   flutter clean
   flutter pub get
   ```

---

## 🚀 Complete Startup Sequence

### **Method 1: Automated (Recommended)**
```bash
# 1. Start IPFS Desktop (manually)
# 2. Test connection
.\test-ipfs-connection.bat

# 3. Start OrbitDB server
.\start-with-ipfs-desktop.bat

# 4. Start Flutter app (in new terminal)
cd blockchain_fyp
flutter run
```

### **Method 2: Manual Step-by-Step**
```bash
# Terminal 1: Start IPFS Desktop (GUI)
# Open IPFS Desktop application

# Terminal 2: Test IPFS
Invoke-WebRequest -Uri "http://192.168.0.33:5001/api/v0/id" -Method POST

# Terminal 3: Start OrbitDB Server
npm start

# Terminal 4: Start Flutter App
cd blockchain_fyp
flutter run
```

---

## 📊 Verification Checklist

### **✅ IPFS Desktop**
- [ ] IPFS Desktop is running
- [ ] Status shows "Connected"
- [ ] API accessible at `192.168.0.33:5001`
- [ ] Gateway accessible at `192.168.0.33:8081`
- [ ] CORS enabled

### **✅ OrbitDB Server**
- [ ] Server starts without errors
- [ ] Health check: `http://localhost:3000/health`
- [ ] WebSocket: `ws://localhost:8080`
- [ ] IPFS connection successful

### **✅ Flutter App**
- [ ] App starts without errors
- [ ] Connects to server
- [ ] WebSocket connection established
- [ ] Can send/receive messages

---

## 🔍 Debug Commands

### **Check IPFS Status**
```bash
# Test API
Invoke-WebRequest -Uri "http://192.168.0.33:5001/api/v0/id" -Method POST

# Test Gateway
Invoke-WebRequest -Uri "http://192.168.0.33:8081/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme"
```

### **Check Server Status**
```bash
# Health check
Invoke-WebRequest -Uri "http://localhost:3000/health"

# List databases
Invoke-WebRequest -Uri "http://localhost:3000/api/databases"
```

### **Check Network**
```bash
# Check IP address
ipconfig

# Check ports
netstat -an | findstr :3000
netstat -an | findstr :5001
netstat -an | findstr :8080
```

---

## 🎯 Expected Results

### **Successful Setup:**
1. **IPFS Desktop**: Shows "Connected" status
2. **OrbitDB Server**: Starts without errors, shows health status
3. **Flutter App**: Connects to server, can send/receive messages
4. **File Sharing**: Can upload/download files through IPFS

### **Test Commands:**
```bash
# All should return success
.\test-ipfs-connection.bat
curl http://localhost:3000/health
```

---

## 🆘 Emergency Reset

### **If Everything Fails:**
```bash
# 1. Stop all services
taskkill /F /IM node.exe
taskkill /F /IM ipfs.exe

# 2. Clear OrbitDB data
rmdir /s orbitdb
mkdir orbitdb

# 3. Restart IPFS Desktop
# 4. Run setup again
npm install
.\start-with-ipfs-desktop.bat
```

---

**Ab aapka project Real OrbitDB ke saath fully functional hona chahiye! 🎉**

**Next Steps:**
1. Follow the complete setup guide
2. Test each step
3. Start Flutter app
4. Enjoy decentralized file sharing!

Koi bhi issue ho toh mujhe batayen!
