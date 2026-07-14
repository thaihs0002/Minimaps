import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import 'config/app_constants.dart';
import 'models/navigation_models.dart';
import 'navigation_controller.dart';
import 'widgets/pocket_lock_overlay.dart';

class MinimapsApp extends StatelessWidget {
  const MinimapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimaps',
      theme: ThemeData.dark(),
      home: const NavigationHomePage(),
    );
  }
}

class NavigationHomePage extends StatefulWidget {
  const NavigationHomePage({super.key});

  @override
  State<NavigationHomePage> createState() => _NavigationHomePageState();
}

class _NavigationHomePageState extends State<NavigationHomePage> {
  final NavigationController _navigationController = NavigationController();
  final TextEditingController _latController = TextEditingController(
    text: '${AppConstants.defaultDestinationLat}',
  );
  final TextEditingController _lngController = TextEditingController(
    text: '${AppConstants.defaultDestinationLng}',
  );

  VietmapController? _mapController;
  Line? _routeLine;
  String _routeSignature = '';

  @override
  void initState() {
    super.initState();
    _navigationController.addListener(_handleControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationController.initialize();
    });
  }

  @override
  void dispose() {
    _navigationController.removeListener(_handleControllerUpdate);
    scheduleMicrotask(() {
      _navigationController.close();
    });
    _navigationController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _handleControllerUpdate() async {
    final mapController = _mapController;
    final position = _navigationController.currentPosition;
    if (mapController != null && position != null) {
      await mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16,
            tilt: 45,
            bearing: _navigationController.currentHeading,
          ),
        ),
      );
    }

    final route = _navigationController.routeData;
    if (mapController == null || route == null || route.geometry.isEmpty) {
      return;
    }

    final newSignature = route.geometry
        .take(6)
        .map((point) => '${point.latitude},${point.longitude}')
        .join('|');
    if (newSignature == _routeSignature) {
      return;
    }

    if (_routeLine != null) {
      await mapController.removeLine(_routeLine!);
    }
    _routeLine = await mapController.addLine(
      LineOptions(
        geometry: route.geometry,
        lineColor: '#00E5FF',
        lineWidth: 5,
        lineOpacity: 0.9,
      ),
    );
    _routeSignature = newSignature;
  }

  Future<void> _loadRoute() async {
    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lngController.text.trim());
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destination coordinates are invalid.')),
      );
      return;
    }

    await _navigationController.loadRoute(
      latitude: latitude,
      longitude: longitude,
      apiKey: AppConstants.vietmapApiKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _navigationController,
      builder: (context, _) {
        final position = _navigationController.currentPosition;
        final projection = _navigationController.currentProjection;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Minimaps Rider Nav'),
            actions: [
              IconButton(
                onPressed: _navigationController.lockScreen,
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Lock Screen',
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: position == null
                        ? const Center(child: CircularProgressIndicator())
                        : Stack(
                            children: [
                              VietmapGL(
                                styleString: AppConstants.minimalMapStyle(
                                  AppConstants.vietmapApiKey,
                                ),
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(
                                    position.latitude,
                                    position.longitude,
                                  ),
                                  zoom: 16,
                                  tilt: 45,
                                ),
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                  _handleControllerUpdate();
                                },
                              ),
                              if (AppConstants.vietmapApiKey.isEmpty)
                                const Align(
                                  alignment: Alignment.topCenter,
                                  child: Card(
                                    margin: EdgeInsets.all(16),
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        'Missing VIETMAP_API_KEY dart-define.',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  _ControlPanel(
                    latitudeController: _latController,
                    longitudeController: _lngController,
                    controller: _navigationController,
                    projection: projection,
                    onLoadRoute: _loadRoute,
                  ),
                ],
              ),
              if (_navigationController.isLocked)
                PocketLockOverlay(
                  value: _navigationController.unlockSliderValue,
                  onChanged: _navigationController.updateUnlockSlider,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.latitudeController,
    required this.longitudeController,
    required this.controller,
    required this.projection,
    required this.onLoadRoute,
  });

  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final NavigationController controller;
  final TftProjection projection;
  final Future<void> Function() onLoadRoute;

  @override
  Widget build(BuildContext context) {
    final route = controller.routeData;

    return Material(
      color: const Color(0xFF121212),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Destination lat',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Destination lng',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: controller.isFetchingRoute ? null : onLoadRoute,
                    child: const Text('Route'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatusTile(
                      label: 'BLE',
                      value: controller.isBleConnected ? 'Connected' : 'Scanning',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatusTile(
                      label: 'Turn',
                      value: route?.instruction.turnIconCode.name ?? '--',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatusTile(
                      label: 'Distance',
                      value: route == null ? '--' : '${route.instruction.distanceM} m',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatusTile(
                      label: 'Speed',
                      value: '${controller.currentSpeedKmh} km/h',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Zoom scale'),
                  Expanded(
                    child: Slider(
                      min: 0.5,
                      max: 4,
                      divisions: 35,
                      value: controller.pixelsPerMeter,
                      label: controller.pixelsPerMeter.toStringAsFixed(1),
                      onChanged: controller.updatePixelsPerMeter,
                    ),
                  ),
                  Text('${controller.pixelsPerMeter.toStringAsFixed(1)} px/m'),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'pointsX: ${projection.pointsX.join(', ')}\n'
                  'pointsY: ${projection.pointsY.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    controller.errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
