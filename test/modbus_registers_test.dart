// Module C register decoder over synthetic Modbus blocks — the hardware-free
// half of VoltMesh. Locks the device quirks (16/32-bit, signedness, 32-bit
// word order, fixed-point scale) and the fail-closed behaviour (a window not
// covered by the block yields no reading, never a fabricated value).

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/energy/modbus_registers.dart';

void main() {
  const specs = [
    RegisterSpec(
        address: 100, metric: 'soc', type: RegisterType.u16, unit: '%'),
    RegisterSpec(
        address: 101, metric: 'batt', type: RegisterType.s16, unit: 'W'),
    RegisterSpec(
        address: 102,
        metric: 'pv',
        type: RegisterType.u32,
        unit: 'W',
        wordOrder: WordOrder.highWordFirst),
    RegisterSpec(
        address: 104,
        metric: 'yield',
        type: RegisterType.u16,
        scaleMilli: 100,
        unit: 'kWh'),
    RegisterSpec(
        address: 105,
        metric: 'net',
        type: RegisterType.s32,
        wordOrder: WordOrder.lowWordFirst),
  ];

  // base address 100:
  final block = <int>[
    85, // 100 soc
    0xFFCE, // 101 batt s16 = -50
    0x0001, // 102 pv high
    0x86A0, // 103 pv low  -> 0x000186A0 = 100000
    123, // 104 yield raw, scale 0.1
    0x0000, // 105 net low  (lowWordFirst)
    0xFFFF, // 106 net high -> 0xFFFF0000 -> -65536
  ];

  Map<String, EnergyReading> decode() => {
        for (final r in decodeRegisters(block, 100, specs)) r.metric: r,
      };

  test('u16 unsigned passes through', () {
    expect(decode()['soc']!.raw, 85);
    expect(decode()['soc']!.value, 85.0);
    expect(decode()['soc']!.unit, '%');
  });

  test('s16 sign extension', () {
    expect(decode()['batt']!.raw, -50);
    expect(decode()['batt']!.value, -50.0);
  });

  test('u32 high-word-first assembly', () {
    expect(decode()['pv']!.raw, 100000);
    expect(decode()['pv']!.value, 100000.0);
  });

  test('s32 low-word-first assembly and sign', () {
    // low = reg[5]=0x0000, high = reg[6]=0xFFFF -> 0xFFFF0000 -> negative.
    expect(decode()['net']!.raw, -65536);
  });

  test('fixed-point scale and whole-unit truncation', () {
    final y = decode()['yield']!;
    expect(y.raw, 123);
    expect(y.milliValue, 12300); // 123 * 100
    expect(y.value, 12.3);
    expect(y.wholeUnits, 12); // stored on the energy_telemetry row
  });

  test('a spec outside the block is skipped, not guessed (fail-closed)', () {
    const outside = [
      RegisterSpec(address: 999, metric: 'absent', type: RegisterType.u16),
    ];
    expect(decodeRegisters(block, 100, outside), isEmpty);
    // A 32-bit spec whose second word falls off the end is skipped too.
    const straddle = [
      RegisterSpec(address: 106, metric: 'half', type: RegisterType.u32),
    ];
    expect(decodeRegisters(block, 100, straddle), isEmpty);
  });

  test('a non-16-bit word is rejected as non-register data', () {
    expect(
      () => decodeRegisters(
          [70000], 100, const [RegisterSpec(address: 100, metric: 'x', type: RegisterType.u16)]),
      throwsArgumentError,
    );
  });

  test('the sample map decodes only the registers a partial block covers', () {
    // A 2-register block at the SOC base covers battery_soc + battery_power,
    // but not the far-away pv_power / daily_yield addresses.
    final readings =
        decodeRegisters([50, 0x0064], 0x0056, kSampleInverterRegisters);
    expect(readings.map((r) => r.metric),
        containsAll(<String>['battery_soc', 'battery_power']));
    expect(readings.length, 2);
    expect(readings.firstWhere((r) => r.metric == 'battery_soc').value, 50.0);
    expect(readings.firstWhere((r) => r.metric == 'battery_power').value, 100.0);
  });
}
