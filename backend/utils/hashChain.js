const crypto = require('crypto');

/**
 * Hash Chain Utilities
 * Implements blockchain-like hash chain for data integrity verification
 */
class HashChain {
  /**
   * Calculate SHA-256 hash for blockchain-like chain
   * @param {Object} data - Data object to hash
   * @param {String} previousHash - Previous hash in the chain
   * @returns {String} SHA-256 hash
   */
  static calculateHash(data, previousHash) {
    try {
      // Convert data to JSON string (sorted keys for consistency)
      const dataString = JSON.stringify(data, Object.keys(data).sort());
      const combined = `${dataString}${previousHash}`;
      
      // Calculate SHA-256 hash
      const hash = crypto.createHash('sha256').update(combined, 'utf8').digest('hex');
      return hash;
    } catch (error) {
      console.error('Hash calculation error:', error);
      throw error;
    }
  }

  /**
   * Get the last hash in a collection's chain
   * @param {Object} collection - MongoDB collection
   * @param {Object} filter - Optional filter for the query
   * @returns {Promise<String>} Last hash or '0' for genesis
   */
  static async getLastHash(collection, filter = {}) {
    try {
      const lastDoc = await collection
        .findOne(filter, { sort: { timestamp: -1 } });
      
      if (lastDoc && lastDoc.current_hash) {
        return lastDoc.current_hash;
      }
      
      return '0'; // Genesis hash
    } catch (error) {
      console.error('Error getting last hash:', error);
      return '0';
    }
  }

  /**
   * Verify chain integrity for a collection
   * @param {Object} collection - MongoDB collection
   * @param {Object} filter - Optional filter for the query
   * @returns {Promise<Object>} { valid: Boolean, brokenAt: String|null, details: Object }
   */
  static async verifyChainIntegrity(collection, filter = {}) {
    try {
      const documents = await collection
        .find(filter)
        .sort({ timestamp: 1 })
        .toArray();
      
      if (documents.length === 0) {
        return { valid: true, brokenAt: null, details: { message: 'Empty chain is valid' } };
      }
      
      // Check if documents have hash fields - if not, they're old messages without chain
      const hasHashFields = documents.some(doc => doc.current_hash || doc.previous_hash);
      
      if (!hasHashFields) {
        // Old messages without hash chain - consider valid for backward compatibility
        console.log('⚠️ Messages without hash chain detected - allowing for backward compatibility');
        return { valid: true, brokenAt: null, details: { message: 'No hash chain found - backward compatibility mode' } };
      }
      
      let expectedHash = '0';
      let brokenAt = null;
      const details = {
        totalDocuments: documents.length,
        verifiedDocuments: 0,
        brokenDocuments: []
      };
      
      for (let i = 0; i < documents.length; i++) {
        const doc = documents[i];
        const currentHash = doc.current_hash;
        const previousHash = doc.previous_hash;
        
        // Skip documents without hash fields (old messages)
        if (!currentHash && !previousHash) {
          console.log(`⚠️ Skipping document ${doc.message_id || doc._id} - no hash fields (old message)`);
          details.verifiedDocuments++;
          continue;
        }
        
        // Verify previous hash matches
        if (previousHash !== expectedHash) {
          brokenAt = doc._id?.toString() || doc.message_id || doc.channel_id || 'unknown';
          console.error(`❌ Chain broken at document: ${brokenAt}`);
          console.error(`   Document index: ${i + 1} of ${documents.length}`);
          console.error(`   Message ID: ${doc.message_id}`);
          console.error(`   Expected previous_hash: ${expectedHash}`);
          console.error(`   Found previous_hash: ${previousHash}`);
          
          // Check if this is the first message (genesis) - previous_hash should be '0'
          if (i === 0 && previousHash !== '0') {
            console.error(`   ⚠️ First message should have previous_hash='0', but found: ${previousHash}`);
          }
          
          details.brokenDocuments.push({
            id: brokenAt,
            reason: 'previous_hash_mismatch',
            expected: expectedHash,
            found: previousHash,
            messageId: doc.message_id,
            index: i + 1
          });
          
          // Mark all subsequent documents as chain broken
          await this.markChainBroken(collection, filter, brokenAt);
          
          return {
            valid: false,
            brokenAt: brokenAt,
            details: details
          };
        }
        
        // Recalculate hash to verify current_hash
        // Only include fields that were present when hash was created
        const dataForHash = {
          message_id: doc.message_id,
          workspace_id: doc.workspace_id,
          sender_address: doc.sender_address,
          message_text: doc.message_text,
          timestamp: doc.timestamp
        };
        
        // Add optional fields only if they exist
        if (doc.channel_id) dataForHash.channel_id = doc.channel_id;
        if (doc.receiver_address) dataForHash.receiver_address = doc.receiver_address;
        if (doc.file_id) dataForHash.file_id = doc.file_id;
        
        // Calculate hash using only the original data fields
        const calculatedHash = this.calculateHash(dataForHash, previousHash);
        
        if (calculatedHash !== currentHash) {
          brokenAt = doc._id?.toString() || doc.message_id || doc.channel_id || 'unknown';
          console.error(`❌ Hash mismatch at document: ${brokenAt}`);
          console.error(`   Message ID: ${doc.message_id}`);
          console.error(`   Document index: ${i + 1} of ${documents.length}`);
          console.error(`   Expected current_hash: ${calculatedHash}`);
          console.error(`   Found current_hash: ${currentHash}`);
          console.error(`   Data used for hash:`, JSON.stringify(dataForHash, null, 2));
          console.error(`   Previous hash: ${previousHash}`);
          console.error(`   ⚠️ MESSAGE DATA HAS BEEN MODIFIED - Chain integrity compromised!`);
          
          // Additional check: Compare actual message text to detect what changed
          if (doc.message_text) {
            console.error(`   Current message_text in DB: "${doc.message_text}"`);
          }
          
          details.brokenDocuments.push({
            id: brokenAt,
            reason: 'current_hash_mismatch',
            expected: calculatedHash,
            found: currentHash,
            messageId: doc.message_id,
            index: i + 1,
            message: 'Message data has been modified. Hash does not match stored hash.'
          });
          
          // Mark this document and all subsequent documents as chain broken
          await this.markChainBroken(collection, filter, brokenAt);
          
          return {
            valid: false,
            brokenAt: brokenAt,
            details: details
          };
        }
        
        expectedHash = currentHash;
        details.verifiedDocuments++;
      }
      
      // Clear chain_broken flag if chain is valid (only for documents that were incorrectly marked)
      // But keep chain_broken flag if it was set due to actual break
      const clearedCount = await collection.updateMany(
        { ...filter, chain_broken: true, timestamp: { $lt: Date.now() - 86400000 } }, // Only clear old flags (>24 hours)
        { $unset: { chain_broken: '', chain_broken_at: '' } }
      );
      
      if (clearedCount.modifiedCount > 0) {
        console.log(`✅ Cleared ${clearedCount.modifiedCount} old chain_broken flags`);
      }
      
      console.log(`✅ Chain integrity verified - ${documents.length} documents, ${details.verifiedDocuments} verified`);
      return {
        valid: true,
        brokenAt: null,
        details: details
      };
    } catch (error) {
      console.error('Chain verification error:', error);
      return {
        valid: false,
        brokenAt: 'verification_error',
        details: { error: error.message }
      };
    }
  }

