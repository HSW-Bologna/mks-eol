import 'package:flutter/material.dart';
import 'package:modbus_client_serial/modbus_client_serial.dart';
import 'package:optional/optional.dart';
import 'package:result_type/result_type.dart';
import 'package:result_type/src/result.dart';

enum ElectronicLoad {
  current,
  voltage,
}

enum PwmState {
  ready,
  active,
}

sealed class TestStep {}

@immutable
class FinalTestStep extends TestStep {
  FinalTestStep();
}

@immutable
class DescriptiveTestStep extends TestStep {
  final String title;
  final String description;
  final List<String> imagePaths;
  final Duration? delay;

  DescriptiveTestStep(
    this.title,
    this.description, {
    this.imagePaths = const <String>[],
    this.delay = null,
  });
}

typedef Curve = ({
  double target,
  double step,
  double period,
  double minAcceptable,
  double maxAcceptable,
});

typedef CheckParameters = ({
  double maxVariance,
  double targetValue,
  double maxDifference,
});

@immutable
class LoadTestStep extends TestStep {
  final String title;
  final ElectronicLoad electronicLoad;
  final Curve? currentCurve;
  final Curve? voltageCurve;
  final String description;
  final String finalDescription;
  final List<String> imagePaths;
  final bool zeroWhenFinished;
  final Optional<CheckParameters> checkParameters;

  LoadTestStep({
    required this.electronicLoad,
    required this.title,
    required this.description,
    required this.finalDescription,
    this.currentCurve,
    this.voltageCurve,
    this.imagePaths = const <String>[],
    this.zeroWhenFinished = true,
    this.checkParameters = const Optional.empty(),
  });
}

@immutable
class PwmTestStep extends TestStep {
  final String title;
  final String description;
  final ElectronicLoad electronicLoad;
  final double voltage;
  final double current;

  PwmTestStep({
    required this.title,
    required this.description,
    required this.electronicLoad,
    required this.voltage,
    required this.current,
  });
}

typedef ElectronicLoadState = ({
  int voltage,
  int current,
  int power,
  bool dcInput,
  double setVoltage,
  double setCurrent,
});

extension MachineStateImpl on ElectronicLoadState {
  ElectronicLoadState copyWith({
    int? voltage,
    int? current,
    int? power,
    bool? dcInput,
    double? setVoltage,
    double? setCurrent,
  }) =>
      (
        voltage: voltage ?? this.voltage,
        current: current ?? this.current,
        setVoltage: setVoltage ?? this.setVoltage,
        setCurrent: setCurrent ?? this.setCurrent,
        power: power ?? this.power,
        dcInput: dcInput ?? this.dcInput
      );
}

typedef ModbusPorts = ({
  ModbusClientSerialRtu firstElectronicLoad,
  ModbusClientSerialRtu secondElectronicLoad,
  ModbusClientSerialRtu pwmControl
});

typedef Model = ({
  String reportsPath,
  Optional<Result<ModbusPorts, String>> ports,
  ElectronicLoadState currentElectronicLoadState,
  ElectronicLoadState voltageElectronicLoadState,
  int testIndex,
  Optional<Result<List<TestStep>, String>> testSteps,
  PwmState pwmState,
  DateTime timestamp,
  Duration remainingDuration,
  List<double> varianceValues,
  double differenceValue,
  List<List<double>> testData,
});

final Model defaultModel = (
  reportsPath: "",
  ports: const Optional.empty(),
  currentElectronicLoadState: (
    voltage: 0,
    current: 0,
    setVoltage: 0,
    setCurrent: 0,
    power: 0,
    dcInput: false
  ),
  voltageElectronicLoadState: (
    voltage: 0,
    current: 0,
    setVoltage: 0,
    setCurrent: 0,
    power: 0,
    dcInput: false
  ),
  testIndex: 0,
  testSteps: const Optional.empty(),
  pwmState: PwmState.ready,
  timestamp: DateTime.now(),
  remainingDuration: Duration.zero,
  varianceValues: [],
  differenceValue: 0,
  testData: [],
);

