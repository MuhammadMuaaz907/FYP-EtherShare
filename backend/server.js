require('dotenv').config();
const express = require('express');
const cors = require('cors');
const database = require('./config/database');

// Import routes
const usersRoutes = require('./routes/users');
const workspacesRoutes = require('./routes/workspaces');
const messagesRoutes = require('./routes/messages');
const membersRoutes = require('./routes/members');
const filesRoutes = require('./routes/files');
const nodesRoutes = require('./routes/nodes');
const channelsRoutes = require('./routes/channels');
const peersRoutes = require('./routes/peers');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
// CORS Configuration: Allow all origins (including Cloudflare Tunnel)
// For production, set CORS_ORIGIN in .env to specific domains
app.use(cors({
  origin: process.env.CORS_ORIGIN?.split(',') || '*',
  credentials: true
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`📥 ${req.method} ${req.path} - ${new Date().toISOString()}`);
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'EtherShare Backend API is running',
    timestamp: new Date().toISOString(),
    database: database.isConnected() ? 'connected' : 'disconnected'
  });
});

// API Routes
app.use('/api/users', usersRoutes);
app.use('/api/workspaces', workspacesRoutes);
app.use('/api/messages', messagesRoutes);
app.use('/api/members', membersRoutes);
app.use('/api/files', filesRoutes);
app.use('/api/nodes', nodesRoutes);
app.use('/api/channels', channelsRoutes);
app.use('/api/peers', peersRoutes);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Welcome to EtherShare Backend API',
    version: '1.0.0',
      endpoints: {
        health: '/health',
        users: '/api/users',
        workspaces: '/api/workspaces',
        messages: '/api/messages',
        members: '/api/members',
        files: '/api/files',
        nodes: '/api/nodes',
        channels: '/api/channels'
      }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Route not found',
    message: `Cannot ${req.method} ${req.path}`
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('❌ Server Error:', err);
  res.status(err.status || 500).json({
    success: false,
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong'
  });
});

// Start server
async function startServer() {
  try {
    // Connect to MongoDB
    await database.connect();
    
    // Get local IP address for network access
    const os = require('os');
    const networkInterfaces = os.networkInterfaces();
    let localIP = 'localhost';
    
    // Find first non-internal IPv4 address (for real device access)
    for (const interfaceName in networkInterfaces) {
      const addresses = networkInterfaces[interfaceName];
      for (const addr of addresses) {
        if (addr.family === 'IPv4' && !addr.internal) {
          localIP = addr.address;
          break;
        }
      }
      if (localIP !== 'localhost') break;
    }
    
    // Start Express server on all interfaces (0.0.0.0) to allow network access
    // This allows connections from:
    // - localhost (127.0.0.1)
    // - local network IP (192.168.0.35)
    // - Android emulator (10.0.2.2)
    app.listen(PORT, '0.0.0.0', () => {
      console.log('\n' + '='.repeat(60));
      console.log('🚀 EtherShare Backend Server Started');
      console.log('='.repeat(60));
      console.log(`📍 Local: http://localhost:${PORT}`);
      console.log(`🌐 Network: http://${localIP}:${PORT}`);
      console.log(`📱 Android Emulator: http://10.0.2.2:${PORT}`);
      console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
      console.log(`💾 Database: ${database.isConnected() ? 'Connected ✅' : 'Disconnected ❌'}`);
      console.log('='.repeat(60));
      console.log('💡 For real Android device, use network IP in Flutter app:');
      console.log(`   DistributedService.setRealDeviceHost('${localIP}');`);
      console.log('='.repeat(60));
      console.log('🌐 Cloudflare Tunnel (if configured):');
      console.log('   Set BACKEND_URL in blockchain_fyp/.env to your tunnel URL');
      console.log('   Example: BACKEND_URL=https://your-tunnel.trycloudflare.com');
      console.log('='.repeat(60));
      console.log('⚠️  IMPORTANT: If IP changes, update Flutter app IP address!');
      console.log('='.repeat(60) + '\n');
      
      // Verify server is actually listening
      const net = require('net');
      const testSocket = new net.Socket();
      testSocket.setTimeout(1000);
      testSocket.on('connect', () => {
        console.log('✅ Server verified: Port is listening and accessible');
        testSocket.destroy();
      });
      testSocket.on('error', () => {
        console.log('⚠️  Warning: Port might not be accessible from network');
        console.log('   Check Windows Firewall settings');
      });
      testSocket.connect(PORT, 'localhost');
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGTERM', async () => {
  console.log('\n⚠️ SIGTERM received, shutting down gracefully...');
  await database.disconnect();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('\n⚠️ SIGINT received, shutting down gracefully...');
  await database.disconnect();
  process.exit(0);
});

// Start the server
startServer();

module.exports = app;

