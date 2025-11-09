# SMTP Configuration Setup Guide

## Error: SMTP not configured

If you're seeing the error "SMTP not configured. Please call configureSMTP() first", you need to set up SMTP credentials for sending OTP emails.

## Steps to Fix:

### 1. Create a `.env` file

Create a file named `.env` in the `blockchain_fyp` directory (same level as `pubspec.yaml`).

### 2. Add SMTP Configuration

Add the following to your `.env` file:

```
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=true
```

### 3. For Gmail Users:

1. **Enable 2-Step Verification** in your Google Account:
   - Go to: https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Generate an App Password**:
   - Go to: https://myaccount.google.com/apppasswords
   - Select "Mail" and "Other (Custom name)"
   - Enter "EtherShare" as the name
   - Copy the 16-character App Password
   - Use this as `SMTP_PASSWORD` (NOT your regular Gmail password)

### 4. For SendGrid Users:

```
SMTP_USERNAME=apikey
SMTP_PASSWORD=your_sendgrid_api_key
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_SECURE=true
```

### 5. For Custom SMTP Server:

```
SMTP_USERNAME=your_username
SMTP_PASSWORD=your_password
SMTP_HOST=smtp.yourdomain.com
SMTP_PORT=587
SMTP_SECURE=true
```

## Important Notes:

- **Never commit your `.env` file to Git** - it contains sensitive credentials
- The `.env` file should be in your `.gitignore`
- After creating/updating `.env`, you MUST rebuild your app:
  ```bash
  flutter clean
  flutter pub get
  flutter run
  ```
- The `.env` file is now listed in `pubspec.yaml` assets section - this is required for mobile apps
- Make sure `flutter_dotenv` package is properly configured in your `pubspec.yaml`

## Troubleshooting:

- If emails still don't send, check:
  1. SMTP credentials are correct
  2. Firewall/network allows SMTP connections
  3. App Password is used (not regular password for Gmail)
  4. 2-Step Verification is enabled (for Gmail)

