import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import '../models/navigation_models.dart';

class VietmapDirectionsService {
  const VietmapDirectionsService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<RouteData> fetchRoute({
    required String apiKey,
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.parse(
      'https://maps.vietmap.vn/api/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&steps=true&geometries=geojson&access_token=$apiKey',
    );

    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Directions request failed: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['code'] != 'Ok') {
        throw Exception(decoded['message'] ?? 'Directions API returned an error');
      }

      final routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw Exception('No route returned from Vietmap');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.isEmpty) {
        throw Exception('Route geometry is empty');
      }

      final points = coordinates
          .map((coordinate) {
            final pair = coordinate as List<dynamic>;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          })
          .toList(growable: false);

      final legs = route['legs'] as List<dynamic>?;
      final firstLeg = legs?.isNotEmpty == true
          ? legs!.first as Map<String, dynamic>
          : <String, dynamic>{};
      final steps = firstLeg['steps'] as List<dynamic>?;
      final firstStep = steps?.isNotEmpty == true
          ? steps!.first as Map<String, dynamic>
          : <String, dynamic>{};
      final maneuver = firstStep['maneuver'] as Map<String, dynamic>?;
      final distanceM =
          ((firstStep['distance'] ?? route['distance'] ?? 0) as num).round();

      return RouteData(
        geometry: points,
        instruction: RouteInstruction(
          turnIconCode: TurnIconCode.fromManeuver(maneuver),
          distanceM: distanceM,
        ),
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
