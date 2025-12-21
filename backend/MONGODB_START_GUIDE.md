# 🔧 MongoDB Start Guide - Access Denied Fix

## ❌ Problem
```
System error 5 has occurred.
Access is denied.
```

This happens because starting Windows services requires **Administrator privileges**.

## ✅ Solutions

### **Solution 1: Run PowerShell as Administrator** (Recommended)

1. **Close current PowerShell**
2. **Right-click on PowerShell** (in Start Menu or Desktop)
3. **Select "Run as Administrator"**
4. **Click "Yes"** on the UAC prompt
5. **Navigate to your project:**
   ```powershell
   cd "C:\Users\R.A LAPTOPS\OneDrive\Desktop\EtherShare Backup\FYP-EtherShare\backend"
   ```
6. **Start MongoDB:**
   ```powershell
   net start MongoDB
   ```

### **Solution 2: Use the Helper Script**

1. **Right-click** `start-mongodb.ps1`
2. **Select "Run with PowerShell"** (as Administrator if prompted)
3. The script will check and start MongoDB automatically

### **Solution 3: Start MongoDB Manually** (No Admin Needed)

If MongoDB is not installed as a service, start it manually:

1. **Create data directory** (if doesn't exist):
   ```powershell
   mkdir C:\data\db
   ```

2. **Start MongoDB manually:**
   ```powershell
   mongod --dbpath C:\data\db
   ```

   **Note:** Keep this window open while using MongoDB!

### **Solution 4: Install MongoDB as Service** (One-time setup)

If MongoDB service doesn't exist:

1. **Open PowerShell as Administrator**
2. **Run:**
   ```powershell
   mongod --install --serviceName MongoDB --serviceDisplayName "MongoDB"
   ```
3. **Then start it:**
   ```powershell
   net start MongoDB
   ```

## 🔍 Check MongoDB Status

### Check if MongoDB is already running:
```powershell
Get-Service -Name MongoDB
```

### Check if MongoDB is listening:
```powershell
Test-NetConnection -ComputerName localhost -Port 27017
```

### Test connection in MongoDB Compass:
- Open MongoDB Compass
- Connect to: `mongodb://localhost:27017`
- Should connect successfully ✅

## 🚀 Quick Start (After MongoDB is Running)

Once MongoDB is running:

```powershell
cd backend
npm run dev
```

Then test: `http://localhost:3000/health`

## 📝 Alternative: Use MongoDB Atlas (Cloud)

If local MongoDB is too complicated, use MongoDB Atlas (free tier):

1. Sign up at: https://www.mongodb.com/cloud/atlas
2. Create a free cluster
3. Get connection string
4. Update `.env` file:
   ```
   MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/EtherShare
   ```

No local installation needed! ✅

---

## ✅ Verification

After starting MongoDB, verify it's working:

1. **Check service status:**
   ```powershell
   Get-Service MongoDB
   ```
   Should show: `Status: Running`

2. **Test connection:**
   ```powershell
   mongosh
   ```
   Should connect to MongoDB shell

3. **Or use MongoDB Compass:**
   - Connect to: `mongodb://localhost:27017`
   - Should show databases

---

**Most Common Solution:** Run PowerShell as Administrator! 🚀

