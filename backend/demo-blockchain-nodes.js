/**
 * Visual Demonstration Script for Blockchain-like Node System
 * Shows: Chain structure, hash links, gas calculation, immutability
 */

const http = require('http');

const BASE_URL = 'http://localhost:3000';
const API_BASE = '/api/nodes';

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
  cyan: '\x1b[36m',
  magenta: '\x1b[35m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function printHeader(title) {
  console.log('\n' + '═'.repeat(70));
  log(`  ${title}`, 'cyan');
  console.log('═'.repeat(70));
}

function printNode(node, index, isLast) {
  const isGenesis = node.chain_position === 0;
  const isDeprecated = node.is_deprecated;
  
  console.log('\n' + '─'.repeat(70));
  log(`📍 Node ${index + 1}: ${node.node_name}`, isDeprecated ? 'yellow' : isGenesis ? 'green' : 'blue');
  if (isDeprecated) {
    log('   ⚠️  DEPRECATED (Replaced by newer node)', 'yellow');
  }
  if (isGenesis) {
    log('   🌱 GENESIS NODE', 'green');
  }
  console.log('─'.repeat(70));
  console.log(`   ID: ${node.node_id}`);
  console.log(`   Position: ${node.chain_position}`);
  console.log(`   IP: ${node.ip_address}:${node.tcp_port}`);
  console.log(`   Status: ${node.status || 'online'}`);
  
  log(`\n   🔐 Hash Chain:`, 'magenta');
  const prevHash = node.previous_hash === '0' || !node.previous_hash ? 'GENESIS (0)' : (node.previous_hash.substring(0, 20) + '...');
  const currHash = node.current_hash ? (node.current_hash.substring(0, 20) + '...') : 'undefined';
  console.log(`   Previous Hash: ${prevHash}`);
  console.log(`   Current Hash:  ${currHash}`);
  
  log(`\n   ⛽ Gas Information:`, 'yellow');
  console.log(`   Gas Used: ${node.gas_used}`);
  console.log(`   Gas Price: ${node.gas_price || 1}`);
  console.log(`   Transaction Fee: ${node.transaction_fee}`);
  
  if (node.deprecated_by) {
    log(`\n   🔄 Replaced By: ${node.deprecated_by}`, 'yellow');
  }
  
  if (!isLast) {
    console.log('\n   ⬇️  Linked to next node');
  }
}

function printChainVisualization(chain) {
  console.log('\n' + '═'.repeat(70));
  log('   🔗 HASH CHAIN VISUALIZATION', 'cyan');
  console.log('═'.repeat(70));
  
  chain.forEach((node, index) => {
    const prevHash = node.previous_hash === '0' || !node.previous_hash ? 'GENESIS' : (node.previous_hash.substring(0, 12) + '...');
    const currHash = node.current_hash ? (node.current_hash.substring(0, 12) + '...') : 'undefined';
    const nodeName = (node.node_name || 'Unknown').padEnd(15);
    
    console.log(`   ${index + 1}. ${nodeName} | ${prevHash} → ${currHash}`);
    
    if (index < chain.length - 1) {
      console.log('      ' + '│'.padEnd(30) + '│');
      console.log('      ' + '↓'.padEnd(30) + '↓');
    }
  });
  
  console.log('═'.repeat(70));
}

async function showChain() {
  try {
    const response = await makeRequest('GET', `${API_BASE}/chain`);
    if (response.status !== 200 || !response.data.success) {
      throw new Error('Failed to get chain');
    }
    const chainData = response.data.data;
    
    printHeader('🔗 BLOCKCHAIN NODE CHAIN');
    
    log('\n📊 Chain Statistics:', 'blue');
    console.log(`   Total Nodes: ${chainData.length}`);
    console.log(`   Active Nodes: ${chainData.chain.filter(n => !n.is_deprecated).length}`);
    console.log(`   Deprecated Nodes: ${chainData.chain.filter(n => n.is_deprecated).length}`);
    console.log(`   Chain Valid: ${chainData.chain_valid ? '✅ YES' : '❌ NO'}`);
    log(`   Total Gas Used: ${chainData.total_gas_used}`, 'yellow');
    log(`   Total Transaction Fee: ${chainData.total_transaction_fee}`, 'yellow');
    log(`   Average Gas per Node: ${Math.round(chainData.total_gas_used / chainData.length)}`, 'yellow');
    
    console.log(`\n🔗 Chain Structure:`);
    chainData.chain.forEach((node, index) => {
      printNode(node, index, index === chainData.chain.length - 1);
    });
    
    printChainVisualization(chainData.chain);
    
    return chainData;
  } catch (error) {
    log('❌ Error loading chain:', 'red');
    console.error(error.data || error.message);
    return null;
  }
}

