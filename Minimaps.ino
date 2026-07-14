/*
  Minimaps - ESP32-C3 + GC9A01 (240x240) Motorcycle Navigation Display

  Features:
  - BLE Server receives binary navigation payload from Flutter app.
  - Segmented double buffering:
      Zone A (0..149): 240x150 8-bit sprite for heading-up route map.
      Zone B (150..239): direct partial redraw for turn icon, distance, speed limit, time.
  - Software debounce button logic.

  IMPORTANT HARDWARE NOTE:
  - Requested pin map uses TFT_DC = GPIO2 and BUTTON = GPIO2 simultaneously.
  - One GPIO cannot be both TFT D/C control and a reliable button input at the same time.
  - This sketch keeps the requested TFT pin map for display stability.
  - Button logic is included; by default BUTTON_PIN is moved to GPIO4 to avoid conflict.
    If you really force BUTTON_PIN to 2, TFT behavior may be unstable.
*/

#include <Arduino.h>

// -----------------------------
// TFT_eSPI compile-time config
// -----------------------------
// This allows the sketch to build even if TFT_eSPI's global User_Setup.h is not yet edited.
// You still should update TFT_eSPI/User_Setup.h in Arduino libraries (template provided separately).
#define USER_SETUP_LOADED
#define GC9A01_DRIVER

#define TFT_WIDTH 240
#define TFT_HEIGHT 240

#define TFT_MOSI 7
#define TFT_SCLK 6
#define TFT_CS   10
#define TFT_DC   2
#define TFT_RST  -1
#define TFT_MISO -1

#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define LOAD_FONT6
#define LOAD_FONT7
#define LOAD_FONT8
#define LOAD_GFXFF
#define SMOOTH_FONT

#define SPI_FREQUENCY  40000000
#define SPI_READ_FREQUENCY  20000000

#include <TFT_eSPI.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// -----------------------------
// Pin map
// -----------------------------
static constexpr int8_t BACKLIGHT_PIN = 3;
// Requested: GPIO2, but conflicts with TFT_DC=2. Use GPIO4 as safe default.
static constexpr int8_t BUTTON_PIN = 4;

// -----------------------------
// BLE UUIDs (custom)
// -----------------------------
static const char* BLE_DEVICE_NAME = "MiniMaps-ESP32C3";
static const char* SERVICE_UUID = "1d3b8a53-7f52-4e2f-b8b9-12089d3e0001";
static const char* CHAR_UUID    = "1d3b8a53-7f52-4e2f-b8b9-12089d3e0002";

// -----------------------------
// Display objects
// -----------------------------
TFT_eSPI tft = TFT_eSPI();
TFT_eSprite mapSprite = TFT_eSprite(&tft);

// -----------------------------
// Navigation data model
// -----------------------------
static constexpr uint8_t MAX_POINTS = 10;

struct NavData {
  uint8_t turnIconCode = 3; // 1=left, 2=right, 3=straight
  uint16_t distanceM = 0;
  uint8_t hour = 0;
  uint8_t minute = 0;
  uint8_t speedLimit = 0;
  uint8_t pointsX[MAX_POINTS] = {0};
  uint8_t pointsY[MAX_POINTS] = {0};
  uint8_t pointCount = 0;
};

volatile bool newDataReceived = false;
portMUX_TYPE navMux = portMUX_INITIALIZER_UNLOCKED;
NavData navData;

// Cache for Zone B partial redraw
uint8_t prevTurnIconCode = 255;
uint16_t prevDistanceM = 65535;
uint8_t prevHour = 255;
uint8_t prevMinute = 255;
uint8_t prevSpeedLimit = 255;

// -----------------------------
// Button debounce state
// -----------------------------
bool lastButtonStableState = HIGH;
bool lastButtonRawState = HIGH;
uint32_t lastDebounceMs = 0;
static constexpr uint16_t DEBOUNCE_MS = 40;

