import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/model/model.dart' as model;
import 'package:mks_eol/services/logger.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_serial/modbus_client_serial.dart';
import 'package:optional/optional.dart';
import 'package:result_type/result_type.dart';

const int _deviceClassAddress = 0;
const int _remoteModeAddress = 402;
const int _dcInputAddress = 405;
const int _voltageAddress = 500;
const int _currentAddress = 501;
const int _actualVoltageAddress = 507;

const String _jsonSteps = "steps";
const String _jsonTarget = "target";
const String _jsonTargetOperator = "operator";
const String _jsonTargetLoad = "load";
const String _jsonDescription = "description";
const String _jsonFinalDescription = "finalDescription";
const String _jsonTitle = "title";
const String _jsonElectronicLoad = "electronicLoad";
const String _jsonImages = "images";
const String _jsonDelay = "delay";
const String _jsonCurrent = "current";
const String _jsonVoltage = "voltage";
const String _jsonStep = "step";
const String _jsonPeriod = "period";
const String _jsonMin = "min";
const String _jsonMax = "max";
const String _jsonZeroWhenFinished = "zeroWhenFinished";

class ViewUpdater extends Cubit<Model> {
  ViewUpdater() : super(defaultModel);

  Future<void> loadTestConfiguration() async {
    final File file = File("test.json");
    try {
      this.emit(this.state.copyWith(testSteps: const Optional.empty()));

      final jsonContent = jsonDecode(await file.readAsString());
      final List<dynamic> jsonSteps = jsonContent[_jsonSteps] as List<dynamic>;

      this.emit(this
          .state
          .updateTestSteps(jsonSteps.map(testStepFromJson).nonNulls.toList()));
    } catch (e, s) {
      this.emit(this.state.copyWith(
          testSteps: Optional.of(Failure("Configurazione non valida!"))));
      logger.w("Invalid json!", error: e, stackTrace: s);
    }
  }

  Future<void> findPorts() async {
    final ports = SerialPort.availablePorts;

    ModbusClientSerialRtu? firstPort = null;
    ModbusClientSerialRtu? secondPort = null;

    this.emit(this.state.copyWith(ports: const Optional.empty()));

    for (final port in ports) {
      logger.i("Trying port ${port}");

      for (int address = 0; address <= 1; address++) {
        try {
          final client = ModbusClientSerialRtu(
            portName: port,
            connectionMode: ModbusConnectionMode.autoConnectAndDisconnect,
            dataBits: SerialDataBits.bits8,
            stopBits: SerialStopBits.one,
            parity: SerialParity.none,
            baudRate: SerialBaudRate.b115200,
            flowControl: SerialFlowControl.none,
            unitId: address,
          );

          final int deviceType =
              await this._readHoldingRegister(client, _deviceClassAddress);
          logger.i("Device type found ${deviceType}");
          switch (deviceType) {
            case 59:
              firstPort = client;
              break;
            case 33:
              secondPort = client;
              break;
            case 0xbeef:
              break;
          }
        } catch (e, s) {
          logger.i("Unable to open port ${port}", error: e, stackTrace: s);
        }
      }
    }

    if (ports.isEmpty) {
      this.emit(this
          .state
          .copyWith(ports: Optional.of(Failure("Nessuna porta disponibile"))));
    } else if (firstPort == null) {
      this.emit(this.state.copyWith(
          ports: Optional.of(Failure("Primo carico elettronico non trovato"))));
    } else if (secondPort == null) {
      this.emit(this.state.copyWith(
          ports:
              Optional.of(Failure("Secondo carico elettronico non trovato"))));
    } else {
      this.emit(this.state.copyWith(
              ports: Optional.of(Success((
            firstElectronicLoad: firstPort,
            secondElectronicLoad: secondPort
          )))));
      logger.i(
          "Successfully connected to ${firstPort.serialPort.name} / ${secondPort.serialPort.name}");

      for (final load in ElectronicLoad.values) {
        final port = this.state.getElectronicLoadPort(load)!;
        await this.writeCoil(port, _remoteModeAddress, true);
        await this._dcInput(load, false);
        await this.writeHoldingRegister(port, _currentAddress, 0);
        await this.writeHoldingRegister(port, _voltageAddress, 0);
      }
    }
  }

