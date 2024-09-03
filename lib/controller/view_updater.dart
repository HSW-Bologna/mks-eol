import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_serial/modbus_client_serial.dart';
import 'package:optional/optional.dart';
import 'package:logging/logging.dart';

const int _remoteModeAddress = 402;
const int _dcInputAddress = 405;
const int _currentAddress = 501;
const int _actualVoltageAddress = 507;

class ViewUpdater extends Cubit<Model> {
  ViewUpdater() : super(defaultModel);

  void refreshSerialPorts() =>
      this.emit(this.state.copyWith(serialPorts: SerialPort.availablePorts));

  void connectToPort(String port) async {
    //ModbusAppLogger(Level.ALL);
    this.emit(this.state.copyWith(connectedPort: Optional.of(port)));
    await this.writeCoil(_remoteModeAddress, true);
    await this.dcInput(false);
    await this.setCurrent(0);
  }

  void updateState() async {
    final rawState = await this._readHoldingRegisters(_actualVoltageAddress, 3);
    if (rawState.length >= 3) {
      this.emit(this.state.copyWith(machineState: (
        voltage: rawState[0],
        current: rawState[1],
        power: rawState[2],
      )));
    }
  }

  void nextStep() => this.emit(this.state.nextStep());

  Future<void> dcInput(bool enable) async {
    logger.i("About to turn ${enable ? 'on' : 'off'} dcInput");
    await this.writeCoil(_dcInputAddress, enable);
  }

  Future<void> setCurrent(double amperes) async {
    final int value = (((amperes * 10) * 0xD0E5) / 400).floor();
    logger.i("About to write $value to current register");
    await this.writeHoldingRegister(_currentAddress, value);
  }

  Future<List<int>> _readHoldingRegisters(int address, int number) async =>
      this._getModbusClient().map((client) async {
        Uint8List bytes = Uint8List(number * 2);

        final register = ModbusBytesRegister(
          name: "register $address",
          type: ModbusElementType.holdingRegister,
          address: address,
          byteCount: number * 2,
        );

        await client.send(
          register.getReadRequest(),
        );

        bytes = register.value ?? bytes;

        return List.generate(number, (index) => index * 2)
            .map((i) => bytes[i] << 8 | bytes[i + 1])
            .toList();
      }).orElse(Future.value([]));

  Future<int> readHoldingRegister(int address) async =>
      (await this._readHoldingRegisters(address, 1)).elementAtOrNull(0) ?? 0;

  Future<bool> readCoil(int address) async =>
      this._getModbusClient().map((client) async {
        final register = ModbusUint16Register(
          name: "register",
          type: ModbusElementType.coil,
          address: address,
        );

        await client.send(
          register.getReadRequest(),
        );

        return (register.value as bool?) ?? false;
      }).orElse(Future.value(false));

  Future<void> writeCoil(int address, bool value) async {
    final client = this._getModbusClient();

    if (client.isPresent) {
      await client.value.send(
        ModbusUint16Register(
          name: "register",
          type: ModbusElementType.coil,
          address: address,
        ).getWriteRequest(value ? 0xFF00 : 0x0000),
      );
    }
  }

  Future<void> writeHoldingRegister(int address, int value) async {
    final client = this._getModbusClient();
    if (client.isPresent) {
      await client.value.send(
        ModbusUint16Register(
          name: "register",
          type: ModbusElementType.holdingRegister,
          address: address,
        ).getWriteRequest(value),
      );
    }
  }

  Optional<ModbusClientSerialRtu> _getModbusClient() {
    return this.state.connectedPort.map((port) => ModbusClientSerialRtu(
          portName: port,
          connectionMode: ModbusConnectionMode.autoConnectAndDisconnect,
          dataBits: SerialDataBits.bits8,
          stopBits: SerialStopBits.one,
          parity: SerialParity.none,
          baudRate: SerialBaudRate.b115200,
          flowControl: SerialFlowControl.none,
          unitId: 0,
        ));
  }
}
