import { createHelia } from 'helia';
import { createOrbitDB } from '@orbitdb/core';
import { v4 as uuidv4 } from 'uuid';
import { LevelBlockstore } from 'blockstore-level';
import { createLibp2p } from 'libp2p';
import { gossipsub } from '@libp2p/gossipsub';
import { identify } from '@libp2p/identify';
import { tcp } from '@libp2p/tcp';
import { noise } from '@chainsafe/libp2p-noise';
import { yamux } from '@chainsafe/libp2p-yamux';
import { webSockets } from '@libp2p/websockets';
import { bootstrap } from '@libp2p/bootstrap';

// Global variables for Helia and OrbitDB instances
let helia = null;
let orbitdb = null;
let isInitialized = false;

// Create a lightweight Libp2p configuration for mobile
async function createLibp2pNode() {
  return await createLibp2p({
    addresses: {
      listen: [
        '/ip4/0.0.0.0/tcp/0',
        '/ip4/0.0.0.0/tcp/0/ws'
      ]
    },
    transports: [
      tcp(),
      webSockets()
    ],
    connectionEncryption: [noise()],
    streamMuxers: [yamux()],
    services: {
      identify: identify(),
      pubsub: gossipsub({
        allowPublishToZeroPeers: true,
        emitSelf: true
      })
    },
    peerDiscovery: [
      bootstrap({
        list: [
          '/dnsaddr/bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
          '/dnsaddr/bootstrap.libp2p.io/tcp/443/wss/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
          '/dnsaddr/bootstrap.libp2p.io/tcp/443/wss/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiNNNs6F5q5eA4Tu37bg',
          '/dnsaddr/bootstrap.libp2p.io/tcp/443/wss/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt'
        ]
      })
    ]
  });
}

