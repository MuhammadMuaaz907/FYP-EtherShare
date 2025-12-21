# EtherShare Backend Setup Script
# Run this script to setup the backend

Write-Host "Setting up EtherShare Backend..." -ForegroundColor Green

# Create .env file if it doesn't exist
if (-not (Test-Path ".env")) {
    Write-Host "Creating .env file..." -ForegroundColor Yellow
    
    $envContent = @"
PORT=3000
NODE_ENV=development

# MongoDB Configuration
MONGODB_URI=mongodb://localhost:27017/EtherShare

# JWT Secret (Change this to a random string in production!)
JWT_SECRET=ethershare_super_secret_key_change_in_production
JWT_EXPIRES_IN=7d

# CORS Configuration
CORS_ORIGIN=http://localhost:3000,http://localhost:8080

# File Upload Configuration
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads
"@
    
    Set-Content -Path ".env" -Value $envContent -Encoding UTF8
    Write-Host ".env file created!" -ForegroundColor Green
} else {
    Write-Host ".env file already exists" -ForegroundColor Cyan
}

# Install dependencies
Write-Host ""
Write-Host "Installing dependencies..." -ForegroundColor Yellow
npm install

if ($LASTEXITCODE -eq 0) {
    Write-Host "Dependencies installed!" -ForegroundColor Green
} else {
    Write-Host "Failed to install dependencies" -ForegroundColor Red
    exit 1
}

# Create uploads directory
if (-not (Test-Path "uploads")) {
    New-Item -ItemType Directory -Path "uploads" | Out-Null
    Write-Host "Created uploads directory" -ForegroundColor Green
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Make sure MongoDB is running (net start MongoDB)" -ForegroundColor White
Write-Host "2. Start the server: npm run dev" -ForegroundColor White
Write-Host "3. Test API: http://localhost:3000/health" -ForegroundColor White

