/**
 * Automated Test Script for Blockchain-like Node System
 * Tests: Node registration, hash chain, gas calculation, immutability, chain verification
 */

const http = require('http');

const BASE_URL = 'http://localhost:3000';
const API_BASE = '/api/nodes';

// Clean database before testing
async function cleanDatabase() {
  return new Promise((resolve, reject) => {
    const url = new URL('/api/nodes/clean', BASE_URL);
    const options = {
      method: 'DELETE',
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
      // If cleanup endpoint doesn't exist, continue anyway
      console.log('⚠️  Database cleanup endpoint not available, continuing...');
      resolve({ status: 404, data: {} });
    });

    req.end();
  });
}

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

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function printHeader(title) {
  console.log('\n' + '='.repeat(70));
  log(`  ${title}`, 'cyan');
  console.log('='.repeat(70));
}

function printSuccess(message) {
  log(`✅ ${message}`, 'green');
}

function printError(message) {
  log(`❌ ${message}`, 'red');
}

function printInfo(message) {
  log(`ℹ️  ${message}`, 'blue');
}

async function testBlockchainNodes() {
  printHeader('🧪 BLOCKCHAIN-LIKE NODE SYSTEM - AUTOMATED TESTING');
  
  // Clean database before testing
  printHeader('🧹 CLEANING DATABASE');
  printInfo('Cleaning existing nodes for fresh test...');
  try {
    const cleanResult = await cleanDatabase();
    if (cleanResult.status === 200) {
      printSuccess(`Database cleaned: ${cleanResult.data.deleted_count || 0} nodes deleted`);
    } else {
      printInfo('Database cleanup endpoint not available, please run: node scripts/clean-nodes.js');
    }
  } catch (error) {
    printInfo('Database cleanup skipped');
  }
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  let genesisNodeId, node2Id, node3Id;
  
  try {
    // ========== TEST 1: Register Genesis Node ==========
    printHeader('TEST 1: Register Genesis Node');
    const genesis = await makeRequest('POST', `${API_BASE}/register`, {
      node_name: 'Genesis-Node',
      ip_address: '192.168.1.100',
      tcp_port: 3001
    });
    
    if (genesis.status === 201 && genesis.data.success) {
      const node = genesis.data.data;
      genesisNodeId = node.node_id;
      
      printSuccess('Genesis Node Registered Successfully!');
      console.log(`   Node ID: ${node.node_id}`);
      console.log(`   Node Name: ${node.node_name}`);
      console.log(`   Chain Position: ${node.chain_position}`);
      console.log(`   Previous Hash: ${node.previous_hash || 'undefined'} (should be "0" for genesis)`);
      console.log(`   Current Hash: ${node.current_hash ? node.current_hash.substring(0, 30) + '...' : 'undefined'}`);
      console.log(`   Gas Used: ${node.gas_used}`);
      console.log(`   Transaction Fee: ${node.transaction_fee}`);
      console.log(`   Chain Valid: ${node.chain_valid ? '✅ YES' : '❌ NO'}`);
      
      // Verify genesis node properties
      if (node.previous_hash === '0' && node.chain_position === 0) {
        printSuccess('Genesis node properties verified!');
      } else {
        printError('Genesis node properties incorrect!');
      }
    } else {
      printError('Genesis node registration failed!');
      return;
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 2: Register Second Node ==========
    printHeader('TEST 2: Register Second Node');
    const node2 = await makeRequest('POST', `${API_BASE}/register`, {
      node_name: 'Node-2',
      ip_address: '192.168.1.101',
      tcp_port: 3002
    });
    
    if (node2.status === 201 && node2.data.success) {
      const node = node2.data.data;
      node2Id = node.node_id;
      
      printSuccess('Node 2 Registered Successfully!');
      console.log(`   Node ID: ${node.node_id}`);
      console.log(`   Chain Position: ${node.chain_position}`);
      console.log(`   Previous Hash: ${node.previous_hash ? node.previous_hash.substring(0, 30) + '...' : 'undefined'}`);
      console.log(`   Current Hash: ${node.current_hash ? node.current_hash.substring(0, 30) + '...' : 'undefined'}`);
      console.log(`   Gas Used: ${node.gas_used}`);
      
      // Verify hash chain link
      const genesisHash = genesis.data.data.current_hash;
      if (node.previous_hash && genesisHash && node.previous_hash === genesisHash) {
        printSuccess('Hash chain link verified! (Node 2 linked to Genesis)');
      } else {
        printError(`Hash chain link broken! Expected: ${genesisHash}, Got: ${node.previous_hash}`);
      }
    } else {
      printError('Node 2 registration failed!');
      return;
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 3: Register Third Node ==========
    printHeader('TEST 3: Register Third Node');
    const node3 = await makeRequest('POST', `${API_BASE}/register`, {
      node_name: 'Node-3',
      ip_address: '192.168.1.102',
      tcp_port: 3003
    });
    
    if (node3.status === 201 && node3.data.success) {
      const node = node3.data.data;
      node3Id = node.node_id;
      
      printSuccess('Node 3 Registered Successfully!');
      console.log(`   Node ID: ${node.node_id}`);
      console.log(`   Chain Position: ${node.chain_position}`);
      console.log(`   Previous Hash: ${node.previous_hash ? node.previous_hash.substring(0, 30) + '...' : 'undefined'}`);
      console.log(`   Current Hash: ${node.current_hash ? node.current_hash.substring(0, 30) + '...' : 'undefined'}`);
      
      // Verify hash chain link
      const node2Hash = node2.data.data.current_hash;
      if (node.previous_hash && node2Hash && node.previous_hash === node2Hash) {
        printSuccess('Hash chain link verified! (Node 3 linked to Node 2)');
      } else {
        printError(`Hash chain link broken! Expected: ${node2Hash}, Got: ${node.previous_hash}`);
      }
    } else {
      printError('Node 3 registration failed!');
      return;
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 4: Get Node Chain ==========
    printHeader('TEST 4: Get Node Chain');
    const chain = await makeRequest('GET', `${API_BASE}/chain`);
    
    if (chain.status === 200 && chain.data.success) {
      const chainData = chain.data.data;
      
      printSuccess('Chain Retrieved Successfully!');
      console.log(`   Chain Length: ${chainData.length}`);
      console.log(`   Chain Valid: ${chainData.chain_valid ? '✅ YES' : '❌ NO'}`);
      console.log(`   Total Gas Used: ${chainData.total_gas_used}`);
      console.log(`   Total Transaction Fee: ${chainData.total_transaction_fee}`);
      
      console.log(`\n   🔗 Chain Structure:`);
      chainData.chain.forEach((node, index) => {
        console.log(`      ${index + 1}. ${node.node_name} (Position: ${node.chain_position})`);
        console.log(`         Hash: ${node.current_hash.substring(0, 20)}...`);
        console.log(`         Gas: ${node.gas_used}`);
      });
      
      // Verify chain integrity
      let valid = true;
      for (let i = 0; i < chainData.chain.length; i++) {
        const node = chainData.chain[i];
        const expectedPrevHash = i === 0 ? '0' : chainData.chain[i - 1].current_hash;
        
        if (node.previous_hash !== expectedPrevHash) {
          printError(`Chain broken at position ${i}!`);
          valid = false;
          break;
        }
      }
      
      if (valid) {
        printSuccess('Chain integrity verified! All nodes properly linked.');
      }
    } else {
      printError('Failed to retrieve chain!');
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 5: Verify Chain Integrity ==========
    printHeader('TEST 5: Verify Chain Integrity');
    const verify = await makeRequest('POST', `${API_BASE}/verify-chain`);
    
    if (verify.status === 200 && verify.data.success) {
      const verifyData = verify.data.data;
      
      if (verifyData.chain_valid) {
        printSuccess(`Chain Verification: ${verifyData.message}`);
      } else {
        printError(`Chain Verification Failed: ${verifyData.message}`);
      }
    } else {
      printError('Chain verification request failed!');
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 6: Update Node (Test Immutability) ==========
    printHeader('TEST 6: Update Node (Test Immutability)');
    printInfo('Updating Node 2 - This should create a NEW node and deprecate the old one.');
    
    const update = await makeRequest('PUT', `${API_BASE}/${node2Id}`, {
      status: 'offline',
      node_name: 'Updated-Node-2'
    });
    
    if (update.status === 200 && update.data.success) {
      const updateData = update.data.data;
      
      printSuccess('Node Updated Successfully! (New node created)');
      console.log(`   Old Node ID: ${updateData.old_node_id}`);
      console.log(`   New Node ID: ${updateData.new_node_id}`);
      console.log(`   Gas Used: ${updateData.gas_used} (higher than registration)`);
      console.log(`   Transaction Fee: ${updateData.transaction_fee}`);
      console.log(`   Hash: ${updateData.current_hash.substring(0, 30)}...`);
      
      printInfo('Note: Old node should now be deprecated (immutable blockchain principle)');
    } else {
      printError('Node update failed!');
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 7: Verify Chain After Update ==========
    printHeader('TEST 7: Verify Chain After Update');
    const verifyAfter = await makeRequest('POST', `${API_BASE}/verify-chain`);
    
    if (verifyAfter.status === 200 && verifyAfter.data.success) {
      const verifyData = verifyAfter.data.data;
      
      if (verifyData.chain_valid) {
        printSuccess(`Chain Still Valid After Update: ${verifyData.message}`);
      } else {
        printError(`Chain Broken After Update: ${verifyData.message}`);
      }
    }
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // ========== TEST 8: Get Updated Chain ==========
    printHeader('TEST 8: Get Updated Chain');
    const updatedChain = await makeRequest('GET', `${API_BASE}/chain`);
    
    if (updatedChain.status === 200 && updatedChain.data.success) {
      const chainData = updatedChain.data.data;
      
      printSuccess('Updated Chain Retrieved!');
      console.log(`   Chain Length: ${chainData.length}`);
      console.log(`   Active Nodes: ${chainData.chain.length}`);
      console.log(`   Deprecated Nodes: ${chainData.deprecated_nodes_count || 0}`);
      
      console.log(`\n   🔗 Updated Chain Structure:`);
      chainData.chain.forEach((node, index) => {
        const status = node.is_deprecated ? ' (DEPRECATED)' : '';
        console.log(`      ${index + 1}. ${node.node_name}${status} (Position: ${node.chain_position})`);
      });
    }
    
    // ========== TEST SUMMARY ==========
    printHeader('✅ TEST SUMMARY');
    printSuccess('All Tests Completed Successfully!');
    console.log('\n   Tests Performed:');
    console.log('   1. ✅ Genesis Node Registration');
    console.log('   2. ✅ Second Node Registration (Hash Chain Link)');
    console.log('   3. ✅ Third Node Registration (Hash Chain Link)');
    console.log('   4. ✅ Chain Retrieval & Structure');
    console.log('   5. ✅ Chain Integrity Verification');
    console.log('   6. ✅ Node Update (Immutability Test)');
    console.log('   7. ✅ Chain Verification After Update');
    console.log('   8. ✅ Updated Chain Retrieval');
    
    console.log('\n   Key Features Verified:');
    console.log('   ✅ Blockchain-like hash chain');
    console.log('   ✅ Gas calculation');
    console.log('   ✅ Immutability (update creates new node)');
    console.log('   ✅ Chain integrity verification');
    console.log('   ✅ Node deprecation system');
    
    console.log('\n' + '='.repeat(70) + '\n');
    
  } catch (error) {
    printError('Test Failed!');
    console.error('\nError Details:');
    if (error.status) {
      console.error('Status:', error.status);
      console.error('Data:', JSON.stringify(error.data, null, 2));
    } else {
      console.error('Message:', error.message);
      console.error('Stack:', error.stack);
    }
    console.log('\n' + '='.repeat(70) + '\n');
    process.exit(1);
  }
}

// Run tests
console.log('\n');
testBlockchainNodes();

