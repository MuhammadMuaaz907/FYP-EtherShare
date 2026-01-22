# 📘 EtherShare – Complete Project Flow (Roman Urdu)

## 🎯 Project Kya Hai?

**EtherShare** ek **blockchain-based secure messaging aur file sharing app** hai. Ye FYP (Final Year Project) hai jisme:

- **Blockchain** (Ethereum/Smart Contract) se **user authentication** (login, 2FA)
- **MongoDB + Node.js backend** se **distributed messaging** (hash chain, encryption)
- **SQLite + TCP P2P** se **offline / direct device-to-device** chat
- **AES-256 encryption** se **zero-knowledge** – server ko plaintext kabhi nahi milta

---

## 🛠️ Tech Stack (Summary)

| Layer | Technology | Kaam |
|-------|------------|------|
| **Mobile/Desktop App** | Flutter (Dart) | UI, crypto, P2P, SQLite |
| **Blockchain** | Solidity (UserAuth.sol), web3dart, ngrok RPC | Login, Register, 2FA on-chain |
| **Backend** | Node.js, Express | REST API, hash chain, MongoDB |
| **Database (Server)** | MongoDB | messages, workspaces, channels, nodes, peers, ledgers |
| **Database (Local)** | SQLite | Offline messages, peers, workspaces, sync_queue |
| **P2P** | TCP sockets (Dart) | Device-to-device messaging jab server offline ho |
| **Encryption** | AES-256-CBC (encrypt pkg) | Message encryption, zero-knowledge |
| **Hashing** | SHA-256 (hashChain.js, crypto) | Hash chain integrity |

---

## 🏗️ Architecture (3 Layers)

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: APPLICATION (Flutter App)                              │
│  - Login/SignUp (ContractService → Blockchain)                   │
│  - Workspaces, Channels, DMs                                     │
│  - Message send: HybridStorageService → Server ya P2P            │
│  - AESCryptoService: encrypt before send, decrypt on receive     │
└─────────────────────────────────────────────────────────────────┘
                    │                           │
        Server Online?                    Server Offline?
                    │                           │
                    ▼                           ▼
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│  LAYER 2: DISTRIBUTED (Backend) │   │  LAYER 3: DECENTRALIZED (P2P)   │
│  - Node.js + MongoDB            │   │  - SQLite (local)               │
│  - Hash chain (messages)        │   │  - P2PService (TCP)             │
│  - Encrypted storage only       │   │  - sync_queue (baad mein sync)  │
│  - /api/messages, /api/nodes    │   │  - Direct device ↔ device       │
└─────────────────────────────────┘   └─────────────────────────────────┘
```

---

## 📱 Complete Flow – Step by Step

### 1️⃣ App Start (main.dart → Splash)

1. **main.dart**
   - Flutter init, `.env` load (BACKEND_URL agar hai).
   - **Web3App** (WalletConnect) register.
   - **ContractService** FutureProvider se create (blockchain connect).
   - **DistributedService.connect()** – backend health check (localhost / 10.0.2.2 / real device IP).
   - **DistributedService.buildChain()** – agar nodes hain toh chain build.
   - **HybridStorageService.initialize(userAddress)** – sirf jab user logged in ho:
     - Server online check
     - **P2PService.startServer()** – TCP server 8080 par
     - Peer register (DistributedService.registerPeer) agar server online
     - **sync_queue** se restore, SQLite se peers restore.

2. **Splash.dart**
   - Animation, ~2 sec.
   - **SessionService.getLoginSession()**:
     - `isLoggedIn == 'true'` + `userAddress` hai → **TeamHomePage** (workspace + channel).
     - Warna → **LoginScreen**.

---

### 2️⃣ Login / SignUp Flow (Blockchain + 2FA)

- **LoginScreen** → Sign Up / Sign In / Private Key login.
- **ContractService** (web3dart) **Ethereum RPC** (ngrok URL) se **UserAuth** contract se baat karta hai.

**Sign Up:**
1. User **private key** deta hai (ya wallet connect).
2. `ContractService.register(privateKey)` → `UserAuth.register()` on-chain.
3. `SessionService.saveLoginSession(...)` – userAddress, workspace, channel save.

**Sign In (agar 2FA on hai):**
1. `ContractService.login(privateKey)` → `UserAuth.login()`.
2. `ContractService.is2FAEnabled(address)` → true.
3. **Verify2FAScreen** – TOTP ya backup code.
4. `ContractService.verify2FA(code)` → on-chain verify.
5. Session save → **TeamHomePage**.

**Private Key Login** (PrivateKeyLoginScreen):  
- Sirf key daal ke login, 2FA bypass (development/test).

Login ke baad **HybridStorageService.initialize(userAddress)** main.dart mein (ya login success par) call hota hai – P2P server + SQLite + sync ready.

---

### 3️⃣ Workspace & Channel Flow

- **TeamHomePage** = workspace home. Yahan se:
  - **Channels** (e.g. General, Random) – `_loadChannels()` (HybridStorageService / DistributedService).
  - **DMs** – **DMsPage** → **DirectMessagePage**.
  - **Create Workspace** → **CreateWorkspacePage**.
  - **Invite** → **InviteTeammatesPage**, **InviteService**, deep links: `ethershare://invite?workspace=...&inviter=...`.

