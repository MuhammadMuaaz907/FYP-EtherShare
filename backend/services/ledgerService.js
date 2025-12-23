const Ledger = require('../models/ledger');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');
const crypto = require('crypto');

/**
 * Ledger Service - Manages blockchain-like ledger
 */
class LedgerService {
  /**
   * Add a new block to the ledger chain
   */
  static async addBlock(nodeId, transactionData) {
    try {
      // Get last block for this node
      const lastBlock = await Ledger.findOne({ node_id: nodeId })
        .sort({ block_number: -1 })
        .lean();
      
      const blockNumber = lastBlock ? lastBlock.block_number + 1 : 0;
      const previousHash = lastBlock ? lastBlock.current_hash : '0';
      
      // Calculate gas for transaction (blockchain-like)
      const gasUsed = GasCalculator.calculateTransactionGas(transactionData);
      const gasPrice = GasCalculator.getCurrentGasPrice();
      const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
      
      // Create block data
      const blockData = {
        block_number: blockNumber,
        node_id: nodeId,
        data: transactionData,
        transaction_type: transactionData.type || 'message',
        sender_address: transactionData.sender_address,
        receiver_address: transactionData.receiver_address,
        workspace_id: transactionData.workspace_id,
        timestamp: Date.now(),
        previous_hash: previousHash,
        gas_used: gasUsed,
        gas_price: gasPrice,
        transaction_fee: transactionFee
      };
      
      // Calculate current hash (blockchain-like)
      const dataString = JSON.stringify(blockData.data, Object.keys(blockData.data).sort());
      const combined = `${dataString}${previousHash}${blockNumber}${nodeId}${gasUsed}${transactionFee}`;
      const currentHash = crypto.createHash('sha256').update(combined, 'utf8').digest('hex');
      
      blockData.current_hash = currentHash;
      blockData.block_id = `block_${nodeId}_${blockNumber}_${Date.now()}`;
      
      // Create and save block
      const block = new Ledger(blockData);
      await block.save();
      
      console.log(`✅ Block added to ledger: ${blockData.block_id}`);
      
      // Verify chain integrity
      const isValid = await this.verifyChain(nodeId);
      if (!isValid) {
        console.error('❌ Chain integrity check failed after adding block!');
        await Ledger.updateOne(
          { block_id: blockData.block_id },
          { $set: { chain_broken: true } }
        );
      }
      
      return block;
    } catch (error) {
      console.error('❌ Add block error:', error);
      throw error;
    }
  }

  /**
   * Verify chain integrity for a node
   */
  static async verifyChain(nodeId) {
    try {
      const blocks = await Ledger.find({ node_id: nodeId })
        .sort({ block_number: 1 })
        .lean();
      
      if (blocks.length === 0) {
        return true; // Empty chain is valid
      }
      
      let expectedHash = '0';
      
      for (const block of blocks) {
        // Verify previous hash
        if (block.previous_hash !== expectedHash) {
          console.error(`❌ Chain broken at block ${block.block_number}`);
          console.error(`   Expected previous_hash: ${expectedHash}`);
          console.error(`   Found previous_hash: ${block.previous_hash}`);
          
          // Mark chain as broken
          await Ledger.updateMany(
            { node_id: nodeId, block_number: { $gte: block.block_number } },
            { $set: { chain_broken: true } }
          );
          
          return false;
        }
        
        // Recalculate hash (include gas fields)
        const dataString = JSON.stringify(block.data, Object.keys(block.data).sort());
        const gasUsed = block.gas_used || 0;
        const transactionFee = block.transaction_fee || 0;
        const combined = `${dataString}${block.previous_hash}${block.block_number}${nodeId}${gasUsed}${transactionFee}`;
        const calculatedHash = crypto.createHash('sha256').update(combined, 'utf8').digest('hex');
        
        if (calculatedHash !== block.current_hash) {
          console.error(`❌ Hash mismatch at block ${block.block_number}`);
          console.error(`   Expected current_hash: ${calculatedHash}`);
          console.error(`   Found current_hash: ${block.current_hash}`);
          
          await Ledger.updateOne(
            { block_id: block.block_id },
            { $set: { chain_broken: true } }
          );
          
          return false;
        }
        
        expectedHash = block.current_hash;
      }
      
      console.log(`✅ Chain verified for node ${nodeId} - ${blocks.length} blocks`);
      return true;
    } catch (error) {
      console.error('❌ Verify chain error:', error);
      return false;
    }
  }

  /**
   * Get ledger for a node
   */
  static async getLedger(nodeId, limit = 100) {
    try {
      const blocks = await Ledger.find({ node_id: nodeId })
        .sort({ block_number: -1 })
        .limit(limit)
        .lean();
      
      return blocks.reverse(); // Return in chronological order
    } catch (error) {
      console.error('❌ Get ledger error:', error);
      throw error;
    }
  }

  /**
   * Get messages between UserA and UserB
   */
  static async getMessagesBetweenUsers(userA, userB, nodeId = null) {
    try {
      const query = {
        $or: [
          { sender_address: userA, receiver_address: userB },
          { sender_address: userB, receiver_address: userA }
        ],
        transaction_type: 'message',
        chain_broken: false
      };
      
      if (nodeId) {
        query.node_id = nodeId;
      }
      
      const blocks = await Ledger.find(query)
        .sort({ timestamp: 1 })
        .lean();
      
      // Extract messages from blocks
      const messages = blocks.map(block => ({
        ...block.data,
        block_id: block.block_id,
        block_number: block.block_number,
        timestamp: block.timestamp,
        verified: block.verified
      }));
      
      return messages;
    } catch (error) {
      console.error('❌ Get messages error:', error);
      throw error;
    }
  }

  /**
   * Verify all chains in network
   */
  static async verifyAllChains() {
    try {
      const nodeIds = await Ledger.distinct('node_id');
      const results = {};
      
      for (const nodeId of nodeIds) {
        results[nodeId] = await this.verifyChain(nodeId);
      }
      
      return results;
    } catch (error) {
      console.error('❌ Verify all chains error:', error);
      throw error;
    }
  }
}

module.exports = LedgerService;

