const crypto = require('crypto');

/**
 * Hash Chain Utilities
 * Implements blockchain-like hash chain for data integrity verification
 */
class HashChain {
  /**
   * Calculate SHA-256 hash for blockchain-like chain
   * Supports hash_version-based hashing:
   * - Version 1: Uses message_text in hash calculation (legacy)
   * - Version 2: Uses payload_hash in hash calculation (new)
   * @param {Object} data - Data object to hash
   * @param {String} previousHash - Previous hash in the chain
   * @param {Number} hashVersion - Hash version (1 = message_text, 2 = payload_hash)
   * @returns {String} SHA-256 hash
   */
  static calculateHash(data, previousHash, hashVersion = 1) {
    try {
      // Create a copy of data for modification
      const dataToHash = { ...data };
      
      // For hash version 2, replace message_text with payload_hash
      if (hashVersion === 2) {
        const payloadHash = dataToHash.payload_hash;
        if (payloadHash && payloadHash.trim().length > 0) {
          // Remove message_text and use payload_hash instead
          delete dataToHash.message_text;
          // payload_hash is already in the map, so we use it
        } else {
          // Fallback: if payload_hash not available, calculate it from message_text
          const messageText = dataToHash.message_text || '';
          if (messageText.trim().length > 0) {
            const calculatedPayloadHash = crypto.createHash('sha256')
              .update(messageText, 'utf8')
              .digest('hex');
            delete dataToHash.message_text;
            dataToHash.payload_hash = calculatedPayloadHash;
          }
        }
      }
      // For hash version 1, keep message_text (default behavior)
      
      // Convert data to JSON string (sorted keys for consistency)
      const dataString = JSON.stringify(dataToHash, Object.keys(dataToHash).sort());
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
   * Get the last hash in a collection's chain (atomic operation)
   * Uses findOneAndUpdate to atomically get and "reserve" the last hash
   * This prevents race conditions when multiple messages are inserted simultaneously
   * @param {Object} collection - MongoDB collection
   * @param {Object} filter - Optional filter for the query
   * @returns {Promise<String>} Last hash or '0' for genesis
   */
  static async getLastHash(collection, filter = {}) {
    try {
      // Use findOne with sort to get the last document
      // This is more reliable than findOneAndUpdate for read-only operations
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
   * Atomically get the last hash and verify it hasn't changed
   * This is used to prevent race conditions during rapid message insertion
   * @param {Object} collection - MongoDB collection
   * @param {Object} filter - Optional filter for the query
   * @param {String} expectedPreviousHash - The hash we expect to be the last one
   * @returns {Promise<Object>} { hash: String, isValid: Boolean }
   */
  static async getAndVerifyLastHash(collection, filter = {}, expectedPreviousHash = null) {
    try {
      const lastDoc = await collection
        .findOne(filter, { sort: { timestamp: -1 } });
      
      const currentLastHash = lastDoc && lastDoc.current_hash ? lastDoc.current_hash : '0';
      
      // If we expected a specific hash, verify it matches
      if (expectedPreviousHash !== null) {
        const isValid = currentLastHash === expectedPreviousHash;
        return {
          hash: currentLastHash,
          isValid: isValid,
          messageId: lastDoc ? lastDoc.message_id : null
        };
      }
      
      return {
        hash: currentLastHash,
        isValid: true,
        messageId: lastDoc ? lastDoc.message_id : null
      };
    } catch (error) {
      console.error('Error getting and verifying last hash:', error);
      return {
        hash: '0',
        isValid: false,
        messageId: null
      };
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
      
      // CRITICAL: Track seen message_ids to detect duplicates
      const seenMessageIds = new Set();
      
      for (let i = 0; i < documents.length; i++) {
        const doc = documents[i];
        const currentHash = doc.current_hash;
        const previousHash = doc.previous_hash;
        const messageId = doc.message_id;
        
        // CRITICAL: Skip duplicate message_ids (idempotent sync duplicates)
        // Duplicates are NOT chain breaks - they're just repeated sync attempts
        if (messageId && seenMessageIds.has(messageId)) {
          console.log(`⚠️ Skipping duplicate message_id: ${messageId} (not a chain break)`);
          details.verifiedDocuments++; // Count as verified (duplicate is valid)
          continue; // Skip duplicate, don't advance expectedHash
        }
        
        // Track this message_id
        if (messageId) {
          seenMessageIds.add(messageId);
        }
        
        // Skip documents without hash fields (old messages)
        if (!currentHash && !previousHash) {
          console.log(`⚠️ Skipping document ${doc.message_id || doc._id} - no hash fields (old message)`);
          details.verifiedDocuments++;
          continue;
        }
        
        // CRITICAL: Verify previous hash matches
        // BUT: If previous_hash doesn't match, check if it's a duplicate message_id first
        // Duplicates can have different previous_hash if they were synced out of order
        if (previousHash !== expectedHash) {
          // Check if this is a duplicate by message_id (already handled above, but double-check)
          if (messageId && seenMessageIds.has(messageId)) {
            console.log(`⚠️ Skipping duplicate message_id with mismatched previous_hash: ${messageId}`);
            details.verifiedDocuments++;
            continue;
          }
          
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
        // Support mixed hash versions (v1 uses message_text, v2 uses payload_hash)
        const hashVersion = doc.hash_version || 1; // Default to 1 if not set (backward compatibility)
        
        // Only include fields that were present when hash was created
        const dataForHash = {
          message_id: doc.message_id,
          workspace_id: doc.workspace_id,
          sender_address: doc.sender_address,
          timestamp: doc.timestamp
        };
        
        // For hash version 1, include message_text (if it exists - backward compatibility)
        // For hash version 2, message_text is NOT stored in MongoDB, only payload_hash is used
        if (hashVersion === 1 && doc.message_text) {
          dataForHash.message_text = doc.message_text;
        }
        
        // Add optional fields only if they exist
        if (doc.channel_id) dataForHash.channel_id = doc.channel_id;
        if (doc.receiver_address) dataForHash.receiver_address = doc.receiver_address;
        if (doc.file_id) dataForHash.file_id = doc.file_id;
        
        // For hash version 2, include payload_hash in dataForHash (required for v2)
        if (hashVersion === 2) {
          if (doc.payload_hash) {
            dataForHash.payload_hash = doc.payload_hash;
          } else {
            // v2 message without payload_hash is invalid
            console.error(`⚠️ Hash version 2 message ${doc.message_id} missing payload_hash`);
          }
        }
        
        // Calculate hash using hash_version-aware logic
        const calculatedHash = this.calculateHash(dataForHash, previousHash, hashVersion);
        
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
          
          // Additional check: Log message data to detect what changed
          if (hashVersion === 1 && doc.message_text) {
            console.error(`   Current message_text in DB: "${doc.message_text}"`);
          } else if (hashVersion === 2 && doc.payload_hash) {
            console.error(`   Current payload_hash in DB: "${doc.payload_hash.substring(0, 20)}..."`);
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
   * @param {Number} retryCount - Internal retry counter for race condition handling
   * @returns {Object} Document with hash fields added
   */
  static async addHashFields(collection, documentData, filter = {}, retryCount = 0) {
    try {
      // Add exponential backoff delay to avoid race conditions
      if (retryCount > 0) {
        // Delay increases with retry count: 20ms, 40ms, 80ms, 160ms, 200ms
        const delay = Math.min(20 * Math.pow(2, retryCount - 1), 200);
        await new Promise(resolve => setTimeout(resolve, delay + Math.random() * 30));
      }
      
      // CRITICAL: Get and verify the last hash atomically
      // This prevents race conditions where multiple messages read the same previous_hash
      let hashInfo = await this.getAndVerifyLastHash(collection, filter);
      let previousHash = hashInfo.hash;
      
      // If this is a retry and we expected a different hash, verify it changed correctly
      if (retryCount > 0 && !hashInfo.isValid) {
        console.log(`⚠️ Hash verification failed on retry ${retryCount} - hash changed, continuing with new hash`);
      }
      
      // Determine hash version (default to 2 for new messages, 1 for backward compatibility)
      const hashVersion = documentData.hash_version || 2;
      
      // Calculate current hash with the verified previous hash and hash version
      const currentHash = this.calculateHash(documentData, previousHash, hashVersion);
      
      // CRITICAL: Verify the hash hasn't changed AFTER calculation but BEFORE returning
      // This is the most important check - if another message was inserted while we calculated,
      // we need to retry with the new hash
      if (retryCount < 10) { // Increased max retries to 10 for high concurrency
        // Small delay to let any pending inserts complete
        await new Promise(resolve => setTimeout(resolve, 15));
        
        // Verify the hash is still valid
        const verifyInfo = await this.getAndVerifyLastHash(collection, filter, previousHash);
        
        if (!verifyInfo.isValid) {
          // Hash changed - another message was inserted
          console.log(`⚠️ Race condition detected - previous hash changed from ${previousHash.substring(0, 10)}... to ${verifyInfo.hash.substring(0, 10)}... - retrying with new hash (attempt ${retryCount + 1}/10)`);
          console.log(`   Last message ID: ${verifyInfo.messageId || 'unknown'}`);
          
          // CRITICAL: Retry with the NEW hash
          return await this.addHashFields(collection, documentData, filter, retryCount + 1);
        }
      }
      
      // Add hash fields with verified hashes
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

