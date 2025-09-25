#include <Arduino.h>
#include <NimBLEDevice.h>
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>
#include <cctype>
#include <time.h>

#ifdef CONFIG_IDF_TARGET_ESP32S3
  #include <Adafruit_NeoPixel.h>
#endif

// Output format options:
enum class OutputFormat {
  LOG,   // Human-readable log format (default)
  CSV,   // Comma-separated values
  YAML   // YAML format
};

// Output format configuration (can be set via build flags)
#ifndef OUTPUT_FORMAT_FLAG
  #define OUTPUT_FORMAT_FLAG 1  // Default: CSV (0=LOG, 1=CSV, 2=YAML)
#endif

#if OUTPUT_FORMAT_FLAG == 0
  constexpr OutputFormat OUTPUT_FORMAT = OutputFormat::LOG;
#elif OUTPUT_FORMAT_FLAG == 1
  constexpr OutputFormat OUTPUT_FORMAT = OutputFormat::CSV;
#elif OUTPUT_FORMAT_FLAG == 2
  constexpr OutputFormat OUTPUT_FORMAT = OutputFormat::YAML;
#else
  constexpr OutputFormat OUTPUT_FORMAT = OutputFormat::LOG;
#endif

// RSSI filter (minimum signal strength to process devices)
// Can be set via build flags, default is -50
#ifndef MIN_RSSI_FLAG
  #define MIN_RSSI_FLAG -50
#endif
constexpr int MIN_RSSI = MIN_RSSI_FLAG;

// Manufacturer filter configuration (can be set via build flags)
// Bit mask for individual manufacturers:
//   0x1 = Apple    (bit 0)
//   0x2 = Google   (bit 1)
//   0x4 = Samsung  (bit 2)
//   0x8 = Xiaomi   (bit 3)
// Default: 0xF (all manufacturers enabled)
// Examples of any combination:
//   -DMANUFACTURES_FLAG=0x1  (only Apple)
//   -DMANUFACTURES_FLAG=0x2  (only Google)
//   -DMANUFACTURES_FLAG=0x3  (Apple + Google)
//   -DMANUFACTURES_FLAG=0x5  (Apple + Samsung)
//   -DMANUFACTURES_FLAG=0x6  (Google + Samsung)
//   -DMANUFACTURES_FLAG=0x7  (Apple + Google + Samsung)
//   -DMANUFACTURES_FLAG=0x8  (only Xiaomi)
//   -DMANUFACTURES_FLAG=0x9  (Apple + Xiaomi)
//   -DMANUFACTURES_FLAG=0xA  (Google + Xiaomi)
//   -DMANUFACTURES_FLAG=0xB  (Apple + Google + Xiaomi)
//   -DMANUFACTURES_FLAG=0xC  (Samsung + Xiaomi)
//   -DMANUFACTURES_FLAG=0xD  (Apple + Samsung + Xiaomi)
//   -DMANUFACTURES_FLAG=0xE  (Google + Samsung + Xiaomi)
//   -DMANUFACTURES_FLAG=0xF  (all manufacturers - default)
#ifndef MANUFACTURES_FLAG
  #define MANUFACTURES_FLAG 0xF
#endif


#ifndef BUILD_TIME_UNIX
#define BUILD_TIME_UNIX 0
#endif

// LED built-in para feedback visual
#ifndef LED_BUILTIN
  #if defined(CONFIG_IDF_TARGET_ESP32)
    #define LED_BUILTIN 2   // GPIO2 no ESP32 DOIT DevKit V1
  #else
    #define LED_BUILTIN 2   // Default para compatibilidade
  #endif
#endif

// LED WS2812B built-in no ESP32-S3
#ifdef CONFIG_IDF_TARGET_ESP32S3
  #define WS2812_PIN    48    // Pino do LED WS2812B built-in no ESP32-S3 DevKitC
  #define WS2812_COUNT  1     // Apenas 1 LED WS2812B
  #define WS2812_BRIGHTNESS 50 // Brilho (0-255)

  // Instância do NeoPixel
  Adafruit_NeoPixel neoPixel(WS2812_COUNT, WS2812_PIN, NEO_GRB + NEO_KHZ800);
#endif

// Company IDs (Bluetooth SIG) — little endian in manufacturer data bytes
constexpr uint16_t CID_APPLE   = 0x004C;
constexpr uint16_t CID_GOOGLE  = 0x00E0;
constexpr uint16_t CID_SAMSUNG = 0x0075;
constexpr uint16_t CID_XIAOMI  = 0x038F;

// Service UUIDs for Find My devices
constexpr uint16_t SVC_GOOGLE_FAST_PAIR  = 0xFEF3; // Google Fast Pair
constexpr uint16_t SVC_APPLE_FIND_MY     = 0xFD6F; // Apple Find My
constexpr uint16_t SVC_SAMSUNG_FIND      = 0xFD5A; // Samsung Find

