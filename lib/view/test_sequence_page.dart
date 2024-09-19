import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          create: (_) => _CurveTestStepCubit(), child: _TestSequenceView()),
    );
  }
}

class _TestSequenceView extends StatelessWidget {
  final FocusNode focusNode = FocusNode();

  _TestSequenceView();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;

    return KeyboardListener(
        focusNode: this.focusNode,
        autofocus: true,
        onKeyEvent: (event) async {
          logger.i(event.toString());
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              context.read<ViewUpdater>().moveToNextStep();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              await _abort(context);
            }
          }
        },
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox.expand(
              child: switch (model.getTestStep()) {
                DescriptiveTestStep step => _DescriptiveTestStepView(step),
                LoadTestStep step => _CurveTestStepView(step),
                null => const Center(child: Text("Attendere...")),
              },
            )));
  }
}

class _DescriptiveTestStepView extends StatelessWidget {
  final DescriptiveTestStep testStep;

  const _DescriptiveTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;
    final waitTime = model.getOperatorWaitTime();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (this.testStep.title.isNotEmpty)
            Text(
              this.testStep.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          Center(
              child:
                  Text(this.testStep.description, textAlign: TextAlign.center)),
          if (this.testStep.imagePaths.isNotEmpty)
            Expanded(flex: 1, child: _imageWrap(this.testStep.imagePaths)),
        ])),
        if (this.testStep.delay == null || waitTime <= 0) ...[
          const SizedBox(height: 32),
          _bottom(context)
        ],
        if (this.testStep.delay != null && waitTime > 0) ...[
          waitTime == 1
              ? Text("Attendere per ${waitTime} secondo")
              : Text("Attendere per ${waitTime} secondi"),
        ]
      ],
    );
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

    return Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (this.testStep.title.isNotEmpty)
            Text(
              this.testStep.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          Wrap(
              direction: Axis.horizontal,
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.center,
              spacing: 32,
              runSpacing: 32,
              children: [
                const SizedBox(height: 32),
                Column(children: [
                  switch (state) {
                    _CurrentTestStepState.ready => Text(
                        "Test di raggiungimento ${this.testStep.currentCurve?.target ?? 0.0} A / ${this.testStep.voltageCurve?.target ?? 0.0} V"),
                    _CurrentTestStepState.voltageRamp =>
                      const Text("Incremento della tensione in corso..."),
                    _CurrentTestStepState.currentRamp =>
                      const Text("Incremento della corrente in corso..."),
                    _CurrentTestStepState.done => model.canProceed()
                        ? const SizedBox()
                        : const Text("Valori fuori dai limiti richiesti!"),
                  },
                  Text(
                      "Tensione: ${model.getVoltage(electronicLoad).toStringAsFixed(2)} V\nCorrente ${model.getAmperes(electronicLoad).toStringAsFixed(2)} A\nPotenza ${model.getPower(electronicLoad).toStringAsFixed(2)} Watt"),
                ]),
                state == _CurrentTestStepState.done
                    ? Text(this.testStep.finalDescription)
                    : Text(this.testStep.description),
              ]),
          const SizedBox(height: 32),
          if (this.testStep.imagePaths.isNotEmpty)
            Expanded(flex: 2, child: _imageWrap(this.testStep.imagePaths)),
        ],
      )),
      const SizedBox(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _cancelButton(context),
        switch (state) {
          _CurrentTestStepState.ready => _proceedButton(() async {
              final stateCubit = context.read<_CurveTestStepCubit>();
              final viewUpdater = context.read<ViewUpdater>();

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
            }),
          _CurrentTestStepState.done => _proceedButton(model.canProceed()
              ? () async {
                  final viewUpdater = context.read<ViewUpdater>();
                  final stateCubit = context.read<_CurveTestStepCubit>();

                  await viewUpdater.moveToNextStep();
                  stateCubit.resetStep();
                }
              : null),
          _ => const SizedBox(),
        }
      ]),
    ]);
  }
}

Widget _imageWrap(List<String> imagePaths) {
  return LayoutBuilder(builder: (context, constraints) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: imagePaths
          .map((imagePath) => Container(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Image.file(
                    File(imagePath),
                  ))))
          .toList(),
    );
  });
}

Widget _proceedButton(void Function()? onClick) => ElevatedButton(
    onPressed: onClick,
    child: const Padding(padding: EdgeInsets.all(8), child: Text("Prosegui")));

Widget _cancelButton(BuildContext context) {
  return ElevatedButton(
      onPressed: () async {
        await _abort(context);
      },
      child:
          const Padding(padding: EdgeInsets.all(8), child: Text("Interrompi")));
}

Widget _bottom(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _cancelButton(context),
        _proceedButton(() => context.read<ViewUpdater>().moveToNextStep()),
      ],
    );

Future<void> _abort(BuildContext context) async {
  final viewUpdater = context.read<ViewUpdater>();

  if (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text("Attenzione"),
                content: const Text("Interrompere la procedura di collaudo?"),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, false);
                      },
                      child: const Text("No")),
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      child: const Text("Si"))
                ],
              )) ==
      true) {
    viewUpdater.abortTest();
  }
}
