# 🚀 Quick Start - Blockchain Node System Testing

## 📋 Quick Commands

### **1. Start Backend**
```bash
cd backend
npm run dev
```

### **2. Run Automated Tests**
```bash
cd backend
node test-blockchain-nodes.js
```

### **3. Run Visual Demo**
```bash
cd backend
node demo-blockchain-nodes.js
```

### **4. Test with Postman/Thunder Client**

**Register Node:**
```
POST http://localhost:3000/api/nodes/register
{
  "node_name": "Node-1",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001
}
```

**Get Chain:**
```
GET http://localhost:3000/api/nodes/chain
```

**Verify Chain:**
```
POST http://localhost:3000/api/nodes/verify-chain
```

**Update Node:**
```
PUT http://localhost:3000/api/nodes/{nodeId}
{
  "status": "offline"
}
```

### **5. View in MongoDB**
```javascript
// Connect to MongoDB
use ethershare

// View chain
db.nodes.find({ is_deprecated: false })
  .sort({ chain_position: 1 })
  .pretty()

// View gas stats
db.nodes.aggregate([
  { $match: { is_deprecated: false } },
  {
    $group: {
      _id: null,
      totalGas: { $sum: "$gas_used" },
      totalFee: { $sum: "$transaction_fee" }
    }
  }
])
```

## 📚 Full Documentation

- **Testing Guide:** `BLOCKCHAIN_NODES_TESTING_GUIDE.md`
- **Implementation Details:** `BLOCKCHAIN_NODES_IMPLEMENTATION.md`

## ✅ What to Check

1. ✅ Node registration with gas calculation
2. ✅ Hash chain linking between nodes
3. ✅ Chain integrity verification
4. ✅ Immutability (update creates new node)
5. ✅ Node deprecation system

---

**Ready to test!** 🎉

