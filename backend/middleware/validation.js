const { body, validationResult } = require('express-validator');

/**
 * Validation Middleware
 * Validates request data using express-validator
 */

/**
 * Handle validation errors
 */
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Validation failed',
      errors: errors.array()
    });
  }
  next();
};

/**
 * User profile validation rules
 */
const validateUserProfile = [
  body('address')
    .notEmpty()
    .withMessage('Address is required')
    .isString()
    .withMessage('Address must be a string')
    .trim()
    .toLowerCase(),
  body('username')
    .notEmpty()
    .withMessage('Username is required')
    .isString()
    .withMessage('Username must be a string')
    .trim()
    .isLength({ min: 3, max: 50 })
    .withMessage('Username must be between 3 and 50 characters'),
  body('email')
    .notEmpty()
    .withMessage('Email is required')
    .isEmail()
    .withMessage('Invalid email format')
    .normalizeEmail(),
  handleValidationErrors
];

/**
 * Workspace validation rules
 */
const validateWorkspace = [
  body('workspaceName')
    .notEmpty()
    .withMessage('Workspace name is required')
    .isString()
    .withMessage('Workspace name must be a string')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Workspace name must be between 1 and 100 characters'),
  handleValidationErrors
];

/**
 * Message validation rules
 */
const validateMessage = [
  body('workspaceId')
    .notEmpty()
    .withMessage('Workspace ID is required')
    .isString()
    .withMessage('Workspace ID must be a string'),
  body('messageText')
    .notEmpty()
    .withMessage('Message text is required')
    .isString()
    .withMessage('Message text must be a string')
    .trim()
    .isLength({ min: 1, max: 5000 })
    .withMessage('Message must be between 1 and 5000 characters'),
  body('senderAddress')
    .notEmpty()
    .withMessage('Sender address is required')
    .isString()
    .withMessage('Sender address must be a string'),
  handleValidationErrors
];

/**
 * Member validation rules
 */
const validateMember = [
  body('workspaceId')
    .notEmpty()
    .withMessage('Workspace ID is required')
    .isString()
    .withMessage('Workspace ID must be a string'),
  body('memberAddress')
    .notEmpty()
    .withMessage('Member address is required')
    .isString()
    .withMessage('Member address must be a string'),
  handleValidationErrors
];

module.exports = {
  handleValidationErrors,
  validateUserProfile,
  validateWorkspace,
  validateMessage,
  validateMember
};

