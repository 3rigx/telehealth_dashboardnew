/// Single source of truth for the plantar-pressure hardware layout on the
/// dashboard side. Mirrors Unity's `PressureConfig`.
///
/// The study runs ONE insole on a fixed foot with four FSR pads. The live wire
/// message and each recording's manifest carry the authoritative `foot` /
/// `insoleCount` for that session; these constants are the study defaults used
/// when a value is absent (e.g. the mock generator, or a label fallback).
///
/// Pad names are canonical and identical across firmware, wire, disk, and UI:
/// `toe, medial, lateral, heel` — never midInner/midOuter, never sensor1..4.
class PressureConfig {
  PressureConfig._();

  /// Study default. 1 = single insole; 2 = legacy left+right rig.
  static const int insoleCount = 1;

  /// Which foot the single insole is on. Fixed for the whole study.
  static const String foot = 'right';

  /// Canonical pad names in Arduino analog-pin order (A0..A3).
  static const List<String> channelNames = ['toe', 'medial', 'lateral', 'heel'];

  /// ADC full-scale (10-bit → 1023). Recorded raw values are 0..adcMax.
  static const int adcMax = 1023;

  /// A baseline with any pad above this was captured under load (foot already in
  /// the shoe) — mirrors Unity's PressureConfig.BaselineMaxAdc.
  static const int baselineMaxAdc = 80;

  static bool get isSingleFoot => insoleCount == 1;

  /// True when [foot] (or a session's foot value) is the left side.
  static bool isLeft(String? f) => (f ?? foot).toLowerCase() == 'left';
}
