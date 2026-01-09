# 🔧 Server Accessibility Guide

## Common Issues and Solutions

### Issue 1: Server Unaccessible When IP Changes

**Problem**: When your PC's IPv4 address changes, Flutter app can't connect to server.

**Solution**:
1. **Check Current IP**:
   ```powershell
   ipconfig
   # Look for IPv4 Address (e.g., 192.168.0.35)
   ```

2. **Update Flutter App IP**:
   ```dart
   // In distributed_service.dart or at app startup:
   DistributedService.setRealDeviceHost('192.168.0.35'); // Your current IP
   ```

3. **Or Use Environment Variable**:
   ```env
   # In .env file
   BACKEND_URL=http://192.168.0.35:3000
   ```

### Issue 2: Windows Firewall Blocking Port 3000

**Problem**: Server starts but Android device can't connect.

**Solution**:
```powershell
# Run this script to allow port 3000:
.\allow-port-3000.ps1

# Or manually:
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

**Verify**:
```powershell
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
```

### Issue 3: Server Not Starting

**Check**:
1. **MongoDB Running?**
   ```powershell
   net start MongoDB
   # Or check: Test-NetConnection localhost -Port 27017
   ```

2. **Port 3000 Available?**
   ```powershell
   netstat -an | findstr :3000
   # If port in use, kill process or change PORT in .env
   ```

3. **Dependencies Installed?**
   ```bash
   npm install
   ```

### Issue 4: Server Starts But Can't Access from Network

**Check**:
1. **Server Listening on 0.0.0.0?**
   - Check `server.js` line 119: `app.listen(PORT, '0.0.0.0', ...)`
   - Should be `'0.0.0.0'` not `'localhost'`

2. **Firewall Rule Active?**
   ```powershell
   Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" | Select Enabled
   ```

3. **Network Connectivity?**
   - Make sure PC and Android device on same WiFi network
   - Test from phone browser: `http://192.168.0.35:3000/health`

## Quick Start Scripts

### 1. Start Server with Verification
```powershell
.\start-server.ps1
```

### 2. Check Server Accessibility
```bash
node check-server.js
```

### 3. Allow Firewall Port
```powershell
.\allow-port-3000.ps1
```

## Verification Steps

### Step 1: Start Server
```bash
cd backend
npm run dev
```

**Expected Output**:
```
🚀 EtherShare Backend Server Started
📍 Local: http://localhost:3000
🌐 Network: http://192.168.0.35:3000
💾 Database: Connected ✅
```

### Step 2: Test from PC Browser
```
http://localhost:3000/health
```

**Expected Response**:
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "database": "connected"
}
```

### Step 3: Test from Phone Browser
```
http://192.168.0.35:3000/health
```

**Expected**: Same JSON response

### Step 4: Update Flutter App
```dart
// At app startup or in distributed_service.dart:
DistributedService.setRealDeviceHost('192.168.0.35');
```

## Troubleshooting Checklist

- [ ] MongoDB is running
- [ ] Server starts without errors
- [ ] Port 3000 is listening (`netstat -an | findstr :3000`)
- [ ] Windows Firewall allows port 3000
- [ ] Server shows network IP in console
- [ ] Can access from PC browser: `http://localhost:3000/health`
- [ ] Can access from phone browser: `http://192.168.0.35:3000/health`
- [ ] Flutter app IP matches server IP
- [ ] PC and phone on same WiFi network

## Auto IP Detection (Future Enhancement)

For automatic IP detection in Flutter app, you can:
1. Use UDP broadcast to discover server
2. Store last known IP in SharedPreferences
3. Try multiple common IP ranges

## Network Configuration

### Same Network Required
- PC and Android device must be on same WiFi network
- Check IP ranges match (e.g., both 192.168.0.x)

### Static IP (Recommended)
To avoid IP changes:
1. Set static IP in router settings
2. Or reserve IP for your PC's MAC address

## Support

If issues persist:
1. Check server logs for errors
2. Verify MongoDB connection
3. Test with `check-server.js`
4. Check Windows Firewall logs

