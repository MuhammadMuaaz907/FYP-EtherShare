# ⛽ Time-Based Gas Calculation - Complete Testing Guide

## 🎯 **Testing Overview:**

Is guide mein aap seekhenge:
1. ✅ Manual testing (Postman/Browser)
2. ✅ Automated testing scripts
3. ✅ Database verification
4. ✅ Different scenarios testing
5. ✅ Expected results

---

## 📋 **Prerequisites:**

### **1. Backend Server Running:**
```powershell
cd backend
npm run dev
```

**Expected Output:**
```
🚀 EtherShare Backend Server Started
📍 Local: http://localhost:3000
🌐 Network: http://192.168.0.35:3000
```

### **2. MongoDB Running:**
- MongoDB Compass open karein
- Database connection verify karein

### **3. Tools Needed:**
- ✅ Postman (API testing)
- ✅ MongoDB Compass (Database viewing)
- ✅ Terminal/PowerShell (Scripts running)

---

## 🧪 **Test 1: Message Gas Calculation**

### **Step 1: Send a Message**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/messages`  
**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Body:**
```json
{
  "workspaceId": "ws_test_123",
  "channelId": "general",
  "senderAddress": "0xUserA",
  "messageText": "Hello, this is a test message!"
}
```

### **Step 2: Check Response**

**Expected Response:**
```json
{
  "success": true,
  "message": "Message sent successfully",
  "data": {
    "message_id": "msg_...",
    "workspace_id": "ws_test_123",
    "sender_address": "0xusera",
    "message_text": "Hello, this is a test message!",
    "timestamp": 1234567890,
    "gas_used": 25000,
    "gas_price": 1,
    "transaction_fee": 25000,
    "transaction_time_ms": 40.5
  }
}
```

**✅ Verify:**
- `gas_used` > 0
- `gas_price` = 1
- `transaction_fee` = `gas_used` × `gas_price`
- `transaction_time_ms` > 0

### **Step 3: Check Database**

**MongoDB Compass:**
1. Open `messages` collection
2. Find document with `message_id` from response
3. Verify fields:
   ```javascript
   {
     message_id: "msg_...",
     message_text: "Hello, this is a test message!",
     gas_used: 25000,
     gas_price: 1,
     transaction_fee: 25000,
     transaction_time_ms: 40.5
   }
   ```

**MongoDB Query:**
```javascript
db.messages.findOne({ message_id: "msg_..." })
```

---

## 🧪 **Test 2: Channel Gas Calculation**

### **Step 1: Create a Channel**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/channels`  
**Body:**
```json
{
  "workspaceId": "ws_test_123",
  "channelId": "test-channel",
  "channelName": "Test Channel",
  "creatorAddress": "0xUserA",
  "isPrivate": false
}
```

### **Step 2: Check Response**

**Expected Response:**
```json
{
  "success": true,
  "message": "Channel created successfully",
  "data": {
    "channel_id": "test-channel",
    "workspace_id": "ws_test_123",
    "channel_name": "Test Channel",
    "gas_used": 30000,
    "gas_price": 1,
    "transaction_fee": 30000,
    "transaction_time_ms": 90.2
  }
}
```

### **Step 3: Check Database**

**MongoDB Query:**
```javascript
db.channels.findOne({ channel_id: "test-channel", workspace_id: "ws_test_123" })
```

**✅ Verify:**
- `gas_used` present
- `transaction_time_ms` present
- Gas fields populated

---

## 🧪 **Test 3: Workspace Gas Calculation**

### **Step 1: Create a Workspace**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/workspaces`  
**Body:**
```json
{
  "workspaceName": "Test Workspace",
  "inviterAddress": "0xUserA"
}
```

### **Step 2: Check Response**

**Expected Response:**
```json
{
  "success": true,
  "message": "Workspace created successfully",
  "data": {
    "workspace_id": "ws_...",
    "name": "Test Workspace",
    "inviter_address": "0xusera",
    "created_at": 1234567890,
    "gas_used": 50000,
    "gas_price": 1,
    "transaction_fee": 50000,
    "transaction_time_ms": 290.5
  }
}
```

**✅ Verify:**
- `gas_used` > 0 (workspace creation takes more time)
- `transaction_time_ms` > 0
- Gas fields present

### **Step 3: Check Database**

**MongoDB Query:**
```javascript
db.workspaces.findOne({ workspace_id: "ws_..." })
```

---

## 🧪 **Test 4: Ledger Block Gas Calculation**

### **Step 1: Register a Node**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/nodes/register`  
**Body:**
```json
{
  "node_name": "Test-Node",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001
}
```

