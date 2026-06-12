import 'package:audio_dashcam/src/models/geo_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tag = GeoTag(
    latitude: 37.422100,
    longitude: -122.084000,
    accuracyMeters: 3.7,
    capturedAtUtc: DateTime.utc(2026, 6, 11, 17, 30, 5),
    altitudeMeters: 12.5,
    source: 'gps',
  );

  test('JSON round-trips without loss', () {
    final restored = GeoTag.fromJson(tag.toJson());
    expect(restored.latitude, tag.latitude);
    expect(restored.longitude, tag.longitude);
    expect(restored.accuracyMeters, tag.accuracyMeters);
    expect(restored.capturedAtUtc, tag.capturedAtUtc);
    expect(restored.altitudeMeters, tag.altitudeMeters);
    expect(restored.source, tag.source);
  });

  test('canonical evidence string is stable and fixed-precision', () {
    expect(
      tag.canonicalEvidenceString(),
      'lat=37.422100|lon=-122.084000|acc=3.70|at=2026-06-11T17:30:05.000Z|src=gps',
    );
  });

  test('accuracy label rounds to whole metres', () {
    expect(tag.accuracyLabel, '±4 m');
  });

  test('optional fields are omitted from JSON when null', () {
    final minimal = GeoTag(
      latitude: 1,
      longitude: 2,
      accuracyMeters: 5,
      capturedAtUtc: DateTime.utc(2026),
    );
    final json = minimal.toJson();
    expect(json.containsKey('altitudeMeters'), isFalse);
    expect(json.containsKey('headingDegrees'), isFalse);
  });
}
