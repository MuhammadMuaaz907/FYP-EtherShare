# ⚡ Quick Fix: "No Route to Host" Error

## 🚀 Fastest Solution (2 Steps)

### **Step 1: Run Firewall Fix Script**

**Open PowerShell as Administrator:**
1. Press `Win + X`
2. Select **"Windows PowerShell (Admin)"** or **"Terminal (Admin)"**
3. Navigate to project directory:
   ```powershell
   cd "C:\Users\R.A LAPTOPS\OneDrive\Desktop\EtherShare Backup\FYP-EtherShare"
   ```
4. Run the fix script:
   ```powershell
   .\fix-firewall.ps1
   ```

**Script will automatically:**
- ✅ Create firewall rule for port 3000
- ✅ Verify rule is active
- ✅ Check if server is running
- ✅ Show your PC IP address

---

### **Step 2: Restart Backend Server**

**In a new terminal:**
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

### **Step 3: Test from Phone**

**From your Android device browser:**
1. Open Chrome
2. Go to: `http://192.168.0.35:3000/health`
3. Should see JSON response ✅

**If this works, Flutter app will work!**

---

## 🔧 Manual Fix (If Script Doesn't Work)

### **Option A: PowerShell Command**

**Run as Administrator:**
```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow
```

### **Option B: Windows Firewall GUI**

1. Press `Win + R` → Type `wf.msc` → Enter
2. **Inbound Rules** → **New Rule**
3. **Port** → **TCP** → **3000** → **Allow** → **All profiles** → **Finish**

---

## ✅ Verification

**Check firewall rule:**
```powershell
Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
```

**Check server is listening:**
```powershell
netstat -ano | findstr :3000
```

**Get your IP:**
```powershell
ipconfig | findstr /i "IPv4"
```

---

## 🎯 Expected Result

**After fix, Flutter app logs should show:**
```
✅ Backend health: OK, Database: connected
✅ Distributed System initialized successfully
```

**Instead of:**
```
❌ Health check error: No route to host
```

---

**Status: Ready to Fix! Run `fix-firewall.ps1` as Administrator** 🚀

