import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
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

const String _jsonSteps = "steps";
const String _jsonTarget = "target";
const String _jsonTargetOperator = "operator";
const String _jsonTargetOperatorDelayed = "operatorDelayed";
const String _jsonTargetCurrent = "current";
const String _jsonDescription = "description";
const String _jsonImage = "image";
const String _jsonDelay = "delay";
const String _jsonAmperes = "amperes";
const String _jsonAmperesStep = "amperesStep";
const String _jsonStepPeriod = "stepPeriod";

class ViewUpdater extends Cubit<Model> {
  ViewUpdater() : super(defaultModel);

  void refreshSerialPorts() =>
      this.emit(this.state.copyWith(serialPorts: SerialPort.availablePorts));

  Future<void> loadTestConfiguration() async {
    final File file = File("test.json");
    try {
      final jsonContent = jsonDecode(await file.readAsString());
      final List<dynamic> jsonSteps = jsonContent[_jsonSteps] as List<dynamic>;
      this.emit(this.state.copyWith(
          testSteps: jsonSteps.map(testStepFromJson).nonNulls.toList()));
    } catch (e, s) {
      logger.w("Invalid json!", error: e, stackTrace: s);
    }
  }

  void connectToPort(String port) async {
    //ModbusAppLogger(Level.ALL);
    this.emit(this.state.copyWith(connectedPort: Optional.of(port)));
    await this.writeCoil(_remoteModeAddress, true);
    await this._dcInput(false);
    await this.setCurrent(0);
  }

  void updateState() async {
    final rawState = await this._readHoldingRegisters(_actualVoltageAddress, 3);
    if (rawState.length >= 3) {
      this.emit(this.state.updateMachineState(
            rawState[0],
            rawState[1],
            rawState[2],
          ));
    }
  }

  void moveToNextStep() => this.emit(this.state.moveToNextStep());

  Future<void> _dcInput(bool enable) async {
    logger.i("About to turn ${enable ? 'on' : 'off'} dcInput");
    await this.writeCoil(_dcInputAddress, enable);
    this.emit(this.state.updateDcInput(enable));
  }

  Future<void> startCurrentTest(
      double amperes, double amperesStep, double stepPeriod) async {
    await this.writeHoldingRegister(_currentAddress, 0);
    await this._dcInput(true);

    double current = 0;

    while (current < amperes) {
      await Future.delayed(Duration(milliseconds: (stepPeriod * 1000).floor()));

      current += amperesStep;
      if (current > amperes) {
        current = amperes;
      }

      final int value = (((current * 10) * 0xD0E5) / 400).floor();
      logger.i("About to write $value to current register");
      await this.writeHoldingRegister(_currentAddress, value);
    }
  }

  Future<void> stopCurrentTest() async {
    await this._dcInput(false);
    await this.writeHoldingRegister(_currentAddress, 0);
    this.moveToNextStep();
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

TestStep? testStepFromJson(dynamic json) {
  try {
    final jsonMap = json as Map<String, dynamic>;
    final String? target = (jsonMap[_jsonTarget] as String?);

    logger.i("Test $target");

    if (target != null) {
      switch (target) {
        case _jsonTargetCurrent:
          {
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? image = cast<String>(jsonMap[_jsonImage]);
            final double amperes = cast<double>(jsonMap[_jsonAmperes])!;
            final double amperesStep = cast<double>(jsonMap[_jsonAmperesStep])!;
            final double stepPeriod = cast<double>(jsonMap[_jsonStepPeriod])!;
            return CurrentTestStep(
              description: description ?? "",
              imagePath: image,
              currentTarget: amperes,
              currentStep: amperesStep,
              stepPeriod: stepPeriod,
            );
          }
        case _jsonTargetOperator:
          {
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? image = cast<String>(jsonMap[_jsonImage]);
            if (description != null || image != null) {
              return DescriptiveTestStep(description ?? "", imagePath: image);
            } else {
              return null;
            }
          }
        case _jsonTargetOperatorDelayed:
          {
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? image = cast<String>(jsonMap[_jsonImage]);
            final int seconds = cast<num>(jsonMap[_jsonDelay])!.toInt();
            if (description != null || image != null) {
              return DelayedTestStep(
                  description ?? "", Duration(seconds: seconds),
                  imagePath: image);
            } else {
              return null;
            }
          }
        default:
          return null;
      }
    } else {
      return null;
    }
  } catch (e, s) {
    logger.w("Invalid json!", error: e, stackTrace: s);
    return null;
  }
}

T? cast<T>(dynamic value) => value is T ? value : null;
