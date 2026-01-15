# Authentication Flows

This guide explains the different authentication flows supported by the BankID strategy.

## Overview

The BankID authentication strategy supports two main flows:

1. **QR Code (Cross-device) Flow** - Desktop users authenticate using their mobile device
2. **Same-device Flow** - Mobile users authenticate directly on their device

Both flows follow the same high-level pattern:
1. Initiate authentication → 2. Poll for status → 3. Complete sign-in

## QR Code (Cross-device) Flow

### Use Case
Perfect for web applications where users are on desktop computers and want to authenticate using their BankID mobile app.

### Flow Diagram

```
┌─────────────┐    POST /user/bank_id/initiate    ┌─────────────┐
│   Desktop   │ ────────────────────────────────► │   Backend   │
│   Browser   │                                   │   Server    │
└─────────────┐    ←──── QR Code Data ──────────── └─────────────┘
       │                                                   │
       │              Show QR Code to User                  │
       │                                                   ▼
       │                                            ┌─────────────┐
       │                                            │   BankID    │
       │                                            │   API       │
       │                                            └─────────────┘
       │                                                   │
       │           User scans QR with mobile app            │
       │                                                   ▼
       │                                            ┌─────────────┐
       │                                            │   Mobile    │
       │                                            │   BankID    │
       │                                            │   App       │
       │                                            └─────────────┘
       │                                                   │
       │              Authentication complete               │
       │                                                   ▼
┌─────────────┐    GET /user/bank_id/poll          ┌─────────────┐
│   Desktop   │ ───────────────────────────────────► │   Backend   │
│   Browser   │                                   │   Server    │
└─────────────┐    ←────── Auth Success ──────────── └─────────────┘
       │
       ▼
┌─────────────┐    POST /user/bank_id             ┌─────────────┐
│   Desktop   │ ──────────────────────────────────► │   Backend   │
│   Browser   │                                   │   Server    │
└─────────────┐    ←────── JWT Token ────────────── └─────────────┘
```

### Implementation Steps

#### 1. Initiate Authentication

```elixir
# POST /user/bank_id/initiate
{
  "return_url": "https://yourapp.com/auth/callback",
  "device_info": {
    "user_agent": "Mozilla/5.0...",
    "ip_address": "192.168.1.100"
  }
}
```

**Response:**
```elixir
{
  "status": "pending",
  "order_ref": "12345678-1234-1234-1234-123456789012",
  "qr_start_token": "abc123...",
  "qr_start_secret": "def456...",  # Never exposed to client
  "auto_start_token": "ghi789...", # For same-device apps
  "expires_at": "2024-01-01T12:05:00Z"
}
```

#### 2. Generate QR Code

```javascript
// Frontend: Generate QR code using the qr_start_token
// Note: Use qr_start_token + qr_start_secret + timestamp for animated QR
const qrData = `${qrStartToken}${time}`;

// Use any QR code library
QRCode.toCanvas(canvas, qrData, function (error) {
  if (error) console.error(error);
  console.log('QR code generated!');
});
```

#### 3. Poll for Status

```elixir
# GET /user/bank_id/poll?order_ref=12345678-1234-1234-1234-123456789012
# Server-side polling every 2 seconds (recommended)

# Response examples:
{
  "status": "pending",     # Still waiting for user
  "hint_code": "outstandingTransaction"  # User has BankID app open
}

{
  "status": "failed",      # Authentication failed
  "hint_code": "userCancel" # User cancelled
}

{
  "status": "complete",    # Authentication successful!
  "completion_data": {
    "user": {
      "personal_number": "199001011234",
      "name": "Anna Svensson",
      "given_name": "Anna",
      "surname": "Svensson"
    },
    "device": {
      "ip_address": "192.168.1.100"
    },
    "bankid_issue_date": "2024-01-01T12:03:45Z"
  }
}
```

#### 4. Complete Sign-in

```elixir
# POST /user/bank_id
{
  "order_ref": "12345678-1234-1234-1234-123456789012",
  "completion_data": {
    # Data from successful poll response
  }
}

# Response: JWT token for authenticated session
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "def50200...",
  "expires_in": 3600,
  "user": {
    "id": "user_123",
    "personal_number": "199001011234",
    "given_name": "Anna",
    "surname": "Svensson"
  }
}
```

## Same-device Flow

### Use Case
Perfect for mobile web applications where users want to authenticate directly on the same device.

