const mongoose = require('mongoose');

/**
 * MongoDB Connection Service
 * Handles connection to MongoDB with proper error handling
 */
class Database {
  constructor() {
    this.connection = null;
  }

  /**
   * Connect to MongoDB
   * @returns {Promise<void>}
   */
  async connect() {
    try {
      const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/EtherShare';
      
      console.log('🔄 Connecting to MongoDB...');
      console.log(`   URI: ${mongoUri.replace(/\/\/.*@/, '//***:***@')}`); // Hide credentials
      
      const options = {
        useNewUrlParser: true,
        useUnifiedTopology: true,
        maxPoolSize: 10, // Maintain up to 10 socket connections
        serverSelectionTimeoutMS: 5000, // Keep trying to send operations for 5 seconds
        socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity
      };

      this.connection = await mongoose.connect(mongoUri, options);
      
      console.log('✅ MongoDB: Connected successfully');
      console.log(`   Database: ${this.connection.connection.name}`);
      console.log(`   Host: ${this.connection.connection.host}`);
      console.log(`   Port: ${this.connection.connection.port}`);
      
      // Create indexes
      await this.createIndexes();
      
      // Handle connection events
      mongoose.connection.on('error', (err) => {
        console.error('❌ MongoDB connection error:', err);
      });

      mongoose.connection.on('disconnected', () => {
        console.warn('⚠️ MongoDB disconnected');
      });

      mongoose.connection.on('reconnected', () => {
        console.log('✅ MongoDB reconnected');
      });

      return this.connection;
    } catch (error) {
      console.error('❌ MongoDB: Connection failed');
      console.error('   Error:', error.message);
      
      if (error.message.includes('ECONNREFUSED')) {
        console.error('\n💡 TROUBLESHOOTING:');
        console.error('   1. Make sure MongoDB is running');
        console.error('   2. Check connection string in .env file');
        console.error('   3. For local MongoDB: mongod --dbpath <path>');
        console.error('   4. For Windows: net start MongoDB');
      }
      
      throw error;
    }
  }

  /**
   * Create database indexes for better performance
   */
  async createIndexes() {
    try {
      const db = mongoose.connection.db;
      
      // Users collection indexes
      const usersCollection = db.collection('users');
      await usersCollection.createIndex({ address: 1 }, { unique: true });
      await usersCollection.createIndex({ email: 1 });
      await usersCollection.createIndex({ username: 1 }, { unique: true }); // Username must be unique
      
      // Workspaces collection indexes
      const workspacesCollection = db.collection('workspaces');
      await workspacesCollection.createIndex({ workspace_id: 1 }, { unique: true });
      await workspacesCollection.createIndex({ inviter_address: 1 });
      await workspacesCollection.createIndex({ timestamp: 1 });
      // Unique workspace name per user (case-insensitive)
      await workspacesCollection.createIndex(
        { inviter_address: 1, name: 1 }, 
        { unique: false } // We'll handle uniqueness in application logic for case-insensitive matching
      );
      
      // Messages collection indexes
      const messagesCollection = db.collection('messages');
      await messagesCollection.createIndex({ message_id: 1 }, { unique: true });
      await messagesCollection.createIndex({ workspace_id: 1 });
      await messagesCollection.createIndex({ channel_id: 1 });
      await messagesCollection.createIndex({ sender_address: 1 });
      await messagesCollection.createIndex({ receiver_address: 1 });
      await messagesCollection.createIndex({ timestamp: 1 });
      
      // Members collection indexes
      const membersCollection = db.collection('members');
      await membersCollection.createIndex({ workspace_id: 1, member_address: 1 }, { unique: true });
      await membersCollection.createIndex({ member_address: 1 });
      
      // Files collection indexes
      const filesCollection = db.collection('files');
      await filesCollection.createIndex({ file_id: 1 }, { unique: true });
      await filesCollection.createIndex({ workspace_id: 1 });
      await filesCollection.createIndex({ uploader_address: 1 });
      
      // Channels collection indexes
      const channelsCollection = db.collection('channels');
      await channelsCollection.createIndex({ channel_id: 1, workspace_id: 1 }, { unique: true });
      await channelsCollection.createIndex({ workspace_id: 1 });
      await channelsCollection.createIndex({ creator_address: 1 });
      await channelsCollection.createIndex({ is_default: 1 });
      await channelsCollection.createIndex({ deleted: 1 });
      
      // Nodes collection indexes (blockchain-like)
      const nodesCollection = db.collection('nodes');
      await nodesCollection.createIndex({ node_id: 1 }, { unique: true });
      await nodesCollection.createIndex({ previous_hash: 1 });
      await nodesCollection.createIndex({ current_hash: 1 });
      await nodesCollection.createIndex({ chain_position: 1, is_deprecated: 1 });
      await nodesCollection.createIndex({ is_deprecated: 1 });
      
      // Ledger collection indexes (for gas)
      const ledgerCollection = db.collection('ledgers');
      await ledgerCollection.createIndex({ gas_used: 1 });
      await ledgerCollection.createIndex({ transaction_fee: 1 });
      
      console.log('✅ MongoDB: Indexes created successfully');
    } catch (error) {
      console.warn('⚠️ MongoDB: Index creation warning -', error.message);
    }
  }

  /**
   * Disconnect from MongoDB
   */
  async disconnect() {
    try {
      if (this.connection) {
        await mongoose.disconnect();
        console.log('✅ MongoDB: Disconnected');
      }
    } catch (error) {
      console.error('❌ MongoDB: Disconnect error -', error.message);
    }
  }

  /**
   * Get connection status
   */
  isConnected() {
    return mongoose.connection.readyState === 1;
  }
}

// Export singleton instance
module.exports = new Database();

