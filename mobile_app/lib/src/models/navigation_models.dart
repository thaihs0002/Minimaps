import 'dart:math';
import 'dart:typed_data';

import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

enum TurnIconCode {
  left(1),
  right(2),
  straight(3);

  const TurnIconCode(this.code);

  final int code;

  static TurnIconCode fromManeuver(Map<String, dynamic>? maneuver) {
    final modifier = [
      maneuver?['modifier'],
      maneuver?['type'],
      maneuver?['instruction'],
    ].whereType<String>().join(' ').toLowerCase();

    if (modifier.contains('left')) {
      return TurnIconCode.left;
    }
    if (modifier.contains('right')) {
      return TurnIconCode.right;
    }
    return TurnIconCode.straight;
  }
}

class RouteInstruction {
  const RouteInstruction({
    required this.turnIconCode,
    required this.distanceM,
  });

  final TurnIconCode turnIconCode;
  final int distanceM;
}

class RouteData {
  const RouteData({
    required this.geometry,
    required this.instruction,
  });

  final List<LatLng> geometry;
  final RouteInstruction instruction;
}

class TftProjection {
  const TftProjection({
    required this.pointsX,
    required this.pointsY,
  });

  final List<int> pointsX;
  final List<int> pointsY;

  int get pointCount => min(pointsX.length, pointsY.length);
}

class BleNavPayload {
  const BleNavPayload({
    required this.turnIconCode,
    required this.distanceM,
    required this.hour,
    required this.minute,
    required this.speedLimit,
    required this.currentSpeed,
    required this.pointsX,
    required this.pointsY,
  });

  final TurnIconCode turnIconCode;
  final int distanceM;
  final int hour;
  final int minute;
  final int speedLimit;
  final int currentSpeed;
  final List<int> pointsX;
  final List<int> pointsY;

  Uint8List toBytes() {
    final pairCount = min(pointsX.length, pointsY.length);
    final payload = Uint8List(7 + pairCount * 2);
    payload[0] = turnIconCode.code;
    payload[1] = distanceM & 0xFF;
    payload[2] = (distanceM >> 8) & 0xFF;
    payload[3] = hour.clamp(0, 23).toInt();
    payload[4] = minute.clamp(0, 59).toInt();
    payload[5] = speedLimit.clamp(0, 255).toInt();
    payload[6] = currentSpeed.clamp(0, 255).toInt();

    for (var i = 0; i < pairCount; i++) {
      payload[7 + i * 2] = pointsX[i].clamp(0, 255).toInt();
      payload[8 + i * 2] = pointsY[i].clamp(0, 255).toInt();
    }
    return payload;
  }
}
