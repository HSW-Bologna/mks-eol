import 'package:flutter/material.dart';
import 'package:optional/optional.dart';

sealed class TestStep {}

@immutable
class DescriptiveTestStep extends TestStep {
  final String description;
  final String? imagePath;

  DescriptiveTestStep(this.description, {this.imagePath});
}

@immutable
class CurrentTestStep extends TestStep {}

typedef MachineState = ({
  int voltage,
  int current,
  int power,
  bool dcInput,
});

extension MachineStateImpl on MachineState {
  MachineState copyWith(
          {int? voltage, int? current, int? power, bool? dcInput}) =>
      (
        voltage: voltage ?? this.voltage,
        current: current ?? this.current,
        power: power ?? this.power,
        dcInput: dcInput ?? this.dcInput
      );
}

typedef Model = ({
  List<String> serialPorts,
  Optional<String> connectedPort,
  MachineState machineState,
  int testIndex,
  List<TestStep> testSteps,
});

final Model defaultModel = (
  serialPorts: [],
  connectedPort: const Optional.empty(),
  machineState: (voltage: 0, current: 0, power: 0, dcInput: false),
  testIndex: 0,
  testSteps: [],
);

extension Impl on Model {
  Model copyWith({
    List<String>? serialPorts,
    Optional<String>? connectedPort,
    MachineState? machineState,
    int? testIndex,
    List<TestStep>? testSteps,
  }) =>
      (
        serialPorts: serialPorts ?? this.serialPorts,
        connectedPort: connectedPort ?? this.connectedPort,
        machineState: machineState ?? this.machineState,
        testIndex: testIndex ?? this.testIndex,
        testSteps: testSteps ?? this.testSteps,
      );

  Model moveToNextStep() =>
      this.copyWith(testIndex: (this.testIndex + 1) % this.testSteps.length);

  Model updateMachineState(int voltage, int current, int power) =>
      this.copyWith(
          machineState: this
              .machineState
              .copyWith(voltage: voltage, current: current, power: power));

  Model updateDcInput(bool enable) =>
      this.copyWith(machineState: this.machineState.copyWith(dcInput: enable));

  Model updateTestSteps(List<TestStep> steps) =>
      this.copyWith(testIndex: 0, testSteps: steps);

  bool isConnected() => this.connectedPort.isPresent;

  TestStep? getTestStep() => this.testSteps.elementAtOrNull(this.testIndex);

  double getAmperes() => (this.machineState.current * 50.0) / 0xFFFF;
  double getVoltage() => (this.machineState.voltage * 1250.0) / 0xFFFF;
}
