const mongoose = require('mongoose');

/**
 * Get MongoDB database connection
 * Returns the database instance when connected
 * @returns {Object} MongoDB database instance
 */
function getDb() {
  if (!mongoose.connection.db) {
    throw new Error('Database not connected. Make sure MongoDB connection is established.');
  }
  return mongoose.connection.db;
}

/**
 * Get MongoDB collection
 * @param {String} collectionName - Name of the collection
 * @returns {Object} MongoDB collection
 */
function getCollection(collectionName) {
  const db = getDb();
  return db.collection(collectionName);
}

module.exports = {
  getDb,
  getCollection
};

