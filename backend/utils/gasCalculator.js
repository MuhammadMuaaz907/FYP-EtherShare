/**
 * Gas Calculator - Blockchain-like gas calculation
 * Similar to Ethereum gas system
 */
class GasCalculator {
  // Base gas costs (similar to Ethereum)
  static GAS_COSTS = {
    // Node operations
    NODE_REGISTRATION: 21000,      // Base cost for node registration
    NODE_UPDATE: 50000,            // Cost for creating new node (deprecating old)
    NODE_VERIFICATION: 3000,       // Cost for chain verification
    
    // Transaction operations
    TRANSACTION_BASE: 21000,       // Base transaction cost
    DATA_BYTE: 16,                 // Cost per byte of data
    STORAGE_SLOT: 20000,           // Cost for storage operation
    
    // Network operations
    TCP_CONNECTION: 5000,          // Cost for TCP connection
    MESSAGE_ROUTING: 10000,        // Cost for routing message through chain
  };
  
  /**
   * Calculate gas for node registration
   * @param {Object} nodeData - Node data
   * @returns {Number} Gas units required
   */
  static calculateNodeRegistrationGas(nodeData) {
    let gas = this.GAS_COSTS.NODE_REGISTRATION;
    
    // Add gas for data size
    const dataSize = JSON.stringify(nodeData).length;
    gas += dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage
    gas += this.GAS_COSTS.STORAGE_SLOT;
    
    return gas;
  }
  
  /**
   * Calculate gas for node update (creating new node)
   * @param {Object} oldNodeData - Old node data
   * @param {Object} newNodeData - New node data
   * @returns {Number} Gas units required
   */
  static calculateNodeUpdateGas(oldNodeData, newNodeData) {
    let gas = this.GAS_COSTS.NODE_UPDATE;
    
    // Calculate data size difference
    const oldSize = JSON.stringify(oldNodeData).length;
    const newSize = JSON.stringify(newNodeData).length;
    const sizeDiff = Math.abs(newSize - oldSize);
    
    gas += sizeDiff * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage (new node + deprecation)
    gas += this.GAS_COSTS.STORAGE_SLOT * 2;
    
    return gas;
  }
  
  /**
   * Calculate gas for transaction
   * @param {Object} transactionData - Transaction data
   * @returns {Number} Gas units required
   */
  static calculateTransactionGas(transactionData) {
    let gas = this.GAS_COSTS.TRANSACTION_BASE;
    
    // Add gas for data size
    const dataSize = JSON.stringify(transactionData).length;
    gas += dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for message routing through chain
    if (transactionData.type === 'message') {
      gas += this.GAS_COSTS.MESSAGE_ROUTING;
    }
    
    return gas;
  }
  
  /**
   * Calculate transaction fee
   * @param {Number} gasUsed - Gas units used
   * @param {Number} gasPrice - Gas price (default: 1)
   * @returns {Number} Transaction fee
   */
  static calculateTransactionFee(gasUsed, gasPrice = 1) {
    return gasUsed * gasPrice;
  }
  
  /**
   * Get current gas price (can be dynamic based on network load)
   * @returns {Number} Current gas price
   */
  static getCurrentGasPrice() {
    // In real blockchain, this would be based on network congestion
    // For now, return base price
    return 1;
  }
}

module.exports = GasCalculator;