extension Impl on Model {
  Model copyWith({
    String? reportsPath,
    Optional<Result<ModbusPorts, String>>? ports,
    ElectronicLoadState? currentElectronicLoadState,
    ElectronicLoadState? voltageElectronicLoadState,
    int? testIndex,
    Optional<Result<List<TestStep>, String>>? testSteps,
    PwmState? pwmState,
    DateTime? timestamp,
    Duration? remainingDuration,
    List<double>? varianceValues,
    double? differenceValue,
    List<List<double>>? testData,
  }) =>
      (
        reportsPath: reportsPath ?? this.reportsPath,
        ports: ports ?? this.ports,
        currentElectronicLoadState:
            currentElectronicLoadState ?? this.currentElectronicLoadState,
        voltageElectronicLoadState:
            voltageElectronicLoadState ?? this.voltageElectronicLoadState,
        testIndex: testIndex ?? this.testIndex,
        testSteps: testSteps ?? this.testSteps,
        pwmState: pwmState ?? this.pwmState,
        timestamp: timestamp ?? this.timestamp,
        remainingDuration: remainingDuration ?? this.remainingDuration,
        varianceValues: varianceValues ?? this.varianceValues,
        differenceValue: differenceValue ?? this.differenceValue,
        testData: testData ?? this.testData,
      );

  Model updateVarianceValue(int index, double value) {
    List<double> newValues = List.from(this.varianceValues);
    if (index >= newValues.length) {
      newValues.addAll(List.filled(index - newValues.length + 1, 0));
    }
    newValues[index] = value;
    return this.copyWith(varianceValues: newValues);
  }

  Model moveToNextStep() {
    if (this.isConfigured()) {
      List<List<double>> testData = List.from(this.testData);

      final currentStep = this.getTestStep();
      if (currentStep != null &&
          (currentStep is LoadTestStep &&
              currentStep.checkParameters.isPresent) &&
          this.canProceed()) {
        testData.add([
          this.getVarianceValue(0),
          this.getVarianceValue(1),
          this.getVarianceValue(2),
          this.differenceValue,
          this.getPower(ElectronicLoad.current),
          this.getVoltage(ElectronicLoad.current),
          this.getPower(ElectronicLoad.voltage),
          this.getVoltage(ElectronicLoad.voltage),
        ]);
      }

      var newModel = this.copyWith(
          testData: testData,
          testIndex:
              (this.testIndex + 1) % this.testSteps.value.success.length);

      if (newModel.testIndex == 0) {
        newModel = newModel.copyWith(testData: []);
      }

      final newStep = newModel.getTestStep();
      if (newStep != null &&
          newStep is DescriptiveTestStep &&
          newStep.delay != null) {
        return newModel.copyWith(timestamp: DateTime.now());
      } else {
        return newModel;
      }
    } else {
      return this;
    }
  }

  Model updateElectronicLoadState(
      ElectronicLoad electronicLoad, int voltage, int current, int power) {
    final state = this.getElectronicLoadState(electronicLoad);
    return this._updateElectronicLoadState(electronicLoad,
        state.copyWith(voltage: voltage, current: current, power: power));
  }

  Model setElectronicLoadValues(ElectronicLoad electronicLoad,
      {double? setVoltage, double? setCurrent}) {
    final state = this.getElectronicLoadState(electronicLoad);
    return this._updateElectronicLoadState(electronicLoad,
        state.copyWith(setVoltage: setVoltage, setCurrent: setCurrent));
  }

  Model updateDcInput(ElectronicLoad electronicLoad, bool enable) {
    final state = this.getElectronicLoadState(electronicLoad);
    return this._updateElectronicLoadState(
        electronicLoad, state.copyWith(dcInput: enable));
  }

  Model updateTestSteps(List<TestStep> steps) => this.copyWith(
      testIndex: 0, testSteps: Optional.of(Success(steps + [FinalTestStep()])));

  bool isConnected() => this.ports.isPresent && this.ports.value.isSuccess;

  bool isThereAConnectionError() =>
      this.ports.isPresent && this.ports.value.isFailure;

  TestStep? getTestStep() {
    if (this.testSteps.isPresent && this.testSteps.value.isSuccess) {
      return this.testSteps.value.success.elementAtOrNull(this.testIndex);
    } else {
      return null;
    }
  }

