String _oneDecimal(double v) {
  final s = v.toStringAsFixed(1);
  return s == '-0.0' ? '0.0' : s;
}

String formatGrams(double g) => '${_oneDecimal(g)} g';

String formatFlow(double gps) => '${_oneDecimal(gps)} g/s';
