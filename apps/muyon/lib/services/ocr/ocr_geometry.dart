import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef OcrPoint = math.Point<double>;

class DetectedLine {
  const DetectedLine(this.points, this.score);
  final List<OcrPoint> points;
  final double score;
}

double _cross(OcrPoint o, OcrPoint a, OcrPoint b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
List<OcrPoint> _hull(List<OcrPoint> points) {
  points.sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  final lower = <OcrPoint>[], upper = <OcrPoint>[];
  for (final point in points) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  for (final point in points.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

/// Connected binary contours, convex hull, minimum rotated rectangle, DB score,
/// and area/perimeter unclip. Output coordinates belong to the oriented image.
List<DetectedLine> detectBoxes(
  List<double> probability,
  int width,
  int height,
  int sourceWidth,
  int sourceHeight, {
  double threshold = .3,
  double boxThreshold = .6,
  double unclipRatio = 1.5,
  int maxCandidates = 1000,
}) {
  if (probability.length != width * height || width * height > 4000000) {
    throw ArgumentError('Invalid detection map');
  }
  final visited = Uint8List(probability.length),
      queue = Int32List(probability.length);
  final results = <DetectedLine>[];
  var candidates = 0;
  for (
    var start = 0;
    start < probability.length && candidates < maxCandidates;
    start++
  ) {
    if (visited[start] != 0 || probability[start] <= threshold) continue;
    var head = 0, tail = 1;
    queue[0] = start;
    visited[start] = 1;
    final boundary = <OcrPoint>[];
    while (head < tail) {
      final at = queue[head++], x = at % width, y = at ~/ width;
      var edge = false;
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1],
      ]) {
        final nx = x + d[0], ny = y + d[1];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          edge = true;
          continue;
        }
        final ni = ny * width + nx;
        if (probability[ni] <= threshold) {
          edge = true;
          continue;
        }
        if (visited[ni] == 0) {
          visited[ni] = 1;
          queue[tail++] = ni;
        }
      }
      if (edge) boundary.add(OcrPoint(x.toDouble(), y.toDouble()));
    }
    candidates++;
    if (boundary.length < 4) continue;
    final hull = _hull(boundary);
    if (hull.length < 3) continue;
    var bestArea = double.infinity,
        cosine = 1.0,
        sine = 0.0,
        minU = 0.0,
        maxU = 0.0,
        minV = 0.0,
        maxV = 0.0;
    for (var i = 0; i < hull.length; i++) {
      final a = hull[i],
          b = hull[(i + 1) % hull.length],
          angle = math.atan2(b.y - a.y, b.x - a.x),
          c = math.cos(angle),
          s = math.sin(angle);
      var loU = double.infinity,
          hiU = double.negativeInfinity,
          loV = double.infinity,
          hiV = double.negativeInfinity;
      for (final q in hull) {
        final u = q.x * c + q.y * s, v = -q.x * s + q.y * c;
        loU = math.min(loU, u);
        hiU = math.max(hiU, u);
        loV = math.min(loV, v);
        hiV = math.max(hiV, v);
      }
      final area = (hiU - loU) * (hiV - loV);
      if (area < bestArea) {
        bestArea = area;
        cosine = c;
        sine = s;
        minU = loU;
        maxU = hiU;
        minV = loV;
        maxV = hiV;
      }
    }
    final w = maxU - minU, h = maxV - minV;
    if (math.min(w, h) < 3) continue;
    var sum = 0.0, count = 0;
    final left = boundary.map((p) => p.x).reduce(math.min).floor(),
        right = boundary.map((p) => p.x).reduce(math.max).ceil();
    final top = boundary.map((p) => p.y).reduce(math.min).floor(),
        bottom = boundary.map((p) => p.y).reduce(math.max).ceil();
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        final u = x * cosine + y * sine, v = -x * sine + y * cosine;
        if (u >= minU && u <= maxU && v >= minV && v <= maxV) {
          sum += probability[y * width + x];
          count++;
        }
      }
    }
    if (count == 0 || sum / count < boxThreshold) continue;
    final offset = w * h * unclipRatio / (2 * (w + h));
    minU -= offset;
    maxU += offset;
    minV -= offset;
    maxV += offset;
    final points = [
      for (final q in [
        OcrPoint(minU, minV),
        OcrPoint(maxU, minV),
        OcrPoint(maxU, maxV),
        OcrPoint(minU, maxV),
      ])
        OcrPoint(
          ((q.x * cosine - q.y * sine) * sourceWidth / width)
              .clamp(0, sourceWidth - 1)
              .toDouble(),
          ((q.x * sine + q.y * cosine) * sourceHeight / height)
              .clamp(0, sourceHeight - 1)
              .toDouble(),
        ),
    ];
    points.sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    final upper = points.take(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    final lower = points.skip(2).toList()..sort((a, b) => b.x.compareTo(a.x));
    results.add(DetectedLine([...upper, ...lower], sum / count));
  }
  results.sort((a, b) {
    final dy = a.points.first.y - b.points.first.y;
    return dy.abs() < 10
        ? a.points.first.x.compareTo(b.points.first.x)
        : dy.sign.toInt();
  });
  return results;
}

/// Solves the projective transform from crop coordinates to source coordinates.
img.Image perspectiveCrop(img.Image source, List<OcrPoint> box) {
  double distance(OcrPoint a, OcrPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  final width = math
      .max(distance(box[0], box[1]), distance(box[2], box[3]))
      .round()
      .clamp(2, 4096);
  final height = math
      .max(distance(box[0], box[3]), distance(box[1], box[2]))
      .round()
      .clamp(2, 4096);
  final target = [
    OcrPoint(0, 0),
    OcrPoint(width - 1.0, 0),
    OcrPoint(width - 1.0, height - 1.0),
    OcrPoint(0, height - 1.0),
  ];
  final matrix = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final x = target[i].x, y = target[i].y, u = box[i].x, v = box[i].y;
    matrix.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    matrix.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (matrix[r][col].abs() > matrix[pivot][col].abs()) pivot = r;
    }
    final tmp = matrix[col];
    matrix[col] = matrix[pivot];
    matrix[pivot] = tmp;
    final div = matrix[col][col];
    if (div.abs() < 1e-10) throw StateError('Degenerate OCR quadrilateral');
    for (var c = col; c <= 8; c++) {
      matrix[col][c] /= div;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final scale = matrix[r][col];
      for (var c = col; c <= 8; c++) {
        matrix[r][c] -= scale * matrix[col][c];
      }
    }
  }
  final h = matrix.map((r) => r[8]).toList(),
      out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final divisor = h[6] * x + h[7] * y + 1,
          sx = (h[0] * x + h[1] * y + h[2]) / divisor,
          sy = (h[3] * x + h[4] * y + h[5]) / divisor;
      out.setPixel(
        x,
        y,
        source.getPixelInterpolate(
          sx,
          sy,
          interpolation: img.Interpolation.linear,
        ),
      );
    }
  }
  return height / width >= 1.5 ? img.copyRotate(out, angle: 90) : out;
}
