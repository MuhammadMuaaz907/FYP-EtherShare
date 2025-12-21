# 🔧 Fix: "No Route to Host" Error - Complete Solution

## 🐛 Problem Analysis

**Error:** `No route to host (OS Error: No route to host, errno = 113)`

**Root Causes:**
1. ❌ **Windows Firewall blocking port 3000** (Most common)
2. ❌ Backend server not accessible from network
3. ❌ PC and device on different networks
4. ❌ IP address mismatch

---

## ✅ Solution Steps

### **Step 1: Allow Port 3000 in Windows Firewall (CRITICAL!)**

**Option A: PowerShell (Run as Administrator)**
```powershell
# Allow inbound connections on port 3000
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow

# Verify rule created
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
```

**Option B: Windows Firewall GUI**
1. Press `Win + R` → Type `wf.msc` → Enter
2. Click **Inbound Rules** → **New Rule**
3. Select **Port** → **Next**
4. Select **TCP** → Enter **3000** in "Specific local ports" → **Next**
5. Select **Allow the connection** → **Next**
6. Check all profiles (Domain, Private, Public) → **Next**
7. Name: **"Node.js Backend Port 3000"** → **Finish**

---

### **Step 2: Verify Backend Server is Running**

**Check if server is listening:**
```powershell
netstat -ano | findstr :3000
```

**Should show:**
```
TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING       <PID>
```

**If not running, start it:**
```powershell
cd backend
npm run dev
```

**Should see:**
```
🚀 EtherShare Backend Server Started
📍 Local: http://localhost:3000
🌐 Network: http://192.168.0.35:3000
```

---

### **Step 3: Verify PC IP Address**

**Get your PC's IP:**
```powershell
ipconfig | findstr /i "IPv4"
```

**Should show:**
```
IPv4 Address. . . . . . . . . . . : 192.168.0.35
```

**If different, update `distributed_service.dart`:**
```dart
static const String realDeviceHost = 'YOUR_ACTUAL_IP'; // Update this
```

---

### **Step 4: Test Connection from Android Device**

**From your Android device browser:**
1. Open Chrome/Browser
2. Go to: `http://192.168.0.35:3000/health`
3. Should see JSON response:
   ```json
   {
     "success": true,
     "message": "EtherShare Backend API is running",
     "database": "connected"
   }
   ```

**If this works, Flutter app will also work!**

---

### **Step 5: Verify Same Network**

**Check both devices are on same WiFi:**
- PC: `ipconfig | findstr /i "IPv4"`
- Phone: WiFi Settings → Check IP (should be like `192.168.0.XX`)

**Both should start with same network prefix (e.g., `192.168.0.`)**

---

## 🔍 Troubleshooting

### **Issue 1: Still Getting "No Route to Host"**

**Check 1: Firewall**
```powershell
# Check if rule exists
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"

# If not, create it again
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

**Check 2: Server Binding**
- Server should listen on `0.0.0.0` (already configured ✅)
- Check server logs show: `🌐 Network: http://192.168.0.35:3000`

**Check 3: Temporarily Disable Firewall (for testing)**
```powershell
# Disable firewall temporarily (NOT RECOMMENDED for production)
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Re-enable after testing
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
```

---

### **Issue 2: Connection Timeout**

**Possible causes:**
1. Backend server crashed → Check backend logs
2. MongoDB not running → Start MongoDB
3. Port already in use → Check with `netstat -ano | findstr :3000`

---

### **Issue 3: Wrong IP Address**

**Update IP in Flutter app:**
1. Find your PC IP: `ipconfig | findstr /i "IPv4"`
2. Update `blockchain_fyp/lib/services/distributed_service.dart`:
   ```dart
   static const String realDeviceHost = '192.168.0.35'; // Your actual IP
   ```
3. Hot restart Flutter app: Press `R` in terminal

---

## ✅ Verification Checklist

- [ ] **Firewall rule created** for port 3000
- [ ] **Backend server running** and listening on `0.0.0.0:3000`
- [ ] **PC IP verified** (matches Flutter app config)
- [ ] **Can access from phone browser** (`http://192.168.0.35:3000/health`)
- [ ] **PC and phone on same WiFi network**
- [ ] **Flutter app shows** `✅ Backend health: OK`

---

## 🚀 Quick Test Script

**Run this PowerShell script (as Administrator):**
```powershell
# Allow firewall
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

# Check server
netstat -ano | findstr :3000

# Show IP
ipconfig | findstr /i "IPv4"
```

---

## 📝 Expected Behavior After Fix

**Flutter App Logs:**
```
📱 Detected Real Android Device, using: http://192.168.0.35:3000
🔍 Checking backend health at: http://192.168.0.35:3000/health
✅ Backend health: OK, Database: connected
✅ Distributed System initialized successfully
```

**Backend Server Logs:**
```
📥 GET /health - 2025-12-18T...
📥 GET /api/users/profile/... - 2025-12-18T...
✅ User profile found: ...
```

---

**Status: ✅ Ready to Fix - Follow steps above!**

