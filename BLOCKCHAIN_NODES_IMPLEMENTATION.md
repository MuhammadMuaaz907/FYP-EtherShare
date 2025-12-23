# 🔗 Blockchain-like Node System - Professional Implementation

## ✅ Problem Solved

**Requirements:**
1. ✅ Nodes managed like blockchain blocks
2. ✅ Hash chain for node integrity
3. ✅ Immutable nodes (modification creates new node)
4. ✅ Gas calculation like real blockchain
5. ✅ Chain breaks when data is modified
6. ✅ Professional blockchain implementation

## 🔐 Blockchain-like Node Structure

### **Node Model (Immutable)**

Each node is like a blockchain block:
```javascript
{
  node_id: "node_1234567890_abc123",
  node_name: "Node-1",
  ip_address: "192.168.1.1",
  tcp_port: 3001,
  public_key: "...",
  
  // Blockchain-like hash chain
  previous_hash: "0x...",      // Hash of previous node
  current_hash: "0x...",        // Hash of this node
  
  // Gas calculation (like Ethereum)
  gas_used: 21000,
  gas_price: 1,
  transaction_fee: 21000,       // gas_used * gas_price
  
  // Immutability
  is_deprecated: false,         // If true, node was replaced
  deprecated_by: null,          // New node_id that replaced this
  chain_broken: false,          // If chain integrity compromised
  
  chain_position: 0,            // Position in chain
  previous_node_id: null,       // Previous node in chain
  next_node_id: "node_...",     // Next node in chain
}
```

## 🔗 Node Chain Structure

```
Genesis Node (position 0):
  previous_hash = "0"
  current_hash = hash(node_data + "0")
  
Node 1 (position 1):
  previous_hash = genesis.current_hash
  current_hash = hash(node_data + previous_hash)
  
Node 2 (position 2):
  previous_hash = node1.current_hash
  current_hash = hash(node_data + previous_hash)
```

## ⛽ Gas Calculation System

### **Gas Costs (Similar to Ethereum)**

```javascript
GAS_COSTS = {
  NODE_REGISTRATION: 21000,      // Base cost
  NODE_UPDATE: 50000,            // Creating new node
  NODE_VERIFICATION: 3000,       // Chain verification
  TRANSACTION_BASE: 21000,       // Base transaction
  DATA_BYTE: 16,                 // Per byte
  STORAGE_SLOT: 20000,           // Storage operation
  TCP_CONNECTION: 5000,          // Network connection
  MESSAGE_ROUTING: 10000,        // Message routing
}
```

### **Gas Calculation Examples**

**Node Registration:**
```
Base: 21,000 gas
Data: 500 bytes × 16 = 8,000 gas
Storage: 20,000 gas
Total: 49,000 gas
Fee: 49,000 × 1 = 49,000 units
```

**Node Update (Creating New Node):**
```
Base: 50,000 gas
Data difference: 200 bytes × 16 = 3,200 gas
Storage (new + deprecation): 40,000 gas
Total: 93,200 gas
Fee: 93,200 × 1 = 93,200 units
```

## 🛡️ Immutability Implementation

### **Node Update Flow**

**Before (Mutable - WRONG):**
```javascript
// Direct update - breaks blockchain integrity
await Node.updateOne(
  { node_id: nodeId },
  { $set: { status: 'offline' } }
);
```

**After (Immutable - CORRECT):**
```javascript
// 1. Get old node
const oldNode = await Node.findOne({ node_id: nodeId });

// 2. Create new node with updated data
const newNode = new Node({
  ...updatedData,
  previous_hash: oldNode.current_hash,  // Link to old node
  current_hash: hash(newData + oldNode.current_hash)
});

// 3. Deprecate old node
await Node.updateOne(
  { node_id: oldNodeId },
  { 
    $set: { 
      is_deprecated: true,
      deprecated_by: newNode.node_id 
    } 
  }
);
```

## 🔒 Chain Breaking Detection

### **When Node Data is Modified:**

1. **Direct Database Modification:**
   - User modifies node data in MongoDB
   - Next verification recalculates hash
   - Hash mismatch detected
   - Chain breaks

2. **Automatic Detection:**
   ```javascript
   // Verification recalculates hash
   const calculatedHash = hash(nodeData, previousHash);
   
   if (calculatedHash !== storedHash) {
     // Chain broken!
     await markChainBroken(nodeId);
   }
   ```

3. **Chain Breaking:**
   - Modified node marked as `chain_broken: true`
   - All subsequent nodes marked as broken
   - Chain verification fails
   - System alerts user

## 📊 Implementation Details

### **1. Node Registration (Blockchain-like)**