// -----------------------------
// UI helpers
// -----------------------------
void drawBikeMarkerOnSprite() {
  const int cx = 120;
  const int tipY = 126;
  const int baseY = 145;
  mapSprite.fillTriangle(cx, tipY, cx - 9, baseY, cx + 9, baseY, TFT_CYAN);
  mapSprite.drawTriangle(cx, tipY, cx - 9, baseY, cx + 9, baseY, TFT_WHITE);
}

void drawTurnIconDirect(uint8_t iconCode) {
  const int x = 20;
  const int y = 182;
  const int s = 28;

  // Clear icon region first (partial redraw)
  tft.fillRect(4, 154, 48, 44, TFT_BLACK);

  switch (iconCode) {
    case 1: // Left
      tft.drawLine(x + s, y, x, y, TFT_GREEN);
      tft.drawLine(x, y, x + 8, y - 8, TFT_GREEN);
      tft.drawLine(x, y, x + 8, y + 8, TFT_GREEN);
      break;
    case 2: // Right
      tft.drawLine(x, y, x + s, y, TFT_GREEN);
      tft.drawLine(x + s, y, x + s - 8, y - 8, TFT_GREEN);
      tft.drawLine(x + s, y, x + s - 8, y + 8, TFT_GREEN);
      break;
    case 3: // Straight
    default:
      tft.drawLine(x + s / 2, y + 10, x + s / 2, y - 12, TFT_GREEN);
      tft.drawLine(x + s / 2, y - 12, x + s / 2 - 6, y - 6, TFT_GREEN);
      tft.drawLine(x + s / 2, y - 12, x + s / 2 + 6, y - 6, TFT_GREEN);
      break;
  }
}

void updateBottomInfo(const NavData& d, bool forceRedraw) {
  tft.setTextColor(TFT_WHITE, TFT_BLACK);

  if (forceRedraw || d.turnIconCode != prevTurnIconCode) {
    drawTurnIconDirect(d.turnIconCode);
    prevTurnIconCode = d.turnIconCode;
  }

  if (forceRedraw || d.distanceM != prevDistanceM) {
    tft.fillRect(56, 156, 176, 32, TFT_BLACK);
    tft.setTextDatum(TL_DATUM);
    tft.setTextSize(2);
    tft.drawString(String(d.distanceM) + " m", 60, 164, 4);
    prevDistanceM = d.distanceM;
  }

  if (forceRedraw || d.speedLimit != prevSpeedLimit) {
    tft.fillRect(56, 198, 100, 34, TFT_BLACK);
    tft.setTextSize(2);
    tft.drawString("SPD " + String(d.speedLimit), 60, 206, 2);
    prevSpeedLimit = d.speedLimit;
  }

  if (forceRedraw || d.hour != prevHour || d.minute != prevMinute) {
    tft.fillRect(156, 198, 80, 34, TFT_BLACK);
    char timeBuf[8];
    snprintf(timeBuf, sizeof(timeBuf), "%02u:%02u", d.hour, d.minute);
    tft.setTextSize(2);
    tft.drawString(timeBuf, 166, 206, 2);
    prevHour = d.hour;
    prevMinute = d.minute;
  }
}

void updateMapZone(const NavData& d) {
  mapSprite.fillSprite(TFT_BLACK);

  if (d.pointCount >= 2) {
    for (uint8_t i = 0; i < d.pointCount - 1; i++) {
      int x1 = d.pointsX[i];
      int y1 = d.pointsY[i];
      int x2 = d.pointsX[i + 1];
      int y2 = d.pointsY[i + 1];

      // Keep route in Zone A bounds
      x1 = constrain(x1, 0, 239);
      x2 = constrain(x2, 0, 239);
      y1 = constrain(y1, 0, 149);
      y2 = constrain(y2, 0, 149);

      mapSprite.drawLine(x1, y1, x2, y2, TFT_WHITE);
    }
  }

  drawBikeMarkerOnSprite();
  mapSprite.pushSprite(0, 0);
}

