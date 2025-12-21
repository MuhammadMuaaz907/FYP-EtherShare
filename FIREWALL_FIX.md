# 🔥 Windows Firewall Fix - "This site can't be reached"

## ✅ Problem Identified

Server is running correctly on `0.0.0.0:3000`, but Windows Firewall is blocking incoming connections from your Android device.

## 🔧 Solution: Allow Port 3000 in Firewall

### Method 1: PowerShell Script (Easiest)

**Run PowerShell as Administrator:**
1. Press `Win + X`
2. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
3. Navigate to backend folder:
   ```powershell
   cd "C:\Users\R.A LAPTOPS\OneDrive\Desktop\EtherShare Backup\FYP-EtherShare\backend"
   ```
4. Run the script:
   ```powershell
   .\allow-port-3000.ps1
   ```

### Method 2: PowerShell Command (Manual)

**Run PowerShell as Administrator:**
```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow -Profile Domain,Private,Public
```

### Method 3: Windows Firewall GUI (Visual)

1. **Open Windows Defender Firewall:**
   - Press `Win + R`
   - Type: `wf.msc`
   - Press Enter

2. **Create Inbound Rule:**
   - Click **"Inbound Rules"** in left panel
   - Click **"New Rule..."** in right panel

3. **Rule Type:**
   - Select **"Port"**
   - Click **Next**

4. **Protocol and Ports:**
   - Select **TCP**
   - Select **"Specific local ports"**
   - Enter: `3000`
   - Click **Next**

5. **Action:**
   - Select **"Allow the connection"**
   - Click **Next**

6. **Profile:**
   - Check all three: **Domain**, **Private**, **Public**
   - Click **Next**

7. **Name:**
   - Name: `Node.js Backend Port 3000`
   - Description: `Allow inbound connections to Node.js backend server`
   - Click **Finish**

## ✅ Verify Firewall Rule

**Check if rule exists:**
```powershell
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" | Select-Object DisplayName, Enabled, Direction, Action
```

Should show:
```
DisplayName                    Enabled Direction Action
-----------                    ------- --------- ------
Node.js Backend Port 3000      True    Inbound   Allow
```

## 🧪 Test Connection

### From PC Browser:
```
http://localhost:3000/health
```
✅ Should work

### From Android Device Browser:
```
http://192.168.0.34:3000/health
```
✅ Should work after firewall fix

## 🔍 Troubleshooting

### Still Not Working?

**1. Check Server is Running:**
```powershell
netstat -ano | findstr :3000
```
Should show: `TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING`

**2. Check Firewall Rule:**
```powershell
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
```

**3. Temporarily Disable Firewall (Testing Only):**
```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```
⚠️ **Remember to enable it back!**

**4. Check Network:**
- PC and phone must be on **same WiFi network**
- Verify PC IP: `ipconfig | findstr IPv4`
- Should be `192.168.0.34` or similar

**5. Test from PC:**
```powershell
curl http://192.168.0.34:3000/health
```
If this works but phone doesn't, it's definitely firewall.

## 📋 Quick Checklist

- [ ] PowerShell run as Administrator
- [ ] Firewall rule created/verified
- [ ] Server running (`npm run dev`)
- [ ] PC and phone on same WiFi
- [ ] Test from phone browser: `http://192.168.0.34:3000/health`

## 🎯 Expected Result

After firewall fix, Android browser should show:
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "timestamp": "2025-12-17T...",
  "database": "connected"
}
```

---

**Status: 🔥 Firewall blocking - Fix with steps above!**

