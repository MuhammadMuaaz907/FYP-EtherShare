# EtherShare – FYP Defense & Presentation Guide (Roman Urdu)

**BSCS Final Year Project | Blockchain-Based Secure File Sharing and Communication System**

---

## 1. Project Ka Short Introduction (30 seconds)

**EtherShare** ek **blockchain-based secure file sharing aur communication system** hai. Ismein:

- **Blockchain** (Ethereum-style) se user **authentication** (register, login) aur **2FA** (Two-Factor Authentication)
- **Hash chain** (blockchain jaisi) se **message integrity** verify hoti hai – koi message change hua toh pata chal jata hai
- **AES-256 encryption** se messages **encrypt** hotey hain – server ko plaintext dikhta hi nahi (zero-knowledge)
- **P2P (Peer-to-Peer)** se do users **direct device-to-device** message bhej sakte hain, bina server ke
- **Hybrid storage**: **SQLite** (local) + **MongoDB** (server) – online/offline dono kaam karta hai

**One-liner:**  
*“Blockchain se auth + hash chain se integrity + encryption se privacy + P2P se direct sharing – sab mila ke EtherShare banaya.”*

---

## 2. Problem Statement (Slide / 1 minute)

- Traditional apps mein **centralized server** sab data dekhta hai – **privacy** kam
- **Data integrity** guarantee nahi – koi message edit/delete kare toh pata nahi chalta
- **Single point of failure** – server down = app kaam nahi karti
- **2FA** simple apps mein weak ya missing hota hai

**EtherShare in problems ko address karta hai:**  
decentralized auth (blockchain), integrity (hash chain), encryption (AES), aur offline/P2P support.

---

## 3. Solution / Main Features

| Feature | Kya Hai | Kaise Implement |
|--------|---------|------------------|
| **Blockchain Auth** | User register/login blockchain pe | Solidity **UserAuth** contract, **web3dart** |
| **2FA** | TOTP + backup codes | **UserAuth** contract (enable2FA, verify2FA), **totp_service** |
| **Hash Chain** | Message chain, integrity check | **HashChain** (SHA-256), `previous_hash` → `current_hash` |
| **AES Encryption** | Messages encrypt | **AESCryptoService** (AES-256-CBC), **payload_hash** for integrity |
| **P2P Messaging** | Device-to-device TCP | **P2PService** (Dart), TCP server, **SQLite** pe store |
| **Hybrid Storage** | Local + Server | **HybridStorageService**, **SQLite** + **MongoDB** |
| **Workspaces & Channels** | Slack jaisa structure | Workspace → Channels, **MongoDB** + **SQLite** |
| **Invite System** | Email + deep link | **InviteService**, **app_links**, `ethershare://invite?workspace=...` |
| **Offline Support** | Server na ho toh bhi | SQLite + P2P; jab online aaye sync |

---

## 4. Tech Stack (Slide ke liye)

| Layer | Technology |
|-------|------------|
| **Frontend / Mobile** | **Flutter** (Dart), **Provider**, **WalletConnect** v2 |
| **Blockchain** | **Solidity** (UserAuth), **Truffle**, **web3dart**, **Web3** (Node) |
| **Backend** | **Node.js**, **Express**, **MongoDB** (Mongoose) |
| **Local DB** | **SQLite** (sqflite) – messages, peers, workspaces |
| **Security** | **AES-256-CBC** (encrypt), **TOTP**, **flutter_secure_storage** |
| **P2P** | **Dart** `ServerSocket` / `Socket`, TCP |
| **File / Media** | **file_picker**, **image_picker**, **record**, **audioplayers** |

---

## 5. System Architecture (High-Level)

```
[Flutter App]
    |
    |-- ContractService (web3dart) -----> [Ethereum / UserAuth Contract]  (Auth + 2FA)
    |
    |-- DistributedService (HTTP) ------> [Node.js Backend] -------------> [MongoDB]
    |        |                                    |
    |        |                            [HashChain, Ledger, Messages, Channels, Files]
    |
    |-- HybridStorageService
    |        |-- SQLite (local messages, peers, workspaces)
    |        |-- P2PService (TCP server + client)
    |
    |-- AESCryptoService ---------------> Encrypt/Decrypt (device pe only)
```