// Initialize Helia and OrbitDB
export async function init() {
  try {
    console.log('🚀 Initializing OrbitDB Bridge...');
    
    // Create blockstore for Helia
    const blockstore = new LevelBlockstore('./helia-data');
    
    // Create Libp2p node
    const libp2p = await createLibp2pNode();
    
    // Create Helia instance
    helia = await createHelia({
      blockstore,
      libp2p
    });
    
    console.log('✅ Helia IPFS initialized');
    console.log('📊 Helia ID:', helia.libp2p.peerId.toString());
    
    // Create OrbitDB instance
    orbitdb = await createOrbitDB(helia);
    
    console.log('✅ OrbitDB initialized');
    console.log('📊 OrbitDB ID:', orbitdb.id);
    
    isInitialized = true;
    
    return {
      success: true,
      heliaId: helia.libp2p.peerId.toString(),
      orbitdbId: orbitdb.id,
      message: 'OrbitDB Bridge initialized successfully'
    };
    
  } catch (error) {
    console.error('❌ Failed to initialize OrbitDB Bridge:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Create a chat database (EventLog)
export async function createChatDB(dbName) {
  try {
    if (!isInitialized || !orbitdb) {
      throw new Error('OrbitDB not initialized');
    }
    
    console.log(`📁 Creating chat database: ${dbName}`);
    
    // Create EventLog database for chat messages
    const db = await orbitdb.open(dbName, {
      type: 'eventlog',
      accessController: {
        write: ['*'] // Allow all peers to write for now
      }
    });
    
    // Load the database
    await db.load();
    
    console.log(`✅ Chat database created: ${db.address.toString()}`);
    
    return {
      success: true,
      address: db.address.toString(),
      dbName: dbName,
      message: 'Chat database created successfully'
    };
    
  } catch (error) {
    console.error('❌ Failed to create chat database:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Add a message to the chat database
export async function addMessage(address, msgObj) {
  try {
    if (!isInitialized || !orbitdb) {
      throw new Error('OrbitDB not initialized');
    }
    
    console.log(`💬 Adding message to database: ${address}`);
    console.log(`📋 Message object:`, JSON.stringify(msgObj, null, 2));
    
    // Open the database by address
    const db = await orbitdb.open(address);
    await db.load();
    
    // Create message object - preserve ALL fields from msgObj
    // Add required fields with defaults if not present
    const message = {
      id: msgObj.id || uuidv4(),
      timestamp: msgObj.timestamp || Date.now(),
      // Preserve all fields from the original message object
      ...msgObj,
      // Ensure required fields have defaults if not provided
      text: msgObj.text || msgObj.content || '',
      cid: msgObj.cid || '',
      sender: msgObj.sender || msgObj.senderName || 'unknown',
      type: msgObj.type || 'text',
      fileName: msgObj.fileName || '',
      fileSize: msgObj.fileSize || 0
    };
    
    console.log(`📝 Final message to save:`, JSON.stringify(message, null, 2));
    
    // Add message to database
    const hash = await db.add(message);
    
    console.log(`✅ Message added with hash: ${hash}`);
    
    return {
      success: true,
      hash: hash,
      messageId: message.id,
      message: 'Message added successfully'
    };
    
  } catch (error) {
    console.error('❌ Failed to add message:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Get all messages from the chat database
export async function getMessages(address) {
  try {
    if (!isInitialized || !orbitdb) {
      throw new Error('OrbitDB not initialized');
    }
    
    console.log(`📨 Getting messages from database: ${address}`);
    
    // Open the database by address
    const db = await orbitdb.open(address);
    await db.load();
    
    // Get all messages - extract payload values
    const allEntries = db.iterator({ limit: -1 }).collect();
    const messages = allEntries.map(entry => {
      // Extract the value from the entry
      const value = entry.payload.value;
      console.log(`📄 Message entry:`, JSON.stringify(value, null, 2));
      return value;
    });
    
    console.log(`✅ Retrieved ${messages.length} messages`);
    console.log(`📊 Sample message:`, messages.length > 0 ? JSON.stringify(messages[0], null, 2) : 'No messages');
    
    return {
      success: true,
      messages: messages,
      count: messages.length,
      message: 'Messages retrieved successfully'
    };
    
  } catch (error) {
    console.error('❌ Failed to get messages:', error);
    return {
      success: false,
      error: error.message,
      messages: []
    };
  }
}

// Set up real-time updates for a database
export async function loadUpdates(address, callback) {
  try {
    if (!isInitialized || !orbitdb) {
      throw new Error('OrbitDB not initialized');
    }
    
    console.log(`🔄 Setting up real-time updates for: ${address}`);
    
    // Open the database by address
    const db = await orbitdb.open(address);
    await db.load();
    
    // Listen for updates
    db.events.on('update', (entry) => {
      console.log('📨 New message received:', entry);
      if (callback) {
        callback(entry);
      }
    });
    
    console.log('✅ Real-time updates enabled');
    
    return {
      success: true,
      message: 'Real-time updates enabled'
    };
    
  } catch (error) {
    console.error('❌ Failed to setup real-time updates:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Get the status of the OrbitDB Bridge
export async function getStatus() {
  try {
    return {
      success: true,
      initialized: isInitialized,
      heliaId: helia ? helia.libp2p.peerId.toString() : null,
      orbitdbId: orbitdb ? orbitdb.id : null,
      peerCount: helia ? helia.libp2p.getPeers().length : 0,
      message: isInitialized ? 'OrbitDB Bridge is running' : 'OrbitDB Bridge not initialized'
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

// Stop the OrbitDB Bridge
export async function stop() {
  try {
    console.log('🛑 Stopping OrbitDB Bridge...');
    
    if (orbitdb) {
      await orbitdb.stop();
      orbitdb = null;
    }
    
    if (helia) {
      await helia.stop();
      helia = null;
    }
    
    isInitialized = false;
    
    console.log('✅ OrbitDB Bridge stopped');
    
    return {
      success: true,
      message: 'OrbitDB Bridge stopped successfully'
    };
    
  } catch (error) {
    console.error('❌ Failed to stop OrbitDB Bridge:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Export all functions for use in Flutter
export default {
  init,
  createChatDB,
  addMessage,
  getMessages,
  loadUpdates,
  getStatus,
  stop
};
