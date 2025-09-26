const { createHelia } = require('helia');
const { createOrbitDB } = require('@orbitdb/core');
const { v4: uuidv4 } = require('uuid');

let helia;
let orbitdb;
const dbs = new Map(); // Map to store opened OrbitDB instances
let methodChannel; // To send data back to Flutter

// Function to set the MethodChannel for Flutter communication
function setMethodChannel(channel) {
  methodChannel = channel;
}

// Initialize Helia and OrbitDB
async function init() {
  try {
    console.log('Node.js Bridge: Initializing Helia and OrbitDB...');

    // Create Helia instance with minimal configuration for mobile
    helia = await createHelia({
      // Use in-memory storage for mobile optimization
      storage: {
        blocks: new Map(),
        pins: new Map()
      }
    });

    // Create OrbitDB instance
    orbitdb = await createOrbitDB({ ipfs: helia });

    console.log('Node.js Bridge: Helia and OrbitDB initialized successfully');
    console.log('Node.js Bridge: Helia ID:', helia.libp2p.peerId.toString());
    
    return {
      success: true,
      heliaId: helia.libp2p.peerId.toString(),
      message: 'OrbitDB and Helia initialized successfully'
    };
  } catch (error) {
    console.error('Node.js Bridge: Initialization failed:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Create a chat database
async function createChatDB(name) {
  try {
    console.log(`Node.js Bridge: Creating chat database: ${name}`);
    
    const db = await orbitdb.open(name, {
      type: 'eventlog',
      create: true
    });

    // Store the database reference
    dbs.set(name, db);
    
    console.log(`Node.js Bridge: Chat database created: ${db.address}`);
    
    return {
      success: true,
      address: db.address.toString(),
      message: `Chat database '${name}' created successfully`
    };
  } catch (error) {
    console.error('Node.js Bridge: Failed to create chat database:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Add a message to a database
async function addMessage(address, message) {
  try {
    console.log(`Node.js Bridge: Adding message to ${address}`);
    
    // Find the database by address
    let db = null;
    for (const [name, database] of dbs.entries()) {
      if (database.address.toString() === address) {
        db = database;
        break;
      }
    }

    if (!db) {
      throw new Error(`Database with address ${address} not found`);
    }

    // Add message with unique ID and timestamp
    const messageWithId = {
      id: uuidv4(),
      timestamp: Date.now(),
      ...message
    };

    const hash = await db.add(messageWithId);
    
    console.log(`Node.js Bridge: Message added with hash: ${hash}`);
    
    return {
      success: true,
      hash: hash,
      messageId: messageWithId.id,
      message: 'Message added successfully'
    };
  } catch (error) {
    console.error('Node.js Bridge: Failed to add message:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Get messages from a database
async function getMessages(address) {
  try {
    console.log(`Node.js Bridge: Getting messages from ${address}`);
    
    // Find the database by address
    let db = null;
    for (const [name, database] of dbs.entries()) {
      if (database.address.toString() === address) {
        db = database;
        break;
      }
    }

    if (!db) {
      throw new Error(`Database with address ${address} not found`);
    }

    // Load all messages
    await db.load();
    const messages = db.iterator({ limit: -1 }).collect();
    
    console.log(`Node.js Bridge: Retrieved ${messages.length} messages`);
    
    return {
      success: true,
      messages: messages.map(msg => msg.payload.value),
      count: messages.length
    };
  } catch (error) {
    console.error('Node.js Bridge: Failed to get messages:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Load updates from a database (for real-time sync)
async function loadUpdates(address) {
  try {
    console.log(`Node.js Bridge: Loading updates from ${address}`);
    
    // Find the database by address
    let db = null;
    for (const [name, database] of dbs.entries()) {
      if (database.address.toString() === address) {
        db = database;
        break;
      }
    }

    if (!db) {
      throw new Error(`Database with address ${address} not found`);
    }

    // Set up event listener for new messages
    db.events.on('replicated', async () => {
      console.log('Node.js Bridge: Database replicated, sending update to Flutter');
      
      if (methodChannel) {
        const messages = db.iterator({ limit: -1 }).collect();
        const latestMessages = messages.map(msg => msg.payload.value);
        
        // Send update to Flutter
        methodChannel.invokeMethod('onMessageUpdate', {
          address: address,
          messages: latestMessages
        });
      }
    });

    return {
      success: true,
      message: 'Update listener set up successfully'
    };
  } catch (error) {
    console.error('Node.js Bridge: Failed to load updates:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

// Stop the bridge
async function stop() {
  try {
    console.log('Node.js Bridge: Stopping...');
    
    // Close all databases
    for (const [name, db] of dbs.entries()) {
      await db.close();
    }
    dbs.clear();

    // Stop Helia
    if (helia) {
      await helia.stop();
    }

    console.log('Node.js Bridge: Stopped successfully');
    return { success: true };
  } catch (error) {
    console.error('Node.js Bridge: Error stopping:', error);
    return { success: false, error: error.message };
  }
}

// Export functions for use in Flutter
module.exports = {
  setMethodChannel,
  init,
  createChatDB,
  addMessage,
  getMessages,
  loadUpdates,
  stop
};