**Flow in short:**  
App blockchain se auth karti hai, backend se workspaces/channels/messages manage karti hai, hash chain integrity check karti hai, encryption client-side hoti hai, aur P2P se direct messaging + offline SQLite use hoti hai.

---

## 6. Complete User Flow (Step-by-Step)

### 6.1 App Start → Splash → Login

1. **main.dart**: `ContractService` create, `DistributedService.connect()`, `HybridStorageService` init (agar user logged in ho).
2. **Splash.dart**: Session check (`SessionService.getLoginSession()`). Agar logged in → **TeamHomePage** (workspace). Warna → **LoginScreen**.
3. **LoginScreen**:  
   - **WalletConnect** (MetaMask) se connect.  
   - **ContractService**: `isRegistered(wallet)` → agar nahi to **Sign Up** flow.  
   - **ContractService**: `login(privateKey)` blockchain pe.  
   - 2FA on hai to **Verify2FAScreen** → TOTP ya backup code.  
   - Session save → **ProfileSetup** / **Workspace** / **TeamHomePage**.

### 6.2 Workspace & Channel

1. **Create Workspace** (create_workspace_page, project_name_page, etc.) → backend **POST /api/workspaces**.
2. **TeamHomePage**: Workspace ke **channels** list (General, Random, …). **DistributedService** / **HybridStorageService** se channels.
3. **ChannelPage**: Koi channel open → messages load (HybridStorage → SQLite + server).  
   - **Send message**: `HybridStorageService.addMessage()`.

### 6.3 Message Send Flow (Important for Defense)

1. User message likhta hai → **ChannelPage** / **DirectMessagePage**.
2. **AESCryptoService**: plaintext encrypt → `encryptedMessage` + `iv`. Plaintext ka **payload_hash** (SHA-256) banta hai.
3. **HybridStorageService.addMessage()**:
   - Pehle **SQLite** mein save (local).
   - **P2P**: Agar receiver **peer** connected hai to **P2PService.sendMessageToPeer()** → direct TCP.
   - **Server online** ho to **DistributedService.addMessage()** → **POST /api/messages**.
4. Backend **messages** route:
   - **HashChain.addHashFields()**: `previous_hash` (last message) + `current_hash` (SHA-256 of data + previous_hash).
   - **payload_hash** use hota hai (plaintext server pe nahi jata).
   - Message **MongoDB** mein store (encrypted + hash chain).
5. **Ledger**: Agar ledger use ho (e.g. node-based) to **LedgerService.addBlock()** bhi – block chain jaisa structure.

**Defense tip:**  
*“Message pehle encrypt hoti hai, phir local SQLite mein save, phir P2P se bheji ja sakti hai ya server ko encrypted + hash chain ke sath. Server ko kabhi plaintext nahi milta.”*

---

## 7. Blockchain Part (UserAuth Contract)

**File:** `contracts/UserAuth.sol`

- **register()**: `msg.sender` ko registered users mein add.
- **login()**: Registered user ke liye `lastSuccessfulLogin` update, event emit.
- **enable2FA(backupCodes)**: 2FA on, backup codes store.
- **verify2FA(code)**: TOTP ya backup code check.  
  - 3 galat attempts → **lockout** (5 min).  
  - Backup code use hone pe remove.
- **disable2FA()**, **regenerateBackupCodes()**, **is2FAEnabled()**, **isLockedOut()**, etc.

**Modifiers:** `onlyRegistered`, `notLockedOut`, `onlyOwner`, `validBackupCodes`.

**Defense tip:**  
*“Auth logic blockchain pe hai, is liye tamper-proof. 2FA failed attempts limit aur lockout bhi contract mein enforce hota hai.”*

---

## 8. Hash Chain (Integrity) – Backend

**File:** `backend/utils/hashChain.js`

- **calculateHash(data, previousHash, hashVersion)**:
  - v1: `message_text` use (legacy).
  - v2: `payload_hash` use (plaintext server pe nahi).
  - `SHA-256( JSON(data) + previousHash )` → `current_hash`.
