/**
 * Clean Nodes Script
 * Removes all nodes from database for fresh testing
 * 
 * Usage: node scripts/clean-nodes.js
 */

const mongoose = require('mongoose');
const Node = require('../models/node');
require('dotenv').config();

async function cleanNodes() {
  try {
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/ethershare', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    });
    
    console.log('✅ Connected to MongoDB');
    
    // Count existing nodes
    const countBefore = await Node.countDocuments();
    console.log(`\n📊 Existing nodes: ${countBefore}`);
    
    if (countBefore === 0) {
      console.log('✅ Database is already clean!');
      await mongoose.connection.close();
      return;
    }
    
    // Delete all nodes
    const result = await Node.deleteMany({});
    
    console.log(`\n🗑️  Deleted ${result.deletedCount} nodes`);
    console.log('✅ Database cleaned successfully!');
    console.log('\n💡 You can now run tests with a fresh database.\n');
    
    await mongoose.connection.close();
  } catch (error) {
    console.error('❌ Error cleaning nodes:', error);
    process.exit(1);
  }
}

// Run cleanup
cleanNodes();

