# ⚡ Quick Test Start - Distributed System

## 🚀 3-Step Quick Start

### Step 1: Start MongoDB
```powershell
net start MongoDB
```

### Step 2: Start Backend Server
```bash
cd backend
npm run dev
```

### Step 3: Run Tests

**Option A: Automated Test Script (Recommended)**
```bash
cd backend
node test-distributed-system.js
```

**Option B: Manual Testing with Postman**
1. Import `DISTRIBUTED_SYSTEM_POSTMAN_COLLECTION.json` in Postman
2. Run tests in sequence

**Option C: Follow Detailed Guide**
- Open `DISTRIBUTED_SYSTEM_TESTING_GUIDE.md`
- Follow step-by-step instructions

---

## ✅ Expected Results

After running tests, you should see:

```
🚀 Starting Distributed System Tests...
✅ PASSED: Health Check
✅ PASSED: Register Node 1
✅ PASSED: Register Node 2
✅ PASSED: Register Node 3
✅ PASSED: Build Chain
✅ PASSED: Add Block 0
✅ PASSED: Add Block 1
✅ PASSED: Add Block 2
✅ PASSED: Verify Chain Integrity
✅ PASSED: Send Message UserA to UserB
✅ PASSED: Get Messages Between Users

📊 TEST SUMMARY
✅ Passed: 15
❌ Failed: 0
📈 Total: 15

🎉 All tests passed! Distributed System is working correctly!
```

---

## 📋 Quick Checklist

- [ ] MongoDB running (`net start MongoDB`)
- [ ] Backend server running (`npm run dev`)
- [ ] Health check passes (`http://localhost:3000/health`)
- [ ] All automated tests pass
- [ ] Data visible in MongoDB Compass

---

## 🎯 Next Steps

1. ✅ **Distributed System Tested** - Complete!
2. ⏳ **Decentralized System** - Ready to implement!

---

**For detailed testing guide, see:** `DISTRIBUTED_SYSTEM_TESTING_GUIDE.md`