  /**
   * Mark chain as broken from a specific point
   * @param {Object} collection - MongoDB collection
   * @param {Object} filter - Filter for the query
   * @param {String} brokenAt - ID of the document where chain broke
   */
  static async markChainBroken(collection, filter = {}, brokenAt) {
    try {
      // Find the broken document by message_id first (most common case)
      let brokenDoc = await collection.findOne({
        ...filter,
        message_id: brokenAt
      });
      
      // If not found, try to find by getting all documents and finding the one
      if (!brokenDoc) {
        const allDocs = await collection.find(filter).sort({ timestamp: 1 }).toArray();
        const brokenIndex = allDocs.findIndex(doc => 
          doc._id?.toString() === brokenAt || 
          doc.message_id === brokenAt ||
          doc._id?.toString() === String(brokenAt)
        );
        
        if (brokenIndex >= 0) {
          brokenDoc = allDocs[brokenIndex];
        } else if (allDocs.length > 0) {
          // If exact match not found, use first document as fallback
          brokenDoc = allDocs[0];
          console.warn(`⚠️ Exact broken document not found, marking from first document`);
        }
      }
      
      if (!brokenDoc) {
        console.warn(`⚠️ Could not find broken document: ${brokenAt}`);
        return;
      }
      
      // Mark this document and all subsequent documents as chain broken
      const result = await collection.updateMany(
        {
          ...filter,
          timestamp: { $gte: brokenDoc.timestamp }
        },
        {
          $set: {
            chain_broken: true,
            chain_broken_at: Date.now(),
            chain_broken_reason: 'Message data modified - hash mismatch detected'
          }
        }
      );
      
      console.log(`⚠️ Marked ${result.modifiedCount} documents as chain broken from: ${brokenDoc.message_id || brokenDoc._id}`);
      console.log(`   Broken document timestamp: ${brokenDoc.timestamp}`);
      console.log(`   All messages from this point forward are marked as compromised`);
    } catch (error) {
      console.error('Error marking chain broken:', error);
    }
  }

  /**
   * Add hash chain fields to a document
   * @param {Object} collection - MongoDB collection
   * @param {Object} documentData - Document data (without hash fields)
   * @param {Object} filter - Optional filter for getting previous hash
   * @returns {Object} Document with hash fields added
   */
  static async addHashFields(collection, documentData, filter = {}) {
    try {
      // Get previous hash
      const previousHash = await this.getLastHash(collection, filter);
      
      // Calculate current hash
      const currentHash = this.calculateHash(documentData, previousHash);
      
      // Add hash fields
      return {
        ...documentData,
        previous_hash: previousHash,
        current_hash: currentHash,
      };
    } catch (error) {
      console.error('Error adding hash fields:', error);
      throw error;
    }
  }
}

module.exports = HashChain;

