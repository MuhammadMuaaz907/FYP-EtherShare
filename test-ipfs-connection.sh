#!/bin/bash

echo "🔍 Testing IPFS Desktop Connection..."

echo ""
echo "📡 Testing API connection..."
if curl -s http://192.168.0.35:5001/api/v0/id > /dev/null; then
    echo "✅ IPFS API is accessible"
    curl -s http://192.168.0.35:5001/api/v0/id | grep -o '"ID":"[^"]*"'
else
    echo "❌ IPFS API is not accessible"
fi

echo ""
echo "🌐 Testing Gateway connection..."
if curl -s http://192.168.0.35:8080/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme > /dev/null; then
    echo "✅ IPFS Gateway is accessible"
else
    echo "❌ IPFS Gateway is not accessible"
fi

echo ""
echo "🚀 Testing OrbitDB server..."
if curl -s http://localhost:3000/health > /dev/null; then
    echo "✅ OrbitDB server is running"
else
    echo "❌ OrbitDB server is not running"
fi

echo ""
echo "📊 Connection test complete!"
