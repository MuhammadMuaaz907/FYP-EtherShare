# ⚡ Quick Gas Testing Guide

## 🚀 **Fastest Way to Test:**

### **Step 1: Start Backend**
```powershell
cd backend
npm run dev
```

### **Step 2: Run Automated Tests**
```powershell
node test-gas-calculation.js
```

**That's it!** ✅

---

## 📋 **Manual Testing (Postman):**

### **1. Test Message Gas:**

**POST** `http://localhost:3000/api/messages`
```json
{
  "workspaceId": "ws_test",
  "channelId": "general",
  "senderAddress": "0xTest",
  "messageText": "Hello World"
}
```

**Check Response:**
- ✅ `gas_used` present
- ✅ `transaction_time_ms` present
- ✅ Values > 0

---

### **2. Test Channel Gas:**

**POST** `http://localhost:3000/api/channels`
```json
{
  "workspaceId": "ws_test",
  "channelId": "test",
  "channelName": "Test Channel",
  "creatorAddress": "0xTest"
}
```

---

### **3. Test Workspace Gas:**

**POST** `http://localhost:3000/api/workspaces`
```json
{
  "workspaceName": "Test Workspace",
  "inviterAddress": "0xTest"
}
```

---

## 🔍 **Check Database (MongoDB Compass):**

1. Open MongoDB Compass
2. Connect to: `mongodb://localhost:27017`
3. Database: `EtherShare`
4. Check collections:
   - `messages` → Find document → Check gas fields
   - `channels` → Find document → Check gas fields
   - `workspaces` → Find document → Check gas fields

**Expected Fields:**
```javascript
{
  gas_used: 25000,
  gas_price: 1,
  transaction_fee: 25000,
  transaction_time_ms: 40.5
}
```

---

## ✅ **Success Criteria:**

- ✅ All API responses have gas fields
- ✅ All database documents have gas fields
- ✅ Gas values > 0
- ✅ Time values > 0
- ✅ Transaction fee = gas_used × gas_price

---

## 🐛 **If Tests Fail:**

1. Check backend is running
2. Check MongoDB is running
3. Check backend logs for errors
4. Verify GasCalculator is imported

---

**For detailed testing, see:** `GAS_CALCULATION_TESTING_GUIDE.md`

