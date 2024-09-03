import 'package:flutter/material.dart';
import 'package:optional/optional.dart';

sealed class TestStep {}

@immutable
class DescriptiveTestStep extends TestStep {
  final String description;

  DescriptiveTestStep(this.description);
}

@immutable
class CurveTestStep extends TestStep {}

typedef MachineState = ({
  int voltage,
  int current,
  int power,
});

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
  machineState: (voltage: 0, current: 0, power: 0),
  testIndex: 0,
  testSteps: [
    DescriptiveTestStep("Collegare i terminali come da immagine"),
    DescriptiveTestStep("Eseguire il test come da immagine"),
    CurveTestStep(),
  ],
);

extension Impl on Model {
  Model copyWith({
    List<String>? serialPorts,
    Optional<String>? connectedPort,
    MachineState? machineState,
    int? testIndex,
  }) =>
      (
        serialPorts: serialPorts ?? this.serialPorts,
        connectedPort: connectedPort ?? this.connectedPort,
        machineState: machineState ?? this.machineState,
        testIndex: testIndex ?? this.testIndex,
        testSteps: this.testSteps,
      );

  bool isConnected() => this.connectedPort.isPresent;

  Model nextStep() =>
      this.copyWith(testIndex: (this.testIndex + 1) % this.testSteps.length);

  TestStep getTestStep() => this.testSteps[this.testIndex];

  double getAmperes() => (this.machineState.current * 50.0) / 0xFFFF;
  double getVoltage() => (this.machineState.voltage * 1250.0) / 0xFFFF;
}