  void updateState() async {
    if (this.state.isConnected()) {
      for (final load in ElectronicLoad.values) {
        final port = this.state.getElectronicLoadPort(load)!;
        final int deviceType =
            await this._readHoldingRegister(port, _deviceClassAddress);
        if (deviceType != 33 && deviceType != 59) {
          this.emit(this.state.copyWith(
              ports: Optional.of(Failure("Errore di comunicazione!"))));
          break;
        }

        final rawState =
            await this._readHoldingRegisters(port, _actualVoltageAddress, 3);
        if (rawState.length >= 3) {
          this.emit(this.state.updateElectronicLoadState(
                load,
                rawState[0],
                rawState[1],
                rawState[2],
              ));
        }
      }
    }
    this.emit(this.state.updateOperatorWaitTime());
  }

  Future<void> abortTest() async {
    for (final load in ElectronicLoad.values) {
      final port = this.state.getElectronicLoadPort(load)!;
      await this._dcInput(load, false);
      await this.writeHoldingRegister(port, _currentAddress, 0);
      await this.writeHoldingRegister(port, _voltageAddress, 0);
      this.emit(this
          .state
          .setElectronicLoadValues(load, setCurrent: 0, setVoltage: 0));
    }
    this.emit(this.state.copyWith(testIndex: 0));
  }

  Future<void> moveToNextStep() async {
    if (!this.state.canProceed()) {
      return;
    }

    final testStep = this.state.getTestStep();

    if (testStep != null &&
        testStep is LoadTestStep &&
        testStep.zeroWhenFinished) {
      for (final load in ElectronicLoad.values) {
        final port = this.state.getElectronicLoadPort(load)!;
        await this._dcInput(load, false);
        await this.writeHoldingRegister(port, _currentAddress, 0);
        await this.writeHoldingRegister(port, _voltageAddress, 0);
        this.emit(this
            .state
            .setElectronicLoadValues(load, setCurrent: 0, setVoltage: 0));
      }
    }
    this.emit(this.state.moveToNextStep());
  }

  Future<void> _dcInput(ElectronicLoad electronicLoad, bool enable) async {
    logger.i("About to turn ${enable ? 'on' : 'off'} dcInput");
    await this.writeCoil(this.state.getElectronicLoadPort(electronicLoad)!,
        _dcInputAddress, enable);
    this.emit(this.state.updateDcInput(electronicLoad, enable));
  }

  Future<void> currentCurve(ElectronicLoad electronicLoad, double amperes,
      double amperesStep, double stepPeriod) async {
    final state = this.state.getElectronicLoadState(electronicLoad);

    await this._curve(
        electronicLoad: electronicLoad,
        address: _currentAddress,
        start: state.setCurrent,
        target: amperes,
        step: amperesStep,
        stepPeriod: stepPeriod,
        maxX: 0xD0E5,
        maxY: 40.8);
    this.emit(this
        .state
        .setElectronicLoadValues(electronicLoad, setCurrent: amperes));
  }

  Future<void> voltageCurve(ElectronicLoad electronicLoad, double volts,
      double voltsStep, double stepPeriod) async {
    final state = this.state.getElectronicLoadState(electronicLoad);

    await this._curve(
        electronicLoad: electronicLoad,
        address: _voltageAddress,
        start: state.setVoltage,
        target: volts,
        step: voltsStep,
        stepPeriod: stepPeriod,
        maxX: 0xD0E5,
        maxY: 1020);
    this.emit(
        this.state.setElectronicLoadValues(electronicLoad, setVoltage: volts));
  }

  Future<void> stopCurrentTest() async {
    for (final load in ElectronicLoad.values) {
      await this._dcInput(load, false);
      final port = this.state.getElectronicLoadPort(load)!;

      await this.writeHoldingRegister(port, _currentAddress, 0);
      await this.writeHoldingRegister(port, _voltageAddress, 0);
    }
    this.moveToNextStep();
  }

  Future<List<int>> _readHoldingRegisters(
      ModbusClientSerialRtu client, int address, int number) async {
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
  }

  Future<int> _readHoldingRegister(
          ModbusClientSerialRtu client, int address) async =>
      (await this._readHoldingRegisters(client, address, 1))
          .elementAtOrNull(0) ??
      0;

  Future<bool> readCoil(ModbusClientSerialRtu client, int address) async {
    final register = ModbusUint16Register(
      name: "register",
      type: ModbusElementType.coil,
      address: address,
    );

    await client.send(
      register.getReadRequest(),
    );

    return (register.value as bool?) ?? false;
  }

