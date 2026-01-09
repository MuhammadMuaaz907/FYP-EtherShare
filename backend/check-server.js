/**
 * Server Health Check Script
 * Run this to verify server is accessible
 */

require('dotenv').config();
const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 3000;

// Get local IP
function getLocalIP() {
  const networkInterfaces = os.networkInterfaces();
  for (const interfaceName in networkInterfaces) {
    const addresses = networkInterfaces[interfaceName];
    for (const addr of addresses) {
      if (addr.family === 'IPv4' && !addr.internal) {
        return addr.address;
      }
    }
  }
  return 'localhost';
}

const localIP = getLocalIP();

console.log('\n' + '='.repeat(60));
console.log('🔍 Server Accessibility Check');
console.log('='.repeat(60));

// Test localhost
console.log('\n1️⃣ Testing localhost connection...');
const localhostTest = http.get(`http://localhost:${PORT}/health`, (res) => {
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    console.log('   ✅ Localhost: OK');
    console.log('   Response:', JSON.parse(data));
  });
}).on('error', (err) => {
  console.log('   ❌ Localhost: FAILED');
  console.log('   Error:', err.message);
  console.log('   💡 Make sure server is running: npm run dev');
});

// Test network IP
console.log('\n2️⃣ Testing network IP connection...');
const networkTest = http.get(`http://${localIP}:${PORT}/health`, (res) => {
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    console.log(`   ✅ Network IP (${localIP}): OK`);
    console.log('   Response:', JSON.parse(data));
  });
}).on('error', (err) => {
  console.log(`   ❌ Network IP (${localIP}): FAILED`);
  console.log('   Error:', err.message);
  console.log('   💡 Possible issues:');
  console.log('      - Windows Firewall blocking port 3000');
  console.log('      - Server not listening on 0.0.0.0');
  console.log('      - Network connectivity issue');
});

// Check if port is listening
console.log('\n3️⃣ Checking if port is listening...');
const net = require('net');
const socket = new net.Socket();
socket.setTimeout(2000);

socket.on('connect', () => {
  console.log(`   ✅ Port ${PORT} is listening`);
  socket.destroy();
});

socket.on('timeout', () => {
  console.log(`   ❌ Port ${PORT} is NOT listening`);
  console.log('   💡 Start server: npm run dev');
  socket.destroy();
});

socket.on('error', (err) => {
  console.log(`   ❌ Port ${PORT} is NOT accessible`);
  console.log('   Error:', err.message);
  socket.destroy();
});

socket.connect(PORT, 'localhost');

// Summary
setTimeout(() => {
  console.log('\n' + '='.repeat(60));
  console.log('📋 Summary');
  console.log('='.repeat(60));
  console.log(`📍 Server should be accessible at:`);
  console.log(`   - Local: http://localhost:${PORT}`);
  console.log(`   - Network: http://${localIP}:${PORT}`);
  console.log(`   - Android Emulator: http://10.0.2.2:${PORT}`);
  console.log('\n💡 For Flutter app, use network IP:');
  console.log(`   DistributedService.setRealDeviceHost('${localIP}');`);
  console.log('='.repeat(60) + '\n');
}, 3000);

