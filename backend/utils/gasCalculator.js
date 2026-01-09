/**
 * Gas Calculator - Blockchain-like gas calculation based on transaction time
 * Similar to Ethereum gas system, but calculates gas based on actual execution time
 * Gas = Computational cost = Time taken to execute transaction
 */
class GasCalculator {
  // Base gas costs (similar to Ethereum)
  static GAS_COSTS = {
    // Base costs
    BASE_TRANSACTION: 21000,      // Base cost for any transaction
    BASE_STORAGE: 20000,           // Base cost for storage operation
    
    // Time-based multipliers (gas per millisecond)
    TIME_MULTIPLIER: 100,         // 100 gas per millisecond of execution time
    MIN_TIME_GAS: 21000,          // Minimum gas even for fast transactions
    
    // Operation-specific base costs
    NODE_REGISTRATION: 21000,     // Base cost for node registration
    NODE_UPDATE: 50000,           // Cost for creating new node (deprecating old)
    NODE_VERIFICATION: 3000,      // Cost for chain verification
    
    // Data size costs
    DATA_BYTE: 16,                // Cost per byte of data
    STORAGE_SLOT: 20000,          // Cost for storage operation
    
    // Network operations
    TCP_CONNECTION: 5000,         // Cost for TCP connection
    MESSAGE_ROUTING: 10000,       // Cost for routing message through chain
    
    // Database operations
    DB_READ: 1000,                // Cost per database read
    DB_WRITE: 5000,               // Cost per database write
    DB_QUERY: 2000,               // Cost per database query
  };
  
  /**
   * Calculate gas based on transaction execution time
   * This is the main method - measures actual time and converts to gas
   * @param {Number} executionTimeMs - Transaction execution time in milliseconds
   * @param {Object} options - Additional options
   * @returns {Number} Gas units required
   */
  static calculateGasFromTime(executionTimeMs, options = {}) {
    const {
      baseCost = this.GAS_COSTS.BASE_TRANSACTION,
      timeMultiplier = this.GAS_COSTS.TIME_MULTIPLIER,
      minGas = this.GAS_COSTS.MIN_TIME_GAS
    } = options;
    
    // Calculate gas: base cost + (time * multiplier)
    let gas = baseCost + (executionTimeMs * timeMultiplier);
    
    // Ensure minimum gas
    if (gas < minGas) {
      gas = minGas;
    }
    
    // Round to nearest integer
    return Math.round(gas);
  }
  
  /**
   * Calculate gas for node registration (time-based)
   * @param {Number} executionTimeMs - Time taken to register node
   * @param {Object} nodeData - Node data
   * @returns {Number} Gas units required
   */
  static calculateNodeRegistrationGas(executionTimeMs, nodeData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.NODE_REGISTRATION;
    
    // Add gas for data size
    const dataSize = nodeData ? JSON.stringify(nodeData).length : 0;
    const dataGas = dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + this.GAS_COSTS.STORAGE_SLOT,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
  }
  
  /**
   * Calculate gas for node update (time-based)
   * @param {Number} executionTimeMs - Time taken to update node
   * @param {Object} oldNodeData - Old node data
   * @param {Object} newNodeData - New node data
   * @returns {Number} Gas units required
   */
  static calculateNodeUpdateGas(executionTimeMs, oldNodeData = {}, newNodeData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.NODE_UPDATE;
    
    // Calculate data size difference
    const oldSize = oldNodeData ? JSON.stringify(oldNodeData).length : 0;
    const newSize = newNodeData ? JSON.stringify(newNodeData).length : 0;
    const sizeDiff = Math.abs(newSize - oldSize);
    
    const dataGas = sizeDiff * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage (new node + deprecation)
    const storageGas = this.GAS_COSTS.STORAGE_SLOT * 2;
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + storageGas,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
  }
  
  /**
   * Calculate gas for transaction (time-based)
   * @param {Number} executionTimeMs - Time taken to process transaction
   * @param {Object} transactionData - Transaction data
   * @returns {Number} Gas units required
   */
  static calculateTransactionGas(executionTimeMs, transactionData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.BASE_TRANSACTION;
    
    // Add gas for data size
    const dataSize = transactionData ? JSON.stringify(transactionData).length : 0;
    const dataGas = dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for message routing through chain
    let routingGas = 0;
    if (transactionData.type === 'message') {
      routingGas = this.GAS_COSTS.MESSAGE_ROUTING;
    }
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + routingGas,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
  }
  