### Flow Implementation

#### 1. Initiate Authentication

```elixir
# POST /user/bank_id/initiate
{
  "return_url": "https://yourapp.com/auth/callback",
  "device_info": {
    "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X)",
    "ip_address": "192.168.1.100"
  },
  "auto_start": true  # Indicates same-device flow
}
```

#### 2. Auto-start BankID App

```javascript
// Frontend: Use auto_start_token to launch BankID app
const bankIdUrl = `bankid:///?autostarttoken=${autoStartToken}&redirect=null`;
window.location.href = bankIdUrl;

// Fallback: Show instructions if app doesn't open
setTimeout(() => {
  // Show "Open BankID app" message
}, 1000);
```

#### 3. Poll for Status (Same as QR flow)

The polling mechanism is identical to the QR code flow.

## Order Renewal

BankID orders expire after ~30 seconds. The library automatically handles order renewal:

```elixir
# GET /user/bank_id/poll may return:
{
  "status": "pending",
  "hint_code": "orderExpired",  # Current order expired
  "auto_start_token": "new123...",  # New order created
  "expires_at": "2024-01-01T12:06:00Z"
}

# Client should:
# 1. Update QR code with new token
# 2. Continue polling with same order_ref
```

## Security Features

### Session Binding
- Orders are bound to Phoenix session ID
- Prevents session hijacking attacks
- Orders cannot be used across different sessions

### Single-use Orders
- Orders are marked as consumed after successful authentication
- Prevents replay attacks
- Cleanup process removes consumed orders after 24 hours

### IP Address Verification
- Authentication is bound to the originating IP address
- Optional verification on completion

## Error Handling

### Common Error Scenarios

#### User Cancels
```elixir
{
  "status": "failed",
  "hint_code": "userCancel"
}
# Action: Show "Try again" button
```

#### User Timeout
```elixir
{
  "status": "failed", 
  "hint_code": "expiredTransaction"
}
# Action: Show "Authentication timed out" message
```

#### No BankID Client
```elixir
{
  "status": "failed",
  "hint_code": "noClient"
}
# Action: Show "Install BankID app" message
```

#### Certificate Issues
```elixir
{
  "status": "failed",
  "hint_code": "certificateErr"
}
# Action: Log error, show generic error message
```

## Frontend Integration Examples

### React Example

```javascript
function BankIDAuth() {
  const [authState, setAuthState] = useState('initiating');
  const [qrData, setQrData] = useState(null);
  const [orderRef, setOrderRef] = useState(null);

  const initiateAuth = async () => {
    try {
      const response = await fetch('/user/bank_id/initiate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ return_url: window.location.href })
      });
      
      const data = await response.json();
      setOrderRef(data.order_ref);
      setQrData(data.qr_start_token);
      setAuthState('pending');
      startPolling(data.order_ref);
    } catch (error) {
      setAuthState('error');
    }
  };

  const startPolling = (orderRef) => {
    const pollInterval = setInterval(async () => {
      try {
        const response = await fetch(`/user/bank_id/poll?order_ref=${orderRef}`);
        const data = await response.json();
        
        if (data.status === 'complete') {
          clearInterval(pollInterval);
          await completeSignIn(data.completion_data);
        } else if (data.status === 'failed') {
          clearInterval(pollInterval);
          setAuthState('failed');
        } else if (data.auto_start_token) {
          // Order renewed, update QR
          setQrData(data.qr_start_token);
        }
      } catch (error) {
        clearInterval(pollInterval);
        setAuthState('error');
      }
    }, 2000);
  };

  const completeSignIn = async (completionData) => {
    // ... complete the sign-in process
  };

  return (
    <div>
      {authState === 'initiating' && (
        <button onClick={initiateAuth}>Start BankID Authentication</button>
      )}
      
      {authState === 'pending' && qrData && (
        <div>
          <QRCode data={qrData} />
          <p>Scan with BankID app</p>
        </div>
      )}
      
      {authState === 'failed' && (
        <div>
          <p>Authentication failed</p>
          <button onClick={initiateAuth}>Try Again</button>
        </div>
      )}
    </div>
  );
}
```

## Next Steps

- [Setup guide](setup.md) - Complete installation and configuration
- [API reference](api.md) - Detailed API documentation
- [Troubleshooting](troubleshooting.md) - Common issues and solutions