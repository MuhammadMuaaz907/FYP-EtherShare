const jwt = require('jsonwebtoken');

/**
 * Authentication Middleware
 * Verifies JWT tokens and attaches user info to request
 */

/**
 * Verify JWT token from Authorization header
 */
const authenticateToken = (req, res, next) => {
  try {
    // Get token from header
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

    if (!token) {
      return res.status(401).json({
        success: false,
        error: 'Access token required',
        message: 'Please provide a valid authentication token'
      });
    }

    // Verify token
    const secret = process.env.JWT_SECRET || 'your_super_secret_jwt_key';
    jwt.verify(token, secret, (err, user) => {
      if (err) {
        return res.status(403).json({
          success: false,
          error: 'Invalid or expired token',
          message: 'Please login again'
        });
      }

      // Attach user info to request
      req.user = user;
      next();
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: 'Authentication error',
      message: error.message
    });
  }
};

/**
 * Optional authentication - doesn't fail if no token
 * Useful for endpoints that work with or without auth
 */
const optionalAuth = (req, res, next) => {
  try {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (token) {
      const secret = process.env.JWT_SECRET || 'your_super_secret_jwt_key';
      jwt.verify(token, secret, (err, user) => {
        if (!err) {
          req.user = user;
        }
        next();
      });
    } else {
      next();
    }
  } catch (error) {
    next();
  }
};

/**
 * Generate JWT token
 * @param {Object} payload - User data to encode
 * @returns {String} JWT token
 */
const generateToken = (payload) => {
  const secret = process.env.JWT_SECRET || 'your_super_secret_jwt_key';
  const expiresIn = process.env.JWT_EXPIRES_IN || '7d';
  
  return jwt.sign(payload, secret, { expiresIn });
};

module.exports = {
  authenticateToken,
  optionalAuth,
  generateToken
};

