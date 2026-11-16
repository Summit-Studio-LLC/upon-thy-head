import 'dart:math' as math;

const double deg = math.pi / 180;
const double tau = math.pi * 2;

/// A direction on the celestial sphere as a unit vector.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  factory Vec3.radec(double ra, double dec) =>
      Vec3(math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec));

  final double x, y, z;
}

/// Where on Earth a blessing was given. Only ever used to find its place in the sky.
class Place {
  const Place(this.lat, this.lon);

  /// Degrees north and degrees east.
  final double lat, lon;
}

/// The rule: a blessing sits at the point of sky that was straight overhead
/// at the place and minute it was given. Right ascension is the local sidereal
/// time; declination is the latitude.
({double ra, double dec}) zenith(DateTime utc, Place place) {
  final jd = utc.millisecondsSinceEpoch / 864e5 + 2440587.5;
  final gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0);
  final lst = ((gmst + place.lon) % 360 + 360) % 360;
  return (ra: lst * deg, dec: place.lat * deg);
}

double easeInOutCubic(double t) => t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
