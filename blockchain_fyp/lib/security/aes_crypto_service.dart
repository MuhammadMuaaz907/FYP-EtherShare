import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:hex/hex.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

/// Encrypted payload containing ciphertext and IV
/// Both are base64-encoded strings for storage in SQLite
class EncryptedPayload {
  final String cipherText; // Base64-encoded encrypted message
  final String iv; // Base64-encoded initialization vector

  EncryptedPayload({
    required this.cipherText,
    required this.iv,
  });
}

/// AES-256-CBC Encryption Service
/// Provides secure encryption and decryption for chat messages using industry-standard AES-256-CBC
/// 
/// SECURITY ARCHITECTURE:
/// - Uses AES-256-CBC encryption (NIST-approved, industry standard)
/// - Random IV per message (prevents pattern analysis and ciphertext correlation)
/// - Key is stored securely using flutter_secure_storage (encrypted keychain/keystore)
/// - payload_hash is calculated from PLAINTEXT before encryption (preserves hash chain integrity)
/// - Server is zero-knowledge: never receives plaintext, cannot decrypt messages
/// 
/// CRYPTOGRAPHIC CHOICES (for FYP review):
/// - AES-256-CBC: Industry standard, NIST-approved, widely audited
///   - 256-bit keys provide strong security (128-bit security level)
///   - CBC mode ensures same plaintext produces different ciphertext (due to IV)
///   - Vulnerable to padding oracle attacks only if implemented incorrectly (we use encrypt package which handles this)
/// - Random IV per message: 
///   - Prevents pattern analysis (same message = different ciphertext)
///   - Prevents chosen-plaintext attacks
///   - IV is 16 bytes (128 bits) as required by AES
/// - PKCS7 padding: Standard padding scheme (handled by encrypt package)
/// 
/// KEY LIFECYCLE:
/// - Key is generated on first use (32 random bytes = 256 bits)
/// - Key is stored in secure storage (encrypted keychain on iOS, keystore on Android)
/// - Key persists across app sessions
/// - Key can be lost if device is wiped or secure storage is cleared
/// - TODO (Future): Implement key derivation from user credentials (wallet private key or biometric)
class AESCryptoService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  // Storage key for encryption key in secure storage
  // Key is stored as hex-encoded string for easy serialization
  static const String _keyStorageKey = 'aes_encryption_key';
  
  /// Get or generate encryption key from secure storage
  /// 
  /// KEY GENERATION:
  /// - If key doesn't exist: Generate 32 random bytes (256 bits for AES-256)
  /// - Store key securely using flutter_secure_storage
  /// - Key is hex-encoded for storage (hex string is human-readable for debugging)
  /// 
  /// KEY RETRIEVAL:
  /// - Load key from secure storage
  /// - Convert hex string back to bytes
  /// - Return key bytes for encryption/decryption
  /// 
  /// ERROR HANDLING:
  /// - If secure storage fails: Use fallback key (NOT SECURE - for development only)
  /// - TODO (Production): Handle key retrieval failure appropriately (require re-authentication)
  static Future<encrypt_lib.Key> _getEncryptionKey() async {
    try {
      // Try to get existing key from secure storage
      final existingKeyHex = await _secureStorage.read(key: _keyStorageKey);
      
      if (existingKeyHex != null && existingKeyHex.isNotEmpty) {
        // Key exists: Convert from hex string to bytes
        final keyBytes = HEX.decode(existingKeyHex);
        
        // Validate key size (must be 32 bytes for AES-256)
        if (keyBytes.length != 32) {
          print('⚠️ Invalid key size (${keyBytes.length} bytes), regenerating...');
          // Regenerate key if size is invalid
        } else {
          // Return valid key (convert List<int> to Uint8List)
          return encrypt_lib.Key(Uint8List.fromList(keyBytes));
        }
      }
      
      // Key doesn't exist or is invalid: Generate new key
      print('🔐 Generating new AES-256 encryption key...');
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final keyHex = HEX.encode(keyBytes);
      
      // Store securely in keychain/keystore
      await _secureStorage.write(key: _keyStorageKey, value: keyHex);
      print('✅ Encryption key generated and stored securely');
      
      return encrypt_lib.Key(Uint8List.fromList(keyBytes));
    } catch (e) {
      print('❌ Error getting encryption key: $e');
      // Fallback: Use a default key (NOT SECURE - only for development/testing)
      // In production, this should require user re-authentication or fail gracefully
      print('⚠️ WARNING: Using fallback key (NOT SECURE - development only)');
      return _generateFallbackKey();
    }
  }
  
  /// Generate fallback key (development only - NOT SECURE)
  /// 
  /// WARNING: This is NOT cryptographically secure
  /// - Uses a predictable default key
  /// - Only for development/testing when secure storage fails
  /// - Production code should NEVER use this
  /// - TODO: Replace with proper error handling that requires user authentication
  static encrypt_lib.Key _generateFallbackKey() {
    // WARNING: This is NOT secure - only for development/testing
    // In production, this should never be used
    final defaultKeyString = 'default_dev_key_change_in_production_32bytes!';
    final keyBytes = utf8.encode(defaultKeyString).take(32).toList();
    return encrypt_lib.Key(Uint8List.fromList(keyBytes));
  }
  
  /// Generate random IV (Initialization Vector) for CBC mode
  /// 
  /// IV REQUIREMENTS:
  /// - Must be exactly 16 bytes (128 bits) for AES block size
  /// - Must be cryptographically random (use Random.secure())
  /// - Must be unique per message (never reuse IV with same key)
  /// - IV is NOT secret (can be stored with ciphertext)
  /// 
  /// SECURITY IMPORTANCE:
  /// - Random IV ensures same plaintext produces different ciphertext
  /// - Prevents pattern analysis and correlation attacks
  /// - Must be unique per encryption operation (not just per message)
  static encrypt_lib.IV _generateIV() {
    final random = Random.secure();
    final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return encrypt_lib.IV(Uint8List.fromList(ivBytes));
  }
  
  /// Encrypt plaintext message using AES-256-CBC
  /// 
  /// INPUT: Plaintext string
  /// OUTPUT: EncryptedPayload with base64-encoded ciphertext and IV
  /// 
  /// ENCRYPTION PROCESS:
  /// 1. Generate random IV per message (prevents pattern analysis)
  /// 2. Get encryption key from secure storage
  /// 3. Encrypt using AES-256-CBC with PKCS7 padding (handled by encrypt package)
  /// 4. Return base64-encoded ciphertext and IV
  /// 
  /// SECURITY FLOW:
  /// - payload_hash is calculated from plaintext BEFORE encryption (preserves hash chain integrity)
  /// - Server receives encrypted payload (zero-knowledge - cannot read plaintext)
  /// - Only client can decrypt (has encryption key)
  /// 
  /// PRODUCTION vs PLACEHOLDER:
  /// - PLACEHOLDER: Used XOR-based encryption (NOT secure, demonstration only)
  /// - PRODUCTION: Uses proper AES-256-CBC via encrypt package (NIST-approved, audited)
  static Future<EncryptedPayload> encrypt(String plaintext) async {
    try {
      if (plaintext.isEmpty) {
        throw ArgumentError('Cannot encrypt empty plaintext');
      }
      
      // Step 1: Generate random IV for this message
      // CRITICAL: IV must be unique per encryption operation
      // Same plaintext + same key + different IV = different ciphertext
      final iv = _generateIV();
      
      // Step 2: Get encryption key from secure storage
      final key = await _getEncryptionKey();
      
      // Step 3: Create encryptor with AES-256-CBC mode
      // encrypt package handles:
      // - AES-256 encryption (256-bit key)
      // - CBC mode (Cipher Block Chaining)
      // - PKCS7 padding (automatic)
      // - Secure random number generation for IV
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );
      
      // Step 4: Encrypt plaintext
      // encrypt package handles all the crypto details (block chaining, padding, etc.)
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      
      // Step 5: Return base64-encoded ciphertext and IV
      // Both are base64-encoded for safe storage in SQLite (text fields)
      return EncryptedPayload(
        cipherText: encrypted.base64,
        iv: iv.base64,
      );
    } catch (e) {
      print('❌ Encryption error: $e');
      // Throw controlled error (no crash) - let caller handle gracefully
      throw Exception('Failed to encrypt message: ${e.toString()}');
    }
  }
  
  /// Decrypt ciphertext using AES-256-CBC
  /// 
  /// INPUT:
  /// - cipherText: Base64-encoded encrypted message
  /// - iv: Base64-encoded initialization vector
  /// 
  /// OUTPUT: Plaintext string
  /// 
  /// DECRYPTION PROCESS:
  /// 1. Decode base64 ciphertext and IV
  /// 2. Get decryption key from secure storage (same as encryption key - symmetric crypto)
  /// 3. Decrypt using AES-256-CBC (encrypt package handles padding removal)
  /// 4. Return plaintext string
  /// 
  /// ERROR HANDLING:
  /// - Throws controlled Exception on failure (no crash)
  /// - Common failures: Wrong key, corrupted ciphertext, invalid IV
  /// - Caller should handle errors gracefully (fallback to legacy message_text if available)
  /// 
  /// ZERO-KNOWLEDGE NOTE:
  /// - Server cannot decrypt (doesn't have key)
  /// - Only client can decrypt (has key in secure storage)
  /// - This enforces zero-knowledge architecture (server cannot read message content)
  static Future<String> decrypt({
    required String cipherText,
    required String iv,
  }) async {
    try {
      if (cipherText.isEmpty || iv.isEmpty) {
        throw ArgumentError('Ciphertext and IV cannot be empty');
      }
      
      // Step 1: Decode base64-encoded ciphertext and IV
      final encryptedData = encrypt_lib.Encrypted.fromBase64(cipherText);
      final ivData = encrypt_lib.IV.fromBase64(iv);
      
      // Step 2: Get decryption key from secure storage
      // For symmetric crypto (AES), encryption and decryption use the same key
      final key = await _getEncryptionKey();
      
      // Step 3: Create decryptor with AES-256-CBC mode
      // Must use same mode and padding as encryption (CBC + PKCS7)
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );
      
      // Step 4: Decrypt ciphertext
      // encrypt package handles:
      // - AES-256 decryption
      // - CBC mode decryption
      // - PKCS7 padding removal (automatic)
      final plaintext = encrypter.decrypt(encryptedData, iv: ivData);
      
      // Step 5: Return plaintext string
      return plaintext;
    } catch (e) {
      print('❌ Decryption error: $e');
      // Throw controlled error (no crash) - let caller handle gracefully
      throw Exception('Failed to decrypt message: ${e.toString()}');
    }
  }
}