async function registerNode(name, ip, port) {
  try {
    printHeader(`📝 Registering Node: ${name}`);
    
    const response = await makeRequest('POST', `${API_BASE}/register`, {
      node_name: name,
      ip_address: ip,
      tcp_port: port
    });
    
    if (response.status === 201 && response.data.success) {
      const node = response.data.data;
      
      log('\n✅ Node Registered Successfully!', 'green');
      console.log(`   Node ID: ${node.node_id}`);
      console.log(`   Chain Position: ${node.chain_position}`);
      log(`   Gas Used: ${node.gas_used}`, 'yellow');
      log(`   Transaction Fee: ${node.transaction_fee}`, 'yellow');
      console.log(`   Hash: ${node.current_hash.substring(0, 30)}...`);
      console.log(`   Chain Valid: ${node.chain_valid ? '✅' : '❌'}`);
      
      return node;
    }
  } catch (error) {
    log('❌ Registration Error:', 'red');
    console.error(error.data || error.message);
    return null;
  }
}

async function updateNode(nodeId, updates) {
  try {
    printHeader(`🔄 Updating Node: ${nodeId.substring(0, 20)}...`);
    log('   Note: This will create a NEW node (immutable blockchain principle)', 'yellow');
    
    const response = await makeRequest('PUT', `${API_BASE}/${nodeId}`, updates);
    
    if (response.status === 200 && response.data.success) {
      const data = response.data.data;
      
      log('\n✅ Node Updated (New Node Created)!', 'green');
      console.log(`   Old Node ID: ${data.old_node_id}`);
      console.log(`   New Node ID: ${data.new_node_id}`);
      log(`   Gas Used: ${data.gas_used} (higher than registration)`, 'yellow');
      log(`   Transaction Fee: ${data.transaction_fee}`, 'yellow');
      console.log(`   Hash: ${data.current_hash.substring(0, 30)}...`);
      log('\n⚠️  Note: Old node is now deprecated (immutable blockchain)', 'yellow');
      
      return data;
    }
  } catch (error) {
    log('❌ Update Error:', 'red');
    console.error(error.data || error.message);
    return null;
  }
}

async function verifyChain() {
  try {
    printHeader('🔍 Verifying Chain Integrity');
    
    const response = await makeRequest('POST', `${API_BASE}/verify-chain`);
    
    if (response.status === 200 && response.data.success) {
      const data = response.data.data;
      
      if (data.chain_valid) {
        log(`\n✅ Chain Status: ${data.message}`, 'green');
      } else {
        log(`\n❌ Chain Status: ${data.message}`, 'red');
      }
      
      return data.chain_valid;
    }
  } catch (error) {
    log('❌ Verification Error:', 'red');
    console.error(error.data || error.message);
    return false;
  }
}

// Main demo flow
async function runDemo() {
  console.clear();
  log('\n🚀 BLOCKCHAIN NODE SYSTEM - VISUAL DEMONSTRATION\n', 'cyan');
  log('This demo will show:', 'blue');
  log('  1. Node registration with gas calculation', 'blue');
  log('  2. Hash chain linking between nodes', 'blue');
  log('  3. Chain integrity verification', 'blue');
  log('  4. Immutability (update creates new node)', 'blue');
  log('  5. Node deprecation system', 'blue');
  
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Step 1: Register nodes
  log('\n📝 STEP 1: Registering Nodes...\n', 'cyan');
  
  const node1 = await registerNode('Genesis-Node', '192.168.1.100', 3001);
  await new Promise(resolve => setTimeout(resolve, 1500));
  
  const node2 = await registerNode('Node-2', '192.168.1.101', 3002);
  await new Promise(resolve => setTimeout(resolve, 1500));
  
  const node3 = await registerNode('Node-3', '192.168.1.102', 3003);
  await new Promise(resolve => setTimeout(resolve, 1500));
  
  // Step 2: Show chain
  log('\n📊 STEP 2: Displaying Chain Structure...\n', 'cyan');
  await showChain();
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Step 3: Verify chain
  log('\n🔍 STEP 3: Verifying Chain Integrity...\n', 'cyan');
  await verifyChain();
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Step 4: Update a node (demonstrates immutability)
  if (node2) {
    log('\n🔄 STEP 4: Updating Node (Testing Immutability)...\n', 'cyan');
    await updateNode(node2.node_id, { 
      status: 'offline',
      node_name: 'Updated-Node-2'
    });
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Show updated chain
    log('\n📊 STEP 5: Displaying Updated Chain...\n', 'cyan');
    await showChain();
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Verify again
    log('\n🔍 STEP 6: Verifying Chain After Update...\n', 'cyan');
    await verifyChain();
  }
  
  // Final summary
  printHeader('✅ DEMONSTRATION COMPLETE');
  log('\nKey Features Demonstrated:', 'green');
  console.log('  ✅ Blockchain-like hash chain');
  console.log('  ✅ Gas calculation for each operation');
  console.log('  ✅ Immutability (updates create new nodes)');
  console.log('  ✅ Chain integrity verification');
  console.log('  ✅ Node deprecation system');
  console.log('  ✅ Professional blockchain implementation');
  
  log('\n🎉 Thank you for watching the demonstration!\n', 'cyan');
}

// Run demo
runDemo().catch(error => {
  log('❌ Demo Error:', 'red');
  console.error(error);
  process.exit(1);
});