- **addHashFields()**: Last message ka `current_hash` = `previous_hash` for new message. Race condition ke liye retry.
- **verifyChainIntegrity()**: Har message ka `previous_hash` ↔ previous `current_hash` match. Agar mismatch → **chain broken**.
- **getAndVerifyLastHash()**: Concurrency ke waqt last hash atomically verify.

**Defense tip:**  
*“Har message ka hash previous message se link hai. Agar koi beech ka message change kare, hashes match nahi karenge aur chain break detect ho jayega.”*

---

## 9. Encryption (AES) – Flutter

**File:** `blockchain_fyp/lib/security/aes_crypto_service.dart`

- **AES-256-CBC**.
- **Random IV** har message ke liye.
- Key **flutter_secure_storage** mein (device pe).
- **Encrypt**: plaintext → ciphertext + IV (base64).
- **Decrypt**: sirf device pe; server kabhi decrypt nahi karta.
- **payload_hash**: plaintext ka SHA-256; hash chain mein use, **not** encryption key.

**Defense tip:**  
*“Messages AES-256 se encrypt hain. Server ko sirf encrypted payload + payload_hash milta hai, plaintext kabhi nahi. Is ko zero-knowledge approach kehte hain.”*

---

## 10. P2P Service (Flutter)

**File:** `blockchain_fyp/lib/services/p2p_service.dart`

- **TCP Server**: Device apna **ServerSocket** bind karta hai (e.g. port 8080).
- **Peers**: Peers ka **IP + port** SQLite aur (optionally) backend se. **Socket** se connect.
- **Send**: `sendMessageToPeer()` → JSON message TCP se bhejta hai.
- **Receive**: `_handleIncomingConnection` → parse message → **SQLite** save → `onMessageReceived` callback.
- **HybridStorageService**: P2P msg receive hone pe agar server online ho to sync bhi kar sakta hai.

**Defense tip:**  
*“P2P se do users same network pe direct TCP se message bhej sakte hain. Server optional hai; offline ya server down pe bhi local + P2P kaam karta hai.”*

---

## 11. Hybrid Storage & Sync

**File:** `blockchain_fyp/lib/services/hybrid_storage_service.dart`

- **SQLite**: Messages, channels, workspaces, peers – local fast access, offline.
- **MongoDB** (via backend): Authoritative store, sync across devices.
- **Flow**:  
  - Message send → pehle SQLite, phir P2P (if peer available), phir server (if online).  
  - Receive → P2P se ya API se → SQLite save.  
- **Sync**: Timer-based / event-based sync; **message_id** se **idempotency** (duplicate sync se bachne ke liye).

**Defense tip:**  
*“Hybrid storage se offline support milta hai. Local SQLite first, phir server sync. Duplicate messages message_id se prevent kiye jate hain.”*

---

## 12. Backend APIs (Quick Reference)

| Route | Purpose |
|-------|---------|
| **GET /health** | Server + DB check |
| **POST /api/users** | User create/fetch |
| **POST /api/workspaces** | Workspace create/list |
| **POST /api/channels** | Channel create/list |
| **POST /api/messages** | Message add (hash chain + optional encryption fields) |
| **GET /api/messages** | Messages fetch (channel/DM) |
| **POST /api/files** | File upload |
| **POST /api/nodes/register** | Node register (distributed) |
| **POST /api/peers** | P2P peer register |

**Postman:** `DISTRIBUTED_SYSTEM_POSTMAN_COLLECTION.json` use kar sakte ho demo ke liye.

---

## 13. Common Defense Questions & Answers

**Q: Blockchain yahan exactly kahan use hua hai?**  
A: User **registration** aur **login** blockchain (UserAuth contract) pe hota hai. 2FA enable/verify bhi contract se. Is se auth logic decentralized aur tamper-resistant rehta hai.

**Q: Hash chain aur blockchain mein farq?**  
A: Dono **chain of hashes** use karte hain. Yahan **hash chain** messages ke liye hai (MongoDB + backend). **Blockchain** (Ethereum) sirf **auth** ke liye. Hash chain se **integrity** verify hoti hai; blockchain se **auth** verify hoti hai.