**Workspace / Channel create:**
- Server online: `DistributedService` (workspaces, channels APIs).
- Offline: **P2PService** se `channel_created` type ka message peers ko; dono SQLite mein bhi save.

**Channel open:**  
- **ChannelPage** – `workspaceName`, `channelName` se `_effectiveWorkspaceId` resolve karke messages load/send.

---

### 4️⃣ Message Sending Flow (Sabse Important)

Ye **HybridStorageService** se control hota hai – logic `addChannelMessage` / `addDirectMessage` jaisi methods mein.

#### Step-by-Step (Channel Message Example):

1. **User message likhta hai** (ChannelPage / DirectMessagePage).

2. **Encryption (client-side, zero-knowledge):**
   - **AESCryptoService.encrypt(plaintext)**:
     - `payload_hash = SHA256(plaintext)` – ye **hash chain** ke liye, server ko plaintext nahi milta.
     - AES-256-CBC: `encrypted_message` (base64), `iv` (base64).
   - `payload_hash` server ko bheja jata hai; `encrypted_message` + `iv` bhi. `message_text` **kabhi nahi** bhejte.

3. **Storage / send strategy:**

   **A) Server online:**
   - **DistributedService** (e.g. `addMessage` / message route):
     - `POST /api/messages` with:
       - `workspaceId`, `channelId` (or `receiverAddress` for DM),
       - `senderAddress`,
       - `encrypted_message`, `iv`, `payload_hash`,
       - `messageId` (idempotency ke liye, optional).
   - **Backend (messages.js):**
     - **Plaintext reject:** Agar `messageText` aaya to 400 – "Plaintext deprecated, use encrypted_message+iv+payload_hash".
     - **Hash chain (HashChain):**
       - Filter: `{ workspace_id, channel_id }` ya DM ke liye sender+receiver.
       - `getLastHash(collection, filter)` → `previous_hash`.
       - `current_hash = HashChain.calculateHash(messageDataForHash, previous_hash, hash_version=2)`  
         – v2 mein `payload_hash` use hota hai, `message_text` nahi.
     - MongoDB: `message_id`, `workspace_id`, `channel_id`/`receiver_address`, `sender_address`, `timestamp`,  
       `encrypted_message`, `iv`, `payload_hash`, `hash_version: 2`, `previous_hash`, `current_hash`.
     - `message_text` DB mein **store nahi** hota (zero-knowledge).
   - Response: `gas_used`, `transaction_fee` (GasCalculator) + message data (bina `message_text` ke).

   **B) Server offline:**
   - Message **SQLite** mein save:
     - `encrypted_message`, `iv`, `payload_hash`, `message_id`, `workspace_id`, `channel_id`, `sender_address`, `receiver_address` (DM), `timestamp`, `synced=0`.
   - **sync_queue** mein entry: `table_name='messages'`, `operation='insert'`, `data=...` – baad mein sync ke liye.
   - **P2P:** Agar receiver ka peer (IP:port) SQLite/known peers se mil jaye:
     - **P2PService.sendMessage()** – TCP se `type: 'message'` with:
       - `message_id`, `workspace_id`, `channel_id`/`receiver_address`, `sender_address`, `encrypted_message`, `iv`, `payload_hash`, `timestamp`, etc.
     - Receiver device **P2PService** data receive karke **SQLite** mein save karta hai (decrypt wahan client-side).

