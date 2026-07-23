// lib/energy/modbus_registers.dart
//
// Module C (VoltMesh) — pure, deterministic Modbus register decoder. A block
// of 16-bit holding registers plus a per-device RegisterSpec map decodes into
// typed EnergyReadings. See docs/MODULE_C_DESIGN.md §1.
//
// This is the only Module C piece that is unit-testable with no hardware, and
// the place where every device quirk (16/32-bit width, signedness, 32-bit word
// order, fixed-point scale) lives as DATA, not code — so supporting a new
// inverter is a new map, not new logic.
//
// Web-safety: 32-bit values are assembled with multiplication, NOT `<<`. Under
// dart2js the shift operators coerce to signed 32-bit (0xFFFF << 16 becomes
// negative), which would corrupt any register pair; multiplication stays in the
// full double range (same spirit as invariant 8's ban on ByteData.setInt64).

/// Modbus value widths. 32-bit values span two consecutive registers.
enum RegisterType { u16, s16, u32, s32 }

/// Word order for a 32-bit value split across two registers. Deye and Growatt
/// firmwares differ, so it is per-register data.
enum WordOrder { highWordFirst, lowWordFirst }

class RegisterSpec {
  const RegisterSpec({
    required this.address,
    required this.metric,
    required this.type,
    this.scaleMilli = 1000,
    this.unit = '',
    this.wordOrder = WordOrder.highWordFirst,
  });

  /// Modbus register address of the (first) word.
  final int address;

  /// Metric name persisted as ResourceIntent.rawTextPayload.
  final String metric;

  final RegisterType type;

  /// Fixed-point scale ×1000: the real value is `raw * scaleMilli / 1000`.
  /// A register in units of 0.1 W → scaleMilli 100. Integer math keeps the
  /// decode deterministic across devices (no float rounding on the wire).
  final int scaleMilli;

  final String unit;

  /// Only consulted for 32-bit types.
  final WordOrder wordOrder;

  bool get isWide => type == RegisterType.u32 || type == RegisterType.s32;
}

class EnergyReading {
  const EnergyReading({
    required this.metric,
    required this.raw,
    required this.milliValue,
    required this.unit,
  });

  final String metric;

  /// Raw integer assembled from the register(s), before scaling.
  final int raw;

  /// `raw * scaleMilli` — the value in thousandths of [unit]. Divide by 1000
  /// for display; the persisted ResourceIntent.structuralQuantity is the
  /// whole-unit value (see [wholeUnits]).
  final int milliValue;

  final String unit;

  /// Value in [unit] as a double (display only).
  double get value => milliValue / 1000.0;

  /// Value truncated toward zero to whole [unit] — the integer stored on the
  /// energy_telemetry ResourceIntent.
  int get wholeUnits => milliValue ~/ 1000;
}

/// Decode [registers] (each a 16-bit word, index 0 == [baseAddress]) into a
/// reading per spec in [specs]. A spec whose window falls outside the block is
/// skipped (fail-closed: a partial read never fabricates a value). A word
/// outside 0..0xFFFF throws — the caller handed us non-register data.
List<EnergyReading> decodeRegisters(
  List<int> registers,
  int baseAddress,
  List<RegisterSpec> specs,
) {
  final out = <EnergyReading>[];
  for (final spec in specs) {
    final offset = spec.address - baseAddress;
    final words = spec.isWide ? 2 : 1;
    if (offset < 0 || offset + words > registers.length) {
      continue; // window not covered by this block
    }

    final int raw;
    if (!spec.isWide) {
      final w = _word(registers, offset);
      raw = (spec.type == RegisterType.s16 && w >= 0x8000) ? w - 0x10000 : w;
    } else {
      final w0 = _word(registers, offset);
      final w1 = _word(registers, offset + 1);
      final high = spec.wordOrder == WordOrder.highWordFirst ? w0 : w1;
      final low = spec.wordOrder == WordOrder.highWordFirst ? w1 : w0;
      final u = high * 0x10000 + low; // multiplication, not <<
      raw = (spec.type == RegisterType.s32 && u >= 0x80000000)
          ? u - 0x100000000
          : u;
    }

    out.add(EnergyReading(
      metric: spec.metric,
      raw: raw,
      milliValue: raw * spec.scaleMilli,
      unit: spec.unit,
    ));
  }
  return out;
}

int _word(List<int> registers, int i) {
  final w = registers[i];
  if (w < 0 || w > 0xFFFF) {
    throw ArgumentError('Register $i = $w is not a 16-bit word');
  }
  return w;
}

/// A minimal, illustrative register map (NOT authoritative — real maps are
/// per-firmware and community-sourced). Enough to exercise the decoder and to
/// stand in until a device map is loaded.
const List<RegisterSpec> kSampleInverterRegisters = [
  RegisterSpec(
    address: 0x0056,
    metric: 'battery_soc',
    type: RegisterType.u16,
    scaleMilli: 1000, // percent, ×1
    unit: '%',
  ),
  RegisterSpec(
    address: 0x0057,
    metric: 'battery_power',
    type: RegisterType.s16,
    scaleMilli: 1000, // watts, ×1, signed (charge -, discharge +)
    unit: 'W',
  ),
  RegisterSpec(
    address: 0x0186,
    metric: 'pv_power',
    type: RegisterType.u32,
    scaleMilli: 1000, // watts, ×1
    unit: 'W',
  ),
  RegisterSpec(
    address: 0x0201,
    metric: 'daily_yield',
    type: RegisterType.u16,
    scaleMilli: 100, // 0.1 kWh steps
    unit: 'kWh',
  ),
];