**Q: Server encrypted message kaise use karta hai?**  
A: Server **decrypt nahi karta**. Sirf **encrypted_message**, **iv**, **payload_hash** store karta hai. **payload_hash** se hash chain verify hoti hai. Decrypt sirf **client** (Flutter app) karta hai.

**Q: P2P kaise kaam karta hai?**  
A: Har device ek **TCP server** chalata hai. Peers ka IP:port **SQLite** ya backend se milta hai. Message **direct TCP** se bheji jati hai. Same WiFi/LAN pe best kaam karta hai.

**Q: Offline mein kya hota hai?**  
A: Messages **SQLite** mein save. **P2P** same network pe kaam karega. Jab device **online** aaye, **HybridStorageService** server ko sync karta hai (idempotent, **message_id** se).

**Q: 2FA contract mein kaise verify hota hai?**  
A: **TOTP** verification production mein typically off-chain hoti hai (secret contract pe store nahi karte). Yahan contract **backup codes** store karta hai aur **verify2FA** se check karta hai. TOTP ke liye **totp_service** (Flutter) use hota hai; contract mein demo ke liye 6-digit check bhi hai.

**Q: Gas cost kis cheez ka hai?**  
A: **Ethereum** pe **register/login/2FA** tx ke liye gas (UserAuth). **Backend** pe **LedgerService** / **GasCalculator** **simulated** gas (time-based) use karta hai – real blockchain gas nahi, metrics ke liye.

**Q: Duplicate messages kaise avoid hote hain?**  
A: **message_id** unique (e.g. `msg_timestamp_sender`). Backend **idempotency** check karta hai: same **message_id** dobara aaye to wahi purani message return, duplicate insert nahi.

**Q: Chain “broken” kab hoti hai?**  
A: Jab **previous_hash** ↔ **current_hash** match na ho (middle mein koi message alter ho). **HashChain.verifyChainIntegrity()** break detect karke **chain_broken** mark karti hai.

---

## 14. Presentation Tips

1. **Order**: Problem → Solution → Architecture → Demo → Tech stack → Results/Limitations → Future work.
2. **Demo flow**:  
   - Login (WalletConnect + 2FA).  
   - Workspace → Channel → encrypted message send.  
   - Optional: P2P (2 devices) ya invite link.
3. **Slides**: Architecture diagram, flow diagram, **UserAuth** snippet, **HashChain** ka simple example, encryption flow.
4. **Confident lines**:  
   - *“Auth blockchain pe hai, messages hash chain se verify, encryption client-side, P2P se direct messaging, hybrid storage se offline support.”*
5. **Agar kuch fail ho**:  
   - *“Ye limitation hai / future work mein address karenge.”*  
   - Backup: architecture aur code explain karna.

---

## 15. Key Files Cheat Sheet

| Component | File |
|----------|------|
| App entry, init | `blockchain_fyp/lib/main.dart` |
| Splash, routing | `blockchain_fyp/lib/Splash.dart` |
| Login, WalletConnect | `blockchain_fyp/lib/login_screen.dart` |
| Blockchain auth | `blockchain_fyp/lib/services/contract_service.dart` |
| Workspace UI | `blockchain_fyp/lib/workspace_home_page.dart` |
| Channel, messages | `blockchain_fyp/lib/channel_page.dart` |
| Hybrid storage | `blockchain_fyp/lib/services/hybrid_storage_service.dart` |
| P2P | `blockchain_fyp/lib/services/p2p_service.dart` |
| AES encryption | `blockchain_fyp/lib/security/aes_crypto_service.dart` |
| Smart contract | `contracts/UserAuth.sol` |
| Backend server | `backend/server.js` |
| Hash chain | `backend/utils/hashChain.js` |
| Messages API | `backend/routes/messages.js` |
| Ledger | `backend/services/ledgerService.js`, `backend/models/ledger.js` |

---

## 16. Last-Minute Checklist

