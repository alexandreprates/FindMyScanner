#include <Arduino.h>
#include <NimBLEDevice.h>
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>
#include <cctype>

// Company IDs (Bluetooth SIG) — little endian in manufacturer data bytes
constexpr uint16_t CID_APPLE   = 0x004C;
constexpr uint16_t CID_GOOGLE  = 0x00E0;
constexpr uint16_t CID_SAMSUNG = 0x0075;
constexpr uint16_t CID_XIAOMI  = 0x038F;

// Service UUIDs for Find My devices
constexpr uint16_t SVC_GOOGLE_FAST_PAIR  = 0xFEF3; // Google Fast Pair
constexpr uint16_t SVC_APPLE_FIND_MY     = 0xFD6F; // Apple Find My
constexpr uint16_t SVC_SAMSUNG_FIND      = 0xFD5A; // Samsung Find

// Filter by Manufacturer type:
constexpr bool FILTER_APPLE   = true;  // Apple (AirTag, Find My)
constexpr bool FILTER_GOOGLE  = true;  // Google (Fast Pair)
constexpr bool FILTER_SAMSUNG = true;  // Samsung (SmartTag)
constexpr bool FILTER_XIAOMI  = true;  // Xiaomi (Anti-Lost)

// --------- Helpers ---------
static inline const char* advTypeName(uint8_t t) {
  switch (t) {
    case 0: return  "ADV_IND ";
    case 1: return  "DIR_IND ";
    case 2: return  "SCAN_IND";
    case 3: return  "NONCONN ";
    case 4: return  "SCAN_RSP";
    default: return "UNKNOWN ";
  }
}

static std::string toHex(const uint8_t* data, size_t len) {
  static const char* hex = "0123456789ABCDEF";
  std::string out;
  out.reserve(len * 3);
  for (size_t i = 0; i < len; ++i) {
    uint8_t b = data[i];
    out.push_back(hex[(b >> 4) & 0xF]);
    out.push_back(hex[b & 0xF]);
    if (i + 1 < len) out.push_back(' ');
  }
  return out;
}

static uint16_t parseCompanyIdLE(const std::string& mfd) {
  if (mfd.size() < 2) return 0xFFFF;
  // Manufacturer specific data: First 2 bytes = CompanyID in Little Endian
  return (uint16_t)((uint8_t)mfd[0] | ((uint16_t)(uint8_t)mfd[1] << 8));
}

static const char* companyName(uint16_t cid) {
  switch (cid) {
    case CID_APPLE:   return "Apple  ";
    case CID_GOOGLE:  return "Google ";
    case CID_SAMSUNG: return "Samsung";
    case CID_XIAOMI:  return "Xiaomi ";
    default:          return "Other  ";
  }
}

// Converts Service UUID to Manufacturer
static uint16_t serviceToManufacturer(uint16_t serviceUuid) {
  switch (serviceUuid) {
    case SVC_GOOGLE_FAST_PAIR: return CID_GOOGLE;
    case SVC_APPLE_FIND_MY:    return CID_APPLE;
    case SVC_SAMSUNG_FIND:     return CID_SAMSUNG;
    default:                   return 0xFFFF;
  }
}

// Detects "Find My" based on service data
static bool isFindMyServiceData(uint16_t serviceUuid, const std::string& serviceData) {
  switch (serviceUuid) {
    case SVC_GOOGLE_FAST_PAIR:
      // Google Fast Pair service data
      return serviceData.size() >= 3;

    case SVC_APPLE_FIND_MY:
      // Apple Find My service data
      return serviceData.size() >= 6;

    case SVC_SAMSUNG_FIND:
      // Samsung Find service data
      return serviceData.size() >= 4;

    default:
      return false;
  }
}

static const char* getServiceFindMyType(uint16_t serviceUuid, const std::string& serviceData) {
  switch (serviceUuid) {
    case SVC_GOOGLE_FAST_PAIR:
      if (serviceData.size() >= 1) {
        uint8_t type = (uint8_t)serviceData[0];
        switch (type) {
          case 0x11: return "FastPair/FindDevice";
          case 0x10: return "FastPair/Generic";
          default: return   "FastPair/Unknown";
        }
      }
      return "FastPair";

    case SVC_APPLE_FIND_MY:
      return "FindMy/Service";

    case SVC_SAMSUNG_FIND:
      return "SmartTag/Service";

    default:
      return "Service/Unknown";
  }
}

