// Copy this file's content into your installed TFT_eSPI/User_Setup.h
// Typical locations:
//   Windows: Documents/Arduino/libraries/TFT_eSPI/User_Setup.h
//   Linux:   ~/Arduino/libraries/TFT_eSPI/User_Setup.h

#ifndef USER_SETUP_INFO
#define USER_SETUP_INFO "User_Setup for ESP32-C3 + GC9A01 240x240"
#endif

#define GC9A01_DRIVER

#define TFT_WIDTH  240
#define TFT_HEIGHT 240

// ESP32-C3 SPI pins (requested)
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

#define SPI_FREQUENCY       40000000
#define SPI_READ_FREQUENCY  20000000
