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
    const node = response.data.data;
    console.log('✅ Node registered successfully!');
    console.log(`   Node ID: ${node.node_id}`);
    console.log(`   Gas Used: ${node.gas_used}`);
    console.log(`   Gas Price: ${node.gas_price}`);
    console.log(`   Transaction Fee: ${node.transaction_fee}`);
    console.log(`   Execution Time: ${node.transaction_time_ms}ms`);
    
    if (node.gas_used > 0 && node.transaction_time_ms > 0) {
      console.log('✅ Gas calculation verified!');
      return node.node_id; // Return node ID for ledger test
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

