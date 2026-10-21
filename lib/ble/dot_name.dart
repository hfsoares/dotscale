/// A Dot anuncia `TIMEMORE_Dot...`; TES017 é o código de modelo dela.
bool isDotName(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('timemore_dot') || lower.contains('tes017');
}
