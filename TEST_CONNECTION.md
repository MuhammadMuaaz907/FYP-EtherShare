# 🧪 Connection Testing Guide

## ✅ Current Status

- ✅ Server running on `0.0.0.0:3000` (all interfaces)
- ✅ PC can access `localhost:3000` ✅
- ✅ PC can access `192.168.0.34:3000` ✅
- ❌ Android device cannot access (Firewall blocking)

## 🔥 Fix Firewall First

**Run as Administrator:**
```powershell
cd backend
.\allow-port-3000.ps1
```

Or manually:
```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

## 🧪 Step-by-Step Testing

### Step 1: Test from PC (Should Work ✅)

**Browser:**
```
http://localhost:3000/health
```

**PowerShell:**
```powershell
curl http://localhost:3000/health
curl http://192.168.0.34:3000/health
```

Both should return JSON response.

### Step 2: Test from Android Device

**After firewall fix, open Chrome on Android:**
```
http://192.168.0.34:3000/health
```

**Expected:** JSON response
**If fails:** Check firewall again

### Step 3: Verify Network

**Check PC IP:**
```powershell
ipconfig | findstr IPv4
```

**Check Phone WiFi:**
- Settings → WiFi → Connected network
- Should be same network as PC

### Step 4: Test Flutter App

After browser test works:
```powershell
cd blockchain_fyp
flutter run
```

Check logs for:
```
✅ Backend health: OK, Database: connected
```

## 🔍 Debug Commands

**Check server status:**
```powershell
netstat -ano | findstr :3000
```

**Check firewall rules:**
```powershell
Get-NetFirewallRule -DisplayName "*3000*" | Format-Table DisplayName, Enabled, Direction, Action
```

**Ping test (from phone):**
- Install network tools app
- Ping: `192.168.0.34`
- Should get responses

## ❌ Common Issues

### "This site can't be reached"
- ✅ Firewall blocking → Fix with script above
- ✅ Server not running → Start with `npm run dev`
- ✅ Wrong IP → Check with `ipconfig`

### "Connection refused"
- ✅ Server not listening on 0.0.0.0 → Restart server
- ✅ Port already in use → Check with `netstat`

### "Timeout"
- ✅ Different WiFi networks → Connect to same network
- ✅ Firewall still blocking → Check rule status

---

**After firewall fix, everything should work!** 🎉

