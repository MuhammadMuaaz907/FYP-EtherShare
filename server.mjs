// Alternative OrbitDB server implementation
// This approach avoids the webrtc-direct protocol issues
// by using a simpler HTTP-based solution

import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';

const app = express();
app.use(cors());
app.use(express.json());

// Simple in-memory storage for demo purposes
// In production, you'd want to use a proper database
const databases = new Map();
const dataStore = new Map();

// Create a simple database
app.post('/create-db', async (req, res) => {
  try {
    const dbName = req.body.dbName;
    const dbType = req.body.dbType || 'keyvalue';
    
    if (!dbName) {
      return res.status(400).json({ error: 'dbName is required' });
    }

    // Generate a unique database address
    const dbAddress = `orbitdb://${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    // Initialize the database
    databases.set(dbAddress, {
      name: dbName,
      type: dbType,
      createdAt: new Date().toISOString()
    });

    console.log(`Database created: ${dbName} with address: ${dbAddress}`);
    res.json({ address: dbAddress });
  } catch (e) {
    console.error('Error in /create-db:', e);
    res.status(500).json({ error: e.message || e.toString() });
  }
});

// Add data to database
app.post('/add-data', async (req, res) => {
  try {
    const { dbAddress, key, value } = req.body;
    
    if (!dbAddress || !key) {
      return res.status(400).json({ error: 'dbAddress and key are required' });
    }

    // Check if database exists
    if (!databases.has(dbAddress)) {
      return res.status(404).json({ error: 'Database not found' });
    }

    // Store the data with a unique key
    const dataKey = `${dbAddress}:${key}`;
    dataStore.set(dataKey, {
      value: value,
      timestamp: new Date().toISOString(),
      dbAddress: dbAddress
    });

    console.log(`Data added to ${dbAddress}: ${key} = ${value}`);
    res.json({ success: true, message: 'Data stored successfully' });
  } catch (e) {
    console.error('Error in /add-data:', e);
    res.status(500).json({ error: e.message || e.toString() });
  }
});

// Get data from database
app.get('/get-data/:dbAddress/:key', async (req, res) => {
  try {
    const { dbAddress, key } = req.params;
    
    if (!dbAddress || !key) {
      return res.status(400).json({ error: 'dbAddress and key are required' });
    }

    // Check if database exists
    if (!databases.has(dbAddress)) {
      return res.status(404).json({ error: 'Database not found' });
    }

    // Retrieve the data
    const dataKey = `${dbAddress}:${key}`;
    const data = dataStore.get(dataKey);

    if (!data) {
      return res.status(404).json({ error: 'Data not found' });
    }

    res.json({ value: data.value, timestamp: data.timestamp });
  } catch (e) {
    console.error('Error in /get-data:', e);
    res.status(500).json({ error: e.message || e.toString() });
  }
});

// List all databases
app.get('/list-dbs', async (req, res) => {
  try {
    const dbList = Array.from(databases.entries()).map(([address, db]) => ({
      address: address,
      name: db.name,
      type: db.type,
      createdAt: db.createdAt
    }));
    
    res.json({ databases: dbList });
  } catch (e) {
    console.error('Error in /list-dbs:', e);
    res.status(500).json({ error: e.message || e.toString() });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    message: 'OrbitDB server is running',
    timestamp: new Date().toISOString(),
    databasesCount: databases.size,
    dataCount: dataStore.size
  });
});

// Start the server
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🚀 OrbitDB server running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`📋 List databases: http://localhost:${PORT}/list-dbs`);
  console.log('✅ Ready to accept connections from your Flutter app!');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down OrbitDB server...');
  process.exit(0);
});