  /**
   * Calculate gas for message operation (time-based)
   * @param {Number} executionTimeMs - Time taken to process message
   * @param {Object} messageData - Message data
   * @returns {Number} Gas units required
   */
  static calculateMessageGas(executionTimeMs, messageData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.BASE_TRANSACTION;
    
    // Add gas for data size
    const dataSize = messageData ? JSON.stringify(messageData).length : 0;
    const dataGas = dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage (message storage)
    const storageGas = this.GAS_COSTS.STORAGE_SLOT;
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + storageGas,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
  }
  
  /**
   * Calculate gas for channel operation (time-based)
   * @param {Number} executionTimeMs - Time taken to process channel operation
   * @param {Object} channelData - Channel data
   * @returns {Number} Gas units required
   */
  static calculateChannelGas(executionTimeMs, channelData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.BASE_TRANSACTION;
    
    // Add gas for data size
    const dataSize = channelData ? JSON.stringify(channelData).length : 0;
    const dataGas = dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage
    const storageGas = this.GAS_COSTS.STORAGE_SLOT;
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + storageGas,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
  }
  
  /**
   * Calculate gas for workspace operation (time-based)
   * @param {Number} executionTimeMs - Time taken to process workspace operation
   * @param {Object} workspaceData - Workspace data
   * @returns {Number} Gas units required
   */
  static calculateWorkspaceGas(executionTimeMs, workspaceData = {}) {
    // Base cost + time-based gas
    const baseCost = this.GAS_COSTS.BASE_TRANSACTION;
    
    // Add gas for data size
    const dataSize = workspaceData ? JSON.stringify(workspaceData).length : 0;
    const dataGas = dataSize * this.GAS_COSTS.DATA_BYTE;
    
    // Add gas for storage (workspace + member creation)
    const storageGas = this.GAS_COSTS.STORAGE_SLOT * 2;
    
    // Calculate time-based gas
    const timeGas = this.calculateGasFromTime(executionTimeMs, {
      baseCost: baseCost + dataGas + storageGas,
      timeMultiplier: this.GAS_COSTS.TIME_MULTIPLIER
    });
    
    return timeGas;
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
  
  /**
   * Measure execution time and calculate gas
   * Wrapper function to measure time and calculate gas automatically
   * @param {Function} asyncFunction - Async function to measure
   * @param {Function} gasCalculator - Gas calculation function
   * @param {Object} data - Data to pass to gas calculator
   * @returns {Promise<Object>} { result, gasUsed, gasPrice, transactionFee, executionTimeMs }
   */
  static async measureAndCalculateGas(asyncFunction, gasCalculator, data = {}) {
    const startTime = process.hrtime.bigint(); // High precision timer
    
    try {
      // Execute the function
      const result = await asyncFunction();
      
      // Calculate execution time
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000; // Convert nanoseconds to milliseconds
      
      // Calculate gas
      const gasUsed = gasCalculator(executionTimeMs, data);
      const gasPrice = this.getCurrentGasPrice();
      const transactionFee = this.calculateTransactionFee(gasUsed, gasPrice);
      
      return {
        result,
        gasUsed,
        gasPrice,
        transactionFee,
        executionTimeMs: Math.round(executionTimeMs * 100) / 100 // Round to 2 decimal places
      };
    } catch (error) {
      // Even on error, calculate gas for time spent
      const endTime = process.hrtime.bigint();
      const executionTimeMs = Number(endTime - startTime) / 1000000;
      const gasUsed = gasCalculator(executionTimeMs, data);
      const gasPrice = this.getCurrentGasPrice();
      const transactionFee = this.calculateTransactionFee(gasUsed, gasPrice);
      
      // Re-throw error with gas info
      error.gasInfo = {
        gasUsed,
        gasPrice,
        transactionFee,
        executionTimeMs: Math.round(executionTimeMs * 100) / 100
      };
      
      throw error;
    }
  }
}

module.exports = GasCalculator;