// Filter by Manufacturer type (controlled by MANUFACTURES_FLAG):
constexpr bool FILTER_APPLE   = (MANUFACTURES_FLAG & 0x1) != 0;  // Apple (AirTag, Find My)
constexpr bool FILTER_GOOGLE  = (MANUFACTURES_FLAG & 0x2) != 0;  // Google (Fast Pair)
constexpr bool FILTER_SAMSUNG = (MANUFACTURES_FLAG & 0x4) != 0;  // Samsung (SmartTag)
constexpr bool FILTER_XIAOMI  = (MANUFACTURES_FLAG & 0x8) != 0;  // Xiaomi (Anti-Lost)

// --------- Helpers ---------
static inline const char* advTypeName(uint8_t t) {
  switch (t) {
    case 0: return  "ADV_IND";
    case 1: return  "DIR_IND";
    case 2: return  "SCAN_IND";
    case 3: return  "NONCONN";
    case 4: return  "SCAN_RSP";
    default: return "UNKNOWN";
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
    case CID_APPLE:   return "Apple";
    case CID_GOOGLE:  return "Google";
    case CID_SAMSUNG: return "Samsung";
    case CID_XIAOMI:  return "Xiaomi";
    default:          return "Other";
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

// Feedback visual para erros usando LED built-in.
// Mantem o device travado pois a função principal não está disponível
// Compatível com:
// - ESP32-S3 DevKitC-1: GPIO48 (LED WS2812B) - Vermelho para erro, Verde para sucesso
// - ESP32 DOIT DevKit V1: GPIO2 (LED azul)
static void signalError() {
#ifdef CONFIG_IDF_TARGET_ESP32S3
  // ESP32-S3: Pisca LED vermelho 5 vezes para indicar erro
  while (true) {
    neoPixel.setPixelColor(0, neoPixel.Color(255, 0, 0)); // Vermelho
    neoPixel.show();
    delay(1000);
    neoPixel.setPixelColor(0, neoPixel.Color(0, 0, 0));   // Desligado
    neoPixel.show();
    delay(1000);
  }
#else
  // ESP32 padrão: Pisca LED built-in 5 vezes rapidamente para indicar erro
  while (true) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(1000);
    digitalWrite(LED_BUILTIN, LOW);
    delay(1000);
  }
#endif
}

static void signalSuccess() {
#ifdef CONFIG_IDF_TARGET_ESP32S3
  // ESP32-S3: Acende LED verde por 2 segundos para indicar sucesso
  neoPixel.setPixelColor(0, neoPixel.Color(0, 255, 0)); // Verde
  neoPixel.show();
  delay(2000);
  neoPixel.setPixelColor(0, neoPixel.Color(0, 0, 0));   // Desligado
  neoPixel.show();
#else
  // ESP32 padrão: Acende LED por 1 segundo para indicar sucesso
  delay(2000);
  digitalWrite(LED_BUILTIN, LOW);
#endif
}

// Função helper para obter timestamp formatado
static std::string getCurrentTimestamp() {
  struct timeval tv;
  struct tm timeinfo;
  char timeString[32];

  gettimeofday(&tv, nullptr);
  localtime_r(&tv.tv_sec, &timeinfo);

  // Formato: YYYY-MM-DD HH:MM:SS.mmm
  snprintf(timeString, sizeof(timeString), "%04d-%02d-%02d %02d:%02d:%02d.%03ld",
           timeinfo.tm_year + 1900,
           timeinfo.tm_mon + 1,
           timeinfo.tm_mday,
           timeinfo.tm_hour,
           timeinfo.tm_min,
           timeinfo.tm_sec,
           tv.tv_usec / 1000);

  return std::string(timeString);
}

// --------- Callback de Scan ---------

// --------- Callback de Scan ---------
class MyAdvertisedDeviceCallbacks : public NimBLEScanCallbacks {
private:
  void formatDeviceAsLog(uint16_t manufacturer, const std::string& deviceType,
                        const std::string& addr, int rssi, uint8_t advType,
                        bool isConnectable, bool isScannable, const std::string& dataType,
                        const std::string& dataHex, const std::string& timestamp,
                        char* buffer, size_t bufferSize) {
    // Formatar linha de log no buffer fornecido usando timestamp fornecido
    snprintf(buffer, bufferSize,
             "%s | %-8s %-18s | %s | RSSI %03d | PDU %s | %s%-2s | %-12s [%s]\n",
             timestamp.c_str(),
             companyName(manufacturer),
             deviceType.c_str(),
             addr.c_str(),
             rssi,
             advTypeName(advType),
             isConnectable ? "CONN" : "NONCONN",
             isScannable ? "/SCAN" : "",
             dataType.c_str(),
             dataHex.c_str());
  }

  void formatDeviceAsCSV(uint16_t manufacturer, const std::string& deviceType,
                        const std::string& addr, int rssi, uint8_t advType,
                        bool isConnectable, bool isScannable, const std::string& dataType,
                        const std::string& dataHex, const std::string& timestamp,
                        char* buffer, size_t bufferSize) {
    // Formatar linha CSV no buffer fornecido usando timestamp fornecido
    snprintf(buffer, bufferSize,
             "%s,%s,%s,%s,%d,%s,%s,%s,%s,%s\n",
             timestamp.c_str(),
             companyName(manufacturer),
             deviceType.c_str(),
             addr.c_str(),
             rssi,
             advTypeName(advType),
             isConnectable ? "true" : "false",
             isScannable ? "true" : "false",
             dataType.c_str(),
             dataHex.c_str());
  }

  void formatDeviceAsYaml(uint16_t manufacturer, const std::string& deviceType,
                         const std::string& addr, int rssi, uint8_t advType,
                         bool isConnectable, bool isScannable, const std::string& dataType,
                         const std::string& dataHex, const std::string& timestamp,
                         char* buffer, size_t bufferSize) {
    // Formatar entrada YAML no buffer fornecido usando timestamp fornecido
    snprintf(buffer, bufferSize,
      "- device:\n"
      "    time: %s\n"
      "    manufacturer: %s\n"
      "    type: %s\n"
      "    address: %s\n"
      "    rssi: %d\n"
      "    adv_type: %s\n"
      "    connectable: %s\n"
      "    scannable: %s\n"
      "    data_type: %s\n"
      "    data_hex: %s\n",
      timestamp.c_str(),
      companyName(manufacturer),
      deviceType.c_str(),
      addr.c_str(),
      rssi,
      advTypeName(advType),
      isConnectable ? "true" : "false",
      isScannable ? "true" : "false",
      dataType.c_str(),
      dataHex.c_str());
  }

  void printDevice(uint16_t manufacturer, const std::string& deviceType,
                   const std::string& addr, int rssi, uint8_t advType,
                   bool isConnectable, bool isScannable, const std::string& dataType,
                   const std::string& dataHex) {
    // Obter timestamp uma única vez para consistência e eficiência
    std::string timestamp = getCurrentTimestamp();
    char outputBuffer[512];

    switch (OUTPUT_FORMAT) {
      case OutputFormat::LOG:
        formatDeviceAsLog(manufacturer, deviceType, addr, rssi, advType,
                         isConnectable, isScannable, dataType, dataHex, timestamp,
                         outputBuffer, sizeof(outputBuffer));
        break;
      case OutputFormat::CSV:
        formatDeviceAsCSV(manufacturer, deviceType, addr, rssi, advType,
                         isConnectable, isScannable, dataType, dataHex, timestamp,
                         outputBuffer, sizeof(outputBuffer));
        break;
      case OutputFormat::YAML:
        formatDeviceAsYaml(manufacturer, deviceType, addr, rssi, advType,
                          isConnectable, isScannable, dataType, dataHex, timestamp,
                          outputBuffer, sizeof(outputBuffer));
        break;
    }

    // Único ponto de saída Serial - centralizado
    Serial.print(outputBuffer);
    delay(5);
    Serial.flush();
  }

public:
  void onResult(const NimBLEAdvertisedDevice* dev) override {
    // Filter by RSSI - ignore devices with weak signal
    if (dev->getRSSI() < MIN_RSSI) {
      return;
    }

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

      // Use the configured output format
      printDevice(detectedManufacturer, deviceType, addr, rssi, advType,
                  isConnectable, dev->isScannable(), dataType, dataHex);
      }
    }
};

