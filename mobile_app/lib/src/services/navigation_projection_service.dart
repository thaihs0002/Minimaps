import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import '../config/app_constants.dart';
import '../models/navigation_models.dart';

class NavigationProjectionService {
  const NavigationProjectionService();

  TftProjection projectRoute({
    required Position userPosition,
    required double headingDegrees,
    required List<LatLng> routeGeometry,
    double pixelsPerMeter = AppConstants.defaultPixelsPerMeter,
  }) {
    if (routeGeometry.isEmpty) {
      return const TftProjection(pointsX: [], pointsY: []);
    }

    final nearestIndex = _nearestPointIndex(userPosition, routeGeometry);
    final nextPoints = routeGeometry
        .skip(nearestIndex)
        .take(AppConstants.maxRoutePoints)
        .toList(growable: false);

    final headingRadians = headingDegrees * pi / 180;
    final cosHeading = cos(headingRadians);
    final sinHeading = sin(headingRadians);
    // Approximate meters per degree at the equator; longitude is adjusted
    // below by the current latitude cosine factor.
    final metersPerDegreeLat = AppConstants.metersPerDegreeAtEquator;
    final metersPerDegreeLon =
        AppConstants.metersPerDegreeAtEquator *
            cos(userPosition.latitude * pi / 180).abs();

    final pointsX = <int>[];
    final pointsY = <int>[];

    for (final point in nextPoints) {
      final dxMeters =
          (point.longitude - userPosition.longitude) * metersPerDegreeLon;
      final dyMeters =
          (point.latitude - userPosition.latitude) * metersPerDegreeLat;

      final rightMeters = (dxMeters * cosHeading) - (dyMeters * sinHeading);
      final forwardMeters = (dxMeters * sinHeading) + (dyMeters * cosHeading);

      final screenX =
          (AppConstants.mapAnchorX + (rightMeters * pixelsPerMeter)).round();
      final screenY =
          (AppConstants.mapAnchorY - (forwardMeters * pixelsPerMeter)).round();

      pointsX.add(screenX.clamp(0, AppConstants.mapWidth - 1));
      pointsY.add(screenY.clamp(0, AppConstants.mapHeight - 1));
    }

    return TftProjection(pointsX: pointsX, pointsY: pointsY);
  }

  int _nearestPointIndex(Position userPosition, List<LatLng> routeGeometry) {
    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < routeGeometry.length; i++) {
      final point = routeGeometry[i];
      final distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }
}
