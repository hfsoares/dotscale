/// Limiares do fluxo do espresso. Valores do design; ajuste aqui se o hardware pedir.
class EspressoTuning {
  const EspressoTuning({
    this.stableWindow = const Duration(seconds: 1),
    this.stableRange = 0.3,
    this.stableMinSamples = 5,
    this.emptyBelow = 1.0,
    this.minObject = 5.0,
    this.matchTolerance = 1.5,
    this.groundsBelow = 3.0,
    this.groundsAbove = 1.0,
    this.minBeans = 3.0,
    this.dripWindow = const Duration(seconds: 1),
    this.dripMaxDip = 0.2,
    this.dripMinRise = 0.3,
    this.dripMinNet = 1.0,
    this.endWindow = const Duration(seconds: 4),
    this.endMinRise = 0.2,
    this.conflictWithin = 3.0,
  });

  /// Estável: amplitude ≤ [stableRange] em [stableWindow], com ≥ [stableMinSamples] leituras.
  final Duration stableWindow;
  final double stableRange;
  final int stableMinSamples;

  /// Vazia: estável com |peso| < [emptyBelow].
  final double emptyBelow;

  /// Só um peso estável ≥ [minObject] conta como objeto colocado; entre vazia e isso, nada muda.
  final double minObject;

  /// Um peso estável bate com um recipiente se estiver a ± [matchTolerance].
  final double matchTolerance;

  /// Copinho com pó: entre copinho + grãos − [groundsBelow] e copinho + grãos + [groundsAbove].
  final double groundsBelow;
  final double groundsAbove;

  /// Abaixo disso considera que não houve pesagem de grãos.
  final double minBeans;

  /// Primeiras gotas: em [dripWindow], sem queda > [dripMaxDip] abaixo do máximo,
  /// subida ≥ [dripMinRise] e líquido > [dripMinNet] no fim.
  final Duration dripWindow;
  final double dripMaxDip;
  final double dripMinRise;
  final double dripMinNet;

  /// Fim: o líquido não sobe mais que [endMinRise] em [endWindow].
  final Duration endWindow;
  final double endMinRise;

  /// No cadastro, avisa de recipientes a menos disso.
  final double conflictWithin;
}