// Check if it's a manufacturer-specific "Find My" ad
static bool isFindMyDevice(uint16_t cid, const std::string& mfd) {
  if (mfd.size() < 4) return false;

  switch (cid) {
    case CID_APPLE:
      // Apple Find My/AirTag: type 0x12 or 0x10
      // Format: [CID_LOW, CID_HIGH, TYPE, ...data...]
      return (mfd.size() >= 3 && ((uint8_t)mfd[2] == 0x12 || (uint8_t)mfd[2] == 0x10));

    case CID_GOOGLE:
      // Google Find My Device/Fast Pair
      return (mfd.size() >= 3 && (uint8_t)mfd[2] == 0x06);

    case CID_SAMSUNG:
      // Samsung SmartTag uses specific types of manufacturer data
      return (mfd.size() >= 4 && ((uint8_t)mfd[2] == 0x01 || (uint8_t)mfd[2] == 0x02));

    case CID_XIAOMI:
      // Xiaomi Anti-Lost: specific ad types
      return (mfd.size() >= 3 && (uint8_t)mfd[2] == 0x30);

    default:
      return false;
  }
}

static const char* getFindMyType(uint16_t cid, const std::string& mfd) {
  if (mfd.size() < 3) return "Unknown";

  uint8_t type = (uint8_t)mfd[2];

  switch (cid) {
    case CID_APPLE:
      switch (type) {
        case 0x12: return "FindMy/AirTag";
        case 0x10: return "FindMy/Offline";
        default: return "FindMy/Other";
      }

    case CID_GOOGLE:
      switch (type) {
        case 0x06: return "FastPair/FindMy";
        default: return "FindMy/Other";
      }

    case CID_SAMSUNG:
      switch (type) {
        case 0x01: return "SmartTag";
        case 0x02: return "SmartTag+";
        default: return "SmartTag/Other";
      }

    case CID_XIAOMI:
      switch (type) {
        case 0x30: return "Anti-Lost";
        default: return "FindMy/Other";
      }

    default:
      return "Unknown";
  }
}

// --------- Apply filter ---------
static bool isManufacturerEnabled(uint16_t cid) {
  switch (cid) {
    case CID_APPLE:   return FILTER_APPLE;
    case CID_GOOGLE:  return FILTER_GOOGLE;
    case CID_SAMSUNG: return FILTER_SAMSUNG;
    case CID_XIAOMI:  return FILTER_XIAOMI;
    default:          return false;
  }
}

static void printFilterStatus() {
  Serial.println("\n=== Filter by Manufacturer ===");
  Serial.printf("Apple:   %s\n", FILTER_APPLE ? "ENABLED" : "DISABLED");
  Serial.printf("Google:  %s\n", FILTER_GOOGLE ? "ENABLED" : "DISABLED");
  Serial.printf("Samsung: %s\n", FILTER_SAMSUNG ? "ENABLED" : "DISABLED");
  Serial.printf("Xiaomi:  %s\n", FILTER_XIAOMI ? "ENABLED" : "DISABLED");
  Serial.println("============================\n");
}

