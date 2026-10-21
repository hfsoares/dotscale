/// CRC-16/MODBUS (init 0xFFFF, poly refletido 0xA001), usado nos frames da Dot.
int crc16Modbus(List<int> bytes) {
  var crc = 0xFFFF;
  for (final b in bytes) {
    crc ^= b & 0xFF;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc;
}
