const { Web3 } = require('web3');
const fs = require('fs');
const path = require('path');

// Verify file existence
const contractPath = path.join(__dirname, 'build/contracts/UserAuth.json');
if (!fs.existsSync(contractPath)) {
  console.error('Error: UserAuth.json not found at', contractPath);
  console.error('Run `truffle compile` and `truffle migrate` first.');
  process.exit(1);
}

// Load contract ABI and address
let contractJson;
try {
  contractJson = JSON.parse(fs.readFileSync(contractPath));
  console.log('Contract JSON loaded successfully');
} catch (error) {
  console.error('Error reading UserAuth.json:', error.message);
  process.exit(1);
}

const contractABI = contractJson.abi;
if (!contractABI) {
  console.error('Error: contractABI is undefined');
  process.exit(1);
}
console.log('Contract ABI:', contractABI);

const contractAddress = '0xdB5A120B482EECfc43Eb1b83810096ACc8D9Bbb9'; // Replace with new contract address from truffle migrate
if (!contractAddress || !contractAddress.startsWith('0x')) {
  console.error('Error: Invalid contract address:', contractAddress);
  process.exit(1);
}
console.log('Contract Address:', contractAddress);

// Connect to ngrok tunnel (Ganache)
const ngrokUrl = 'https://0a0d-103-84-151-7.ngrok-free.app'; // Update if ngrok URL changed
const web3 = new Web3(ngrokUrl);

async function testContract() {
  try {
    // Verify Web3 connection
    const networkId = await web3.eth.net.getId();
    console.log('Connected to network ID:', networkId);

    // Use MetaMask mobile account
    const account = '0x0c0a67AeDEC35eefF5745eB966aC87C18Ae90288';
    const privateKey = '0x201c5b09be2354c705739d02e3583b392262f37405df58c085849d39a73f410a'; // Replace with Ganache private key for 0x8Eb4Db4cBBa88Dfc8c9aFe987EF893E3b5d952dB
    if (!account || !privateKey) {
      console.error('Error: Account or private key missing');
      return;
    }
    console.log('Using account:', account);

    // Normalize and validate private key
    let normalizedPrivateKey = privateKey.startsWith('0x') ? privateKey.slice(2) : privateKey;
    if (normalizedPrivateKey.length !== 64 || !/^[0-9a-fA-F]+$/.test(normalizedPrivateKey)) {
      console.error('Error: Invalid private key format');
      return;
    }
    console.log('Private key validated');

    // Add account to web3
    console.log('Adding account to wallet...');
    const accountObj = web3.eth.accounts.privateKeyToAccount('0x' + normalizedPrivateKey);
    web3.eth.accounts.wallet.add(accountObj);
    console.log('Account added to wallet:', accountObj.address);

    // Verify account address
    if (accountObj.address.toLowerCase() !== account.toLowerCase()) {
      console.error('Error: Private key does not match account address');
      return;
    }

    // Initialize contract
    console.log('Initializing contract...');
    const contract = new web3.eth.Contract(contractABI, contractAddress);
    console.log('Contract initialized');

    // Register
    console.log('Registering user...');
    await contract.methods.register().send({ from: account, gas: 5000000 });
    console.log('User registered!');

    // Check registration
    console.log('Checking registration...');
    const isRegistered = await contract.methods.isRegistered(account).call();
    console.log('Is registered:', isRegistered);

    // Login
    console.log('Logging in...');
    await contract.methods.login().send({ from: account, gas: 5000000 });
    console.log('Logged in!');
  } catch (error) {
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
  }
}

testContract();