/// Recipiente que o usuário cadastrou, reconhecido pelo peso vazio.
enum ContainerKind {
  doser('Dosímetro'),
  grinderCup('Copinho do moedor'),
  cup('Xícara');

  const ContainerKind(this.label);

  final String label;
}

class ScaleContainer {
  final String id;
  final String name;
  final ContainerKind kind;
  final double grams;

  const ScaleContainer({required this.id, required this.name, required this.kind, required this.grams});

  ScaleContainer copyWith({String? name}) => ScaleContainer(id: id, name: name ?? this.name, kind: kind, grams: grams);

  Map<String, Object> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'grams': grams};

  factory ScaleContainer.fromJson(Map<String, Object?> json) => ScaleContainer(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: ContainerKind.values.byName(json['kind'] as String),
    grams: (json['grams'] as num).toDouble(),
  );
}

/// Recipientes a menos de [within] gramas de [grams]: podem ser confundidos com ele.
List<ScaleContainer> containersNear(List<ScaleContainer> all, double grams, {double within = 3.0}) => [
  for (final c in all)
    if ((c.grams - grams).abs() < within) c,
];