  double getAmperes(ElectronicLoad electronicLoad) =>
      (this.getElectronicLoadState(electronicLoad).current * 50.0) / 0xFFFF;

  double getVoltage(ElectronicLoad electronicLoad) =>
      (this.getElectronicLoadState(electronicLoad).voltage * 1250.0) / 0xFFFF;

  double getPower(ElectronicLoad electronicLoad) =>
      (this.getElectronicLoadState(electronicLoad).power * 18750.0) / 0xFFFF;

  int getOperatorWaitTime() {
    return this.remainingDuration.inSeconds;
  }

  Model updateOperatorWaitTime() {
    final step = this.getTestStep();
    if (step != null && step is DescriptiveTestStep && step.delay != null) {
      return this.copyWith(
          remainingDuration:
              step.delay! - DateTime.now().difference(this.timestamp));
    } else {
      return this;
    }
  }

  ModbusClientSerialRtu? getElectronicLoadPort(ElectronicLoad electronicLoad) {
    if (this.ports.isPresent && this.ports.value.isSuccess) {
      return switch (electronicLoad) {
        ElectronicLoad.current => this.ports.value.success.firstElectronicLoad,
        ElectronicLoad.voltage => this.ports.value.success.secondElectronicLoad
      };
    } else {
      return null;
    }
  }

  ModbusClientSerialRtu? getPwmControlPort() {
    if (this.ports.isPresent && this.ports.value.isSuccess) {
      return this.ports.value.success.pwmControl;
    } else {
      return null;
    }
  }

  ElectronicLoadState getElectronicLoadState(ElectronicLoad electronicLoad) =>
      switch (electronicLoad) {
        ElectronicLoad.current => this.currentElectronicLoadState,
        ElectronicLoad.voltage => this.voltageElectronicLoadState
      };

  Model _updateElectronicLoadState(
      ElectronicLoad electronicLoad, ElectronicLoadState state) {
    switch (electronicLoad) {
      case ElectronicLoad.current:
        return this.copyWith(currentElectronicLoadState: state);
      case ElectronicLoad.voltage:
        return this.copyWith(voltageElectronicLoadState: state);
    }
  }

  bool isConfigured() =>
      this.testSteps.isPresent && this.testSteps.value.isSuccess;

  bool isWaitingForConfiguration() => this.testSteps.isEmpty;

  bool isThereAConfigurationError() =>
      this.testSteps.isPresent && this.testSteps.value.isFailure;

  bool canProceed() {
    final testStep = this.getTestStep();
    if (testStep != null) {
      if (testStep is LoadTestStep && testStep.checkParameters.isEmpty) {
        final load = testStep.electronicLoad;
        final amperes = this.getAmperes(load);
        final volts = this.getVoltage(load);

        return (amperes >=
                (testStep.currentCurve?.minAcceptable ??
                    double.negativeInfinity)) &&
            (amperes <=
                (testStep.currentCurve?.maxAcceptable ?? double.infinity)) &&
            (volts >=
                (testStep.voltageCurve?.minAcceptable ??
                    double.negativeInfinity)) &&
            (volts <=
                (testStep.voltageCurve?.maxAcceptable ?? double.infinity));
      } else if (testStep is DescriptiveTestStep) {
        return this.getOperatorWaitTime() <= 0;
      } else if (testStep is LoadTestStep &&
          testStep.checkParameters.isPresent) {
        bool isWithinRange(double value, double target, double difference) =>
            value >= target - difference && value <= target + difference;
        return isWithinRange(this.getVarianceValue(0), this.getVarianceValue(1),
                testStep.checkParameters.value.maxVariance) &&
            isWithinRange(this.getVarianceValue(1), this.getVarianceValue(2),
                testStep.checkParameters.value.maxVariance) &&
            isWithinRange(
                this.differenceValue,
                testStep.checkParameters.value.targetValue,
                testStep.checkParameters.value.maxDifference);
      } else {
        return true;
      }
    } else {
      return false;
    }
  }

  double getVarianceValue(int index) =>
      this.varianceValues.elementAtOrNull(index) ?? 0;
}