4. **Hamesha local copy (HybridStorage):**  
   - Server par bhejne ke baad bhi, ya sirf P2P par bhi, **SQLite** mein encrypted copy save hoti hai taake:
     - Offline pehle dekh sakein,
     - Baad mein **sync_queue** se server par sync ho sake.

5. **Receive / load messages:**
   - **ChannelPage** / **DirectMessagePage**:
     - `HybridStorageService.getChannelMessages()` ya `getDirectMessages()`:
       - Server online: API se fetch (encrypted), + SQLite se bhi merge/override logic.
       - Server offline: sirf SQLite.
     - Har message ke liye **AESCryptoService.decrypt(encrypted_message, iv)** – UI ko plaintext dikhane ke liye.

---

### 5️⃣ P2P (Offline / Decentralized) Flow

- **P2PService** (Dart):
  - **Server:** `ServerSocket` on `0.0.0.0:8080`. Har naya connection:
    - `handshake` bhejta hai: `user_address`, `ip`, `port`.
    - `_handlePeerData` mein: `handshake` → `handshake_ack`; `message` → SQLite save + `onMessageReceived` callback.
  - **Client:** `connectToPeer(ip, port, userAddress)` → socket open, `handshake` bhejo, `handshake_ack` suno; phir `sendMessage` se `type: 'message'` bhejna.

- **Peer discovery:**
  - **Online:** `DistributedService` / `registerPeer`, `getPeers` – backend peers ko IP:port store karta hai.
  - **Offline:** **SQLite** `peers` table – `user_address`, `ip_address`, `port`.  
    **HybridStorageService._restorePeerConnectionsFromSQLite()** – workspaces → members → unke peers SQLite se → `P2PService.connectToPeer()`.

- **Message P2P se:**
  - Sender: `P2PService.sendMessage(peerId, {...})` – JSON: `encrypted_message`, `iv`, `payload_hash`, `message_id`, `workspace_id`, `channel_id`/`receiver_address`, etc.
  - Receiver: `_handlePeerData` → `type=='message'` → SQLite insert (encrypted) + `onMessageReceived(message)`.
  - **ChannelPage** / **DirectMessagePage** ka `onMessageReceived` → `_checkForNewMessages()` / `_loadMessages()` – nayi messages dikhane ke liye.

---

### 6️⃣ Sync Flow (SQLite ↔ MongoDB)

- **HybridStorageService** (concept):
  - **sync_queue:** `table_name`, `record_id`, `operation` (insert/update/delete), `data`, `retry_count`.
  - **Sync up (local → server):**
    - Periodic timer ya "server wapas online" pe:
      - `sync_queue` se unsynced rows.
      - `DistributedService.addMessage()` (ya equivalent) with `encrypted_message`, `iv`, `payload_hash`, `messageId` (idempotency).
      - Success → `synced=1` / sync_queue se remove; fail → `retry_count++`.
  - **Sync down (server → local):**
    - `getChannelMessages` / `getDirectMessages` jab server se fetch karein – jo messages SQLite mein nahi ya purane hain, unhe SQLite mein insert/update (encrypted hi).