void setup() {
  struct timeval tv = { .tv_sec = (time_t)BUILD_TIME_UNIX, .tv_usec = 0 };
  settimeofday(&tv, nullptr);

  // Inicializa LED built-in para feedback visual
#ifdef CONFIG_IDF_TARGET_ESP32S3
  // ESP32-S3: Inicializa LED WS2812B
  neoPixel.begin();
  neoPixel.setBrightness(WS2812_BRIGHTNESS);
  neoPixel.setPixelColor(0, neoPixel.Color(0, 0, 255)); // blue inicial
  neoPixel.show();
#else
  // ESP32 padrão: Inicializa LED built-in
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
#endif

  Serial.begin(115200);
  while (!Serial) { delay(10); } // USB CDC (S3) — waits for connection to see logs

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

  switch (OUTPUT_FORMAT) {
    case OutputFormat::LOG:
      printFilterStatus();
      break;
    case OutputFormat::CSV:
      Serial.println("time,manufacturer,deviceType,addr,rssi,advType,isConnectable,isScannable,dataType,dataHex");
      break;
    case OutputFormat::YAML:
      Serial.println("---");
      break;
  }
  Serial.flush();
  delay(5000);

  // Start continuous scanning (0 = no timeout). Non-blocking; callbacks will be called.
  if (!scan->start(0, false)) {
    signalError();
  } else {
    signalSuccess();
  }
}


void loop() {
  delay(100);
}
