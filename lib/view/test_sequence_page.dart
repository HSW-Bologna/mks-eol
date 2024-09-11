import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';

enum _CurrentTestStepState {
  ready,
  currentRamp,
  voltageRamp,
  done,
}

class _CurveTestStepCubit extends Cubit<_CurrentTestStepState> {
  _CurveTestStepCubit() : super(_CurrentTestStepState.ready);

  void startCurrentRamp() {
    this.emit(_CurrentTestStepState.currentRamp);
  }

  void startVoltageRamp() {
    this.emit(_CurrentTestStepState.voltageRamp);
  }

  void rampDone() {
    this.emit(_CurrentTestStepState.done);
  }

  void resetStep() {
    this.emit(_CurrentTestStepState.ready);
  }
}

class TestSequencePage extends StatelessWidget {
  const TestSequencePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocProvider(
          create: (_) => _CurveTestStepCubit(),
          child: const _TestSequenceView()),
    );
  }
}

class _TestSequenceView extends StatelessWidget {
  const _TestSequenceView();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;

    return Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox.expand(
          child: switch (model.getTestStep()) {
            DescriptiveTestStep step => _DescriptiveTestStepView(step),
            DelayedTestStep step => _DelayedTestStepView(step),
            LoadTestStep step => _CurveTestStepView(step),
            null => const Center(child: Text("Attendere...")),
          },
        ));
  }
}

class _DelayedTestStepView extends StatelessWidget {
  final DelayedTestStep testStep;

  const _DelayedTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    final remainingSeconds =
        context.watch<ViewUpdater>().state.getOperatorWaitTime();
    logger.i("$remainingSeconds");

    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 1,
          child: Center(
              child: Text(
                  remainingSeconds > 0
                      ? "${this.testStep.description}\nRimangono ${remainingSeconds} secondi"
                      : "Procedere",
                  textAlign: TextAlign.center)),
        ),
        if (this.testStep.imagePath != null)
          Expanded(flex: 2, child: Image.file(File(this.testStep.imagePath!))),
        Expanded(
          flex: 1,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(
              onPressed: remainingSeconds > 0
                  ? null
                  : () => context.read<ViewUpdater>().moveToNextStep(),
              child: const Icon(Icons.check),
            )
          ]),
        ),
      ],
    ));
  }
}

class _DescriptiveTestStepView extends StatelessWidget {
  final DescriptiveTestStep testStep;

  const _DescriptiveTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 1,
          child: Center(
              child:
                  Text(this.testStep.description, textAlign: TextAlign.center)),
        ),
        if (this.testStep.imagePath != null)
          Expanded(flex: 2, child: Image.file(File(this.testStep.imagePath!))),
        Expanded(
          flex: 1,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(
              onPressed: () => context.read<ViewUpdater>().moveToNextStep(),
              child: const Icon(Icons.check),
            )
          ]),
        ),
      ],
    ));
  }
}

class _CurveTestStepView extends StatelessWidget {
  final LoadTestStep testStep;

  const _CurveTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<_CurveTestStepCubit>().state;
    final model = context.watch<ViewUpdater>().state;
    final electronicLoad = this.testStep.electronicLoad;

    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
            "State:\nVoltage: ${model.getVoltage(electronicLoad).toStringAsFixed(1)} V\nCurrent ${model.getAmperes(electronicLoad).toStringAsFixed(1)} A\n Power ${model.getElectronicLoadState(electronicLoad).power.toStringAsFixed(1)}"),
        const SizedBox(height: 32),
        ...switch (state) {
          _CurrentTestStepState.ready => [
              Text(
                  "Test di raggiungimento ${this.testStep.currentCurve?.target ?? 0.0} A / ${this.testStep.voltageCurve?.target ?? 0.0} V")
            ],
          _CurrentTestStepState.voltageRamp => [
              const Text("Incremento della tensione in corso...")
            ],
          _CurrentTestStepState.currentRamp => [
              const Text("Incremento della corrente in corso...")
            ],
          _CurrentTestStepState.done => [
              Text(this.testStep.description),
              if (this.testStep.imagePath != null)
                Expanded(child: Image.file(File(this.testStep.imagePath!))),
            ]
        },
        const SizedBox(height: 32),
        switch (state) {
          _CurrentTestStepState.ready => ElevatedButton(
              onPressed: () async {
                final stateCubit = context.read<_CurveTestStepCubit>();
                final viewUpdater = context.read<ViewUpdater>();
                logger.i("Testing load ${electronicLoad}");

                if (this.testStep.currentCurve != null) {
                  stateCubit.startCurrentRamp();
                  await viewUpdater.currentCurve(
                    electronicLoad,
                    this.testStep.currentCurve!.target,
                    this.testStep.currentCurve!.step,
                    this.testStep.currentCurve!.period,
                  );
                }
                if (this.testStep.voltageCurve != null) {
                  stateCubit.startVoltageRamp();
                  await viewUpdater.voltageCurve(
                    electronicLoad,
                    this.testStep.voltageCurve!.target,
                    this.testStep.voltageCurve!.step,
                    this.testStep.voltageCurve!.period,
                  );
                }

                stateCubit.rampDone();
              },
              child: const Icon(Icons.skip_next)),
          _CurrentTestStepState.done => ElevatedButton(
              onPressed: () async {
                final viewUpdater = context.read<ViewUpdater>();
                final stateCubit = context.read<_CurveTestStepCubit>();

                await viewUpdater.moveToNextStep();
                stateCubit.resetStep();
              },
              child: const Icon(Icons.check)),
          _ => const SizedBox(),
        },
      ],
    ));
  }
}