- [ ] MongoDB running.
- [ ] Backend `npm run dev` (port 3000).
- [ ] Flutter app `.env` mein **BACKEND_URL** / IP sahi.
- [ ] WalletConnect (MetaMask) same network pe.
- [ ] UserAuth contract deploy + **contract_service** mein sahi address + RPC.
- [ ] 2–3 flows practice: Login → Workspace → Channel → Send message.
- [ ] Architecture + hash chain + encryption 2–3 baar revise.

---

**All the best for your FYP defense aur presentation. Tum project ko achhe se samajh gaye ho – bas ye points confidently explain karna.**

---

## 17. Last-Minute 1-Page Cheat (Presentation se pehle dekho)

### Elevator Pitch (30 sec)
*"EtherShare ek blockchain-based secure file sharing aur chat app hai. User auth blockchain pe hota hai with 2FA. Messages AES-256 se encrypt hoti hain – server ko plaintext nahi dikhta. Har message hash chain se link hoti hai, is liye tampering detect ho jati hai. P2P se do users direct bina server ke message bhej sakte hain. Offline bhi kaam karta hai – SQLite local, jab online aaye MongoDB sync."*

### 5 Bullets (Slide)
1. **Blockchain Auth** – UserAuth contract (register, login, 2FA)
2. **Hash Chain** – Message integrity, SHA-256, previous_hash → current_hash
3. **AES-256 Encryption** – Zero-knowledge, server plaintext nahi dekhta
4. **P2P + Hybrid Storage** – Direct TCP messaging, SQLite + MongoDB, offline support
5. **Workspaces & Channels** – Slack-style, invite links, DMs

### Top 3 Defense Answers
1. **Blockchain kahan?** → Auth (UserAuth contract). Hash chain alag hai – messages ke integrity ke liye.
2. **Encryption kaise?** → Client encrypt karta hai, server ko sirf encrypted + payload_hash. Decrypt sirf client.
3. **P2P kaise?** → Har device TCP server, peers ka IP:port, direct message bhejna.

### Agar Confusion ho
- **Hash chain** = message chain (backend + MongoDB)
- **Blockchain** = auth (Ethereum + UserAuth)
- **payload_hash** = plaintext ka hash (integrity), encryption nahi

---

## 18. Extra Defense Questions (Zyada Technical)

**Q: AES-256 CBC kyu, AES-GCM kyu nahi?**  
A: CBC mature hai aur encrypt package mein easily available. GCM authenticated encryption deta hai (integrity bhi) – future work mein consider kar sakte hain. Abhi integrity **hash chain** se verify ho rahi hai.

**Q: WalletConnect kyu? Private key directly kyu nahi?**  
A: WalletConnect se MetaMask/wallet se **sign** hota hai – private key app mein store nahi hoti, **security** better. Backup ke liye **private key login** option bhi hai (development/testing).

**Q: MongoDB centralized hai – decentralized kahan hai?**  
A: **Auth** decentralized (blockchain). **Messages** MongoDB pe – ye design choice hai: sync, query, scale easy. **P2P** se direct messaging **optional** hai, server bypass ho sakta hai. Pure decentralized messaging (e.g. Matrix) alag scope hai.

**Q: Hash chain verify kab run hoti hai?**  
A: Backend **addHashFields** ke baad; **verifyChainIntegrity** manually ya periodic job se. Message fetch pe bhi client **chain_broken** check kar sakta hai agar API ye flag return kare.

**Q: Ledger vs Messages collection – dono kyu?**  
A: **Messages** = chat messages (channel/DM), hash chain integrity. **Ledger** = **node-based** blocks (distributed nodes), block_number, gas simulation. Dono alag use-case: messages day-to-day chat, ledger optional “blockchain-like” audit trail.

**Q: Same WiFi pe P2P – different networks pe?**  
A: Same **LAN** pe direct TCP. Different networks pe **NAT** issue – phir server relay ya **TURN/STUN** (WebRTC-style) chahiye. Current scope **same network** hai; cross-network future work.

**Q: SQLite schema kya hai messages ke liye?**  
A: `message_id`, `workspace_id`, `channel_id`, `sender_address`, `receiver_address`, `encrypted_message` / `message_text`, `iv`, `payload_hash`, `timestamp`, etc. **SQLiteService** / migrations mein detail.