### **Step 2: Add Block to Ledger**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/nodes/{nodeId}/ledger`  
**Body:**
```json
{
  "type": "message",
  "sender_address": "0xUserA",
  "receiver_address": "0xUserB",
  "content": "Test message",
  "workspace_id": "ws_test_123"
}
```

### **Step 3: Check Response**

**Expected Response:**
```json
{
  "success": true,
  "message": "Block added to ledger",
  "data": {
    "block_id": "block_...",
    "block_number": 0,
    "gas_used": 35000,
    "gas_price": 1,
    "transaction_fee": 35000,
    "transaction_time_ms": 140.8
  }
}
```

### **Step 4: Check Database**

**MongoDB Query:**
```javascript
db.ledgers.findOne({ block_id: "block_..." })
```

---

## 🧪 **Test 5: Node Registration Gas Calculation**

### **Step 1: Register Node**

**Method:** `POST`  
**URL:** `http://localhost:3000/api/nodes/register`  
**Body:**
```json
{
  "node_name": "Node-1",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001
}
```

### **Step 2: Check Response**

**Expected Response:**
```json
{
  "success": true,
  "message": "Node registered successfully",
  "data": {
    "node_id": "node_...",
    "node_name": "Node-1",
    "gas_used": 45000,
    "gas_price": 1,
    "transaction_fee": 45000,
    "transaction_time_ms": 240.3
  }
}
```

### **Step 3: Check Database**

**MongoDB Query:**
```javascript
db.nodes.findOne({ node_id: "node_..." })
```

---

## 🤖 **Automated Testing Script**

### **Create Test Script:**

**File:** `backend/test-gas-calculation.js`

