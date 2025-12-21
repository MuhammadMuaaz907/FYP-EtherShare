# 🚀 Quick Fix Steps for "No Route to Host"

## ✅ Code Fixed - Now Restart Server

The backend server code has been updated. Follow these steps:

### Step 1: Restart Backend Server

**Stop current server:**
- Find the terminal where `npm run dev` is running
- Press `Ctrl+C` to stop it

**Start server again:**
```powershell
cd backend
npm run dev
```

You should see:
```
🚀 EtherShare Backend Server Started
📍 Local: http://localhost:3000
🌐 Network: http://192.168.0.34:3000
📱 Android Emulator: http://10.0.2.2:3000
```

### Step 2: Fix Firewall (CRITICAL!)

**Run PowerShell as Administrator:**
```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

Or manually:
1. Windows Search → "Windows Defender Firewall"
2. Advanced settings → Inbound Rules → New Rule
3. Port → TCP → 3000 → Allow → All profiles → Finish

### Step 3: Test Connection

**From Android device browser:**
1. Open Chrome
2. Go to: `http://192.168.0.34:3000/health`
3. Should see JSON response

If this works, Flutter app will work!

### Step 4: Run Flutter App

```powershell
cd blockchain_fyp
flutter run
```

Check logs for:
```
✅ Backend health: OK, Database: connected
```

---

**If still not working, check:**
1. ✅ Server restarted?
2. ✅ Firewall allows port 3000?
3. ✅ PC and phone on same WiFi?
4. ✅ Can access from phone browser?

