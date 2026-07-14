class AppConstants {
  static const vietmapApiKey = String.fromEnvironment('VIETMAP_API_KEY');

  static const bleDeviceName = 'MiniMaps-ESP32C3';
  static const bleServiceUuid = '1d3b8a53-7f52-4e2f-b8b9-12089d3e0001';
  static const bleCharacteristicUuid = '1d3b8a53-7f52-4e2f-b8b9-12089d3e0002';

  static const mapAnchorX = 120;
  static const mapAnchorY = 135;
  static const mapWidth = 240;
  static const mapHeight = 150;
  static const maxRoutePoints = 10;
  static const defaultPixelsPerMeter = 1.5;

  static const defaultDestinationLat = 10.77653;
  static const defaultDestinationLng = 106.70098;

  static String minimalMapStyle(String apiKey) =>
      'https://maps.vietmap.vn/maps/styles/lm/style.json?apikey=$apiKey';
}
