// lib/energy/modbus_tcp.dart
//
// Module C phase 3 — the Modbus TCP frame codec: build a Read Holding
// Registers request and parse the response into a register list, which
// modbus_registers.dart then decodes into EnergyReadings. See
// docs/MODULE_C_DESIGN.md §4.
//
// This is the protocol layer, and like the register decoder it is pure and
// fully testable off-device on synthetic frames. Only the actual TCP socket to
// a real inverter needs hardware, and it is a thin wrapper around these two
// functions.
//
// Wire format (MBAP header + PDU, all multi-byte fields big-endian):
//   [txnId:2][protocolId:2 = 0][length:2][unitId:1] | [functionCode:1][data…]
// Read Holding Registers (fc 0x03):
//   request  PDU: 0x03 [startAddress:2][quantity:2]
//   response PDU: 0x03 [byteCount:1][registers: byteCount bytes]
//   error    PDU: 0x83 [exceptionCode:1]

import 'dart:typed_data';

const int _fcReadHoldingRegisters = 0x03;
const int _exceptionFlag = 0x80;

/// A Modbus protocol exception returned by the device (illegal address, etc.).
/// Distinct from a malformed frame (FormatException) — the device answered,
/// it just refused.
class ModbusException implements Exception {
  const ModbusException(this.code);
  final int code;

  String get name => switch (code) {
        0x01 => 'ILLEGAL_FUNCTION',
        0x02 => 'ILLEGAL_DATA_ADDRESS',
        0x03 => 'ILLEGAL_DATA_VALUE',
        0x04 => 'SLAVE_DEVICE_FAILURE',
        _ => 'EXCEPTION_0x${code.toRadixString(16)}',
      };

  @override
  String toString() => 'ModbusException($name)';
}

/// Encode a Read Holding Registers (fc 0x03) request frame.
Uint8List buildReadHoldingRegisters({
  required int transactionId,
  required int startAddress,
  required int quantity,
  int unitId = 1,
}) {
  if (quantity < 1 || quantity > 125) {
    throw ArgumentError.value(quantity, 'quantity', 'must be 1..125');
  }
  final f = Uint8List(12);
  _putU16(f, 0, transactionId);
  _putU16(f, 2, 0); // protocol id
  _putU16(f, 4, 6); // length: unitId(1)+fc(1)+start(2)+qty(2)
  f[6] = unitId & 0xFF;
  f[7] = _fcReadHoldingRegisters;
  _putU16(f, 8, startAddress);
  _putU16(f, 10, quantity);
  return f;
}

/// Parse a Read Holding Registers response into its 16-bit register list.
/// Throws [ModbusException] on a device exception and [FormatException] on a
/// malformed / non-matching frame (fail-closed: never a partial list).
List<int> parseReadHoldingRegisters(
  Uint8List frame, {
  int? expectedTransactionId,
}) {
  if (frame.length < 9) {
    throw const FormatException('Modbus frame shorter than a header + PDU');
  }
  if (_u16(frame, 2) != 0) {
    throw const FormatException('Not a Modbus/TCP frame (protocol id != 0)');
  }
  final length = _u16(frame, 4);
  if (frame.length != 6 + length) {
    throw FormatException(
        'MBAP length $length disagrees with frame size ${frame.length}');
  }
  if (expectedTransactionId != null &&
      _u16(frame, 0) != expectedTransactionId) {
    throw const FormatException('Transaction id mismatch');
  }

  final fc = frame[7];
  if (fc == (_fcReadHoldingRegisters | _exceptionFlag)) {
    throw ModbusException(frame[8]);
  }
  if (fc != _fcReadHoldingRegisters) {
    throw FormatException('Unexpected function code 0x${fc.toRadixString(16)}');
  }

  final byteCount = frame[8];
  if (byteCount.isOdd) {
    throw const FormatException('Odd register byte count');
  }
  if (frame.length != 9 + byteCount) {
    throw const FormatException('Register byte count disagrees with frame');
  }
  final registers = <int>[];
  for (var i = 0; i < byteCount; i += 2) {
    registers.add(_u16(frame, 9 + i));
  }
  return registers;
}

// Big-endian 16-bit helpers. Multiplication/addition only — no `<<` (dart2js
// coerces shifts to signed 32-bit; irrelevant at 16 bits but kept uniform with
// the rest of the codebase's manual byte handling, invariant 8).
int _u16(Uint8List b, int i) => b[i] * 256 + b[i + 1];

void _putU16(Uint8List b, int i, int v) {
  b[i] = (v ~/ 256) & 0xFF;
  b[i + 1] = v & 0xFF;
}
