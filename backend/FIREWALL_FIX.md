# 🔥 Windows Firewall Fix for Port 3000

## Problem
Backend server is running but Android device cannot connect - "No route to host" error.

## Solution

### Method 1: Run PowerShell Script (Recommended)

1. **Open PowerShell as Administrator:**
   - Press `Windows + X`
   - Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
   - Click "Yes" when prompted

2. **Navigate to backend folder:**
   ```powershell
   cd "C:\Users\R.A LAPTOPS\OneDrive\Desktop\EtherShare Backup\FYP-EtherShare\backend"
   ```

3. **Run the firewall script:**
   ```powershell
   .\allow-port-3000.ps1
   ```

4. **Verify the rule was created:**
   ```powershell
   Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
   ```

### Method 2: Manual Firewall Configuration

1. **Open Windows Defender Firewall:**
   - Press `Windows + R`
   - Type: `wf.msc`
   - Press Enter

2. **Create Inbound Rule:**
   - Click "Inbound Rules" → "New Rule..."
   - Select "Port" → Next
   - Select "TCP" → Specific local ports: `3000` → Next
   - Select "Allow the connection" → Next
   - Check all profiles (Domain, Private, Public) → Next
   - Name: `Node.js Backend Port 3000` → Finish

3. **Verify Rule:**
   - Find "Node.js Backend Port 3000" in Inbound Rules
   - Make sure it's enabled (green checkmark)

### Method 3: Quick Command (Run as Admin)

```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow -Profile Domain,Private,Public
```

## Verification Steps

1. **Check if server is listening:**
   ```powershell
   netstat -an | findstr :3000
   ```
   Should show: `TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING`

2. **Test from PC browser:**
   ```
   http://localhost:3000/health
   ```
   Should return JSON response

3. **Test from Android device:**
   - Make sure phone and PC are on same WiFi
   - Open browser on phone
   - Go to: `http://192.168.0.37:3000/health`
   - Should return JSON response

4. **Check firewall rule status:**
   ```powershell
   Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" | Select-Object DisplayName, Enabled, Direction, Action
   ```

## Troubleshooting

### Still can't connect?

1. **Check Windows Firewall Status:**
   ```powershell
   Get-NetFirewallProfile | Select-Object Name, Enabled
   ```

2. **Check if port is actually listening:**
   ```powershell
   netstat -an | findstr :3000
   ```

3. **Check server logs:**
   - Make sure server shows: `🌐 Network: http://192.168.0.37:3000`

4. **Verify IP address:**
   ```powershell
   ipconfig | findstr IPv4
   ```
   Should match: `192.168.0.37`

5. **Test from phone browser:**
   - Open Chrome on Android
   - Go to: `http://192.168.0.37:3000/health`
   - If it works in browser but not in app, check Flutter app IP configuration

6. **Disable firewall temporarily (for testing only):**
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   ```
   ⚠️ **Remember to enable it back after testing!**

## Common Issues

### Issue: "Access Denied" when running script
**Solution:** Run PowerShell as Administrator

### Issue: Port 3000 already in use
**Solution:** 
```powershell
# Find process using port 3000
netstat -ano | findstr :3000
# Kill the process (replace PID with actual process ID)
taskkill /PID <PID> /F
```

### Issue: Server not starting
**Solution:**
1. Check MongoDB is running: `net start MongoDB`
2. Check .env file exists
3. Check server logs for errors

### Issue: Can connect from PC but not from phone
**Solution:**
1. Verify both devices on same WiFi network
2. Check firewall rule includes "Private" profile
3. Try disabling Windows Firewall temporarily to test

## Success Indicators

✅ Firewall rule created and enabled  
✅ Server listening on `0.0.0.0:3000`  
✅ Can access `http://localhost:3000/health` from PC  
✅ Can access `http://192.168.0.37:3000/health` from phone browser  
✅ Flutter app can connect to backend  

## Next Steps

After fixing firewall:
1. Restart backend server: `npm run dev`
2. Test from Flutter app
3. Check terminal logs for connection success

