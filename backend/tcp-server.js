const net = require('net');
const crypto = require('crypto');
const NodeService = require('./services/nodeService');
const LedgerService = require('./services/ledgerService');
const database = require('./config/database');

/**
 * TCP Server for P2P Communication
 * Handles direct node-to-node communication
 */
class TCPServer {
  constructor(port = 3001) {
    this.port = port;
    this.server = null;
    this.clients = new Map(); // Map of connected clients
    this.nodeId = null;
  }

  /**
   * Start TCP server
   */
  async start() {
    try {
      // Connect to MongoDB first
      await database.connect();
      
      // Register this node
      const os = require('os');
      const networkInterfaces = os.networkInterfaces();
      let ipAddress = '127.0.0.1';
      
      // Find first non-internal IPv4 address
      for (const interfaceName in networkInterfaces) {
        const addresses = networkInterfaces[interfaceName];
        for (const addr of addresses) {
          if (addr.family === 'IPv4' && !addr.internal) {
            ipAddress = addr.address;
            break;
          }
        }
        if (ipAddress !== '127.0.0.1') break;
      }
      
      const nodeData = await NodeService.registerNode({
        node_name: `Node-${crypto.randomBytes(4).toString('hex')}`,
        ip_address: ipAddress,
        tcp_port: this.port
      });
      
      this.nodeId = nodeData.node_id;
      console.log(`✅ Node registered: ${this.nodeId}`);
      
      // Build chain
      await NodeService.buildChain();
      
      // Create TCP server
      this.server = net.createServer((socket) => {
        this.handleConnection(socket);
      });
      
      this.server.listen(this.port, () => {
        console.log(`\n${'='.repeat(50)}`);
        console.log('🌐 TCP P2P Server Started');
        console.log('='.repeat(50));
        console.log(`📍 Listening on: ${ipAddress}:${this.port}`);
        console.log(`🆔 Node ID: ${this.nodeId}`);
        console.log('='.repeat(50) + '\n');
      });
      
      this.server.on('error', (error) => {
        console.error('❌ TCP Server error:', error);
      });
      
      // Discover and connect to other nodes
      this.discoverNodes();
      
    } catch (error) {
      console.error('❌ Failed to start TCP server:', error);
      throw error;
    }
  }

