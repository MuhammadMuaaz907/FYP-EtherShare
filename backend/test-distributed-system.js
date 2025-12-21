/**
 * Distributed System Testing Script
 * Run this script to test all distributed system features
 * 
 * Usage: node test-distributed-system.js
 */

const http = require('http');

const BASE_URL = 'http://localhost:3000';
let nodeIds = [];
let testResults = {
  passed: 0,
  failed: 0,
  tests: []
};

// Helper function to make HTTP requests
function makeRequest(method, path, data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      method: method,
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

    req.on('error', (error) => {
      reject(error);
    });

    if (data) {
      req.write(JSON.stringify(data));
    }

    req.end();
  });
}

// Test function
function test(name, testFn) {
  return async () => {
    try {
      console.log(`\n🧪 Testing: ${name}`);
      await testFn();
      console.log(`✅ PASSED: ${name}`);
      testResults.passed++;
      testResults.tests.push({ name, status: 'PASSED' });
    } catch (error) {
      console.error(`❌ FAILED: ${name}`);
      console.error(`   Error: ${error.message}`);
      testResults.failed++;
      testResults.tests.push({ name, status: 'FAILED', error: error.message });
    }
  };
}

// Test Cases
async function runTests() {
  console.log('🚀 Starting Distributed System Tests...\n');
  console.log('='.repeat(60));

  // Test 1: Health Check
  await test('Health Check', async () => {
    const response = await makeRequest('GET', '/health');
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.database !== 'connected') {
      throw new Error('MongoDB not connected');
    }
    console.log('   ✅ Backend server is running');
    console.log('   ✅ MongoDB is connected');
  })();

  // Test 2: Register Node 1
  await test('Register Node 1', async () => {
    const response = await makeRequest('POST', '/api/nodes/register', {
      node_name: 'Node-Device-1',
      ip_address: '192.168.1.100',
      tcp_port: 3001
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    if (!response.data.data || !response.data.data.node_id) {
      throw new Error('Node ID not returned');
    }
    nodeIds.push(response.data.data.node_id);
    console.log(`   ✅ Node 1 registered: ${nodeIds[0]}`);
  })();

  // Test 3: Register Node 2
  await test('Register Node 2', async () => {
    const response = await makeRequest('POST', '/api/nodes/register', {
      node_name: 'Node-Device-2',
      ip_address: '192.168.1.101',
      tcp_port: 3002
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    nodeIds.push(response.data.data.node_id);
    console.log(`   ✅ Node 2 registered: ${nodeIds[1]}`);
  })();

  // Test 4: Register Node 3
  await test('Register Node 3', async () => {
    const response = await makeRequest('POST', '/api/nodes/register', {
      node_name: 'Node-Device-3',
      ip_address: '192.168.1.102',
      tcp_port: 3003
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    nodeIds.push(response.data.data.node_id);
    console.log(`   ✅ Node 3 registered: ${nodeIds[2]}`);
  })();

  // Test 5: Get All Nodes
  await test('Get All Nodes', async () => {
    const response = await makeRequest('GET', '/api/nodes');
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.count !== 3) {
      throw new Error(`Expected 3 nodes, got ${response.data.count}`);
    }
    console.log(`   ✅ Found ${response.data.count} nodes`);
  })();

  // Test 6: Build Chain
  await test('Build Chain', async () => {
    const response = await makeRequest('POST', '/api/nodes/build-chain');
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.data.chain_length !== 3) {
      throw new Error(`Expected chain length 3, got ${response.data.data.chain_length}`);
    }
    console.log(`   ✅ Chain built with ${response.data.data.chain_length} nodes`);
  })();

  // Test 7: Get Chain Structure
  await test('Get Chain Structure', async () => {
    const response = await makeRequest('GET', '/api/nodes/chain');
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    const chain = response.data.data.chain;
    if (chain[0].previous_node_id !== null) {
      throw new Error('First node should have previous_node_id = null');
    }
    if (chain[chain.length - 1].next_node_id !== null) {
      throw new Error('Last node should have next_node_id = null');
    }
    console.log('   ✅ Chain structure is correct');
  })();

  // Test 8: Add Block 0 (Genesis)
  await test('Add Block 0 (Genesis)', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/ledger`, {
      type: 'message',
      sender_address: '0xUserA123',
      receiver_address: '0xUserB456',
      content: 'Hello World - Block 0',
      workspace_id: 'ws_test123'
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    if (response.data.data.block_number !== 0) {
      throw new Error(`Expected block_number 0, got ${response.data.data.block_number}`);
    }
    if (response.data.data.previous_hash !== '0') {
      throw new Error(`Expected previous_hash "0", got ${response.data.data.previous_hash}`);
    }
    console.log('   ✅ Genesis block created');
    console.log(`   ✅ Block hash: ${response.data.data.current_hash.substring(0, 20)}...`);
  })();

  // Test 9: Add Block 1
  await test('Add Block 1', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/ledger`, {
      type: 'message',
      sender_address: '0xUserA123',
      receiver_address: '0xUserB456',
      content: 'This is Block 1',
      workspace_id: 'ws_test123'
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    if (response.data.data.block_number !== 1) {
      throw new Error(`Expected block_number 1, got ${response.data.data.block_number}`);
    }
    console.log('   ✅ Block 1 created');
  })();

  // Test 10: Add Block 2
  await test('Add Block 2', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/ledger`, {
      type: 'message',
      sender_address: '0xUserA123',
      receiver_address: '0xUserB456',
      content: 'This is Block 2',
      workspace_id: 'ws_test123'
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    if (response.data.data.block_number !== 2) {
      throw new Error(`Expected block_number 2, got ${response.data.data.block_number}`);
    }
    console.log('   ✅ Block 2 created');
  })();

  // Test 11: Get Ledger
  await test('Get Ledger', async () => {
    const response = await makeRequest('GET', `/api/nodes/${nodeIds[0]}/ledger`);
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.count !== 3) {
      throw new Error(`Expected 3 blocks, got ${response.data.count}`);
    }
    const blocks = response.data.data;
    
    // Verify hash chain
    if (blocks[0].previous_hash !== '0') {
      throw new Error('Block 0 should have previous_hash = "0"');
    }
    if (blocks[1].previous_hash !== blocks[0].current_hash) {
      throw new Error('Block 1 previous_hash should match Block 0 current_hash');
    }
    if (blocks[2].previous_hash !== blocks[1].current_hash) {
      throw new Error('Block 2 previous_hash should match Block 1 current_hash');
    }
    console.log('   ✅ Ledger retrieved');
    console.log('   ✅ Hash chain integrity verified');
  })();

  // Test 12: Verify Chain
  await test('Verify Chain Integrity', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/verify`);
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.data.chain_valid !== true) {
      throw new Error('Chain should be valid');
    }
    console.log('   ✅ Chain verification passed');
  })();

  // Test 13: Send Message UserA to UserB
  await test('Send Message UserA to UserB', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/ledger`, {
      type: 'message',
      sender_address: '0xUserA123',
      receiver_address: '0xUserB456',
      content: 'Hello UserB, how are you?',
      workspace_id: 'ws_test123'
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    console.log('   ✅ Message sent from UserA to UserB');
  })();

  // Test 14: Send Message UserB to UserA
  await test('Send Message UserB to UserA', async () => {
    const response = await makeRequest('POST', `/api/nodes/${nodeIds[0]}/ledger`, {
      type: 'message',
      sender_address: '0xUserB456',
      receiver_address: '0xUserA123',
      content: 'Hi UserA, I\'m doing great!',
      workspace_id: 'ws_test123'
    });
    if (response.status !== 201) {
      throw new Error(`Expected status 201, got ${response.status}`);
    }
    console.log('   ✅ Message sent from UserB to UserA');
  })();

  // Test 15: Get Messages Between Users
  await test('Get Messages Between UserA and UserB', async () => {
    const response = await makeRequest('GET', '/api/nodes/messages/0xUserA123/0xUserB456');
    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }
    if (response.data.count < 2) {
      throw new Error(`Expected at least 2 messages, got ${response.data.count}`);
    }
    console.log(`   ✅ Retrieved ${response.data.count} messages between users`);
  })();

  // Print Summary
  console.log('\n' + '='.repeat(60));
  console.log('📊 TEST SUMMARY');
  console.log('='.repeat(60));
  console.log(`✅ Passed: ${testResults.passed}`);
  console.log(`❌ Failed: ${testResults.failed}`);
  console.log(`📈 Total: ${testResults.passed + testResults.failed}`);
  console.log('='.repeat(60));

  if (testResults.failed === 0) {
    console.log('\n🎉 All tests passed! Distributed System is working correctly!');
    console.log('\n💡 Next Steps:');
    console.log('   1. Test manually with Postman/Thunder Client');
    console.log('   2. Verify data in MongoDB Compass');
    console.log('   3. Test chain breaking detection');
    console.log('   4. Proceed to Decentralized System implementation');
  } else {
    console.log('\n⚠️  Some tests failed. Please check the errors above.');
    console.log('\n💡 Troubleshooting:');
    console.log('   1. Make sure backend server is running: npm run dev');
    console.log('   2. Check MongoDB is running: net start MongoDB');
    console.log('   3. Verify .env file has correct MONGODB_URI');
  }

  console.log('\n');
}

// Run tests
runTests().catch((error) => {
  console.error('❌ Test script error:', error);
  process.exit(1);
});

