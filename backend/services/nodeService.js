const Node = require('../models/node');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');
const crypto = require('crypto');

/**
 * Node Service - Manages distributed nodes with blockchain-like integrity
 */
class NodeService {
  /**
   * Register a new node in the network (blockchain-like)
   */
  static async registerNode(nodeData) {
    const startTime = process.hrtime.bigint(); // Start timing
    
    try {
      const nodeId = `node_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      
      // Get last node's hash for chain (BEFORE creating nodeDataForHash)
      const lastNode = await Node.findOne({ is_deprecated: false })
        .sort({ chain_position: -1 })
        .lean();
      
      const previousHash = lastNode ? lastNode.current_hash : '0';
      const chainPosition = lastNode ? lastNode.chain_position + 1 : 0;
      
      // Prepare node data (WITHOUT gas for hash calculation - gas will be added after)
      const nodeDataForHash = {
        node_id: nodeId,
        node_name: nodeData.node_name || `Node-${nodeId.slice(-6)}`,
        ip_address: nodeData.ip_address,
        tcp_port: nodeData.tcp_port || 3001,
        public_key: nodeData.public_key || crypto.randomBytes(32).toString('hex'),
        status: 'online',
        chain_position: chainPosition // Use actual chain_position, not hardcoded 0
      };
      
      // Calculate current hash (blockchain-like) - using correct chain_position
      const currentHash = HashChain.calculateHash(nodeDataForHash, previousHash);
      
      // Create node with hash chain (without gas initially)
      const node = new Node({
        ...nodeDataForHash,
        chain_position: chainPosition,
        previous_hash: previousHash,
        current_hash: currentHash,
        previous_node_id: lastNode ? lastNode.node_id : null
      });
      
      await node.save();
      
      // Update previous node's next_node_id
      if (lastNode) {
        await Node.updateOne(
          { node_id: lastNode.node_id },
          { $set: { next_node_id: nodeId } }
        );
      }
      
      // Rebuild chain to ensure integrity
      await this.buildChain();
      
      // Calculate execution time and gas
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000; // Convert nanoseconds to milliseconds
      
      // Calculate gas based on execution time
      const gasUsed = GasCalculator.calculateNodeRegistrationGas(executionTimeMs, nodeData);
      const gasPrice = GasCalculator.getCurrentGasPrice();
      const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
      
      // Update node with gas information
      node.gas_used = gasUsed;
      node.gas_price = gasPrice;
      node.transaction_fee = transactionFee;
      node.transaction_time_ms = Math.round(executionTimeMs * 100) / 100;
      await node.save();
      
      console.log(`✅ Node registered: ${nodeId} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
      return node;
    } catch (error) {
      // Calculate gas even on error
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000;
      const gasUsed = GasCalculator.calculateNodeRegistrationGas(executionTimeMs, nodeData);
      const gasPrice = GasCalculator.getCurrentGasPrice();
      const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
      
      console.error(`❌ Node registration error: ${error.message} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
      throw error;
    }
  }

  /**
   * Get all online nodes (non-deprecated)
   */
  static async getOnlineNodes() {
    try {
      const nodes = await Node.find({ 
        status: 'online',
        is_deprecated: false 
      })
        .sort({ chain_position: 1 })
        .lean();
      
      return nodes;
    } catch (error) {
      console.error('❌ Get online nodes error:', error);
      throw error;
    }
  }
  
  /**
   * Update node (blockchain-like: creates new node, deprecates old)
   * Nodes are immutable - any modification creates a new node
   */
  static async updateNode(oldNodeId, updatedData) {
    const startTime = process.hrtime.bigint(); // Start timing
    
    try {
      // Get old node
      const oldNode = await Node.findOne({ node_id: oldNodeId, is_deprecated: false });
      
      if (!oldNode) {
        throw new Error('Node not found');
      }
      
      // Create new node with updated data (without gas initially)
      const newNodeId = `node_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      
      const newNodeData = {
        node_id: newNodeId,
        node_name: updatedData.node_name || oldNode.node_name,
        ip_address: updatedData.ip_address || oldNode.ip_address,
        tcp_port: updatedData.tcp_port || oldNode.tcp_port,
        public_key: updatedData.public_key || oldNode.public_key,
        status: updatedData.status || oldNode.status,
        chain_position: oldNode.chain_position, // Same position
        previous_node_id: oldNode.previous_node_id,
        next_node_id: oldNode.next_node_id
      };
      
      // Get the previous node in chain (not the old node being updated)
      // Previous hash should be the previous node's current_hash, not old node's hash
      let previousHash = '0';
      if (oldNode.previous_node_id) {
        const previousNode = await Node.findOne({ 
          node_id: oldNode.previous_node_id,
          is_deprecated: false 
        }).lean();
        if (previousNode) {
          previousHash = previousNode.current_hash;
        }
      } else if (oldNode.chain_position > 0) {
        // If no previous_node_id but position > 0, find previous by position
        const previousNode = await Node.findOne({
          chain_position: oldNode.chain_position - 1,
          is_deprecated: false
        }).sort({ chain_position: -1 }).lean();
        if (previousNode) {
          previousHash = previousNode.current_hash;
        }
      }
      
      // Calculate hash
      const currentHash = HashChain.calculateHash(newNodeData, previousHash);
      
      newNodeData.previous_hash = previousHash;
      newNodeData.current_hash = currentHash;
      
      // Create new node
      const newNode = new Node(newNodeData);
      await newNode.save();
      
      // Deprecate old node FIRST (before updating references)
      const deprecateResult = await Node.updateOne(
        { node_id: oldNodeId },
        {
          $set: {
            is_deprecated: true,
            deprecated_by: newNodeId,
            deprecated_at: new Date(),
            status: 'offline'
          }
        }
      );
      
      console.log(`✅ Old node deprecated: ${oldNodeId} (${deprecateResult.modifiedCount} document updated)`);
      
      // Update chain references
      if (oldNode.previous_node_id) {
        await Node.updateOne(
          { node_id: oldNode.previous_node_id },
          { $set: { next_node_id: newNodeId } }
        );
      }
      
      if (oldNode.next_node_id) {
        // Update next node's previous_node_id AND previous_hash
        // This is necessary because the next node's previous_hash must point to the new node
        await Node.updateOne(
          { node_id: oldNode.next_node_id },
          { 
            $set: { 
              previous_node_id: newNodeId,
              previous_hash: currentHash  // Update to point to new node's hash
            } 
          }
        );
        
        // Recalculate next node's current_hash since previous_hash changed
        const nextNode = await Node.findOne({ node_id: oldNode.next_node_id }).lean();
        if (nextNode) {
          const nextNodeDataForHash = {
            node_id: nextNode.node_id,
            node_name: nextNode.node_name,
            ip_address: nextNode.ip_address,
            tcp_port: nextNode.tcp_port,
            public_key: nextNode.public_key,
            status: nextNode.status,
            chain_position: nextNode.chain_position,
            gas_used: nextNode.gas_used,
            gas_price: nextNode.gas_price,
            transaction_fee: nextNode.transaction_fee
          };
          
          const nextNodeNewHash = HashChain.calculateHash(nextNodeDataForHash, currentHash);
          
          await Node.updateOne(
            { node_id: oldNode.next_node_id },
            { $set: { current_hash: nextNodeNewHash } }
          );
          
          console.log(`✅ Next node (${oldNode.next_node_id}) hash updated to link to new node`);
        }
      }
      
      // Small delay to ensure MongoDB has committed all changes
      await new Promise(resolve => setTimeout(resolve, 100));
      
      // Verify chain integrity
      const isValid = await this.verifyNodeChain();
      if (!isValid) {
        console.error('❌ Node chain integrity check failed after update!');
      }
      
      // Calculate execution time and gas
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000; // Convert nanoseconds to milliseconds
      
      // Calculate gas based on execution time
      const gasUsed = GasCalculator.calculateNodeUpdateGas(executionTimeMs, oldNode.toObject(), updatedData);
      const gasPrice = GasCalculator.getCurrentGasPrice();
      const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
      
      // Update new node with gas information
      newNode.gas_used = gasUsed;
      newNode.gas_price = gasPrice;
      newNode.transaction_fee = transactionFee;
      newNode.transaction_time_ms = Math.round(executionTimeMs * 100) / 100;
      await newNode.save();
      
      console.log(`✅ Node updated: ${oldNodeId} → ${newNodeId} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
      return newNode;
    } catch (error) {
      // Calculate gas even on error
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000;
      const gasUsed = GasCalculator.calculateNodeUpdateGas(executionTimeMs, {}, updatedData);
      const gasPrice = GasCalculator.getCurrentGasPrice();
      const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
      
      console.error(`❌ Update node error: ${error.message} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
      throw error;
    }
  }
  
  /**
   * Verify node chain integrity (blockchain-like)
   */
  static async verifyNodeChain() {
    try {
      const nodes = await Node.find({ is_deprecated: false })
        .sort({ chain_position: 1 })
        .lean();
      
      if (nodes.length === 0) {
        return true; // Empty chain is valid
      }
      
      let expectedHash = '0';
      
      for (const node of nodes) {
        // Verify previous hash
        if (node.previous_hash !== expectedHash) {
          console.error(`❌ Node chain broken at: ${node.node_id}`);
          console.error(`   Expected previous_hash: ${expectedHash}`);
          console.error(`   Found previous_hash: ${node.previous_hash}`);
          
          // Mark chain as broken
          await Node.updateMany(
            { chain_position: { $gte: node.chain_position }, is_deprecated: false },
            { $set: { chain_broken: true } }
          );
          
          return false;
        }
        
        // Recalculate hash to verify current_hash
        const nodeDataForHash = {
          node_id: node.node_id,
          node_name: node.node_name,
          ip_address: node.ip_address,
          tcp_port: node.tcp_port,
          public_key: node.public_key,
          status: node.status,
          chain_position: node.chain_position,
          gas_used: node.gas_used,
          gas_price: node.gas_price,
          transaction_fee: node.transaction_fee
        };
        
        const calculatedHash = HashChain.calculateHash(nodeDataForHash, node.previous_hash);
        
        if (calculatedHash !== node.current_hash) {
          console.error(`❌ Node hash mismatch at: ${node.node_id}`);
          console.error(`   Expected current_hash: ${calculatedHash}`);
          console.error(`   Found current_hash: ${node.current_hash}`);
          
          // Mark chain as broken
          await Node.updateOne(
            { node_id: node.node_id },
            { $set: { chain_broken: true } }
          );
          
          return false;
        }
        
        expectedHash = node.current_hash;
      }
      
      console.log(`✅ Node chain verified - ${nodes.length} nodes`);
      return true;
    } catch (error) {
      console.error('❌ Verify node chain error:', error);
      return false;
    }
  }

  /**
   * Build chain structure - Connect nodes in sequence (blockchain-like)
   * Verifies chain integrity and updates connections
   */
  static async buildChain() {
    try {
      const nodes = await Node.find({ is_deprecated: false })
        .sort({ chain_position: 1 })
        .lean();
      
      if (nodes.length === 0) {
        return { message: 'No nodes available' };
      }
      
      // Verify chain integrity first
      const isValid = await this.verifyNodeChain();
      if (!isValid) {
        console.error('❌ Chain integrity check failed!');
        return {
          success: false,
          message: 'Chain integrity compromised',
          chain_length: nodes.length
        };
      }
      
      // Update node connections (next_node_id)
      for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i];
        const updates = {
          last_seen: new Date()
        };
        
        if (i < nodes.length - 1) {
          updates.next_node_id = nodes[i + 1].node_id;
        } else {
          updates.next_node_id = null; // Last node
        }
        
        await Node.updateOne(
          { node_id: node.node_id },
          { $set: updates }
        );
      }
      
      console.log(`✅ Chain built with ${nodes.length} nodes (verified)`);
      return {
        success: true,
        chain_length: nodes.length,
        chain_valid: true,
        nodes: nodes.map(n => ({
          node_id: n.node_id,
          position: n.chain_position,
          previous: n.previous_node_id,
          next: n.next_node_id,
          hash: n.current_hash.substring(0, 16) + '...'
        }))
      };
    } catch (error) {
      console.error('❌ Build chain error:', error);
      throw error;
    }
  }

