# 🔍 FindMyScanner

A Bluetooth Low Energy (BLE) scanner designed to detect and monitor "Find My" advertisements from major device manufacturers. This project captures and analyzes BLE advertisements from tracking devices such as Apple AirTags, Google Fast Pair devices, Samsung SmartTags, and Xiaomi Anti-Lost devices.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Supported Devices](#supported-devices)
- [Hardware Requirements](#hardware-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Output Format](#output-format)
- [Technical Details](#technical-details)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This project is a research tool for studying BLE advertisements from "Find My" type devices. It provides real-time monitoring and analysis of tracking device advertisements, helping researchers understand device behavior, advertisement patterns, and manufacturer-specific implementations.

The scanner operates passively, capturing and decoding BLE advertisements without connecting to or interfering with the target devices.

## ✨ Features

- **Multi-Manufacturer Support**: Detects devices from Apple, Google, Samsung, and Xiaomi
- **Real-time Monitoring**: Continuous scanning with live output
- **Flexible Filtering**: Enable/disable specific manufacturers
- **Detailed Analysis**: Decodes both manufacturer data and service data
- **Passive Scanning**: Non-intrusive monitoring that doesn't interfere with devices
- **Comprehensive Logging**: Detailed information about detected devices

## 📱 Supported Devices

### Apple

- **AirTags** (Find My network)
- **Find My accessories** (offline finding)
- Company ID: `0x004C`
- Service UUID: `0xFD6F`

### Google

- **Fast Pair devices** with Find My capability
- **Find My Device network** participants
- Company ID: `0x00E0`
- Service UUID: `0xFEF3`

### Samsung

- **SmartTag** devices
- **SmartTag+** (UWB-enabled)
- Company ID: `0x0075`
- Service UUID: `0xFD5A`

### Xiaomi

- **Anti-Lost** tracking devices
- Company ID: `0x038F`

## 🛠 Hardware Requirements

### Supported ESP32 Boards

- **ESP32-S3** (recommended for better performance)
- **ESP32-WROOM** (standard ESP32)
- **ESP32-U** (compact variant)

### Minimum Specifications

- ESP32 microcontroller with BLE support
- USB connection for serial monitoring
- 3.3V power supply

## 🚀 Installation

### Prerequisites

- [PlatformIO](https://platformio.org/) IDE or CLI
- USB cable for ESP32 programming
- ESP32 development board

### Setup Steps

1. **Clone the repository**

   ```bash
   git clone https://github.com/alexandreprates/FindMyScanner.git
   cd FindMyScanner
   ```

2. **Install dependencies**

   ```bash
   pio lib install
   ```

3. **Select your board environment**
   - For ESP32-S3: `esp32-s3`
   - For ESP32-WROOM: `esp32-wroom`
   - For ESP32-32U: `esp32-32u`

4. **Build and upload**

   ```bash
   # For ESP32-S3
   pio run -e esp32-s3 --target upload

   # For ESP32-WROOM
   pio run -e esp32-wroom --target upload
   ```

5. **Start monitoring**

   ```bash
   pio device monitor
   ```

## ⚙️ Configuration

### Manufacturer Filtering

Edit the filter constants in `src/main.cpp` to enable/disable specific manufacturers:

```cpp
// Filter by Manufacturer type:
constexpr bool FILTER_APPLE   = false;  // Apple (AirTag, Find My)
constexpr bool FILTER_GOOGLE  = true;   // Google (Fast Pair)
constexpr bool FILTER_SAMSUNG = true;   // Samsung (SmartTag)
constexpr bool FILTER_XIAOMI  = true;   // Xiaomi (Anti-Lost)
```

### Scan Parameters

Adjust scanning behavior by modifying these parameters:

```cpp
// Scan interval and window (in 0.625ms units)
scan->setInterval(80);  // 50ms
scan->setWindow(70);    // ~43.75ms

// Passive vs Active scanning
scan->setActiveScan(false);  // true for scan response requests

// Duplicate filtering
scan->setDuplicateFilter(false);  // true to filter repeat advertisements
```

## 📊 Usage

1. **Power on** your ESP32 board
2. **Open serial monitor** at 115200 baud rate
3. **Wait for initialization** - you'll see the filter status
4. **Observe real-time output** as devices are detected

### Example Session

```text
BLE scan started!

=== Filter by Manufacturer ===
Apple:   DISABLED
Google:  ENABLED
Samsung: ENABLED
Xiaomi:  ENABLED
============================

Google   FastPair/FindDevice  | 7b:59:8d:19:f3:a9 | RSSI -46 | PDU NONCONN | Service [11 01 8D 97 54 8D]
Samsung  SmartTag            | a1:b2:c3:d4:e5:f6 | RSSI -52 | PDU NONCONN | Manufacturer [75 00 01 A3 B4]
```

## 📈 Output Format

Each detected device is displayed with the following information:

```text
[Manufacturer] [Device Type] | [MAC Address] | RSSI [dBm] | PDU [Type] | [Connectivity] | [Data Type] [Hex Data]
```

### Field Descriptions

- **Manufacturer**: Apple, Google, Samsung, Xiaomi, or Other
- **Device Type**: Specific device classification (e.g., AirTag, SmartTag, FastPair)
- **MAC Address**: Bluetooth device address (often randomized)
- **RSSI**: Received Signal Strength Indicator in dBm
- **PDU Type**: Advertisement PDU type (NONCONN, ADV_IND, etc.)
- **Connectivity**: CONN (connectable) or NONCONN (non-connectable)
- **Data Type**: Source of detection (Manufacturer or Service data)
- **Hex Data**: Raw advertisement data in hexadecimal format

## 🔧 Technical Details

### BLE Advertisement Analysis

The scanner analyzes two types of BLE advertisement data:

1. **Manufacturer Specific Data**: Company-specific advertisement format
2. **Service Data**: Standardized service UUID-based advertisements

### Detection Logic

- **Apple Find My**: Detects type 0x12 (AirTag) and 0x10 (offline finding) in manufacturer data
- **Google Fast Pair**: Identifies service UUID 0xFEF3 with type 0x11 for Find My devices
- **Samsung SmartTag**: Recognizes types 0x01 (SmartTag) and 0x02 (SmartTag+) in manufacturer data
- **Xiaomi Anti-Lost**: Detects type 0x30 in manufacturer data

### Privacy Considerations

- This tool is for educational and research purposes only
- Respects device privacy by operating in passive mode
- Does not attempt to connect or communicate with target devices
- Does not store or transmit personal data

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- Follow existing code style and formatting
- Add comments for complex logic
- Test on multiple ESP32 variants when possible
- Update documentation for new features

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This project is intended for educational and research purposes only. Users are responsible for complying with local laws and regulations regarding radio frequency monitoring and privacy. The authors assume no responsibility for misuse of this software.

## 🔗 References

- [NimBLE-Arduino Library](https://github.com/h2zero/NimBLE-Arduino)
- [Bluetooth SIG Company Identifiers](https://www.bluetooth.com/specifications/assigned-numbers/company-identifiers/)
- [Apple Find My Network](https://developer.apple.com/find-my/)
- [Google Fast Pair](https://developers.google.com/nearby/fast-pair)

---

**⭐ If this project helps your research, please give it a star!**
