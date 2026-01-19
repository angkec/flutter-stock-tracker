import 'dart:math';

/// 解码 TDX 协议中的成交量编码
/// 这是通达信特有的浮点数编码格式
double decodeVolume(int ivol) {
  if (ivol == 0) return 0.0;

  final logpoint = ivol >> 24; // [3]
  final hleax = (ivol >> 16) & 0xFF; // [2]
  final lheax = (ivol >> 8) & 0xFF; // [1]
  final lleax = ivol & 0xFF; // [0]

  final dwEcx = logpoint * 2 - 0x7F;
  final dwEdx = logpoint * 2 - 0x86;
  final dwEsi = logpoint * 2 - 0x8E;
  final dwEax = logpoint * 2 - 0x96;

  double dblXmm6;
  if (dwEcx < 0) {
    dblXmm6 = 1.0 / pow(2.0, -dwEcx);
  } else {
    dblXmm6 = pow(2.0, dwEcx).toDouble();
  }

  double dblXmm4;
  if (hleax > 0x80) {
    final dwtmpeax = dwEdx + 1;
    final tmpdblXmm3 = pow(2.0, dwtmpeax).toDouble();
    var dblXmm0 = pow(2.0, dwEdx).toDouble() * 128.0;
    dblXmm0 += (hleax & 0x7F) * tmpdblXmm3;
    dblXmm4 = dblXmm0;
  } else {
    double dblXmm0;
    if (dwEdx >= 0) {
      dblXmm0 = pow(2.0, dwEdx).toDouble() * hleax;
    } else {
      dblXmm0 = (1.0 / pow(2.0, -dwEdx)) * hleax;
    }
    dblXmm4 = dblXmm0;
  }

  var dblXmm3 = pow(2.0, dwEsi).toDouble() * lheax;
  var dblXmm1 = pow(2.0, dwEax).toDouble() * lleax;

  if ((hleax & 0x80) != 0) {
    dblXmm3 *= 2.0;
    dblXmm1 *= 2.0;
  }

  return dblXmm6 + dblXmm4 + dblXmm3 + dblXmm1;
}