- **Idempotency:**  
  - Client `messageId` bhejta hai (e.g. `msg_<timestamp>_<sender>`).  
  - Backend agar `message_id` pehle se dekhe to 200 + "already exists" – duplicate insert nahi.

---

### 7️⃣ Hash Chain (Integrity) – Short

- **Filter:** Per channel: `{ workspace_id, channel_id }`; per DM: `{ sender_address, receiver_address }` (dono order).
- **Genesis:** Pehla message: `previous_hash = '0'`.
- **Har naya message:**
  - `previous_hash = last message ka current_hash`.
  - `current_hash = SHA256( sortedKeys( messageData ) + previous_hash )`.  
    v2: `messageData` mein `payload_hash` hai, `message_text` nahi (server ko plaintext hai hi nahi).
- **Verification:** `HashChain.verifyChainIntegrity(collection, filter)` – koi beech ka message change hua to `current_hash` mismatch → `chain_broken`.
- **Ledgers/nodes:** Alag collections (ledgers, nodes) – yahan zyada focus **messages** hash chain par hai.

---

### 8️⃣ File / Voice / Extra

- **Files:** `files` routes, file upload → `file_id` message ke sath.  
- **Voice:** Record → file save → message with `file_id` / audio URL.  
- **Channels/DMs** ka UI: **ChannelPage**, **DirectMessagePage** – messages list, encryption/decryption, P2P callbacks, polling.

---

## 📂 Important Files – Quick Reference

| Kaam | File(s) |
|------|---------|
| App start, providers, Hybrid init | `main.dart` |
| Splash, session check, navigate | `Splash.dart` |
| Blockchain login, 2FA | `contract_service.dart`, `UserAuth.sol` |
| Backend API (messages, workspaces, nodes, peers) | `distributed_service.dart` |
| Dual storage, sync, offline | `hybrid_storage_service.dart` |
| Local DB | `sqlite_service.dart` |
| P2P TCP | `p2p_service.dart` |
| AES encrypt/decrypt, payload_hash | `aes_crypto_service.dart` |
| Message send UI, load, P2P callback | `channel_page.dart`, `direct_message_page.dart` |
| Workspace, channels list, create | `workspace_home_page.dart` |
| Backend server, routes | `backend/server.js` |
| Message API, plaintext reject, hash chain, encryption fields | `backend/routes/messages.js` |
| Hash chain logic | `backend/utils/hashChain.js` |
| Session (userAddress, workspace, channel) | `session_service.dart` |

---

## 🔐 Security Flow (Encryption + Zero-Knowledge) – Ek Nazar

1. **Client:**  
   - `payload_hash = SHA256(plaintext)`  
   - `encrypted_message, iv = AESCryptoService.encrypt(plaintext)`  
   - Server ko: `encrypted_message`, `iv`, `payload_hash` (never `message_text`).

2. **Server (messages.js):**  
   - `message_text` agar aaye → 400, "use encrypted_message+iv+payload_hash".  
   - Store: `encrypted_message`, `iv`, `payload_hash`, `hash_version: 2`.  
   - Hash: `payload_hash` use karke `current_hash` (v2).

3. **Client receive:**  
   - Server ya P2P se encrypted + iv milega.  
   - `AESCryptoService.decrypt(encrypted_message, iv)` → plaintext → UI.

Is tarah server **kabhi plaintext nahi dekhta** – zero-knowledge.

---

## ✅ Flow Summary (Ek Line Mein)

**App start** → **Splash** (session) → **Login** (blockchain+2FA) → **TeamHomePage** → **Channel/DM** → message **encrypt (AES + payload_hash)** → **server online** = API (hash chain, encrypted only) **+ SQLite**; **server offline** = **SQLite + sync_queue + P2P** → receive par **decrypt** client-side; **sync** jab server wapas aaye.

Agar kisi specific part (e.g. sirf P2P, ya sirf messages.js, ya SQLite schema) ka flow chahiye ho to batao, us hisse ko aur detail mein likh sakta hoon.
