String _oneDecimal(double v) {
  final s = v.toStringAsFixed(1);
  return s == '-0.0' ? '0.0' : s;
}

String formatGrams(double g) => '${_oneDecimal(g)} g';

String formatFlow(double gps) => '${_oneDecimal(gps)} g/s';

String formatRatio(double beverage, double dose) => '1:${_oneDecimal(beverage / dose)}';

String formatSeconds(Duration d) => '${_oneDecimal(d.inMilliseconds / 1000)} s';
