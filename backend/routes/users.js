const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateUserProfile } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');

/**
 * @route   POST /api/users/profile
 * @desc    Create or update user profile
 * @access  Public (can add auth later)
 */
router.post('/profile', validateUserProfile, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const { address, username, email } = req.body;
    const timestamp = Date.now();
    
    const normalizedAddress = address.toLowerCase().trim();
    const normalizedUsername = (username || '').trim();
    
    if (!normalizedUsername || normalizedUsername.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Username is required'
      });
    }
    
    // Check if username already exists (case-insensitive) for a different address
    const existingUsername = await usersCollection.findOne({
      username: { $regex: new RegExp(`^${normalizedUsername.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') },
      address: { $ne: normalizedAddress } // Different address
    });
    
    if (existingUsername) {
      return res.status(409).json({
        success: false,
        error: 'Username already taken',
        details: `Username "${normalizedUsername}" is already in use. Please choose a different username.`
      });
    }
    
    // Check if user exists by address
    const existing = await usersCollection.findOne({ 
      address: normalizedAddress 
    });
    
    if (existing) {
      // Check if username is being changed and if new username is available
      if (existing.username && existing.username.toLowerCase() !== normalizedUsername.toLowerCase()) {
        // Username is being changed, check if new username is available
        const usernameTaken = await usersCollection.findOne({
          username: { $regex: new RegExp(`^${normalizedUsername.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') },
          address: { $ne: normalizedAddress }
        });
        
        if (usernameTaken) {
          return res.status(409).json({
            success: false,
            error: 'Username already taken',
            details: `Username "${normalizedUsername}" is already in use. Please choose a different username.`
          });
        }
      }
      
      // Update existing user
      await usersCollection.updateOne(
        { address: normalizedAddress },
        {
          $set: {
            username: normalizedUsername,
            email,
            updated_at: timestamp
          }
        }
      );
      
      console.log(`✅ User profile updated: ${normalizedAddress}`);
      
      return res.json({
        success: true,
        message: 'User profile updated successfully',
        data: {
          address: normalizedAddress,
          username: normalizedUsername,
          email,
          updated_at: timestamp
        }
      });
    } else {
      // Create new user
      const userData = {
        address: normalizedAddress,
        username: normalizedUsername,
        email,
        created_at: timestamp,
        updated_at: timestamp
      };
      
      try {
        await usersCollection.insertOne(userData);
        console.log(`✅ User profile created: ${normalizedAddress}`);
        
        return res.status(201).json({
          success: true,
          message: 'User profile created successfully',
          data: userData
        });
      } catch (insertError) {
        // Handle duplicate key error (race condition)
        if (insertError.code === 11000) {
          // Check which field caused the duplicate
          if (insertError.keyPattern?.username) {
            return res.status(409).json({
              success: false,
              error: 'Username already taken',
              details: `Username "${normalizedUsername}" is already in use. Please choose a different username.`
            });
          } else if (insertError.keyPattern?.address) {
            return res.status(409).json({
              success: false,
              error: 'Address already registered',
              details: 'This address is already registered. Please sign in instead.'
            });
          }
        }
        throw insertError;
      }
    }
  } catch (error) {
    console.error('❌ Save user profile error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to save user profile',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/users/profile/:address
 * @desc    Get user profile by address
 * @access  Public
 */
router.get('/profile/:address', optionalAuth, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const address = req.params.address.toLowerCase().trim();
    
    const user = await usersCollection.findOne({ address });
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: `No profile found for address: ${address}`
      });
    }
    
    // Remove MongoDB _id from response
    delete user._id;
    
    console.log(`✅ User profile found: ${address}`);
    
    return res.json({
      success: true,
      data: user
    });
  } catch (error) {
    console.error('❌ Get user profile error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get user profile',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/users/search
 * @desc    Search users by username or email
 * @access  Public
 */
router.get('/search', optionalAuth, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const { query } = req.query;
    
    if (!query || query.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Invalid search query',
        message: 'Search query must be at least 2 characters'
      });
    }
    
    const searchRegex = new RegExp(query.trim(), 'i');
    
    const users = await usersCollection
      .find({
        $or: [
          { username: searchRegex },
          { email: searchRegex }
        ]
      })
      .limit(20)
      .toArray();
    
    // Remove _id from results
    const cleanUsers = users.map(user => {
      const { _id, ...rest } = user;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanUsers.length,
      data: cleanUsers
    });
  } catch (error) {
    console.error('❌ Search users error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to search users',
      message: error.message
    });
  }
});

module.exports = router;

