// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title UserAuth
 * @dev Enhanced user authentication contract with 2FA functionality
 * @author EtherShare Team
 * 
 * This contract provides:
 * - User registration and login functionality
 * - Two-Factor Authentication (2FA) support
 * - Backup code management
 * - Rate limiting and security features
 * - Comprehensive event logging
 */
contract UserAuth {
    // ============ STATE VARIABLES ============
    
    /// @dev Mapping to track registered users
    mapping(address => bool) private registeredUsers;
    
    /// @dev Mapping to track 2FA enabled users
    mapping(address => bool) private twoFactorEnabled;
    
    /// @dev Mapping to store user backup codes
    mapping(address => string[]) private userBackupCodes;
    
    /// @dev Mapping to track failed 2FA attempts per session
    mapping(address => uint256) private failedAttempts;
    
    /// @dev Mapping to track last failed attempt timestamp
    mapping(address => uint256) private lastFailedAttempt;
    
    /// @dev Mapping to track user's last successful login
    mapping(address => uint256) private lastSuccessfulLogin;
    
    /// @dev Maximum number of failed attempts before lockout
    uint256 private constant MAX_FAILED_ATTEMPTS = 3;
    
    /// @dev Lockout duration in seconds (5 minutes)
    uint256 private constant LOCKOUT_DURATION = 300;
    
    /// @dev Maximum number of backup codes per user
    uint256 private constant MAX_BACKUP_CODES = 20;
    
    /// @dev Contract owner for administrative functions
    address private owner;
    
    /// @dev Contract deployment timestamp
    uint256 private immutable deploymentTime;
    
    // ============ EVENTS ============
    
    /// @dev Emitted when a user registers
    event UserRegistered(address indexed user, uint256 timestamp);
    
    /// @dev Emitted when a user logs in
    event UserLoggedIn(address indexed user, uint256 timestamp);
    
    /// @dev Emitted when 2FA is enabled for a user
    event TwoFactorEnabled(address indexed user, uint256 timestamp, uint256 backupCodeCount);
    
    /// @dev Emitted when 2FA is disabled for a user
    event TwoFactorDisabled(address indexed user, uint256 timestamp);
    
    /// @dev Emitted when a backup code is used
    event BackupCodeUsed(address indexed user, uint256 timestamp, uint256 remainingCodes);
    
    /// @dev Emitted when 2FA verification fails
    event TwoFactorFailed(address indexed user, uint256 attemptCount, uint256 timestamp);
    
    /// @dev Emitted when a user is locked out due to failed attempts
    event UserLockedOut(address indexed user, uint256 lockoutUntil, uint256 timestamp);
    
    /// @dev Emitted when backup codes are regenerated
    event BackupCodesRegenerated(address indexed user, uint256 newCodeCount, uint256 timestamp);
    
    // ============ MODIFIERS ============
    
    /// @dev Ensures only registered users can perform certain actions
    modifier onlyRegistered() {
        require(registeredUsers[msg.sender], "User not registered");
        _;
    }
    
    /// @dev Ensures user is not locked out due to failed attempts
    modifier notLockedOut() {
        require(!isLockedOut(msg.sender), "Account temporarily locked due to failed attempts");
        _;
    }
    
    /// @dev Ensures only contract owner can perform administrative actions
    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can perform this action");
        _;
    }
    
    /// @dev Ensures backup codes array is within limits
    modifier validBackupCodes(string[] memory codes) {
        require(codes.length > 0, "Backup codes cannot be empty");
        require(codes.length <= MAX_BACKUP_CODES, "Too many backup codes");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    /// @dev Initializes the contract with owner and deployment timestamp
    constructor() {
        owner = msg.sender;
        deploymentTime = block.timestamp;
    }
    
    // ============ REGISTRATION & LOGIN FUNCTIONS ============
    
    /**
     * @dev Registers a new user
     * @notice Users must register before they can enable 2FA or login
     */
    function register() external {
        require(!registeredUsers[msg.sender], "User already registered");
        registeredUsers[msg.sender] = true;
        emit UserRegistered(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Checks if a user is registered
     * @param user The address to check
     * @return bool True if user is registered
     */
    function isRegistered(address user) external view returns (bool) {
        return registeredUsers[user];
    }
    
    /**
     * @dev Performs user login
     * @notice Registered users can login, 2FA verification is handled separately
     */
    function login() external onlyRegistered {
        lastSuccessfulLogin[msg.sender] = block.timestamp;
        emit UserLoggedIn(msg.sender, block.timestamp);
    }
    
    // ============ 2FA FUNCTIONS ============
    
    /**
     * @dev Enables 2FA for the calling user
     * @param backupCodes Array of backup codes for the user
     * @notice Only registered users can enable 2FA
     * @notice Backup codes must be provided and within limits
     */
    function enable2FA(string[] memory backupCodes) 
        external 
        onlyRegistered 
        validBackupCodes(backupCodes) 
    {
        require(!twoFactorEnabled[msg.sender], "2FA already enabled");
        
        // Store backup codes
        userBackupCodes[msg.sender] = backupCodes;
        
        // Enable 2FA
        twoFactorEnabled[msg.sender] = true;
        
        // Reset failed attempts counter
        failedAttempts[msg.sender] = 0;
        
        emit TwoFactorEnabled(msg.sender, block.timestamp, backupCodes.length);
    }
    
    /**
     * @dev Verifies 2FA code (TOTP or backup code)
     * @param code The verification code to check
     * @return bool True if verification is successful
     * @notice This function handles both TOTP codes and backup codes
     * @notice Implements rate limiting and lockout protection
     */
    function verify2FA(string memory code) 
        external 
        onlyRegistered 
        notLockedOut 
        returns (bool) 
    {
        require(twoFactorEnabled[msg.sender], "2FA not enabled");
        require(bytes(code).length > 0, "Code cannot be empty");
        
        // Check if it's a backup code
        if (_isBackupCode(msg.sender, code)) {
            _useBackupCode(msg.sender, code);
            _resetFailedAttempts(msg.sender);
            return true;
        }
        
        // For TOTP codes, we would typically verify against a hash stored off-chain
        // In a real implementation, you might store a hash of the secret key
        // and verify the TOTP code using a library like OpenZeppelin's TOTP
        
        // For this example, we'll simulate TOTP verification
        // In production, implement proper TOTP verification
        bool isValidTOTP = _verifyTOTPCode(msg.sender, code);
        
        if (isValidTOTP) {
            _resetFailedAttempts(msg.sender);
            return true;
        } else {
            _handleFailedAttempt(msg.sender);
            return false;
        }
    }
    
    /**
     * @dev Disables 2FA for the calling user
     * @notice Removes all 2FA data and backup codes
     */
    function disable2FA() external onlyRegistered {
        require(twoFactorEnabled[msg.sender], "2FA not enabled");
        
        // Clear 2FA data
        twoFactorEnabled[msg.sender] = false;
        delete userBackupCodes[msg.sender];
        failedAttempts[msg.sender] = 0;
        lastFailedAttempt[msg.sender] = 0;
        
        emit TwoFactorDisabled(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Checks if 2FA is enabled for a user
     * @param user The address to check
     * @return bool True if 2FA is enabled
     */
    function is2FAEnabled(address user) external view returns (bool) {
        return twoFactorEnabled[user];
    }
    
    /**
     * @dev Regenerates backup codes for the calling user
     * @param newBackupCodes Array of new backup codes
     * @notice Only users with 2FA enabled can regenerate backup codes
     */
    function regenerateBackupCodes(string[] memory newBackupCodes) 
        external 
        onlyRegistered 
        validBackupCodes(newBackupCodes) 
    {
        require(twoFactorEnabled[msg.sender], "2FA not enabled");
        
        // Replace existing backup codes
        userBackupCodes[msg.sender] = newBackupCodes;
        
        emit BackupCodesRegenerated(msg.sender, newBackupCodes.length, block.timestamp);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Gets the number of backup codes remaining for a user
     * @param user The address to check
     * @return uint256 Number of remaining backup codes
     */
    function getBackupCodeCount(address user) external view returns (uint256) {
        return userBackupCodes[user].length;
    }
    
    /**
     * @dev Gets the number of failed attempts for a user
     * @param user The address to check
     * @return uint256 Number of failed attempts
     */
    function getFailedAttempts(address user) external view returns (uint256) {
        return failedAttempts[user];
    }
    
    /**
     * @dev Checks if a user is currently locked out
     * @param user The address to check
     * @return bool True if user is locked out
     */
    function isLockedOut(address user) public view returns (bool) {
        if (failedAttempts[user] < MAX_FAILED_ATTEMPTS) {
            return false;
        }
        
        // Check if lockout period has expired
        return (block.timestamp - lastFailedAttempt[user]) < LOCKOUT_DURATION;
    }
    
    /**
     * @dev Gets the remaining lockout time for a user
     * @param user The address to check
     * @return uint256 Remaining lockout time in seconds
     */
    function getRemainingLockoutTime(address user) external view returns (uint256) {
        if (!isLockedOut(user)) {
            return 0;
        }
        
        uint256 lockoutEndTime = lastFailedAttempt[user] + LOCKOUT_DURATION;
        return lockoutEndTime > block.timestamp ? lockoutEndTime - block.timestamp : 0;
    }
    
    /**
     * @dev Gets the last successful login timestamp for a user
     * @param user The address to check
     * @return uint256 Timestamp of last successful login
     */
    function getLastSuccessfulLogin(address user) external view returns (uint256) {
        return lastSuccessfulLogin[user];
    }
    
    /**
     * @dev Gets contract information
     * @return address Contract owner
     * @return uint256 Contract deployment timestamp
     * @return uint256 Current contract version
     */
    function getContractInfo() external view returns (address, uint256, uint256) {
        return (owner, deploymentTime, 2); // Version 2 with 2FA support
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @dev Checks if a code is a valid backup code for the user
     * @param user The user address
     * @param code The code to check
     * @return bool True if it's a valid backup code
     */
    function _isBackupCode(address user, string memory code) internal view returns (bool) {
        string[] memory codes = userBackupCodes[user];
        for (uint256 i = 0; i < codes.length; i++) {
            if (keccak256(bytes(codes[i])) == keccak256(bytes(code))) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Uses a backup code (removes it from the list)
     * @param user The user address
     * @param code The backup code to use
     */
    function _useBackupCode(address user, string memory code) internal {
        string[] storage codes = userBackupCodes[user];
        
        // Find and remove the used backup code
        for (uint256 i = 0; i < codes.length; i++) {
            if (keccak256(bytes(codes[i])) == keccak256(bytes(code))) {
                // Remove the code by moving the last element to this position
                codes[i] = codes[codes.length - 1];
                codes.pop();
                break;
            }
        }
        
        emit BackupCodeUsed(user, block.timestamp, codes.length);
    }
    
    /**
     * @dev Handles failed 2FA attempts
     * @param user The user address
     */
    function _handleFailedAttempt(address user) internal {
        failedAttempts[user]++;
        lastFailedAttempt[user] = block.timestamp;
        
        emit TwoFactorFailed(user, failedAttempts[user], block.timestamp);
        
        // Check if user should be locked out
        if (failedAttempts[user] >= MAX_FAILED_ATTEMPTS) {
            uint256 lockoutUntil = block.timestamp + LOCKOUT_DURATION;
            emit UserLockedOut(user, lockoutUntil, block.timestamp);
        }
    }
    
    /**
     * @dev Resets failed attempts counter
     * @param user The user address
     */
    function _resetFailedAttempts(address user) internal {
        failedAttempts[user] = 0;
        lastFailedAttempt[user] = 0;
    }
    
    /**
     * @dev Simulates TOTP code verification
     * @param code The TOTP code to verify
     * @return bool True if code is valid
     * @notice In production, implement proper TOTP verification
     */
    function _verifyTOTPCode(address, string memory code) internal pure returns (bool) {
        // This is a placeholder implementation
        // In a real implementation, you would:
        // 1. Retrieve the user's secret key (stored off-chain)
        // 2. Generate the expected TOTP code using the current timestamp
        // 3. Compare the provided code with the expected code
        // 4. Allow for time window tolerance (±30 seconds)
        
        // For this example, we'll simulate verification
        // In production, use a proper TOTP library
        
        // Simulate valid TOTP codes (6-digit numbers)
        if (bytes(code).length == 6) {
            // Check if it's a valid 6-digit number
            for (uint256 i = 0; i < bytes(code).length; i++) {
                if (bytes(code)[i] < 0x30 || bytes(code)[i] > 0x39) {
                    return false; // Not a digit
                }
            }
            // For demo purposes, accept any 6-digit code
            // In production, implement proper TOTP verification
            return true;
        }
        
        return false;
    }
    
    // ============ ADMINISTRATIVE FUNCTIONS ============
    
    /**
     * @dev Emergency function to reset failed attempts for a user
     * @param user The user address
     * @notice Only contract owner can call this function
     */
    function resetFailedAttempts(address user) external onlyOwner {
        failedAttempts[user] = 0;
        lastFailedAttempt[user] = 0;
    }
    
    /**
     * @dev Emergency function to disable 2FA for a user
     * @param user The user address
     * @notice Only contract owner can call this function
     */
    function emergencyDisable2FA(address user) external onlyOwner {
        twoFactorEnabled[user] = false;
        delete userBackupCodes[user];
        failedAttempts[user] = 0;
        lastFailedAttempt[user] = 0;
        
        emit TwoFactorDisabled(user, block.timestamp);
    }
    
    /**
     * @dev Transfers contract ownership
     * @param newOwner The new owner address
     * @notice Only current owner can call this function
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        owner = newOwner;
    }
}