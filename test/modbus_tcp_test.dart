// Module C Modbus/TCP frame codec over synthetic frames — the protocol layer
// that feeds the register decoder, testable with no inverter. Fail-closed: a
// device exception is a ModbusException, a malformed frame is a FormatException,
// and neither ever yields a partial register list.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/energy/modbus_registers.dart';
import 'package:omnimesh/energy/modbus_tcp.dart';

/// Craft a well-formed Read Holding Registers response.
Uint8List response(int txn, List<int> registers, {int unitId = 1}) {
  final byteCount = registers.length * 2;
  final f = Uint8List(9 + byteCount);
  f[0] = txn ~/ 256;
  f[1] = txn & 0xFF;
  f[2] = 0;
  f[3] = 0;
  final length = 3 + byteCount;
  f[4] = length ~/ 256;
  f[5] = length & 0xFF;
  f[6] = unitId;
  f[7] = 0x03;
  f[8] = byteCount;
  for (var i = 0; i < registers.length; i++) {
    f[9 + i * 2] = registers[i] ~/ 256;
    f[9 + i * 2 + 1] = registers[i] & 0xFF;
  }
  return f;
}

Uint8List exceptionResponse(int txn, int code) => Uint8List.fromList(
    [txn ~/ 256, txn & 0xFF, 0, 0, 0, 3, 1, 0x83, code]);

void main() {
  test('buildReadHoldingRegisters encodes the MBAP + PDU exactly', () {
    final f = buildReadHoldingRegisters(
        transactionId: 1, startAddress: 0x0056, quantity: 2);
    expect(f, [0, 1, 0, 0, 0, 6, 1, 3, 0x00, 0x56, 0x00, 0x02]);
  });

  test('quantity out of 1..125 is rejected', () {
    expect(
        () => buildReadHoldingRegisters(
            transactionId: 1, startAddress: 0, quantity: 0),
        throwsArgumentError);
    expect(
        () => buildReadHoldingRegisters(
            transactionId: 1, startAddress: 0, quantity: 200),
        throwsArgumentError);
  });

  test('a valid response parses to its register list', () {
    final regs = parseReadHoldingRegisters(response(7, [0x0055, 0xFFCE, 100]));
    expect(regs, [0x0055, 0xFFCE, 100]);
  });

  test('request/response round-trips into decoded readings', () {
    buildReadHoldingRegisters(
        transactionId: 42, startAddress: 0x0056, quantity: 2);
    final regs =
        parseReadHoldingRegisters(response(42, [85, 100]),
            expectedTransactionId: 42);
    final readings = decodeRegisters(regs, 0x0056, kSampleInverterRegisters);
    expect(readings.firstWhere((r) => r.metric == 'battery_soc').value, 85.0);
    expect(readings.firstWhere((r) => r.metric == 'battery_power').value, 100.0);
  });

  test('a device exception surfaces as ModbusException with its code', () {
    expect(
      () => parseReadHoldingRegisters(exceptionResponse(1, 0x02)),
      throwsA(isA<ModbusException>()
          .having((e) => e.code, 'code', 0x02)
          .having((e) => e.name, 'name', 'ILLEGAL_DATA_ADDRESS')),
    );
  });

  test('a transaction-id mismatch is rejected', () {
    expect(
      () => parseReadHoldingRegisters(response(9, [1]),
          expectedTransactionId: 8),
      throwsFormatException,
    );
  });

  group('malformed frames fail closed (FormatException)', () {
    test('too short', () {
      expect(() => parseReadHoldingRegisters(Uint8List(5)),
          throwsFormatException);
    });
    test('non-zero protocol id', () {
      final f = response(1, [1]);
      f[2] = 1; // corrupt protocol id
      expect(() => parseReadHoldingRegisters(f), throwsFormatException);
    });
    test('MBAP length disagrees with frame size', () {
      final f = response(1, [1, 2]);
      f[5] = 99; // wrong length
      expect(() => parseReadHoldingRegisters(f), throwsFormatException);
    });
    test('byte count disagrees with frame', () {
      final f = response(1, [1, 2]);
      f[8] = 2; // claims 1 register but frame carries 2
      expect(() => parseReadHoldingRegisters(f), throwsFormatException);
    });
    test('unexpected function code', () {
      final f = response(1, [1]);
      f[7] = 0x04; // read input registers, not what we asked
      expect(() => parseReadHoldingRegisters(f), throwsFormatException);
    });
  });
}