```javascript
static async registerNode(nodeData) {
  // Calculate gas
  const gasUsed = GasCalculator.calculateNodeRegistrationGas(nodeData);
  const gasPrice = GasCalculator.getCurrentGasPrice();
  const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
  
  // Get last node's hash
  const lastNode = await Node.findOne({ is_deprecated: false })
    .sort({ chain_position: -1 });
  
  const previousHash = lastNode ? lastNode.current_hash : '0';
  
  // Calculate hash
  const currentHash = HashChain.calculateHash(nodeData, previousHash);
  
  // Create node
  const node = new Node({
    ...nodeData,
    previous_hash: previousHash,
    current_hash: currentHash,
    gas_used: gasUsed,
    transaction_fee: transactionFee
  });
  
  await node.save();
}
```

### **2. Node Update (Creates New Node)**

```javascript
static async updateNode(oldNodeId, updatedData) {
  // Get old node
  const oldNode = await Node.findOne({ node_id: oldNodeId });
  
  // Calculate gas for update
  const gasUsed = GasCalculator.calculateNodeUpdateGas(oldNode, updatedData);
  
  // Create new node
  const newNode = new Node({
    ...updatedData,
    previous_hash: oldNode.current_hash,  // Link to old
    current_hash: hash(newData + oldNode.current_hash)
  });
  
  // Deprecate old node
  await Node.updateOne(
    { node_id: oldNodeId },
    { $set: { is_deprecated: true, deprecated_by: newNode.node_id } }
  );
}
```

### **3. Chain Verification**

```javascript
static async verifyNodeChain() {
  const nodes = await Node.find({ is_deprecated: false })
    .sort({ chain_position: 1 });
  
  let expectedHash = '0';
  
  for (const node of nodes) {
    // Verify previous hash
    if (node.previous_hash !== expectedHash) {
      // Chain broken!
      await markChainBroken(node);
      return false;
    }
    
    // Recalculate hash
    const calculatedHash = hash(nodeData, node.previous_hash);
    if (calculatedHash !== node.current_hash) {
      // Hash mismatch - data modified!
      await markChainBroken(node);
      return false;
    }
    
    expectedHash = node.current_hash;
  }
  
  return true;
}
```

## ⛽ Gas Calculation Details

### **Gas Calculator (`backend/utils/gasCalculator.js`)**

**Node Registration Gas:**
```javascript
calculateNodeRegistrationGas(nodeData) {
  let gas = 21,000;  // Base cost
  gas += dataSize * 16;  // Per byte
  gas += 20,000;  // Storage
  return gas;
}
```

**Transaction Gas:**
```javascript
calculateTransactionGas(transactionData) {
  let gas = 21,000;  // Base
  gas += dataSize * 16;  // Per byte
  if (type === 'message') {
    gas += 10,000;  // Routing
  }
  return gas;
}
```

**Transaction Fee:**
```javascript
calculateTransactionFee(gasUsed, gasPrice) {
  return gasUsed * gasPrice;
}
```

## 🔗 Node Chain Flow

```
Node Registration:
  1. Calculate gas
  2. Get last node's hash
  3. Calculate current hash
  4. Create node with hash chain
  5. Update previous node's next_node_id
  6. Verify chain integrity

Node Update:
  1. Get old node
  2. Calculate gas for update
  3. Create new node (immutable)
  4. Deprecate old node
  5. Update chain references
  6. Verify chain integrity

Chain Verification:
  1. Get all non-deprecated nodes
  2. Verify previous_hash chain
  3. Recalculate and verify current_hash
  4. Mark broken if mismatch
```

## ✅ Key Features

✅ **Blockchain-like Structure** - Nodes are immutable blocks
✅ **Hash Chain** - Each node linked via hash
✅ **Gas Calculation** - Real blockchain-like gas system
✅ **Immutability** - Updates create new nodes
✅ **Chain Breaking** - Detects data modifications
✅ **Professional Implementation** - Similar to real blockchain

## 📝 API Endpoints

### **Register Node**
```javascript
POST /api/nodes/register
{
  "node_name": "Node-1",
  "ip_address": "192.168.1.1",
  "tcp_port": 3001
}

Response:
{
  "success": true,
  "data": {
    "node_id": "node_...",
    "gas_used": 49000,
    "transaction_fee": 49000,
    "current_hash": "0x...",
    "chain_valid": true
  }
}
```

### **Update Node (Creates New)**
```javascript
PUT /api/nodes/:nodeId
{
  "status": "offline"
}

Response:
{
  "success": true,
  "data": {
    "old_node_id": "node_old",
    "new_node_id": "node_new",
    "gas_used": 93200,
    "transaction_fee": 93200
  }
}
```

### **Verify Node Chain**
```javascript
POST /api/nodes/verify-chain

Response:
{
  "success": true,
  "data": {
    "chain_valid": true,
    "message": "Node chain is valid"
  }
}
```

## 🚀 Status

**✅ IMPLEMENTATION COMPLETE**

Blockchain-like node system fully implemented:
- ✅ Immutable nodes
- ✅ Hash chain integrity
- ✅ Gas calculation
- ✅ Chain breaking detection
- ✅ Professional blockchain implementation

---

**Last Updated:** Blockchain-like node system with gas calculation and immutability.

