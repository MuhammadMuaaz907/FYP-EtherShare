#!/bin/bash

# IPFS Setup Script for EtherShare Project

echo "🚀 Setting up IPFS for EtherShare Project..."

# Create directories
echo "📁 Creating directories..."
mkdir -p orbitdb/ipfs
mkdir -p orbitdb/orbitdb

# Check if IPFS is installed globally
if command -v ipfs &> /dev/null; then
    echo "✅ IPFS found globally installed"
    
    # Initialize IPFS if not already initialized
    if [ ! -d ~/.ipfs ]; then
        echo "🔧 Initializing IPFS..."
        ipfs init
    else
        echo "✅ IPFS already initialized"
    fi
    
    # Configure IPFS
    echo "⚙️  Configuring IPFS..."
    ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
    ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["GET", "POST", "PUT"]'
    ipfs config --json API.HTTPHeaders.Access-Control-Allow-Headers '["X-Requested-With", "Range", "User-Agent"]'
    
    # Set custom ports to avoid conflicts
    ipfs config Addresses.API /ip4/127.0.0.1/tcp/5001
    ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8080
    
    echo "✅ IPFS configured successfully"
    echo "📋 To start IPFS daemon: ipfs daemon"
    
else
    echo "❌ IPFS not found globally"
    echo "📥 Please install IPFS first:"
    echo "   Windows: https://docs.ipfs.io/install/command-line/#windows"
    echo "   macOS: brew install ipfs"
    echo "   Linux: https://docs.ipfs.io/install/command-line/#linux"
fi

# Check Node.js dependencies
echo "📦 Checking Node.js dependencies..."
if [ -f package.json ]; then
    if [ ! -d node_modules ]; then
        echo "📥 Installing Node.js dependencies..."
        npm install
    else
        echo "✅ Node.js dependencies already installed"
    fi
else
    echo "❌ package.json not found"
fi

# Create startup script
echo "📝 Creating startup script..."
cat > start-orbitdb.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting EtherShare OrbitDB Server..."

# Check if IPFS daemon is running
if ! pgrep -f "ipfs daemon" > /dev/null; then
    echo "🔧 Starting IPFS daemon..."
    ipfs daemon &
    sleep 5
fi

# Start the Node.js server
echo "🚀 Starting OrbitDB server..."
npm start

EOF

chmod +x start-orbitdb.sh

echo "✅ Setup complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Start IPFS daemon: ipfs daemon"
echo "2. In another terminal, start OrbitDB server: npm start"
echo "3. Or use the startup script: ./start-orbitdb.sh"
echo ""
echo "📊 Health check: http://localhost:3000/health"
echo "🌐 WebSocket: ws://localhost:8080"