void drawBottomFrame() {
  // Divider line between map and info zones
  tft.drawFastHLine(0, 150, 240, TFT_DARKGREY);
}

// -----------------------------
// BLE callbacks
// -----------------------------
class NavCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    std::string value = pCharacteristic->getValue();

    // Minimum payload length: 6 bytes
    if (value.length() < 6) {
      return;
    }

    NavData temp;
    const uint8_t* b = reinterpret_cast<const uint8_t*>(value.data());

    temp.turnIconCode = b[0];
    temp.distanceM = static_cast<uint16_t>(b[1]) | (static_cast<uint16_t>(b[2]) << 8);

    temp.hour = (b[3] <= 23) ? b[3] : 0;
    temp.minute = (b[4] <= 59) ? b[4] : 0;
    temp.speedLimit = b[5];

    size_t coordBytes = value.length() - 6;
    size_t pairCount = coordBytes / 2;
    if (pairCount > MAX_POINTS) {
      pairCount = MAX_POINTS;
    }

    temp.pointCount = static_cast<uint8_t>(pairCount);
    for (uint8_t i = 0; i < temp.pointCount; i++) {
      temp.pointsX[i] = b[6 + i * 2];
      temp.pointsY[i] = b[6 + i * 2 + 1];
    }

    portENTER_CRITICAL(&navMux);
    navData = temp;
    newDataReceived = true;
    portEXIT_CRITICAL(&navMux);
  }
};

class NavServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    Serial.println("BLE client connected");
    (void)pServer;
  }

  void onDisconnect(BLEServer* pServer) override {
    Serial.println("BLE client disconnected, restart advertising");
    pServer->startAdvertising();
  }
};

void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new NavServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic* pCharacteristic = pService->createCharacteristic(
    CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ
  );

  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new NavCharacteristicCallbacks());
  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started");
}

// -----------------------------
// Arduino setup / loop
// -----------------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\nMinimaps booting...");

  pinMode(BACKLIGHT_PIN, OUTPUT);
  digitalWrite(BACKLIGHT_PIN, HIGH); // Ensure TFT backlight is ON

  if (BUTTON_PIN == TFT_DC) {
    Serial.println("WARNING: BUTTON_PIN conflicts with TFT_DC. Change button GPIO for reliable input.");
  }
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  tft.init();
  tft.setRotation(0);
  tft.fillScreen(TFT_BLACK);

  mapSprite.setColorDepth(8);
  if (mapSprite.createSprite(240, 150) == nullptr) {
    Serial.println("ERROR: mapSprite allocation failed (RAM too low).");
  }

  drawBottomFrame();

  // Initial UI render
  NavData initial;
  updateMapZone(initial);
  updateBottomInfo(initial, true);

  setupBLE();

  Serial.println("Setup complete");
}

void loop() {
  // 1) Non-blocking button debounce
  bool raw = digitalRead(BUTTON_PIN);
  if (raw != lastButtonRawState) {
    lastDebounceMs = millis();
    lastButtonRawState = raw;
  }

  if ((millis() - lastDebounceMs) > DEBOUNCE_MS) {
    if (lastButtonStableState != raw) {
      lastButtonStableState = raw;
      if (lastButtonStableState == LOW) {
        Serial.println("Button pressed (debounced)");
      }
    }
  }

  // 2) UI refresh only when new BLE data arrives
  if (newDataReceived) {
    NavData localCopy;
    portENTER_CRITICAL(&navMux);
    localCopy = navData;
    newDataReceived = false;
    portEXIT_CRITICAL(&navMux);

    updateMapZone(localCopy);           // Zone A sprite redraw + push
    updateBottomInfo(localCopy, false); // Zone B partial redraw only if value changed
  }

  delay(2); // Tiny yield to keep loop responsive
}
