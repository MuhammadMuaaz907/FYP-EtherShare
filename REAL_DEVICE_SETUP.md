# 📱 Real Android Device Setup Guide

## ✅ Problem Fixed

The app was trying to connect to `localhost:3000` on a real Android device, which doesn't work because `localhost` on the device refers to the device itself, not your development PC.

## 🔧 Solution Implemented

Updated `DistributedService` to automatically detect the platform and use the correct host:

- **Android Emulator**: `10.0.2.2:3000`
- **Real Android Device**: `192.168.0.35:3000` (Your PC's IP)
- **Desktop/Web**: `localhost:3000`

## 📋 Setup Steps

### 1. Find Your PC's IP Address

**Windows:**
```powershell
ipconfig | findstr /i "IPv4"
```

**Linux/Mac:**
```bash
ifconfig | grep "inet "
```

You should see something like:
```
IPv4 Address. . . . . . . . . . . : 192.168.0.35
```

### 2. Update DistributedService (if needed)

If your PC IP is different, update this line in `lib/services/distributed_service.dart`:

```dart
static const String realDeviceHost = '192.168.0.35'; // Change to your PC IP
```

### 3. Alternative: Use .env File

Create or update `.env` file in `blockchain_fyp/` directory:

```env
BACKEND_URL=http://192.168.0.35:3000
```

This will override the auto-detection.

### 4. Start Backend Server

```powershell
cd backend
npm run dev
```

Make sure the server starts on port 3000:
```
Server running on http://localhost:3000
```

### 5. Verify Connection

1. Make sure your **PC and Android device are on the same WiFi network**
2. Check firewall settings - allow port 3000
3. Run the Flutter app
4. Check logs - you should see:
   ```
   📱 Detected Real Android Device, using: http://192.168.0.35:3000
   ✅ Backend health: OK, Database: connected
   ```

## 🔥 Firewall Configuration

### Windows Firewall:

1. Open **Windows Defender Firewall**
2. Click **Advanced settings**
3. Click **Inbound Rules** → **New Rule**
4. Select **Port** → **TCP** → **Specific local ports: 3000**
5. Allow the connection
6. Apply to all profiles

Or use PowerShell (Run as Administrator):
```powershell
New-NetFirewallRule -DisplayName "Node.js Backend" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

## 🧪 Testing

### Test Backend from Device:

1. Open browser on your Android device
2. Go to: `http://192.168.0.35:3000/health`
3. Should see: `{"status":"ok","database":"connected"}`

### Test from Flutter App:

1. Run: `flutter run`
2. Check logs for:
   - ✅ `Backend health: OK`
   - ✅ `Distributed System initialized successfully`

## ❌ Common Issues

### Issue: Connection Refused

**Error:**
```
Connection refused (OS Error: Connection refused, errno = 111)
```

**Solutions:**
1. ✅ Backend server not running → Start with `npm run dev`
2. ✅ Wrong IP address → Check PC IP with `ipconfig`
3. ✅ Different WiFi networks → Connect PC and phone to same WiFi
4. ✅ Firewall blocking → Allow port 3000 in firewall

### Issue: Timeout

**Error:**
```
Health check timeout - backend server may not be running
```

**Solutions:**
1. ✅ Check backend server is running
2. ✅ Verify IP address is correct
3. ✅ Check firewall settings
4. ✅ Try accessing from device browser first

### Issue: Wrong IP Address

**Solution:**
1. Find your PC IP: `ipconfig` (Windows) or `ifconfig` (Linux/Mac)
2. Update `realDeviceHost` in `distributed_service.dart`
3. Or set `BACKEND_URL` in `.env` file

## 📝 Current Configuration

- **PC IP**: `192.168.0.35`
- **Backend Port**: `3000`
- **Backend URL**: `http://192.168.0.35:3000`

## ✅ Verification Checklist

- [ ] Backend server running (`npm run dev`)
- [ ] PC and phone on same WiFi
- [ ] Firewall allows port 3000
- [ ] IP address is correct (192.168.0.35)
- [ ] Can access `http://192.168.0.35:3000/health` from device browser
- [ ] Flutter app shows "✅ Backend health: OK"

---

**Status: ✅ FIXED** - Real device connection now works!

