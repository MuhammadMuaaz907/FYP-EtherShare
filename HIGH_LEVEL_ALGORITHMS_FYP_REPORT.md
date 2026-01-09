# High-Level Algorithms - EtherShare FYP Report

## Table of Contents
1. [User Registration & Authentication Algorithm](#1-user-registration--authentication-algorithm)
2. [Message Sending & Storage Algorithm](#2-message-sending--storage-algorithm)
3. [Hash Chain Integrity Verification Algorithm](#3-hash-chain-integrity-verification-algorithm)
4. [P2P Communication Algorithm](#4-p2p-communication-algorithm)
5. [Hybrid Storage Sync Algorithm](#5-hybrid-storage-sync-algorithm)
6. [Two-Factor Authentication (2FA) Algorithm](#6-two-factor-authentication-2fa-algorithm)
7. [File Sharing Algorithm](#7-file-sharing-algorithm)
8. [Workspace/Channel Management Algorithm](#8-workspacechannel-management-algorithm)
9. [Node Registration & Chain Building Algorithm](#9-node-registration--chain-building-algorithm)

---

## 1. User Registration & Authentication Algorithm

### 1.1 User Registration Algorithm

```
ALGORITHM: UserRegistration
INPUT: privateKey (user's Ethereum private key), username, email
OUTPUT: registrationStatus (success/failure)

BEGIN
    1. Extract Ethereum address from privateKey
       address = deriveAddress(privateKey)
    
    2. Check if address is already registered on blockchain
       isRegistered = checkBlockchainRegistration(address)
       
       IF isRegistered == true THEN
           RETURN "Error: Address already registered. Please sign in."
       END IF
    
    3. Check if profile exists in MongoDB
       existingProfile = queryMongoDB("users", {address: address})
       
       IF existingProfile != null THEN
           RETURN "Error: Address already registered. Please sign in."
       END IF
    
    4. Register user on blockchain (smart contract)
       transaction = executeSmartContract("register", {from: address, privateKey: privateKey})
       WAIT_FOR transaction confirmation
    
    5. IF transaction.status == SUCCESS THEN
           Login user on blockchain
           loginTransaction = executeSmartContract("login", {from: address, privateKey: privateKey})
           WAIT_FOR loginTransaction confirmation
           
           RETURN "Registration successful. Proceed to profile setup."
       ELSE
           RETURN "Error: Blockchain registration failed."
       END IF
END
```

### 1.2 User Login Algorithm

```
ALGORITHM: UserLogin
INPUT: privateKey (user's Ethereum private key)
OUTPUT: loginStatus (success/failure), userProfile

BEGIN
    1. Extract Ethereum address from privateKey
       address = deriveAddress(privateKey)
    
    2. Check blockchain registration status
       isRegistered = checkBlockchainRegistration(address)
       
       IF isRegistered == false THEN
           RETURN "Error: Address not registered. Please sign up first."
       END IF
    
    3. Login user on blockchain
       transaction = executeSmartContract("login", {from: address, privateKey: privateKey})
       WAIT_FOR transaction confirmation
    
    4. Retrieve user profile from MongoDB
       userProfile = queryMongoDB("users", {address: address})
    
    5. Check if profile exists
       IF userProfile == null THEN
           RETURN "Profile setup required."
       END IF
    
    6. Check 2FA status
       is2FAEnabled = checkBlockchain2FA(address)
       
       IF is2FAEnabled == true THEN
           RETURN "2FA verification required."
       ELSE
           RETURN "Login successful."
       END IF
END
```

---

## 2. Message Sending & Storage Algorithm

### 2.1 Message Sending with Hash Chain Algorithm

```
ALGORITHM: SendMessageWithHashChain
INPUT: senderAddress, receiverAddress/channelId, messageText, workspaceId
OUTPUT: messageId, transactionStatus

BEGIN
    1. Create message data object
       messageData = {
           message_id: generateUniqueId(),
           sender_address: senderAddress,
           receiver_address: receiverAddress,
           message_text: messageText,
           workspace_id: workspaceId,
           channel_id: channelId,
           timestamp: currentTimestamp()
       }
    
    2. Determine hash chain filter (conversation context)
       IF channelId != null THEN
           filter = {workspace_id: workspaceId, channel_id: channelId}
       ELSE IF receiverAddress != null THEN
           filter = {
               $or: [
                   {sender_address: senderAddress, receiver_address: receiverAddress},
                   {sender_address: receiverAddress, receiver_address: senderAddress}
               ]
           }
       ELSE
           filter = {workspace_id: workspaceId}
       END IF
    
    3. Add hash chain fields (with retry mechanism for race conditions)
       retryAttempts = 0
       maxRetries = 5
       insertSuccess = false
       
       WHILE insertSuccess == false AND retryAttempts < maxRetries DO
           3.1 Get last message in chain
               lastMessage = queryMongoDB("messages", filter, {sort: {timestamp: -1}, limit: 1})
           
           3.2 Calculate previous hash
               IF lastMessage == null THEN
                   previousHash = "0"  // Genesis hash
               ELSE
                   previousHash = lastMessage.current_hash
               END IF
           
           3.3 Calculate current hash
               dataString = JSON.stringify(messageData, sortedKeys)
               combinedString = dataString + previousHash
               currentHash = SHA256(combinedString)
           
           3.4 Verify hash is still valid (atomic check)
               verifyInfo = getAndVerifyLastHash("messages", filter, previousHash)
               
               IF verifyInfo.isValid == false THEN
                   retryAttempts = retryAttempts + 1
                   WAIT (30 * retryAttempts) milliseconds
                   CONTINUE  // Retry with new hash
               END IF
           
           3.5 Add hash fields to message
               messageWithHash = {
                   ...messageData,
                   previous_hash: previousHash,
                   current_hash: currentHash
               }
           
           3.6 Insert message into MongoDB (atomic operation)
               insertResult = insertMongoDB("messages", messageWithHash)
               
               IF insertResult.success == true THEN
                   insertSuccess = true
               ELSE
                   retryAttempts = retryAttempts + 1
                   WAIT (30 * retryAttempts) milliseconds
               END IF
       END WHILE
    
    4. IF insertSuccess == true THEN
           RETURN messageWithHash.message_id, "SUCCESS"
       ELSE
           RETURN null, "FAILED: Max retries exceeded"
       END IF
END
```

### 2.2 Message Retrieval Algorithm

```
ALGORITHM: RetrieveMessages
INPUT: workspaceId, channelId/receiverAddress, senderAddress
OUTPUT: messages[], chainIntegrityStatus

BEGIN
    1. Determine filter for messages
       IF channelId != null THEN
           filter = {workspace_id: workspaceId, channel_id: channelId}
       ELSE IF receiverAddress != null THEN
           filter = {
               $or: [
                   {sender_address: senderAddress, receiver_address: receiverAddress},
                   {sender_address: receiverAddress, receiver_address: senderAddress}
               ]
           }
       ELSE
           filter = {workspace_id: workspaceId}
       END IF
    
    2. Verify chain integrity before retrieval
       integrityResult = VerifyChainIntegrity("messages", filter)
       
       IF integrityResult.valid == false THEN
           RETURN [], "CHAIN_BROKEN"
       END IF
    
    3. Retrieve messages from database
       messages = queryMongoDB("messages", filter, {sort: {timestamp: 1}})
    
    4. RETURN messages, "CHAIN_VALID"
END
```

---

## 3. Hash Chain Integrity Verification Algorithm

```
ALGORITHM: VerifyChainIntegrity
INPUT: collectionName, filter
OUTPUT: {valid: boolean, brokenAt: string, details: object}

BEGIN
    1. Retrieve all documents in chain order
       documents = queryMongoDB(collectionName, filter, {sort: {timestamp: 1}})
    
    2. IF documents.length == 0 THEN
           RETURN {valid: true, brokenAt: null, details: {verifiedDocuments: 0}}
       END IF
    
    3. Initialize verification variables
       expectedPreviousHash = "0"  // Genesis hash
       verifiedDocuments = 0
       brokenAt = null
       brokenDocuments = []
    
    4. FOR each document in documents DO
           4.1 Check previous hash matches
               IF document.previous_hash != expectedPreviousHash THEN
                   brokenAt = document._id
                   brokenDocuments.append({
                       id: document._id,
                       reason: "previous_hash_mismatch",
                       expected: expectedPreviousHash,
                       found: document.previous_hash
                   })
                   
                   MARK chain_broken = true FOR this document and all subsequent documents
                   RETURN {valid: false, brokenAt: brokenAt, details: {brokenDocuments: brokenDocuments}}
               END IF
           
           4.2 Recalculate current hash
               dataForHash = extractDataFields(document)  // Exclude hash fields
               dataString = JSON.stringify(dataForHash, sortedKeys)
               combinedString = dataString + document.previous_hash
               calculatedHash = SHA256(combinedString)
           
           4.3 Verify current hash matches
               IF calculatedHash != document.current_hash THEN
                   brokenAt = document._id
                   brokenDocuments.append({
                       id: document._id,
                       reason: "current_hash_mismatch",
                       expected: calculatedHash,
                       found: document.current_hash
                   })
                   
                   MARK chain_broken = true FOR this document and all subsequent documents
                   RETURN {valid: false, brokenAt: brokenAt, details: {brokenDocuments: brokenDocuments}}
               END IF
           
           4.4 Update expected hash for next iteration
               expectedPreviousHash = document.current_hash
               verifiedDocuments = verifiedDocuments + 1
       END FOR
    
    5. RETURN {valid: true, brokenAt: null, details: {verifiedDocuments: verifiedDocuments}}
END
```

---

## 4. P2P Communication Algorithm

### 4.1 P2P Server Initialization Algorithm

```
ALGORITHM: InitializeP2PServer
INPUT: userAddress, port
OUTPUT: serverStatus (started/failed)

BEGIN
    1. Get local IP address
       networkInterfaces = getNetworkInterfaces()
       localIP = findFirstNonLoopbackIPv4(networkInterfaces)
    
    2. Start TCP server socket
       serverSocket = createTCPServer(port)
       
       IF serverSocket == null THEN
           RETURN "FAILED: Could not bind to port"
       END IF
    
    3. Set up connection handler
       ON newConnection(socket) DO
           peerId = generatePeerId()
           storeConnection(peerId, socket)
           setupMessageHandler(peerId, socket)
           
           SEND handshake message to peer
           handshakeMessage = {
               type: "handshake",
               user_address: userAddress,
               ip_address: localIP,
               port: port,
               timestamp: currentTimestamp()
           }
           SEND(socket, handshakeMessage)
       END ON
    
    4. Register peer information with server (if online)
       IF serverOnline == true THEN
           registerPeer(userAddress, localIP, port)
       END IF
    
    5. Store peer info locally in SQLite
       savePeerInfo(userAddress, localIP, port, "SQLite")
    
    6. RETURN "STARTED"
END
```

### 4.2 P2P Message Sending Algorithm

```
ALGORITHM: SendP2PMessage
INPUT: receiverAddress, messageText, workspaceId, channelId
OUTPUT: deliveryStatus (sent/failed)

BEGIN
    1. Look up receiver's peer information
       peerInfo = querySQLite("peers", {user_address: receiverAddress})
       
       IF peerInfo == null THEN
           IF serverOnline == true THEN
               peerInfo = queryServer("peers", {user_address: receiverAddress})
               IF peerInfo != null THEN
                   savePeerInfo(peerInfo, "SQLite")  // Cache for offline use
               END IF
           END IF
       END IF
       
       IF peerInfo == null THEN
           RETURN "FAILED: Peer information not found"
       END IF
    
    2. Check if connection exists
       IF connectionExists(receiverAddress) == false THEN
           connectionStatus = connectToPeer(peerInfo.ip_address, peerInfo.port, receiverAddress)
           
           IF connectionStatus == false THEN
               RETURN "FAILED: Could not establish connection"
           END IF
       END IF
    
    3. Create message packet
       messagePacket = {
           type: "message",
           sender_address: currentUserAddress,
           receiver_address: receiverAddress,
           message_text: messageText,
           workspace_id: workspaceId,
           channel_id: channelId,
           message_id: generateUniqueId(),
           timestamp: currentTimestamp()
       }
    
    4. Send message via TCP socket
       socket = getConnection(receiverAddress)
       sendStatus = SEND(socket, JSON.stringify(messagePacket))
       
       IF sendStatus == false THEN
           RETURN "FAILED: Could not send message"
       END IF
    
    5. Wait for acknowledgment
       acknowledgment = WAIT_FOR_ACK(messagePacket.message_id, timeout: 5 seconds)
       
       IF acknowledgment == null THEN
           RETURN "FAILED: No acknowledgment received"
       END IF
    
    6. Save message locally to SQLite
       saveMessageToSQLite(messagePacket)
    
    7. Sync to server (if online) - asynchronous
       IF serverOnline == true THEN
           syncMessageToServer(messagePacket)  // Non-blocking
       END IF
    
    8. RETURN "SENT"
END
```

### 4.3 P2P Message Reception Algorithm

```
ALGORITHM: ReceiveP2PMessage
INPUT: socket, rawData
OUTPUT: messageProcessed

BEGIN
    1. Parse incoming message
       message = JSON.parse(rawData)
    
    2. Handle different message types
       SWITCH message.type DO
           CASE "handshake":
               handleHandshake(socket, message)
               BREAK
           
           CASE "handshake_ack":
               handleHandshakeAck(socket, message)
               BREAK
           
           CASE "message":
           CASE "channel_message":
               handleIncomingMessage(message)
               BREAK
           
           CASE "ack":
               handleAcknowledgment(message)
               BREAK
           
           CASE "ping":
               sendPong(socket, message)
               BREAK
           
           DEFAULT:
               log("Unknown message type: " + message.type)
       END SWITCH
END

FUNCTION: handleIncomingMessage(message)
BEGIN
    1. Save message to SQLite (local storage)
       saveMessageToSQLite(message)
    
    2. Trigger callback for UI update
       IF onMessageReceived callback exists THEN
           CALL onMessageReceived(message)
       END IF
    
    3. Sync to server (if online) - asynchronous
       IF serverOnline == true THEN
           syncMessageToServer(message)  // Non-blocking
       END IF
    
    4. Send acknowledgment
       ackMessage = {
           type: "ack",
           message_id: message.message_id,
           status: "received",
           timestamp: currentTimestamp()
       }
       SEND(socket, ackMessage)
END
```

---

## 5. Hybrid Storage Sync Algorithm

```
ALGORITHM: HybridStorageSync
INPUT: userAddress
OUTPUT: syncStatus

BEGIN
    1. Initialize hybrid storage service
       initializeSQLite()
       checkServerStatus()
       initializeP2PServer(userAddress)
    
    2. Start periodic sync timer (every 30 seconds)
       SET_TIMER(30 seconds, syncToServer)
    
    3. FUNCTION: syncToServer()
          3.1 Check server status
              serverOnline = checkServerHealth()
              
              IF serverOnline == false THEN
                  RETURN  // Skip sync if server offline
              END IF
          
          3.2 Sync unsynced messages from SQLite to MongoDB
              unsyncedMessages = querySQLite("messages", {synced: false})
              
              FOR each message in unsyncedMessages DO
                  syncResult = sendMessageToServer(message)
                  
                  IF syncResult.success == true THEN
                      UPDATE SQLite: SET synced = true WHERE message_id = message.message_id
                  END IF
              END FOR
          
          3.3 Sync server messages to SQLite (for offline access)
              serverMessages = queryServer("messages", {workspace_id: currentWorkspace})
              
              FOR each message in serverMessages DO
                  existingMessage = querySQLite("messages", {message_id: message.message_id})
                  
                  IF existingMessage == null THEN
                      saveMessageToSQLite(message)
                  END IF
              END FOR
          
          3.4 Discover and cache peers from server
              IF serverOnline == true THEN
                  peers = queryServer("peers", {status: "online"})
                  
                  FOR each peer in peers DO
                      savePeerInfo(peer, "SQLite")  // Cache for offline P2P
                  END FOR
              END IF
       END FUNCTION
    
    4. FUNCTION: sendMessage(message)
          4.1 Try P2P first (if peer info available)
              IF peerInfoAvailable(receiverAddress) == true THEN
                  p2pStatus = sendP2PMessage(message)
                  
                  IF p2pStatus == "SENT" THEN
                      saveMessageToSQLite(message)
                      
                      IF serverOnline == true THEN
                          syncMessageToServer(message)  // Async backup
                      END IF
                      
                      RETURN "SENT_VIA_P2P"
                  END IF
              END IF
          
          4.2 Fall back to server
              IF serverOnline == true THEN
                  serverStatus = sendMessageToServer(message)
                  
                  IF serverStatus.success == true THEN
                      saveMessageToSQLite(message, synced: true)
                      RETURN "SENT_VIA_SERVER"
                  ELSE
                      saveMessageToSQLite(message, synced: false)  // Queue for later sync
                      RETURN "QUEUED_FOR_SYNC"
                  END IF
              ELSE
                  saveMessageToSQLite(message, synced: false)
                  RETURN "QUEUED_FOR_SYNC"
              END IF
       END FUNCTION
END
```

---

## 6. Two-Factor Authentication (2FA) Algorithm

### 6.1 Enable 2FA Algorithm

```
ALGORITHM: Enable2FA
INPUT: userAddress, privateKey, backupCodes[]
OUTPUT: 2FAStatus

BEGIN
    1. Check if user is registered
       isRegistered = checkBlockchainRegistration(userAddress)
       
       IF isRegistered == false THEN
           RETURN "Error: User not registered"
       END IF
    
    2. Check if 2FA is already enabled
       is2FAEnabled = checkBlockchain2FA(userAddress)
       
       IF is2FAEnabled == true THEN
           RETURN "Error: 2FA already enabled"
       END IF
    
    3. Validate backup codes
       IF backupCodes.length == 0 OR backupCodes.length > 20 THEN
           RETURN "Error: Invalid number of backup codes"
       END IF
    
    4. Enable 2FA on blockchain
       transaction = executeSmartContract("enable2FA", {
           from: userAddress,
           privateKey: privateKey,
           backupCodes: backupCodes
       })
       WAIT_FOR transaction confirmation
    
    5. Generate TOTP secret (off-chain)
       totpSecret = generateTOTPSecret()
       saveTOTPSecret(userAddress, totpSecret, "SecureStorage")
    
    6. Store 2FA settings locally
       save2FASettings(userAddress, {
           enabled: true,
           totpSecret: totpSecret,
           backupCodes: backupCodes
       }, "SecureStorage")
    
    7. IF transaction.status == SUCCESS THEN
           RETURN "2FA enabled successfully"
       ELSE
           RETURN "Error: 2FA enable failed"
       END IF
END
```

### 6.2 Verify 2FA Algorithm

```
ALGORITHM: Verify2FA
INPUT: userAddress, privateKey, code (TOTP or backup code)
OUTPUT: verificationStatus (success/failure)

BEGIN
    1. Check if 2FA is enabled
       is2FAEnabled = checkBlockchain2FA(userAddress)
       
       IF is2FAEnabled == false THEN
           RETURN "Error: 2FA not enabled"
       END IF
    
    2. Check if account is locked out
       isLockedOut = checkBlockchainLockout(userAddress)
       
       IF isLockedOut == true THEN
           lockoutTime = getRemainingLockoutTime(userAddress)
           RETURN "Error: Account locked. Try again after " + lockoutTime + " seconds"
       END IF
    
    3. Verify code on blockchain
       verificationResult = executeSmartContract("verify2FA", {
           from: userAddress,
           privateKey: privateKey,
           code: code
       })
       WAIT_FOR transaction confirmation
    
    4. Check verification result
       IF verificationResult.success == true THEN
           IF code is backup code THEN
               backupCodesRemaining = getBackupCodeCount(userAddress)
               log("Backup code used. Remaining: " + backupCodesRemaining)
           END IF
           
           RETURN "Verification successful"
       ELSE
           failedAttempts = getFailedAttempts(userAddress)
           
           IF failedAttempts >= 3 THEN
               RETURN "Error: Too many failed attempts. Account locked."
           ELSE
               RETURN "Error: Invalid code. Attempts remaining: " + (3 - failedAttempts)
           END IF
       END IF
END
```

---

## 7. File Sharing Algorithm

```
ALGORITHM: ShareFile
INPUT: filePath, receiverAddress/channelId, workspaceId
OUTPUT: fileId, uploadStatus

BEGIN
    1. Read file from local storage
       fileData = readFile(filePath)
       fileSize = getFileSize(fileData)
       fileName = getFileName(filePath)
       fileType = getFileType(filePath)
    
    2. Check file size limits
       IF fileSize > MAX_FILE_SIZE THEN
           RETURN null, "Error: File too large"
       END IF
    
    3. Generate unique file ID
       fileId = generateUniqueId("file_")
    
    4. Upload file to server (if online)
       IF serverOnline == true THEN
           uploadResult = uploadToServer(fileData, fileName, fileType)
           
           IF uploadResult.success == true THEN
               fileUrl = uploadResult.url
               saveFileMetadata(fileId, fileName, fileType, fileSize, fileUrl, "MongoDB")
           ELSE
               RETURN null, "Error: File upload failed"
           END IF
       ELSE
           fileUrl = null  // Will be uploaded when server comes online
           saveFileMetadata(fileId, fileName, fileType, fileSize, null, "SQLite", synced: false)
       END IF
    
    5. Create message with file attachment
       messageData = {
           message_id: generateUniqueId("msg_"),
           sender_address: currentUserAddress,
           receiver_address: receiverAddress,
           channel_id: channelId,
           workspace_id: workspaceId,
           message_text: fileName,
           file_id: fileId,
           file_name: fileName,
           file_type: fileType,
           file_size: fileSize,
           timestamp: currentTimestamp()
       }
    
    6. Send message with file reference
       IF channelId != null THEN
           messageStatus = sendChannelMessage(messageData)
       ELSE
           messageStatus = sendDirectMessage(messageData)
       END IF
    
    7. Save file metadata locally
       saveFileMetadata(fileId, fileName, fileType, fileSize, fileUrl, "SQLite")
    
    8. RETURN fileId, messageStatus
END

ALGORITHM: DownloadFile
INPUT: fileId
OUTPUT: fileData, downloadStatus

BEGIN
    1. Retrieve file metadata
       fileMetadata = querySQLite("files", {file_id: fileId})
       
       IF fileMetadata == null AND serverOnline == true THEN
           fileMetadata = queryServer("files", {file_id: fileId})
           
           IF fileMetadata != null THEN
               saveFileMetadata(fileMetadata, "SQLite")  // Cache
           END IF
       END IF
       
       IF fileMetadata == null THEN
           RETURN null, "Error: File not found"
       END IF
    
    2. Check if file exists locally
       localFilePath = getLocalFilePath(fileId)
       
       IF fileExists(localFilePath) == true THEN
           fileData = readFile(localFilePath)
           RETURN fileData, "SUCCESS (local)"
       END IF
    
    3. Download file from server
       IF serverOnline == true AND fileMetadata.url != null THEN
           downloadResult = downloadFromServer(fileMetadata.url)
           
           IF downloadResult.success == true THEN
               saveFileLocally(fileId, downloadResult.data)
               RETURN downloadResult.data, "SUCCESS (downloaded)"
           ELSE
               RETURN null, "Error: Download failed"
           END IF
       ELSE
           RETURN null, "Error: File not available offline"
       END IF
END
```

---

## 8. Workspace/Channel Management Algorithm

```
ALGORITHM: CreateWorkspace
INPUT: workspaceName, creatorAddress, description
OUTPUT: workspaceId, creationStatus

BEGIN
    1. Generate unique workspace ID
       workspaceId = generateUniqueId("workspace_")
    
    2. Create workspace object
       workspaceData = {
           workspace_id: workspaceId,
           name: workspaceName,
           creator_address: creatorAddress,
           description: description,
           created_at: currentTimestamp(),
           members: [creatorAddress],
           channels: []
       }
    
    3. Add hash chain fields
       workspaceData.previous_hash = "0"  // Genesis
       workspaceData.current_hash = SHA256(JSON.stringify(workspaceData) + "0")
    
    4. Save workspace to database
       IF serverOnline == true THEN
           saveResult = saveToMongoDB("workspaces", workspaceData)
           saveToSQLite("workspaces", workspaceData, synced: true)
       ELSE
           saveToSQLite("workspaces", workspaceData, synced: false)
       END IF
    
    5. RETURN workspaceId, "SUCCESS"
END

ALGORITHM: CreateChannel
INPUT: channelName, workspaceId, creatorAddress
OUTPUT: channelId, creationStatus

BEGIN
    1. Generate unique channel ID
       channelId = generateUniqueId("channel_")
    
    2. Create channel object
       channelData = {
           channel_id: channelId,
           workspace_id: workspaceId,
           name: channelName,
           creator_address: creatorAddress,
           created_at: currentTimestamp(),
           members: [creatorAddress]
       }
    
    3. Add hash chain fields
       lastChannel = queryLastChannel(workspaceId)
       IF lastChannel == null THEN
           channelData.previous_hash = "0"
       ELSE
           channelData.previous_hash = lastChannel.current_hash
       END IF
       channelData.current_hash = SHA256(JSON.stringify(channelData) + channelData.previous_hash)
    
    4. Save channel to database
       IF serverOnline == true THEN
           saveResult = saveToMongoDB("channels", channelData)
           saveToSQLite("channels", channelData, synced: true)
       ELSE
           saveToSQLite("channels", channelData, synced: false)
       END IF
    
    5. Update workspace channels list
       updateWorkspaceChannels(workspaceId, channelId)
    
    6. Broadcast channel creation via P2P (if applicable)
       broadcastChannelCreation(workspaceId, channelData)
    
    7. RETURN channelId, "SUCCESS"
END
```

---

## 9. Node Registration & Chain Building Algorithm

```
ALGORITHM: RegisterNode
INPUT: nodeName, ipAddress, tcpPort
OUTPUT: nodeId, registrationStatus

BEGIN
    1. Generate unique node ID
       nodeId = generateUniqueId("node_")
    
    2. Get last node in chain
       lastNode = queryMongoDB("nodes", {is_deprecated: false}, {sort: {chain_position: -1}, limit: 1})
    
    3. Calculate chain position and hashes
       IF lastNode == null THEN
           chainPosition = 0
           previousHash = "0"  // Genesis hash
           previousNodeId = null
       ELSE
           chainPosition = lastNode.chain_position + 1
           previousHash = lastNode.current_hash
           previousNodeId = lastNode.node_id
       END IF
    
    4. Create node data object
       nodeData = {
           node_id: nodeId,
           node_name: nodeName,
           ip_address: ipAddress,
           tcp_port: tcpPort,
           chain_position: chainPosition,
           previous_node_id: previousNodeId,
           next_node_id: null,
           previous_hash: previousHash,
           is_deprecated: false,
           registered_at: currentTimestamp()
       }
    
    5. Calculate current hash
       dataString = JSON.stringify({
           node_id: nodeId,
           node_name: nodeName,
           ip_address: ipAddress,
           tcp_port: tcpPort,
           chain_position: chainPosition
       })
       combinedString = dataString + previousHash
       currentHash = SHA256(combinedString)
       nodeData.current_hash = currentHash
    
    6. Calculate gas (blockchain-like)
       executionTime = measureExecutionTime()
       gasUsed = calculateGas(executionTime, nodeData)
       gasPrice = getCurrentGasPrice()
       transactionFee = gasUsed * gasPrice
       
       nodeData.gas_used = gasUsed
       nodeData.gas_price = gasPrice
       nodeData.transaction_fee = transactionFee
    
    7. Save node to database
       saveResult = saveToMongoDB("nodes", nodeData)
    
    8. Update previous node's next_node_id
       IF previousNodeId != null THEN
           updateMongoDB("nodes", {node_id: previousNodeId}, {next_node_id: nodeId})
       END IF
    
    9. Verify chain integrity
       chainValid = verifyNodeChain()
       
       IF chainValid == false THEN
           log("WARNING: Chain integrity compromised after node registration")
       END IF
    
    10. RETURN nodeId, "SUCCESS"
END
```

---

## Algorithm Complexity Analysis

### Time Complexity

| Algorithm | Best Case | Average Case | Worst Case |
|-----------|-----------|--------------|------------|
| User Registration | O(1) | O(log n) | O(n) |
| Message Sending | O(1) | O(log n) | O(n) |
| Hash Chain Verification | O(n) | O(n) | O(n) |
| P2P Message Sending | O(1) | O(1) | O(n) |
| Hybrid Storage Sync | O(m) | O(m) | O(m*n) |
| 2FA Verification | O(1) | O(1) | O(1) |
| File Sharing | O(f) | O(f) | O(f*n) |

Where:
- n = number of records in database
- m = number of unsynced messages
- f = file size

### Space Complexity

| Algorithm | Space Complexity |
|-----------|------------------|
| User Registration | O(1) |
| Message Sending | O(1) |
| Hash Chain Verification | O(n) |
| P2P Communication | O(p) |
| Hybrid Storage Sync | O(m) |

Where:
- n = number of messages in chain
- p = number of connected peers
- m = number of unsynced messages

---

## Summary

These high-level algorithms form the core functionality of the EtherShare system:

1. **Blockchain-based Authentication**: Secure user registration and login using Ethereum smart contracts
2. **Hash Chain Integrity**: Tamper-proof message storage with blockchain-like verification
3. **P2P Communication**: Direct device-to-device messaging without server dependency
4. **Hybrid Storage**: Seamless synchronization between server (MongoDB) and local (SQLite) storage
5. **2FA Security**: Multi-factor authentication with TOTP and backup codes
6. **File Sharing**: Secure file upload, download, and sharing with offline support
7. **Workspace Management**: Collaborative workspace and channel creation with integrity checks
8. **Distributed Nodes**: Blockchain-like node registration with chain building and verification

These algorithms work together to provide a secure, decentralized, and resilient file sharing and communication system.

