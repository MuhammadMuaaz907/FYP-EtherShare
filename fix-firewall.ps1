# Fix Network Connection - Windows Firewall Configuration
# Run this script as Administrator

Write-Host "🔧 Fixing Network Connection Issues..." -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "❌ This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "💡 Right-click PowerShell → Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "✅ Running as Administrator" -ForegroundColor Green
Write-Host ""

# Step 1: Create Firewall Rule for Port 3000
Write-Host "📋 Step 1: Creating Firewall Rule for Port 3000..." -ForegroundColor Cyan

$ruleExists = Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue

if ($ruleExists) {
    Write-Host "⚠️  Firewall rule already exists. Removing old rule..." -ForegroundColor Yellow
    Remove-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue
}

try {
    New-NetFirewallRule -DisplayName "Node.js Backend Port 3000" `
        -Direction Inbound `
        -LocalPort 3000 `
        -Protocol TCP `
        -Action Allow `
        -Profile Domain,Private,Public `
        -Description "Allow Node.js backend server on port 3000 for EtherShare app"
    
    Write-Host "✅ Firewall rule created successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create firewall rule: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Verify Firewall Rule
Write-Host "📋 Step 2: Verifying Firewall Rule..." -ForegroundColor Cyan

$rule = Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue

if ($rule) {
    Write-Host "✅ Firewall rule verified:" -ForegroundColor Green
    Write-Host "   DisplayName: $($rule.DisplayName)" -ForegroundColor White
    Write-Host "   Enabled: $($rule.Enabled)" -ForegroundColor White
    Write-Host "   Direction: $($rule.Direction)" -ForegroundColor White
    Write-Host "   Action: $($rule.Action)" -ForegroundColor White
} else {
    Write-Host "❌ Firewall rule not found!" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 3: Check if Port 3000 is Listening
Write-Host "📋 Step 3: Checking if port 3000 is listening..." -ForegroundColor Cyan

$portListening = netstat -ano | findstr ":3000" | findstr "LISTENING"

if ($portListening) {
    Write-Host "✅ Port 3000 is listening!" -ForegroundColor Green
    Write-Host "   $portListening" -ForegroundColor White
} else {
    Write-Host "⚠️  Port 3000 is not listening." -ForegroundColor Yellow
    Write-Host "💡 Make sure backend server is running: cd backend && npm run dev" -ForegroundColor Yellow
}

Write-Host ""

# Step 4: Get PC IP Address
Write-Host "📋 Step 4: Getting PC IP Address..." -ForegroundColor Cyan

$ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
    $_.IPAddress -notlike "127.*" -and 
    $_.IPAddress -notlike "169.254.*" 
} | Select-Object -First 1

if ($ipAddresses) {
    $pcIP = $ipAddresses.IPAddress
    Write-Host "✅ PC IP Address: $pcIP" -ForegroundColor Green
    Write-Host ""
    Write-Host "📱 Use this IP in your Flutter app:" -ForegroundColor Cyan
    Write-Host "   http://$pcIP:3000" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 Update distributed_service.dart if needed:" -ForegroundColor Yellow
    Write-Host "   static const String realDeviceHost = '$pcIP';" -ForegroundColor White
} else {
    Write-Host "⚠️  Could not determine PC IP address" -ForegroundColor Yellow
}

Write-Host ""

# Step 5: Test Connection (if server is running)
Write-Host "📋 Step 5: Testing connection..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/health" -TimeoutSec 2 -ErrorAction Stop
    Write-Host "✅ Backend server is accessible!" -ForegroundColor Green
    Write-Host "   Status: $($response.StatusCode)" -ForegroundColor White
} catch {
    Write-Host "⚠️  Backend server is not accessible on localhost:3000" -ForegroundColor Yellow
    Write-Host "💡 Start backend server: cd backend && npm run dev" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "✅ Firewall Configuration Complete!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Make sure backend server is running: cd backend && npm run dev" -ForegroundColor White
Write-Host "   2. Verify PC and phone are on same WiFi network" -ForegroundColor White
Write-Host "   3. Test from phone browser: http://$pcIP:3000/health" -ForegroundColor White
Write-Host "   4. Run Flutter app: flutter run" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

