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
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:optional/optional.dart';
import 'package:result_type/result_type.dart';

const int _deviceClassAddress = 0;
const int _remoteModeAddress = 402;
const int _dcInputAddress = 405;
const int _voltageAddress = 500;
const int _currentAddress = 501;
const int _actualVoltageAddress = 507;

const String _jsonReportsPath = "reportsPath";
const String _jsonSteps = "steps";
const String _jsonTarget = "target";
const String _jsonTargetOperator = "operator";
const String _jsonTargetLoad = "load";
const String _jsonFirstLoadIp = "firstLoadIp";
const String _jsonSecondLoadIp = "secondLoadIp";
const String _jsonTargetPwm = "pwm";
const String _jsonManualCheck = "manualCheck";
const String _jsonSkippable = "skippable";
const String _jsonCommand = "command";
const String _jsonTargetValue = "targetValue";
const String _jsonMaxVariance = "maxVariance";
const String _jsonMaxDifference = "maxDifference";
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
      final reportsPath = cast<String?>(jsonContent[_jsonReportsPath]) ?? "";
      final firstLoadIp = cast<String?>(jsonContent[_jsonFirstLoadIp]) ?? "";
      final secondLoadIp = cast<String?>(jsonContent[_jsonSecondLoadIp]) ?? "";

      this.emit(this
          .state
          .updateTestSteps(jsonSteps.map(testStepFromJson).nonNulls.toList())
          .copyWith(
            reportsPath: reportsPath,
            firstElectronicLoadAddress: firstLoadIp,
            secondElectronicLoadAddress: secondLoadIp,
          ));
      logger.i("Correct JSON");
    } catch (e, s) {
      this.emit(this.state.copyWith(
          testSteps: Optional.of(Failure("Configurazione non valida!"))));
      logger.w("Total json invalid!", error: e, stackTrace: s);
    }
  }

  Future<void> findPorts() async {
    final ports = SerialPort.availablePorts;

    ModbusClient? firstPort = null;
    ModbusClient? secondPort = null;
    ModbusClient? thirdPort = null;

    this.emit(this.state.copyWith(ports: const Optional.empty()));

    for (final port in ports) {
      logger.i("Trying port ${port}");

      try {
        final client = ModbusClientSerialRtu(
          portName: port,
          connectionMode: ModbusConnectionMode.autoConnectAndDisconnect,
          dataBits: SerialDataBits.bits8,
          stopBits: SerialStopBits.one,
          parity: SerialParity.none,
          baudRate: SerialBaudRate.b115200,
          flowControl: SerialFlowControl.none,
          unitId: 1,
          responseTimeout: const Duration(milliseconds: 2000),
        );

        final int deviceType = await this._readHoldingRegister(
            client, _deviceClassAddress,
            handleError: false);
        logger.i("Device type found ${deviceType}");

        if (deviceType == 0xBEAF) {
          /*
          case 59:
            firstPort = client;
            break;
          case 33:
            secondPort = client;
            break;
            */
          thirdPort = client;
          break;
        }
        thirdPort = client;
      } catch (e, s) {
        logger.i("Unable to open port ${port}", error: e, stackTrace: s);
      }
    }

    logger.i("Done serial ${firstPort} ${secondPort} ${thirdPort}");

    if (ports.isEmpty) {
      this.emit(this
          .state
          .copyWith(ports: Optional.of(Failure("Nessuna porta disponibile"))));
    } else if (thirdPort == null) {
      this.emit(this
          .state
          .copyWith(ports: Optional.of(Failure("Controllo PWM non trovato"))));
    } else {
      final firstAddress =
          InternetAddress.tryParse(this.state.firstElectronicLoadAddress);
      if (firstAddress == null) {
        this.emit(this.state.copyWith(
            ports: Optional.of(Failure(
                "Indirizzo IP del primo carico (${this.state.firstElectronicLoadAddress}) non valido"))));
      } else {
        final serverIp = await ModbusClientTcp.discover(firstAddress.address);
        if (serverIp == null) {
          this.emit(this.state.copyWith(
              ports: Optional.of(
                  Failure("Impossibile connettersi al primo carico"))));
        } else {
          // Create the modbus client.
          firstPort = ModbusClientTcp(serverIp, unitId: 1);
        }
      }

      final secondAddress =
          InternetAddress.tryParse(this.state.secondElectronicLoadAddress);
      if (secondAddress == null) {
        this.emit(this.state.copyWith(
            ports: Optional.of(Failure(
                "Indirizzo IP del secondo carico (${this.state.secondElectronicLoadAddress}) non valido"))));
      } else {
        final serverIp = await ModbusClientTcp.discover(secondAddress.address);
        if (serverIp == null) {
          this.emit(this.state.copyWith(
              ports: Optional.of(
                  Failure("Impossibile connettersi al secondo carico"))));
        } else {
          // Create the modbus client.
          secondPort = ModbusClientTcp(serverIp, unitId: 1);
        }
      }

      logger.i("Done TCP ${firstPort} ${secondPort} ${thirdPort}");

      if (firstPort != null && secondPort != null) {
        this.emit(this.state.copyWith(
                ports: Optional.of(Success((
              firstElectronicLoad: firstPort,
              secondElectronicLoad: secondPort,
              pwmControl: thirdPort,
            )))));
        logger.i("Successfully connected to all ports");

        for (final load in ElectronicLoad.values) {
          final port = this.state.getElectronicLoadPort(load)!;
          await this.writeCoil(port, _remoteModeAddress, true);
          await this._dcInput(load, false);
          await this.writeHoldingRegister(port, _currentAddress, 0);
          await this.writeHoldingRegister(port, _voltageAddress, 0);
        }

        this._enterTest(this.state.getTestStep());
      }
    }
  }

  void updateState() async {
    this.emit(this.state.updateOperatorWaitTime());

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
  }

  Future<bool> saveTestData(String deviceId) async {
    final now = DateTime.now();
    try {
      final fileName = this.state.reportsPath;
      final filePath = fileName;
      File file = File(filePath);

      var contents =
          "${deviceId}, ${now.day}/${now.month}/${now.year}, ${now.hour}:${now.minute}:${now.second}";

      for (final line in this.state.testData) {
        contents += ", ${line.map((d) => d.toStringAsFixed(2)).join(", ")}";
      }

      contents += "\n";

      await file.writeAsString(contents, mode: FileMode.append);

      logger.i(filePath);
    } catch (e, s) {
      logger.w("Unable to save file", error: e, stackTrace: s);
      return false;
    }
    return true;
  }

  void updateVarianceValue(int index, double value) =>
      this.emit(this.state.updateVarianceValue(index, value));

  void updateDifferenceValue(double value) =>
      this.emit(this.state.copyWith(differenceValue: value));

  Future<void> abortTest() async {
    var state = this.state;

    this._exitTest(this.state.getTestStep());

/*
    for (final load in ElectronicLoad.values) {
      final port = this.state.getElectronicLoadPort(load)!;
      await this._dcInput(load, false);
      await this.writeHoldingRegister(port, _currentAddress, 0);
      await this.writeHoldingRegister(port, _voltageAddress, 0);
      state = state.setElectronicLoadValues(load, setCurrent: 0, setVoltage: 0);
    }
    */

    this.emit(state.copyWith(testIndex: 0, testData: []));
  }

  Future<void> moveToNextStep({bool skip = false}) async {
    if (!this.state.canProceed() && !skip) {
      return;
    }

    this._exitTest(this.state.getTestStep());

    var newState = this
        .state
        .copyWith(pwmState: PwmState.ready)
        .moveToNextStep(skip: skip);

    this._enterTest(newState.getTestStep());

    this.emit(newState);
  }

  void startCurrentRamp() => this.emit(
      this.state.copyWith(curveTestStepState: CurveTestStepState.currentRamp));

  void startVoltageRamp() => this.emit(
      this.state.copyWith(curveTestStepState: CurveTestStepState.voltageRamp));

  void rampDone() => this
      .emit(this.state.copyWith(curveTestStepState: CurveTestStepState.done));

  void resetStep() => this.emit(this.state.resetStep());

  Future<void> _dcInput(ElectronicLoad electronicLoad, bool enable) async {
    logger.i("About to turn ${enable ? 'on' : 'off'} dcInput");
    await this.writeCoil(this.state.getElectronicLoadPort(electronicLoad)!,
        _dcInputAddress, enable);
    this.emit(this.state.updateDcInput(electronicLoad, enable));
  }

  Future<void> lockDown() async {
    logger.i("Lockdown");
    final port = this.state.getPwmControlPort()!;
    await this.writeHoldingRegister(port, 2, 1);
  }

  Future<void> unlock() async {
    logger.i("Unlocking");
    final port = this.state.getPwmControlPort()!;
    await this.writeHoldingRegister(port, 2, 0);
  }

  Future<void> startPwm(
      ElectronicLoad electronicLoad, double voltage, double current) async {
    final port = this.state.getElectronicLoadPort(electronicLoad)!;

    {
      final int value = (((voltage * 10) * 0xD0E5) / (1020 * 10)).floor();
      await this.writeHoldingRegister(port, _voltageAddress, value);
    }
    {
      await this._setCurrent(port, current);
    }
    await this._dcInput(electronicLoad, true);

    await this.writeHoldingRegister(this.state.getPwmControlPort()!, 1, 1);
    this.emit(this.state.copyWith(pwmState: PwmState.active));
  }

  Future<void> _stopPwm() async {
    await this.writeHoldingRegister(this.state.getPwmControlPort()!, 1, 0);
    this.emit(this.state.copyWith(pwmState: PwmState.ready));
  }

  Future<void> currentCurve(ElectronicLoad electronicLoad, double amperes,
      double amperesStep, double stepPeriod) async {
    this.startCurrentRamp();

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
    this.rampDone();
  }

  Future<void> voltageCurve(ElectronicLoad electronicLoad, double volts,
      double voltsStep, double stepPeriod) async {
    this.startVoltageRamp();
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
    this.rampDone();
  }

  Future<List<int>> _readHoldingRegisters(
    ModbusClient client,
    int address,
    int number, {
    bool handleError = true,
  }) async {
    Uint8List bytes = Uint8List(number * 2);

    final register = ModbusBytesRegister(
      name: "register $address",
      type: ModbusElementType.holdingRegister,
      address: address,
      byteCount: number * 2,
    );

    if (handleError) {
      this._handleModbusResult(
          () async => await client.send(
                register.getReadRequest(),
              ),
          getPortName(client));
    } else {
      await client.send(register.getReadRequest());
    }

    bytes = register.value ?? bytes;

    return List.generate(number, (index) => index * 2)
        .map((i) => bytes[i] << 8 | bytes[i + 1])
        .toList();
  }

  Future<int> _readHoldingRegister(
    ModbusClient client,
    int address, {
    bool handleError = true,
  }) async =>
      (await this._readHoldingRegisters(client, address, 1,
              handleError: handleError))
          .elementAtOrNull(0) ??
      0;

  Future<void> writeCoil(ModbusClient client, int address, bool value) async {
    this._handleModbusResult(
        () async => await client.send(
              ModbusUint16Register(
                name: "register",
                type: ModbusElementType.coil,
                address: address,
              ).getWriteRequest(value ? 0xFF00 : 0x0000),
            ),
        getPortName(client));
  }

  Future<void> writeHoldingRegister(
      ModbusClient client, int address, int value) async {
    this._handleModbusResult(
        () async => await client.send(
              ModbusUint16Register(
                name: "register",
                type: ModbusElementType.holdingRegister,
                address: address,
              ).getWriteRequest(value),
            ),
        getPortName(client));
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
    logger.i(
        "Curving ${address} on port ${port != null ? getPortName(port) : "Nessuna"}");
    if (port == null) {
      return;
    }

    await this.writeHoldingRegister(port, address, 0);
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

  Future<void> _setCurrent(ModbusClient port, double current) async {
    final int value = (((current * 10) * 0xD0E5) / (40.8 * 10)).floor();
    await this.writeHoldingRegister(port, _currentAddress, value);
  }

  Future<void> _enterTest(TestStep? testStep) async {
    this.resetStep();
    if (testStep != null) {
      if (testStep is DescriptiveTestStep && testStep.command != null) {
        try {
          var arguments = testStep.command!.split(" ");
          final executable = arguments.first;
          arguments.removeAt(0);

          Process.run(executable, arguments, runInShell: true).then((result) {
            logger.i(result.exitCode);
            logger.i(result.stdout);
            logger.i(result.stderr);
          });
        } catch (e, s) {
          logger.w("Unable to run command", error: e, stackTrace: s);
        }
      } else if (testStep is DescriptiveTestStep && testStep.delay != null) {
        logger.i("Delay, lockdown");
        await this.lockDown();
      }
    }
  }

  Future<void> _handleModbusResult(
      Future<ModbusResponseCode> Function() op, String port) async {
    var counter = 0;
    var code = await op();
    while (counter < 3) {
      if (code == ModbusResponseCode.requestSucceed ||
          code == ModbusResponseCode.acknowledge) {
        break;
      } else {
        code = await op();
      }
      counter++;
    }

    if (code != ModbusResponseCode.requestSucceed &&
        code != ModbusResponseCode.acknowledge) {
      this.emit(this.state.copyWith(
              ports: Optional.of(Failure(switch (code) {
            ModbusResponseCode.connectionFailed =>
              "Impossibile connettersi a ${port}",
            ModbusResponseCode.deviceBusy => "${port} occupata",
            ModbusResponseCode.requestTimeout => "Nessuna risposta da ${port}",
            ModbusResponseCode.deviceFailure =>
              "Errore sul dispositivo connesso a ${port}",
            ModbusResponseCode.illegalDataAddress =>
              "Indirizzo dati non valido su ${port}",
            ModbusResponseCode.illegalDataValue =>
              "Valore dati non valido su ${port}",
            ModbusResponseCode.illegalFunction =>
              "Funzione non valida su ${port}",
            ModbusResponseCode.negativeAcknowledgment =>
              "Il dispositivo su ${port} si rifiuta di rispondere",
            _ => "Errore di comunicazione (${code}) verso ${port}!",
          }))));
    }
  }

  Future<void> _exitTest(TestStep? testStep) async {
    this.resetStep();
    this._stopPwm();

    if (testStep != null) {
      if ((testStep is LoadTestStep && testStep.zeroWhenFinished) ||
          (testStep is PwmTestStep)) {
        for (final load in ElectronicLoad.values) {
          final port = this.state.getElectronicLoadPort(load)!;
          await this._dcInput(load, false);
          await this.writeHoldingRegister(port, _currentAddress, 0);
          await this.writeHoldingRegister(port, _voltageAddress, 0);
          this.emit(this
              .state
              .setElectronicLoadValues(load, setCurrent: 0, setVoltage: 0));
        }
      } else if (testStep is DescriptiveTestStep && testStep.delay != null) {
        logger.i("Delay, unlock");
        await this.unlock();
      }
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
                cast<bool>(jsonMap[_jsonZeroWhenFinished]);
            final bool? skippable = cast<bool>(jsonMap[_jsonSkippable]);

            final model.Curve? current = curveFromJson(jsonMap[_jsonCurrent]);
            final model.Curve? voltage = curveFromJson(jsonMap[_jsonVoltage]);

            final jsonCheckParameters =
                cast<Map<String, dynamic>>(jsonMap[_jsonManualCheck]);

            Optional<CheckParameters> checkParameters = const Optional.empty();
            if (jsonCheckParameters != null) {
              final double maxVariance =
                  cast<num>(jsonCheckParameters[_jsonMaxVariance])!.toDouble();
              final double minValue =
                  cast<num>(jsonCheckParameters[_jsonMin])!.toDouble();

              checkParameters = Optional.of((
                maxVariance: maxVariance,
                minValue: minValue,
              ));
            }

            return LoadTestStep(
              electronicLoad: electronicLoad,
              title: title ?? "",
              description: description ?? "",
              finalDescription: finalDescription ?? "",
              imagePaths: imagesFromJson(jsonMap[_jsonImages]),
              currentCurve: current,
              voltageCurve: voltage,
              zeroWhenFinished: zeroWhenFinished ?? true,
              checkParameters: checkParameters,
              skippable: skippable ?? false,
            );
          }
        case _jsonTargetOperator:
          {
            final int? seconds = (cast<num?>(jsonMap[_jsonDelay]))?.toInt();
            final String? title = cast<String>(jsonMap[_jsonTitle]);
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final String? command = cast<String>(jsonMap[_jsonCommand]);
            final bool? skippable = cast<bool>(jsonMap[_jsonSkippable]);

            final Duration? delay =
                seconds != null ? Duration(seconds: seconds) : null;

            return DescriptiveTestStep(
              title ?? "",
              description ?? "",
              imagePaths: imagesFromJson(jsonMap[_jsonImages]),
              delay: delay,
              command: command,
              skippable: skippable ?? false,
            );
          }
        case _jsonTargetPwm:
          {
            final ElectronicLoad electronicLoad = ElectronicLoad
                .values[cast<int?>(jsonMap[_jsonElectronicLoad])!];
            final String? title = cast<String>(jsonMap[_jsonTitle]);
            final String? description = cast<String>(jsonMap[_jsonDescription]);
            final double voltage = cast<num>(jsonMap[_jsonVoltage])!.toDouble();
            final double current = cast<num>(jsonMap[_jsonCurrent])!.toDouble();
            final bool? skippable = cast<bool>(jsonMap[_jsonSkippable]);

            return PwmTestStep(
              electronicLoad: electronicLoad,
              title: title ?? "",
              description: description ?? "",
              imagePaths: imagesFromJson(jsonMap[_jsonImages]),
              voltage: voltage,
              current: current,
              skippable: skippable ?? false,
            );
          }
        default:
          return null;
      }
    } else {
      return null;
    }
  } catch (e, s) {
    logger.w("Invalid json step!", error: e, stackTrace: s);
    return null;
  }
}

T? cast<T>(dynamic value) => value is T ? value : null;

String getPortName(ModbusClient client) {
  if (client is ModbusClientSerialRtu) {
    return client.serialPort.name;
  } else if (client is ModbusClientTcp) {
    return client.serverAddress;
  } else {
    return "<UNK>";
  }
}