```javascript
const http = require('http');

const BASE_URL = 'http://localhost:3000';

// Helper function to make HTTP requests
function makeRequest(method, path, data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(url, options, (res) => {
      let body = '';
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ status: res.statusCode, data: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });

    req.on('error', reject);

    if (data) {
      req.write(JSON.stringify(data));
    }

    req.end();
  });
}

// Test functions
async function testMessageGas() {
  console.log('\n📨 Testing Message Gas Calculation...');
  
  const response = await makeRequest('POST', '/api/messages', {
    workspaceId: 'ws_test_gas',
    channelId: 'general',
    senderAddress: '0xTestUser',
    messageText: 'Test message for gas calculation'
  });

  if (response.status === 201 && response.data.success) {
    const gas = response.data.data;
    console.log('✅ Message sent successfully!');
    console.log(`   Gas Used: ${gas.gas_used}`);
    console.log(`   Gas Price: ${gas.gas_price}`);
    console.log(`   Transaction Fee: ${gas.transaction_fee}`);
    console.log(`   Execution Time: ${gas.transaction_time_ms}ms`);
    
    // Verify gas fields
    if (gas.gas_used > 0 && gas.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return true;
    } else {
      console.log('❌ Gas calculation failed!');
      return false;
    }
  } else {
    console.log('❌ Message send failed:', response.data);
    return false;
  }
}

async function testChannelGas() {
  console.log('\n📺 Testing Channel Gas Calculation...');
  
  const response = await makeRequest('POST', '/api/channels', {
    workspaceId: 'ws_test_gas',
    channelId: 'test-channel-gas',
    channelName: 'Test Channel Gas',
    creatorAddress: '0xTestUser',
    isPrivate: false
  });

  if (response.status === 201 && response.data.success) {
    const gas = response.data.data;
    console.log('✅ Channel created successfully!');
    console.log(`   Gas Used: ${gas.gas_used}`);
    console.log(`   Gas Price: ${gas.gas_price}`);
    console.log(`   Transaction Fee: ${gas.transaction_fee}`);
    console.log(`   Execution Time: ${gas.transaction_time_ms}ms`);
    
    if (gas.gas_used > 0 && gas.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return true;
    } else {
      console.log('❌ Gas calculation failed!');
      return false;
    }
  } else {
    console.log('❌ Channel creation failed:', response.data);
    return false;
  }
}

async function testWorkspaceGas() {
  console.log('\n🏢 Testing Workspace Gas Calculation...');
  
  const timestamp = Date.now();
  const response = await makeRequest('POST', '/api/workspaces', {
    workspaceName: `Test Workspace ${timestamp}`,
    inviterAddress: '0xTestUser'
  });

  if (response.status === 201 && response.data.success) {
    const gas = response.data.data;
    console.log('✅ Workspace created successfully!');
    console.log(`   Gas Used: ${gas.gas_used}`);
    console.log(`   Gas Price: ${gas.gas_price}`);
    console.log(`   Transaction Fee: ${gas.transaction_fee}`);
    console.log(`   Execution Time: ${gas.transaction_time_ms}ms`);
    
    if (gas.gas_used > 0 && gas.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return true;
    } else {
      console.log('❌ Gas calculation failed!');
      return false;
    }
  } else {
    console.log('❌ Workspace creation failed:', response.data);
    return false;
  }
}

async function testNodeGas() {
  console.log('\n🖥️  Testing Node Registration Gas Calculation...');
  
  const response = await makeRequest('POST', '/api/nodes/register', {
    node_name: 'Test-Node-Gas',
    ip_address: '192.168.1.100',
    tcp_port: 3001
  });

  if (response.status === 201 && response.data.success) {
    const gas = response.data.data;
    console.log('✅ Node registered successfully!');
    console.log(`   Gas Used: ${gas.gas_used}`);
    console.log(`   Gas Price: ${gas.gas_price}`);
    console.log(`   Transaction Fee: ${gas.transaction_fee}`);
    console.log(`   Execution Time: ${gas.transaction_time_ms}ms`);
    
    if (gas.gas_used > 0 && gas.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return gas.data.node_id; // Return node ID for ledger test
    } else {
      console.log('❌ Gas calculation failed!');
      return null;
    }
  } else {
    console.log('❌ Node registration failed:', response.data);
    return null;
  }
}

async function testLedgerGas(nodeId) {
  if (!nodeId) {
    console.log('\n⛓️  Skipping Ledger Gas Test (no node available)');
    return false;
  }

  console.log('\n⛓️  Testing Ledger Block Gas Calculation...');
  
  const response = await makeRequest('POST', `/api/nodes/${nodeId}/ledger`, {
    type: 'message',
    sender_address: '0xTestUser',
    receiver_address: '0xTestUser2',
    content: 'Test ledger message',
    workspace_id: 'ws_test_gas'
  });

  if (response.status === 201 && response.data.success) {
    const gas = response.data.data;
    console.log('✅ Block added to ledger successfully!');
    console.log(`   Gas Used: ${gas.gas_used}`);
    console.log(`   Gas Price: ${gas.gas_price}`);
    console.log(`   Transaction Fee: ${gas.transaction_fee}`);
    console.log(`   Execution Time: ${gas.transaction_time_ms}ms`);
    
    if (gas.gas_used > 0 && gas.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return true;
    } else {
      console.log('❌ Gas calculation failed!');
      return false;
    }
  } else {
    console.log('❌ Block creation failed:', response.data);
    return false;
  }
}

// Main test runner
async function runAllTests() {
  console.log('🚀 Starting Gas Calculation Tests...');
  console.log('='.repeat(50));

  const results = {
    message: false,
    channel: false,
    workspace: false,
    node: false,
    ledger: false
  };

  try {
    // Test 1: Message
    results.message = await testMessageGas();

    // Test 2: Channel
    results.channel = await testChannelGas();

    // Test 3: Workspace
    results.workspace = await testWorkspaceGas();

    // Test 4: Node
    const nodeId = await testNodeGas();
    results.node = nodeId !== null;

    // Test 5: Ledger
    results.ledger = await testLedgerGas(nodeId);

    // Summary
    console.log('\n' + '='.repeat(50));
    console.log('📊 Test Results Summary:');
    console.log('='.repeat(50));
    console.log(`Messages:     ${results.message ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Channels:     ${results.channel ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Workspaces:   ${results.workspace ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Nodes:        ${results.node ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Ledgers:      ${results.ledger ? '✅ PASS' : '❌ FAIL'}`);

    const allPassed = Object.values(results).every(r => r === true);
    console.log('\n' + '='.repeat(50));
    if (allPassed) {
      console.log('🎉 All tests passed! Gas calculation is working correctly.');
    } else {
      console.log('⚠️  Some tests failed. Please check the errors above.');
    }
    console.log('='.repeat(50));

  } catch (error) {
    console.error('❌ Test execution error:', error);
  }
}

// Run tests
runAllTests();

```

### **Run Test Script:**

```powershell
cd backend
node test-gas-calculation.js
```

**Expected Output:**
```
🚀 Starting Gas Calculation Tests...
==================================================

📨 Testing Message Gas Calculation...
✅ Message sent successfully!
   Gas Used: 25000
   Gas Price: 1
   Transaction Fee: 25000
   Execution Time: 40.5ms
✅ Gas calculation verified!

📺 Testing Channel Gas Calculation...
✅ Channel created successfully!
   Gas Used: 30000
   Gas Price: 1
   Transaction Fee: 30000
   Execution Time: 90.2ms
✅ Gas calculation verified!

...

==================================================
📊 Test Results Summary:
==================================================
Messages:     ✅ PASS
Channels:     ✅ PASS
Workspaces:   ✅ PASS
Nodes:        ✅ PASS
Ledgers:      ✅ PASS

==================================================
🎉 All tests passed! Gas calculation is working correctly.
==================================================
```

---

## 🔍 **Database Verification**

### **Check All Collections:**

**1. Messages:**
```javascript
db.messages.find({ gas_used: { $exists: true } }).limit(5)
```

**2. Channels:**
```javascript
db.channels.find({ gas_used: { $exists: true } }).limit(5)
```

**3. Workspaces:**
```javascript
db.workspaces.find({ gas_used: { $exists: true } }).limit(5)
```

**4. Ledgers:**
```javascript
db.ledgers.find({ gas_used: { $exists: true } }).limit(5)
```

**5. Nodes:**
```javascript
db.nodes.find({ gas_used: { $exists: true } }).limit(5)
```

### **Verify Gas Fields:**
```javascript
// Check if all required fields exist
db.messages.findOne({}, {
  gas_used: 1,
  gas_price: 1,
  transaction_fee: 1,
  transaction_time_ms: 1
})
```

---

## 📊 **Expected Gas Ranges**

### **Typical Gas Values:**

| Operation | Expected Gas Range | Expected Time (ms) |
|-----------|-------------------|-------------------|
| Message   | 21,000 - 30,000   | 20 - 100          |
| Channel   | 25,000 - 40,000   | 50 - 150          |
| Workspace | 40,000 - 70,000   | 200 - 400         |
| Node      | 40,000 - 60,000   | 200 - 350         |
| Ledger    | 30,000 - 50,000   | 100 - 250         |

**Note:** Actual values depend on:
- Database load
- Network latency
- Data size
- System performance

---

## ✅ **Verification Checklist**

### **For Each Transaction:**

- [ ] ✅ Response contains `gas_used`
- [ ] ✅ Response contains `gas_price`
- [ ] ✅ Response contains `transaction_fee`
- [ ] ✅ Response contains `transaction_time_ms`
- [ ] ✅ `gas_used` > 0
- [ ] ✅ `transaction_time_ms` > 0
- [ ] ✅ `transaction_fee` = `gas_used` × `gas_price`
- [ ] ✅ Database document contains all gas fields
- [ ] ✅ Gas values are reasonable (not too high/low)

---

## 🐛 **Troubleshooting**

### **Issue: Gas fields missing in response**

**Solution:**
1. Check backend logs for errors
2. Verify GasCalculator is imported
3. Check if timing code is present

### **Issue: Gas = 0**

**Solution:**
1. Check execution time measurement
2. Verify GasCalculator methods are called
3. Check base costs in GasCalculator

### **Issue: Database fields missing**

**Solution:**
1. Check update query in route
2. Verify field names match
3. Check MongoDB connection

---

## 🎯 **Quick Test Commands**

### **1. Test Message (cURL):**
```bash
curl -X POST http://localhost:3000/api/messages \
  -H "Content-Type: application/json" \
  -d '{
    "workspaceId": "ws_test",
    "channelId": "general",
    "senderAddress": "0xTest",
    "messageText": "Test"
  }'
```

### **2. Test Channel (cURL):**
```bash
curl -X POST http://localhost:3000/api/channels \
  -H "Content-Type: application/json" \
  -d '{
    "workspaceId": "ws_test",
    "channelId": "test",
    "channelName": "Test",
    "creatorAddress": "0xTest"
  }'
```

### **3. Test Workspace (cURL):**
```bash
curl -X POST http://localhost:3000/api/workspaces \
  -H "Content-Type: application/json" \
  -d '{
    "workspaceName": "Test Workspace",
    "inviterAddress": "0xTest"
  }'
```

---

## 📝 **Test Report Template**

### **After Testing, Document:**

```
Test Date: [Date]
Tester: [Name]

Results:
- Messages: ✅/❌
- Channels: ✅/❌
- Workspaces: ✅/❌
- Nodes: ✅/❌
- Ledgers: ✅/❌

Average Gas Values:
- Message: [value]
- Channel: [value]
- Workspace: [value]
- Node: [value]
- Ledger: [value]

Issues Found:
- [List any issues]

Notes:
- [Any observations]
```

---

## 🎉 **Success Criteria**

**All tests pass if:**
- ✅ All API responses include gas fields
- ✅ All database documents have gas fields
- ✅ Gas values are > 0
- ✅ Transaction times are > 0
- ✅ Transaction fees = gas_used × gas_price
- ✅ Gas values are reasonable

---

**Status:** Ready for Testing! 🚀

**Next Steps:**
1. Run automated test script
2. Test manually with Postman
3. Verify in MongoDB Compass
4. Document results

