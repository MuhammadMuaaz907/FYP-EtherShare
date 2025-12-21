# MongoDB Start Script
# This script helps start MongoDB with proper permissions

Write-Host "Checking MongoDB status..." -ForegroundColor Cyan

# Check if MongoDB service exists
$mongoService = Get-Service -Name MongoDB -ErrorAction SilentlyContinue

if ($null -eq $mongoService) {
    Write-Host "MongoDB service not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible solutions:" -ForegroundColor Yellow
    Write-Host "1. MongoDB might not be installed as a Windows service" -ForegroundColor White
    Write-Host "2. Try starting MongoDB manually:" -ForegroundColor White
    Write-Host "   mongod --dbpath C:\data\db" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Or install MongoDB as a service:" -ForegroundColor White
    Write-Host "   mongod --install --serviceName MongoDB --serviceDisplayName MongoDB" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Check if already running
if ($mongoService.Status -eq 'Running') {
    Write-Host "MongoDB is already running!" -ForegroundColor Green
    Write-Host "Service Status: $($mongoService.Status)" -ForegroundColor Green
    exit 0
}

Write-Host "MongoDB service found but not running." -ForegroundColor Yellow
Write-Host "Attempting to start MongoDB..." -ForegroundColor Cyan

# Try to start MongoDB
try {
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "ERROR: Administrator privileges required!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Solution 1: Run PowerShell as Administrator" -ForegroundColor Yellow
        Write-Host "   1. Right-click PowerShell" -ForegroundColor White
        Write-Host "   2. Select 'Run as Administrator'" -ForegroundColor White
        Write-Host "   3. Run: net start MongoDB" -ForegroundColor White
        Write-Host ""
        Write-Host "Solution 2: Start MongoDB manually (no admin needed)" -ForegroundColor Yellow
        Write-Host "   mongod --dbpath C:\data\db" -ForegroundColor White
        Write-Host ""
        Write-Host "Solution 3: Use this script as Administrator" -ForegroundColor Yellow
        Write-Host "   Right-click this file -> Run with PowerShell (as Administrator)" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    
    # Start the service
    Start-Service -Name MongoDB
    Start-Sleep -Seconds 2
    
    # Check status
    $mongoService = Get-Service -Name MongoDB
    if ($mongoService.Status -eq 'Running') {
        Write-Host "MongoDB started successfully!" -ForegroundColor Green
        Write-Host "Service Status: $($mongoService.Status)" -ForegroundColor Green
    } else {
        Write-Host "Failed to start MongoDB. Status: $($mongoService.Status)" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "Error starting MongoDB: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Try running PowerShell as Administrator and run:" -ForegroundColor Yellow
    Write-Host "   net start MongoDB" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "MongoDB is ready!" -ForegroundColor Green
Write-Host "You can now start your backend server: npm run dev" -ForegroundColor Cyan