  /**
   * Get chain structure (blockchain-like)
   */
  static async getChain() {
    try {
      const nodes = await Node.find({ is_deprecated: false })
        .sort({ chain_position: 1 })
        .select('node_id node_name ip_address tcp_port chain_position previous_node_id next_node_id status previous_hash current_hash gas_used transaction_fee is_deprecated deprecated_by')
        .lean();
      
      // Verify chain integrity
      const isValid = await this.verifyNodeChain();
      
      // Count deprecated nodes
      const deprecatedCount = await Node.countDocuments({ is_deprecated: true });
      
      return {
        chain: nodes,
        length: nodes.length,
        chain_valid: isValid,
        total_gas_used: nodes.reduce((sum, n) => sum + (n.gas_used || 0), 0),
        total_transaction_fee: nodes.reduce((sum, n) => sum + (n.transaction_fee || 0), 0),
        deprecated_nodes_count: deprecatedCount
      };
    } catch (error) {
      console.error('❌ Get chain error:', error);
      throw error;
    }
  }
  
  /**
   * Update node status (blockchain-like: creates new node)
   * Status change requires new node creation for immutability
   */
  static async updateNodeStatus(nodeId, newStatus) {
    try {
      const oldNode = await Node.findOne({ node_id: nodeId, is_deprecated: false });
      
      if (!oldNode) {
        throw new Error('Node not found');
      }
      
      // Create new node with updated status
      return await this.updateNode(nodeId, {
        status: newStatus,
        node_name: oldNode.node_name,
        ip_address: oldNode.ip_address,
        tcp_port: oldNode.tcp_port,
        public_key: oldNode.public_key
      });
    } catch (error) {
      console.error('❌ Update node status error:', error);
      throw error;
    }
  }
}

module.exports = NodeService;