**Q: Biometric 2FA use kiya?**  
A: **local_auth** (Flutter) se biometric **optional** – device unlock / sensitive actions ke liye. **Primary 2FA** TOTP + backup codes (UserAuth contract).

---

## 19. Limitations & Future Work (Slide / Defense ke liye)

**Limitations:**
- P2P **same network** tak – cross-network / NAT traversal nahi.
- **TOTP** contract pe fully verify nahi (secret on-chain nahi); backup codes contract pe hain.
- **MongoDB** centralized – pure decentralized storage nahi.
- **Gas** real Ethereum pe; testnet/local chain pe development.

**Future Work:**
- **AES-GCM** ya authenticated encryption.
- **NAT traversal** / relay server for P2P across networks.
- **End-to-end encryption** key exchange (e.g. Signal-style) – abhi workspace/channel-level.
- **IPFS** ya decentralized storage for files.
- **Multi-chain** support (sidha Ethereum mainnet pe deploy).

---

## 20. Demo Troubleshooting (Agar Live Demo Fail ho)

| Issue | Quick Check |
|-------|-------------|
| **Backend connect nahi ho raha** | MongoDB running? `npm run dev`? Firewall port 3000? `.env` / `BACKEND_URL` sahi? |
| **WalletConnect connect nahi** | MetaMask same network? Chain 1337 / custom RPC sahi? |
| **Contract revert** | User registered? 2FA locked? Sahi chain + contract address? |
| **Messages dikhai nahi** | Channel/workspace ID sahi? SQLite vs API – konsa source use ho raha? |
| **P2P message nahi ja rahi** | Dono devices same WiFi? Peer IP:port sahi? Port 8080 open? |
| **Encryption error** | `flutter_secure_storage` / key init fail? Device ke secure storage check karo. |

**Backup plan:**  
Agar live app fail ho, **architecture diagram** + **Postman** se API demo (health, messages POST/GET) + **code walkthrough** (UserAuth, HashChain, AESCrypto) se defend karo.

---

## 21. “Slack / WhatsApp se compare karo” – Jawab

**Slack:**  
Slack **server** sab kuch dekhta hai. Hum **zero-knowledge** – server ko plaintext nahi. **Hash chain** se **integrity** verify. **Blockchain auth** – tamper-resistant.

**WhatsApp:**  
WhatsApp **E2E** use karta hai, lekin **centralized** (Meta). Hum **blockchain auth** + **hash chain** + **P2P option** dete hain. **Workspace/channel** model Slack jaisa, lekin **privacy** aur **integrity** focus.

**One-liner:**  
*“Slack jaisa structure, lekin encryption + integrity + blockchain auth; WhatsApp jaisi privacy feel, lekin workspace-based aur P2P optional.”*

---

## 22. Hash Chain Ka Simple Example (Whiteboard / Slide)

```
Genesis: previous_hash = "0"
Msg1:    current_hash = SHA256(data1 + "0")     → store
Msg2:    previous_hash = Msg1.current_hash
         current_hash = SHA256(data2 + previous) → store
Msg3:    previous_hash = Msg2.current_hash
         current_hash = SHA256(data3 + previous) → store
```

**Tampering:**  
Agar **Msg2** change kiya → Msg2 ka `current_hash` galat → Msg3 ka `previous_hash` match nahi karega → **chain broken**.

---

## 23. Presentation Flow (Timing – 15–20 min)

| Minute | Kya karo |
|--------|----------|
| 0–1 | Title, intro, problem statement |
| 1–3 | Solution, features (5 bullets) |
| 3–6 | Architecture diagram, flow (login → message send) |
| 6–10 | **Live demo**: Login → Workspace → Channel → Send message |
| 10–12 | Tech stack, key design (hash chain, encryption, P2P) |
| 12–14 | Limitations, future work |
| 14–15+ | Q&A |

Agar **Q&A** zyada ho to demo chhota karo, architecture + code pe zyada bolo.

---

**All the best – tum ready ho.**