// --------- Callback de Scan ---------
class MyAdvertisedDeviceCallbacks : public NimBLEScanCallbacks {
  void onResult(const NimBLEAdvertisedDevice* dev) override {
    bool foundFindMyDevice = false;
    uint16_t detectedManufacturer = 0xFFFF;
    std::string dataType = "";
    std::string deviceType = "";
    std::string dataHex = "";

  // First, check service data (as in nRF Connect log)
    if (dev->haveServiceData()) {
      for (int i = 0; i < dev->getServiceDataCount(); i++) {
        NimBLEUUID serviceUuid = dev->getServiceDataUUID(i);
        std::string serviceData = dev->getServiceData(i);

        // Converts UUID to uint16_t
        uint16_t uuid16 = 0;
        if (serviceUuid.bitSize() == 16) {
          const uint8_t* uuidBytes = serviceUuid.getValue();
          uuid16 = (uuidBytes[1] << 8) | uuidBytes[0]; // Little endian
        }

        // Check if it's a known Find My service
        if (isFindMyServiceData(uuid16, serviceData)) {
          detectedManufacturer = serviceToManufacturer(uuid16);
          if (detectedManufacturer != 0xFFFF && isManufacturerEnabled(detectedManufacturer)) {
            foundFindMyDevice = true;
            dataType = "Service";
            deviceType = getServiceFindMyType(uuid16, serviceData);

            // Convert Service Data to HEX
            std::vector<uint8_t> buf(serviceData.begin(), serviceData.end());
            dataHex = toHex(buf.data(), buf.size());
            break; // Use the first service found
          }
        }
      }
    }

    // If not found via Service Data, check Manufacturer Data
    if (!foundFindMyDevice && dev->haveManufacturerData()) {
      const std::string& mfd = dev->getManufacturerData();
      if (mfd.size() >= 3) { // Needs at least CID (2 bytes) + type (1 byte)
        const uint16_t cid = parseCompanyIdLE(mfd);

        // Filter only manufacturers of interest
        if ((cid == CID_APPLE || cid == CID_GOOGLE || cid == CID_SAMSUNG || cid == CID_XIAOMI) &&
            isManufacturerEnabled(cid) && isFindMyDevice(cid, mfd)) {
          foundFindMyDevice = true;
          detectedManufacturer = cid;
          dataType = "Manufacturer";
          deviceType = getFindMyType(cid, mfd);

          // Convert MFD to HEX
          std::vector<uint8_t> buf(mfd.begin(), mfd.end());
          dataHex = toHex(buf.data(), buf.size());
        }
      }
    }

    // If found a Find My device, display the information
    if (foundFindMyDevice) {
      const std::string addr = dev->getAddress().toString();
      const int rssi = dev->getRSSI();
      const uint8_t advType = dev->getAdvType();
      const bool isConnectable = dev->isConnectable();

      // Extended output format:
      // "Google FastPair/FindDevice | 7b:59:8d:19:f3:a9 | RSSI -46 | PDU NONCONN | Service [11 01 8D 97 54 8D]"
      Serial.printf("%-8s %-18s | %s | RSSI %03d | PDU %s | %s%-2s | %-12s [%s]\n",
                    companyName(detectedManufacturer),
                    deviceType.c_str(),
                    addr.c_str(),
                    rssi,
                    advTypeName(advType),
                    isConnectable ? "CONN" : "NONCONN",
                    dev->isScannable() ? "/SCAN" : "",
                    dataType.c_str(),
                    dataHex.c_str());
      }
    }
};

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(10); } // USB CDC (S3) — waits for connection to see logs
  delay(1000);

  // Initialize NimBLE
  NimBLEDevice::init("FindMyScanner"); // Scanner device name
  NimBLEDevice::setSecurityAuth(false, false, false);
  // TX power only affects active ads/connections; it doesn't change RX gain.
  // We maintain the default setting to avoid "polluting" the environment with our own ads.

  NimBLEScan* scan = NimBLEDevice::getScan();
  scan->setScanCallbacks(new MyAdvertisedDeviceCallbacks(), /*wantDuplicates=*/true);

  // Passive is more "quiet" and sufficient for mfd — change to true if you need scan response
  scan->setActiveScan(false);

  // Interval and window (units of 0.625 ms). Ex.: 80 => 50 ms; 70 => ~43.75 ms
  scan->setInterval(80);
  scan->setWindow(70);

  // Avoid repeating the same advertisement (controlled by controller). true = filter duplicates
  // We set false here because we want to capture ID rotations more easily.
  scan->setDuplicateFilter(false);

  scan->setLimitedOnly(false);

  // Start continuous scanning (0 = no timeout). Non-blocking; callbacks will be called.
  if (!scan->start(0, false)) {
    Serial.println("BLE scan init FAIL.");
  } else {
    Serial.println("BLE scan started!");
  }

  // Show filter status
  printFilterStatus();
}

void loop() {
  // Periodic checkpoint to confirm the system is active
  static uint32_t last = 0;
  if (millis() - last > 30000) { // Every 30 seconds
    last = millis();
  }
}
