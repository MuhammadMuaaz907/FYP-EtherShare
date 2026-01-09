# ⛽ Time-Based Gas Calculation Implementation

## 🎯 **Overview:**

Gas calculation ab **transaction execution time** ke basis par hoti hai, real blockchain ki tarah. Har transaction ka execution time measure karke gas calculate hoti hai.

---

## 🔧 **Implementation Details:**

### **1. Gas Calculator (`backend/utils/gasCalculator.js`)**

**Key Features:**
- ✅ Time-based gas calculation
- ✅ High-precision timing (nanoseconds)
- ✅ Base costs + time multiplier
- ✅ Minimum gas guarantee

**Formula:**
```
Gas = Base Cost + (Execution Time (ms) × Time Multiplier)
```

**Example:**
- Base Cost: 21,000 gas
- Time Multiplier: 100 gas/ms
- Execution Time: 50ms
- **Gas = 21,000 + (50 × 100) = 26,000 gas**

---

### **2. Gas Fields in Database:**

**All Collections Now Include:**
```javascript
{
  gas_used: Number,           // Gas units consumed
  gas_price: Number,           // Gas price (default: 1)
  transaction_fee: Number,     // gas_used × gas_price
  transaction_time_ms: Number // Execution time in milliseconds
}
```

---

## 📊 **Collections Updated:**

### **1. Messages Collection:**
- ✅ `gas_used` - Calculated from message processing time
- ✅ `gas_price` - Current gas price
- ✅ `transaction_fee` - Total fee
- ✅ `transaction_time_ms` - Time taken to process message

**Route:** `POST /api/messages`

**Example:**
```javascript
{
  message_id: "msg_...",
  message_text: "Hello",
  gas_used: 25000,
  gas_price: 1,
  transaction_fee: 25000,
  transaction_time_ms: 40.5
}
```

---

### **2. Channels Collection:**
- ✅ `gas_used` - Calculated from channel creation time
- ✅ `gas_price` - Current gas price
- ✅ `transaction_fee` - Total fee
- ✅ `transaction_time_ms` - Time taken to create channel

**Route:** `POST /api/channels`

**Example:**
```javascript
{
  channel_id: "general",
  channel_name: "General",
  gas_used: 30000,
  gas_price: 1,
  transaction_fee: 30000,
  transaction_time_ms: 90.2
}
```

---

### **3. Workspaces Collection:**
- ✅ `gas_used` - Calculated from workspace creation time
- ✅ `gas_price` - Current gas price
- ✅ `transaction_fee` - Total fee
- ✅ `transaction_time_ms` - Time taken to create workspace

**Route:** `POST /api/workspaces`

**Example:**
```javascript
{
  workspace_id: "ws_...",
  name: "My Workspace",
  gas_used: 50000,
  gas_price: 1,
  transaction_fee: 50000,
  transaction_time_ms: 290.5
}
```

---

### **4. Ledgers Collection:**
- ✅ `gas_used` - Calculated from block creation time
- ✅ `gas_price` - Current gas price
- ✅ `transaction_fee` - Total fee
- ✅ `transaction_time_ms` - Time taken to create block

**Service:** `LedgerService.addBlock()`

**Example:**
```javascript
{
  block_id: "block_...",
  block_number: 0,
  gas_used: 35000,
  gas_price: 1,
  transaction_fee: 35000,
  transaction_time_ms: 140.8
}
```

---

### **5. Nodes Collection:**
- ✅ `gas_used` - Calculated from node registration/update time
- ✅ `gas_price` - Current gas price
- ✅ `transaction_fee` - Total fee
- ✅ `transaction_time_ms` - Time taken to register/update node

**Services:** `NodeService.registerNode()`, `NodeService.updateNode()`

**Example:**
```javascript
{
  node_id: "node_...",
  node_name: "Node-1",
  gas_used: 45000,
  gas_price: 1,
  transaction_fee: 45000,
  transaction_time_ms: 240.3
}
```

---

## 🔄 **How It Works:**

### **Step-by-Step Process:**

1. **Transaction Starts:**
   ```javascript
   const startTime = process.hrtime.bigint(); // High precision timer
   ```

2. **Transaction Executes:**
   - Database operations
   - Hash calculations
   - Chain updates
   - All processing

3. **Transaction Ends:**
   ```javascript
   const endTime = process.hrtime.bigint();
   const executionTimeMs = Number(endTime - startTime) / 1000000;
   ```

