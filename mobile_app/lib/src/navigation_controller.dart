import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import 'config/app_constants.dart';
import 'models/navigation_models.dart';
import 'services/ble_navigation_service.dart';
import 'services/navigation_projection_service.dart';
import 'services/vietmap_directions_service.dart';

class NavigationController extends ChangeNotifier {
  NavigationController({
    BleNavigationService? bleService,
    VietmapDirectionsService? directionsService,
    NavigationProjectionService? projectionService,
  })  : _bleService = bleService ?? BleNavigationService(),
        _directionsService = directionsService ?? const VietmapDirectionsService(),
        _projectionService = projectionService ?? const NavigationProjectionService();

  final BleNavigationService _bleService;
  final VietmapDirectionsService _directionsService;
  final NavigationProjectionService _projectionService;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _headingSubscription;

  Position? currentPosition;
  RouteData? routeData;
  TftProjection currentProjection = const TftProjection(pointsX: [], pointsY: []);
  LatLng? destination;
  String? errorMessage;

  bool isInitialized = false;
  bool isFetchingRoute = false;
  bool isLocked = false;
  double unlockSliderValue = 0;
  double pixelsPerMeter = AppConstants.defaultPixelsPerMeter;
  double currentHeading = 0;
  int currentSpeedKmh = 0;

  DateTime? _lastRouteRefreshAt;
  Position? _lastRouteRefreshOrigin;

  bool get isBleConnected => _bleService.isConnected;

  Future<void> initialize() async {
    if (isInitialized) {
      return;
    }

    try {
      await _requestPermissions();
      await _bleService.start();
      currentPosition = await Geolocator.getCurrentPosition();
      currentSpeedKmh = _speedFromPosition(currentPosition!);
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_handlePositionUpdate);
      _headingSubscription = FlutterCompass.events?.listen(_handleHeadingUpdate);
      isInitialized = true;
      notifyListeners();
    } catch (error) {
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> loadRoute({
    required double latitude,
    required double longitude,
    required String apiKey,
  }) async {
    final position = currentPosition;
    if (position == null) {
      errorMessage = 'Current location is not ready yet.';
      notifyListeners();
      return;
    }
    if (apiKey.isEmpty) {
      errorMessage = 'Provide VIETMAP_API_KEY before loading a route.';
      notifyListeners();
      return;
    }

    destination = LatLng(latitude, longitude);
    await _refreshRoute(position: position, apiKey: apiKey);
  }

  void updatePixelsPerMeter(double value) {
    pixelsPerMeter = value;
    _syncProjection();
    notifyListeners();
  }

  void lockScreen() {
    isLocked = true;
    unlockSliderValue = 0;
    notifyListeners();
  }

  void updateUnlockSlider(double value) {
    unlockSliderValue = value;
    if (value >= 1) {
      isLocked = false;
      unlockSliderValue = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    final positionSubscription = _positionSubscription;
    final headingSubscription = _headingSubscription;
    if (positionSubscription != null) {
      unawaited(positionSubscription.cancel());
    }
    if (headingSubscription != null) {
      unawaited(headingSubscription.cancel());
    }
    unawaited(_bleService.dispose());
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled.');
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied ||
          requested == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }
    }
  }

  void _handlePositionUpdate(Position position) {
    currentPosition = position;
    currentSpeedKmh = _speedFromPosition(position);
    errorMessage = null;
    _syncProjection();
    if (_shouldRefreshRoute(position)) {
      unawaited(_refreshRoute(
        position: position,
        apiKey: AppConstants.vietmapApiKey,
      ));
    } else {
      unawaited(_pushBleUpdate());
    }
    notifyListeners();
  }

  void _handleHeadingUpdate(CompassEvent event) {
    final heading = event.heading;
    if (heading == null || heading.isNaN) {
      return;
    }

    currentHeading = _normalizeHeading(heading);
    _syncProjection();
    unawaited(_pushBleUpdate());
    notifyListeners();
  }

  bool _shouldRefreshRoute(Position position) {
    if (destination == null || isFetchingRoute || AppConstants.vietmapApiKey.isEmpty) {
      return false;
    }
    if (_lastRouteRefreshAt == null || _lastRouteRefreshOrigin == null) {
      return true;
    }

    final distance = Geolocator.distanceBetween(
      _lastRouteRefreshOrigin!.latitude,
      _lastRouteRefreshOrigin!.longitude,
      position.latitude,
      position.longitude,
    );
    final age = DateTime.now().difference(_lastRouteRefreshAt!);
    return distance >= 25 || age >= const Duration(seconds: 15);
  }

  Future<void> _refreshRoute({
    required Position position,
    required String apiKey,
  }) async {
    if (destination == null || apiKey.isEmpty || isFetchingRoute) {
      return;
    }

    isFetchingRoute = true;
    errorMessage = null;
    notifyListeners();
    try {
      routeData = await _directionsService.fetchRoute(
        apiKey: apiKey,
        origin: LatLng(position.latitude, position.longitude),
        destination: destination!,
      );
      _lastRouteRefreshAt = DateTime.now();
      _lastRouteRefreshOrigin = position;
      _syncProjection();
      await _pushBleUpdate();
    } catch (error) {
      errorMessage = '$error';
    } finally {
      isFetchingRoute = false;
      notifyListeners();
    }
  }

  void _syncProjection() {
    final position = currentPosition;
    final route = routeData;
    if (position == null || route == null) {
      currentProjection = const TftProjection(pointsX: [], pointsY: []);
      return;
    }

    currentProjection = _projectionService.projectRoute(
      userPosition: position,
      headingDegrees: currentHeading,
      routeGeometry: route.geometry,
      pixelsPerMeter: pixelsPerMeter,
    );
  }

  Future<void> _pushBleUpdate() async {
    final route = routeData;
    if (route == null) {
      return;
    }

    final now = DateTime.now();
    final payload = BleNavPayload(
      turnIconCode: route.instruction.turnIconCode,
      distanceM: route.instruction.distanceM,
      hour: now.hour,
      minute: now.minute,
      speedLimit: 0,
      currentSpeed: currentSpeedKmh,
      pointsX: currentProjection.pointsX,
      pointsY: currentProjection.pointsY,
    );

    await _bleService.writePayload(payload.toBytes());
  }

  int _speedFromPosition(Position position) {
    return max(0, (position.speed * 3.6).round());
  }

  double _normalizeHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
