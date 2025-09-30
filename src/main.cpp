#include <Arduino.h>
#include <NimBLEDevice.h>

// RSSI filter (minimum signal strength to process devices)
// Can be set via build flags, default is -80 for maximum range
#ifndef MIN_RSSI_FLAG
  #define MIN_RSSI_FLAG -80
#endif
constexpr int MIN_RSSI = MIN_RSSI_FLAG;

// Callback de Scan - Versão simplificada
class MyAdvertisedDeviceCallbacks : public NimBLEScanCallbacks {
public:
  void onResult(const NimBLEAdvertisedDevice* dev) override {
    // Filter by RSSI - ignore devices with weak signal
    if (dev->getRSSI() < MIN_RSSI) {
      return;
    }

    // Print device information using toString()
    Serial.printf("%s\n----\n", dev->toString().c_str());
    delay(5); // Add delay to prevent Serial buffer overload
  }
};

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(10); } // Wait for serial connection

  // Initialize NimBLE
  NimBLEDevice::init("FindMyScanner");
  NimBLEDevice::setSecurityAuth(false, false, false);

  NimBLEScan* scan = NimBLEDevice::getScan();
  scan->setScanCallbacks(new MyAdvertisedDeviceCallbacks(), /*wantDuplicates=*/true);

  // Active scan to get scan responses (more data)
  scan->setActiveScan(true);

  // Aggressive scan parameters for maximum capture (units of 0.625 ms)
  // Minimum interval/window for fastest scanning
  scan->setInterval(16);  // 10ms (16 * 0.625ms) - minimum allowed
  scan->setWindow(16);    // 10ms (16 * 0.625ms) - 100% duty cycle

  // Capture all advertisements including duplicates
  scan->setDuplicateFilter(false);
  scan->setLimitedOnly(false);

  // Set maximum scan response timeout
  scan->setMaxResults(0); // 0 = unlimited results

  Serial.println("Starting BLE scanner...");
  Serial.flush();

  // Start continuous scanning (0 = no timeout)
  if (!scan->start(0, false)) {
    Serial.println("Failed to start scan!");
    while(1) delay(1000); // Stay in error state
  } else {
    Serial.println("Scan started successfully!");
  }
}

void loop() {
  delay(100);
}