  /**
   * Handle new TCP connection
   */
  handleConnection(socket) {
    const clientId = `${socket.remoteAddress}:${socket.remotePort}`;
    console.log(`📡 New TCP connection: ${clientId}`);
    
    this.clients.set(clientId, {
      socket: socket,
      connectedAt: Date.now(),
      nodeId: null
    });
    
    socket.on('data', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        await this.handleMessage(clientId, message);
      } catch (error) {
        console.error('❌ Error parsing message:', error);
        socket.write(JSON.stringify({
          type: 'error',
          message: 'Invalid message format'
        }));
      }
    });
    
    socket.on('close', () => {
      console.log(`🔌 Connection closed: ${clientId}`);
      this.clients.delete(clientId);
    });
    
    socket.on('error', (error) => {
      console.error(`❌ Socket error for ${clientId}:`, error);
      this.clients.delete(clientId);
    });
  }

  /**
   * Handle incoming messages
   */
  async handleMessage(clientId, message) {
    const client = this.clients.get(clientId);
    if (!client) return;
    
    try {
      switch (message.type) {
        case 'handshake':
          client.nodeId = message.node_id;
          client.socket.write(JSON.stringify({
            type: 'handshake_ack',
            node_id: this.nodeId,
            message: 'Connection established'
          }));
          break;
          
        case 'message':
          // Route message: UserA → Node1 → Node2 → UserB
          await this.routeMessage(message);
          break;
          
        case 'sync_request':
          // Sync ledger data
          await this.syncLedger(client, message);
          break;
          
        case 'chain_verify':
          // Verify chain integrity
          const isValid = await LedgerService.verifyChain(message.node_id);
          client.socket.write(JSON.stringify({
            type: 'chain_verify_response',
            node_id: message.node_id,
            valid: isValid
          }));
          break;
          
        default:
          client.socket.write(JSON.stringify({
            type: 'error',
            message: 'Unknown message type'
          }));
      }
    } catch (error) {
      console.error('❌ Handle message error:', error);
      client.socket.write(JSON.stringify({
        type: 'error',
        message: error.message
      }));
    }
  }

  /**
   * Route message through chain
   */
  async routeMessage(message) {
    try {
      // Add to local ledger
      const block = await LedgerService.addBlock(this.nodeId, {
        type: 'message',
        sender_address: message.sender_address,
        receiver_address: message.receiver_address,
        content: message.content,
        workspace_id: message.workspace_id
      });
      
      console.log(`📨 Message routed: ${message.sender_address} → ${message.receiver_address}`);
      
      // Forward to next node in chain if not destination
      const chain = await NodeService.getChain();
      const currentNode = chain.chain.find(n => n.node_id === this.nodeId);
      
      if (currentNode && currentNode.next_node_id) {
        // Forward to next node
        await this.forwardToNode(currentNode.next_node_id, message);
      } else {
        // This might be the destination node
        console.log(`✅ Message reached node: ${this.nodeId}`);
      }
      
    } catch (error) {
      console.error('❌ Route message error:', error);
      throw error;
    }
  }

  /**
   * Forward message to another node
   */
  async forwardToNode(targetNodeId, message) {
    try {
      const chain = await NodeService.getChain();
      const targetNode = chain.chain.find(n => n.node_id === targetNodeId);
      
      if (!targetNode) {
        console.error(`❌ Target node not found: ${targetNodeId}`);
        return;
      }
      
      // Try to connect and send
      const client = new net.Socket();
      
      client.connect(targetNode.tcp_port, targetNode.ip_address, () => {
        console.log(`🔗 Connected to node: ${targetNodeId}`);
        
        // Send handshake
        client.write(JSON.stringify({
          type: 'handshake',
          node_id: this.nodeId
        }));
        
        // Send message
        setTimeout(() => {
          client.write(JSON.stringify({
            type: 'message',
            ...message
          }));
        }, 100);
      });
      
      client.on('error', (error) => {
        console.error(`❌ Failed to connect to node ${targetNodeId}:`, error.message);
      });
      
      client.on('close', () => {
        console.log(`🔌 Connection to ${targetNodeId} closed`);
      });
      
    } catch (error) {
      console.error('❌ Forward to node error:', error);
    }
  }

  /**
   * Sync ledger with peer
   */
  async syncLedger(client, message) {
    try {
      const ledger = await LedgerService.getLedger(this.nodeId, 100);
      client.socket.write(JSON.stringify({
        type: 'sync_response',
        node_id: this.nodeId,
        ledger: ledger
      }));
    } catch (error) {
      console.error('❌ Sync ledger error:', error);
    }
  }

  /**
   * Discover and connect to other nodes
   */
  async discoverNodes() {
    try {
      const nodes = await NodeService.getOnlineNodes();
      const otherNodes = nodes.filter(n => n.node_id !== this.nodeId);
      
      console.log(`🔍 Found ${otherNodes.length} other nodes`);
      
      for (const node of otherNodes) {
        // Try to connect
        setTimeout(() => {
          this.connectToNode(node);
        }, 1000 * otherNodes.indexOf(node));
      }
    } catch (error) {
      console.error('❌ Discover nodes error:', error);
    }
  }

  /**
   * Connect to a peer node
   */
  connectToNode(node) {
    const client = new net.Socket();
    
    client.connect(node.tcp_port, node.ip_address, () => {
      console.log(`✅ Connected to peer: ${node.node_id}`);
      
      // Send handshake
      client.write(JSON.stringify({
        type: 'handshake',
        node_id: this.nodeId
      }));
      
      // Store connection
      const clientId = `${node.ip_address}:${node.tcp_port}`;
      this.clients.set(clientId, {
        socket: client,
        connectedAt: Date.now(),
        nodeId: node.node_id
      });
    });
    
    client.on('data', (data) => {
      try {
        const message = JSON.parse(data.toString());
        if (message.type === 'handshake_ack') {
          console.log(`✅ Handshake confirmed with: ${node.node_id}`);
        }
      } catch (error) {
        console.error('❌ Error parsing peer message:', error);
      }
    });
    
    client.on('error', (error) => {
      console.error(`❌ Connection error to ${node.node_id}:`, error.message);
    });
    
    client.on('close', () => {
      console.log(`🔌 Connection closed to ${node.node_id}`);
    });
  }

  /**
   * Stop TCP server
   */
  async stop() {
    return new Promise((resolve) => {
      if (this.server) {
        this.server.close(() => {
          console.log('✅ TCP Server stopped');
          resolve();
        });
      } else {
        resolve();
      }
    });
  }
}

// Start server if run directly
if (require.main === module) {
  require('dotenv').config();
  const port = process.env.TCP_PORT || 3001;
  const server = new TCPServer(port);
  server.start().catch(console.error);
  
  // Graceful shutdown
  process.on('SIGTERM', async () => {
    await server.stop();
    process.exit(0);
  });
  
  process.on('SIGINT', async () => {
    await server.stop();
    process.exit(0);
  });
}

module.exports = TCPServer;

