/// Relatórios que a Dot envia por FFF1 (classes 0x01 e 0x02).
sealed class DotEvent {
  const DotEvent();
}

final class WeightReading extends DotEvent {
  final double grams;
  final double flowGramsPerSecond;
  final int timerSeconds;
  final bool overload;

  const WeightReading({
    required this.grams,
    required this.flowGramsPerSecond,
    required this.timerSeconds,
    required this.overload,
  });
}

final class BatteryReading extends DotEvent {
  final int percent;

  const BatteryReading(this.percent);
}

final class UnknownReport extends DotEvent {
  final int frameClass;
  final int type;
  final List<int> payload;

  const UnknownReport(this.frameClass, this.type, this.payload);
}