  Future<void> writeCoil(
      ModbusClientSerialRtu client, int address, bool value) async {
    await client.send(
      ModbusUint16Register(
        name: "register",
        type: ModbusElementType.coil,
        address: address,
      ).getWriteRequest(value ? 0xFF00 : 0x0000),
    );
  }

  Future<void> writeHoldingRegister(
      ModbusClientSerialRtu client, int address, int value) async {
    await client.send(
      ModbusUint16Register(
        name: "register",
        type: ModbusElementType.holdingRegister,
        address: address,
      ).getWriteRequest(value),
    );
  }

  Future<void> _curve({
    required ElectronicLoad electronicLoad,
    required int address,
    required double target,
    required double start,
    required double step,
    required double stepPeriod,
    required double maxX,
    required double maxY,
  }) async {
    final port = this.state.getElectronicLoadPort(electronicLoad);
    logger.i("Curving ${address} on port ${port?.serialPort.name}");
    if (port == null) {
      return;
    }

    await this.writeHoldingRegister(port, _voltageAddress, 0);
    await this._dcInput(electronicLoad, true);

    double actualValue = start;

    while (actualValue < target) {
      await Future.delayed(Duration(milliseconds: (stepPeriod * 1000).floor()));

      actualValue += step;
      if (actualValue > target) {
        actualValue = target;
      }

      final int value = (((actualValue * 10) * maxX) / (maxY * 10)).floor();
      await this.writeHoldingRegister(port, address, value);
    }
  }
}

TestStep? testStepFromJson(dynamic json) {
  model.Curve? curveFromJson(Map<String, dynamic>? jsonMap) {
    try {
      final double target = cast<num?>(jsonMap![_jsonTarget])!.toDouble();
      final double step = cast<num>(jsonMap[_jsonStep])!.toDouble();
      final double period = cast<num>(jsonMap[_jsonPeriod])!.toDouble();
      final double min =
          cast<num>(jsonMap[_jsonMin])?.toDouble() ?? double.negativeInfinity;
      final double max =
          cast<num>(jsonMap[_jsonMin])?.toDouble() ?? double.infinity;
      return (
        target: target,
        step: step,
        period: period,
        minAcceptable: min,
        maxAcceptable: max
      );
    } catch (_) {
      return null;
    }
  }

  List<String> imagesFromJson(dynamic rawImages) {
    List<String> images = [];
    if (rawImages != null) {
      if (rawImages is String) {
        images = [rawImages];
      } else if (rawImages is List<dynamic>) {
        images = rawImages.map((i) => i as String).toList();
      }
    }

    return images;
  }

  try {
    final jsonMap = json as Map<String, dynamic>;
    final String? target = (jsonMap[_jsonTarget] as String?);

    if (target != null) {
      switch (target) {
        case _jsonTargetLoad:
          {
            final ElectronicLoad electronicLoad = ElectronicLoad
                .values[cast<int?>(jsonMap[_jsonElectronicLoad])!];
            final String? title = cast<String>(jsonMap[_jsonTitle]);
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? finalDescription =
                cast<String>(jsonMap[_jsonFinalDescription]);
            final bool? zeroWhenFinished =
                cast<bool?>(jsonMap[_jsonZeroWhenFinished]);

            final model.Curve? current = curveFromJson(jsonMap[_jsonCurrent]);
            final model.Curve? voltage = curveFromJson(jsonMap[_jsonVoltage]);

            return LoadTestStep(
              electronicLoad: electronicLoad,
              title: title ?? "",
              description: description ?? "",
              finalDescription: finalDescription ?? "",
              imagePaths: imagesFromJson(jsonMap[_jsonImages]),
              currentCurve: current,
              voltageCurve: voltage,
              zeroWhenFinished: zeroWhenFinished ?? true,
            );
          }
        case _jsonTargetOperator:
          {
            final int? seconds = (cast<num?>(jsonMap[_jsonDelay]))?.toInt();
            final String? title = cast<String>(jsonMap[_jsonTitle]);
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? image = cast<String>(jsonMap[_jsonImages]);

            final Duration? delay =
                seconds != null ? Duration(seconds: seconds) : null;

            if (description != null || image != null) {
              return DescriptiveTestStep(
                title ?? "",
                description ?? "",
                imagePaths: imagesFromJson(jsonMap[_jsonImages]),
                delay: delay,
              );
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
