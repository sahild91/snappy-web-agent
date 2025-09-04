# Snappy Web Agent

A Rust-based web agent for collecting and streaming data from serial devices via Socket.IO. The agent automatically finds available ports and provides real-time device communication through WebSocket connections.

## Features

- 🔌 **Dynamic Port Selection**: Automatically finds available ports starting from 8436
- 🔒 **Encrypted Communication**: Supports ChaCha20 encryption for serial data
- 🌐 **Socket.IO Integration**: Real-time bidirectional communication
- 📊 **Device Monitoring**: Continuous device connection status monitoring
- ⚡ **Start/Stop Data Collection**: Control data streaming on demand

## Getting Started

### Prerequisites

- Rust 1.75+ (2024 edition)
- Serial device with VID: `0xb1b0` and PID: `0x5508`
- On Linux: proper udev rules for device access (see [Linux Setup](#linux-setup))

### Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd snappy-web-agent
```

2. Build and run:

```bash
cargo run
```

The server will start on the first available port starting from 8436.

## Linux Setup

### Udev Rules Installation

On Linux systems, you need to install udev rules to allow non-root access to the USB device. Choose one of the following methods:

#### Method 1: Using the Installation Script (Recommended)

```bash
# Make the script executable (if not already)
chmod +x install-udev-rules.sh

# Install udev rules (requires sudo)
sudo ./install-udev-rules.sh

# Optionally, add a specific user to the dialout group
sudo ./install-udev-rules.sh username
```

#### Method 2: Using the Debian Package

If you install via the Debian package (`.deb`), the udev rules are automatically installed:

```bash
sudo dpkg -i snappy-web-agent_*.deb
```

#### Method 3: Manual Installation

1. Copy the udev rules file:
```bash
sudo cp debian/99-snappy-web-agent.rules /etc/udev/rules.d/
sudo chmod 644 /etc/udev/rules.d/99-snappy-web-agent.rules
```

2. Reload udev rules:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

3. Add your user to the dialout group:
```bash
sudo usermod -a -G dialout $USER
```

4. Log out and log back in for group changes to take effect.

### Uninstalling Udev Rules

To remove the udev rules:

```bash
# Using the uninstall script
sudo ./uninstall-udev-rules.sh

# Or manually
sudo rm -f /etc/udev/rules.d/99-snappy-web-agent.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Troubleshooting Device Access

If the device is not detected:

1. Check if the device is connected:
```bash
lsusb | grep "b1b0:5508"
```

2. Check if udev rules are applied:
```bash
ls -la /dev/tty* | grep dialout
```

3. Verify you're in the dialout group:
```bash
groups $USER
```

4. Check device permissions:
```bash
# Find your device
ls -la /dev/serial/by-id/ | grep -i snappy
# Or check all tty devices
ls -la /dev/ttyACM* /dev/ttyUSB*
```

## Socket.IO API

### Connection

Connect to the Socket.IO server:

```javascript
const socket = io("http://localhost:8437"); // Use the port shown in console
```

### Commands (Client → Server)

#### 1. Get Version

Get the current version of the agent.

**Event:** `version`

**Request:**

```javascript
socket.emit("version", (response) => {
  console.log(response);
});
```

**Response:**

```javascript
{
    "success": true,
    "message": "0.1.0",
    "command": "version",
    "error": null
}
```

#### 2. Start Data Collection

Begin collecting and streaming data from the serial device.

**Event:** `start-snappy`

**Request:**

```javascript
socket.emit("start-snappy", (response) => {
  console.log(response);
});
```

**Response:**

```javascript
{
    "success": true,
    "message": "Snappy data collection started",
    "command": "start-snappy",
    "error": null
}
```

#### 3. Stop Data Collection

Stop collecting and streaming data from the serial device.

**Event:** `stop-snappy`

**Request:**

```javascript
socket.emit("stop-snappy", (response) => {
  console.log(response);
});
```

**Response:**

```javascript
{
    "success": true,
    "message": "Snappy data collection stopped",
    "command": "stop-snappy",
    "error": null
}
```

### Events (Server → Client)

#### 1. Device Connection Status

Notifies about device connection/disconnection status.

**Event:** `device-connected`

**Data:**

```javascript
{
    "event": "device-connection",
    "status": "true"  // or "false"
}
```

**Example:**

```javascript
socket.on("device-connected", (data) => {
  console.log("Device status:", data.status);
});
```

#### 2. Snap Data

Real-time data from the serial device (only when data collection is active).

**Event:** `snappy-data`

**Data:**

```javascript
{
    "mac": "0c:ca:d2:88:19:70",
    "value": 1234,
    "timestamp": "2025-08-25T11:22:16.907Z"
}
```

**Example:**

```javascript
socket.on("snappy-data", (data) => {
  console.log("Device data:", data);
  console.log(
    `MAC: ${data.mac}, Value: ${data.value}, Time: ${data.timestamp}`
  );
});
```

## Data Formats

### SerialResponse

Standard response format for command acknowledgments:

```typescript
interface SerialResponse {
  success: boolean;
  message: string;
  command: string;
  error: string | null;
}
```

### EventResponse

Format for status events:

```typescript
interface EventResponse {
  event: string;
  status: string;
}
```

### SnapDataEvent

Format for device data:

```typescript
interface SnapDataEvent {
  mac: string; // MAC address in format "xx:xx:xx:xx:xx:xx"
  value: number; // 16-bit device value
  timestamp: string; // RFC 3339 UTC timestamp
}
```

## Complete Example

```javascript
const io = require("socket.io-client");
const socket = io("http://localhost:8437");

// Connection handling
socket.on("connect", () => {
  console.log("Connected to Snappy Web Agent");

  // Get version
  socket.emit("version", (response) => {
    console.log("Version:", response.message);
  });
});

// Device status monitoring
socket.on("device-connected", (data) => {
  console.log("Device connection status:", data.status);
});

// Data collection
socket.on("snappy-data", (data) => {
  console.log(`[${data.timestamp}] Device ${data.mac}: ${data.value}`);
});

// Start collecting data
socket.emit("start-snappy", (response) => {
  if (response.success) {
    console.log("Data collection started");
  } else {
    console.error("Failed to start:", response.error);
  }
});

// Stop after 10 seconds
setTimeout(() => {
  socket.emit("stop-snappy", (response) => {
    if (response.success) {
      console.log("Data collection stopped");
    }
  });
}, 10000);
```

## Technical Details

### Device Requirements

- **Vendor ID (VID):** `0xb1b0`
- **Product ID (PID):** `0x5508`
- **Baud Rate:** 230400
- **Data Format:** Encrypted with ChaCha20
- **Message Prefix:** `SNAPPY:` (0x53 0x4e 0x41 0x50 0x50 0x59 0x3a)

### Port Selection

The agent automatically selects the first available port starting from 8436. If 8436 is busy, it will try 8437, 8438, etc., up to 8535.

### Error Handling

All command responses include a `success` field. If `success` is `false`, check the `error` field for details.

### Threading Safety

The agent uses thread-safe mechanisms for managing socket connections and data collection state without unsafe code blocks.

## Logging

The agent provides detailed logging for:

- Port selection and binding
- Device connection/disconnection
- Data collection start/stop events
- Serial data processing
- Socket.IO connections