4. **Gas Calculation:**
   ```javascript
   const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, messageData);
   const gasPrice = GasCalculator.getCurrentGasPrice();
   const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
   ```

5. **Store in Database:**
   ```javascript
   await collection.updateOne(
     { id: documentId },
     {
       $set: {
         gas_used: gasUsed,
         gas_price: gasPrice,
         transaction_fee: transactionFee,
         transaction_time_ms: executionTimeMs
       }
     }
   );
   ```

---

## 📈 **Gas Calculation Methods:**

### **1. Message Gas:**
```javascript
GasCalculator.calculateMessageGas(executionTimeMs, messageData)
```
- Base: 21,000 gas
- Data size: 16 gas per byte
- Storage: 20,000 gas
- Time multiplier: 100 gas/ms

### **2. Channel Gas:**
```javascript
GasCalculator.calculateChannelGas(executionTimeMs, channelData)
```
- Base: 21,000 gas
- Data size: 16 gas per byte
- Storage: 20,000 gas
- Time multiplier: 100 gas/ms

### **3. Workspace Gas:**
```javascript
GasCalculator.calculateWorkspaceGas(executionTimeMs, workspaceData)
```
- Base: 21,000 gas
- Data size: 16 gas per byte
- Storage: 40,000 gas (workspace + member)
- Time multiplier: 100 gas/ms

### **4. Transaction Gas (Ledger):**
```javascript
GasCalculator.calculateTransactionGas(executionTimeMs, transactionData)
```
- Base: 21,000 gas
- Data size: 16 gas per byte
- Routing: 10,000 gas (if message)
- Time multiplier: 100 gas/ms

### **5. Node Registration Gas:**
```javascript
GasCalculator.calculateNodeRegistrationGas(executionTimeMs, nodeData)
```
- Base: 21,000 gas
- Data size: 16 gas per byte
- Storage: 20,000 gas
- Time multiplier: 100 gas/ms

### **6. Node Update Gas:**
```javascript
GasCalculator.calculateNodeUpdateGas(executionTimeMs, oldNodeData, newNodeData)
```
- Base: 50,000 gas
- Data size diff: 16 gas per byte difference
- Storage: 40,000 gas (new + deprecation)
- Time multiplier: 100 gas/ms

---

## 🎯 **Real Blockchain Similarity:**

### **Ethereum Gas System:**
- Gas = Computational cost
- More complex operations = More gas
- Time-based = More accurate cost

### **Our Implementation:**
- ✅ Gas = Base cost + (Time × Multiplier)
- ✅ More time = More gas
- ✅ Similar to Ethereum's approach
- ✅ Accurate cost measurement

---

## 📝 **Database Schema:**

### **All Collections Include:**
```javascript
{
  // ... existing fields ...
  
  // Gas fields (blockchain-like)
  gas_used: {
    type: Number,
    default: 0
  },
  gas_price: {
    type: Number,
    default: 1
  },
  transaction_fee: {
    type: Number,
    default: 0 // gas_used × gas_price
  },
  transaction_time_ms: {
    type: Number,
    default: 0 // Execution time in milliseconds
  }
}
```

---

## ✅ **Benefits:**

1. **✅ Accurate Cost Measurement:**
   - Real execution time measured
   - Fair gas calculation

2. **✅ Blockchain-like:**
   - Similar to Ethereum
   - Gas represents computational cost

3. **✅ Transparent:**
   - All transactions show gas
   - Time visible in database

4. **✅ Scalable:**
   - Can adjust multipliers
   - Can add complexity factors

---

## 🔍 **Testing:**

### **Test Gas Calculation:**
```javascript
// Send a message
POST /api/messages
{
  workspaceId: "...",
  channelId: "...",
  senderAddress: "...",
  messageText: "Test"
}

// Response includes:
{
  gas_used: 25000,
  gas_price: 1,
  transaction_fee: 25000,
  transaction_time_ms: 40.5
}
```

### **Check Database:**
```javascript
// MongoDB query
db.messages.findOne({ message_id: "msg_..." })

// Returns:
{
  message_id: "msg_...",
  message_text: "Test",
  gas_used: 25000,
  gas_price: 1,
  transaction_fee: 25000,
  transaction_time_ms: 40.5
}
```

---

## 🎉 **Status:**

**✅ COMPLETE** - Time-based gas calculation implemented for all transactions!

**Collections Updated:**
- ✅ Messages
- ✅ Channels
- ✅ Workspaces
- ✅ Ledgers
- ✅ Nodes

**All transactions now show gas in database!** 🚀

