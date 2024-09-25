import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';

enum _CurveTestStepState {
  ready,
  currentRamp,
  voltageRamp,
  done,
}

class _CurveTestStepCubit extends Cubit<_CurveTestStepState> {
  _CurveTestStepCubit() : super(_CurveTestStepState.ready);

  void startCurrentRamp() {
    this.emit(_CurveTestStepState.currentRamp);
  }

  void startVoltageRamp() {
    this.emit(_CurveTestStepState.voltageRamp);
  }

  void rampDone() {
    this.emit(_CurveTestStepState.done);
  }

  void resetStep() {
    this.emit(_CurveTestStepState.ready);
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
    final testStep = context.select<ViewUpdater, TestStep?>(
        (updater) => updater.state.getTestStep());

    return KeyboardListener(
        focusNode: this.focusNode,
        autofocus: true,
        onKeyEvent: (event) async {
          logger.i(event.toString());
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (testStep is! FinalTestStep) {
                context.read<ViewUpdater>().moveToNextStep();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              await _abort(context);
            }
          }
        },
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox.expand(
              child: switch (testStep) {
                DescriptiveTestStep step => _DescriptiveTestStepView(step),
                PwmTestStep step => _PwmTestStepView(step),
                LoadTestStep step => _CurveTestStepView(step),
                FinalTestStep _ => const _FinalTestStepWidget(),
                null => const Center(child: Text("Attendere...")),
              },
            )));
  }
}

class _DeviceIdCubit extends Cubit<String> {
  _DeviceIdCubit() : super("");

  void update(String value) => this.emit(value);
}

class _FinalTestStepWidget extends StatelessWidget {
  const _FinalTestStepWidget();

  @override
  Widget build(BuildContext context) {
    final FocusNode unitCodeCtrlFocusNode = FocusNode();
    FocusScope.of(context).requestFocus(unitCodeCtrlFocusNode);

    return BlocProvider(
        create: (_) => _DeviceIdCubit(),
        child: Builder(
            builder: (context) => Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          const Text(
                            "Scannerizzare il numero di serie",
                            style: TextStyle(fontWeight: FontWeight.w400),
                          ),
                          SizedBox(
                              width: 400.0,
                              child: TextField(
                                focusNode: unitCodeCtrlFocusNode,
                                textInputAction: TextInputAction.go,
                                onChanged: (value) {
                                  context.read<_DeviceIdCubit>().update(value);
                                },
                                onSubmitted: (value) async {
                                  logger.i("Enter pressed");
                                  await this.saveReport(context);
                                },
                              )),
                        ])),
                    ElevatedButton(
                        onPressed: () async {
                          logger.i("BUtton pressed");
                          await this.saveReport(context);
                        },
                        child: const Text("Conferma"))
                  ],
                )));
  }

  Future<void> saveReport(BuildContext context) async {
    final viewUpdater = context.read<ViewUpdater>();

    final result =
        await viewUpdater.saveTestData(context.read<_DeviceIdCubit>().state);
    logger.i("$result");

    if (!result && context.mounted) {
      await showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text("Attenzione"),
                content: const Text("Salvataggio del rapporto fallito!"),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, false);
                      },
                      child: const Text("Ok")),
                ],
              ));
    } else {
      logger.i("Moving to next step");
      viewUpdater.moveToNextStep();
    }
  }
}

class _CheckTestStepView extends StatelessWidget {
  final CheckParameters parameters;

  const _CheckTestStepView(this.parameters);

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Column(children: [
          Text(
              "I seguenti valori devono essere entro ${this.parameters.maxVariance} l'uno dall'altro"),
          Wrap(
              spacing: 32,
              runSpacing: 32,
              children: List.generate(
                  3,
                  (index) => SizedBox(
                      width: 200,
                      child: TextField(
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                              RegExp(r'(^-?\d*\.?\d*)'))
                        ],
                        onChanged: (value) {
                          final viewUpdater = context.read<ViewUpdater>();
                          final doubleValue = double.tryParse(value);

                          if (doubleValue != null) {
                            viewUpdater.updateVarianceValue(index, doubleValue);
                          }
                        },
                      )))),
        ])),
        Expanded(
          child: Column(children: [
            Text(
                "Il seguente valore deve essere entro ${this.parameters.maxDifference} da ${this.parameters.targetValue}"),
            SizedBox(
                width: 200,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'(^-?\d*\.?\d*)'))
                  ],
                  onChanged: (value) {
                    final viewUpdater = context.read<ViewUpdater>();
                    final doubleValue = double.tryParse(value);

                    if (doubleValue != null) {
                      viewUpdater.updateDifferenceValue(doubleValue);
                    }
                  },
                )),
          ]),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _cancelButton(context),
            _proceedButton(model.canProceed()
                ? () => context.read<ViewUpdater>().moveToNextStep()
                : null),
          ],
        )
      ],
    );
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

class _PwmTestStepView extends StatelessWidget {
  final PwmTestStep testStep;

  const _PwmTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;

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
              child: Text(
                  model.pwmState == PwmState.ready
                      ? ""
                      : this.testStep.description,
                  textAlign: TextAlign.center)),
        ])),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _cancelButton(context),
            _proceedButton(() {
              final viewUpdater = context.read<ViewUpdater>();
              if (viewUpdater.state.pwmState == PwmState.ready) {
                viewUpdater.startPwm(this.testStep.electronicLoad,
                    this.testStep.voltage, this.testStep.current);
              } else {
                viewUpdater.moveToNextStep();
              }
            }),
          ],
        ),
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
                    _CurveTestStepState.ready => Text(
                        "Test di raggiungimento ${this.testStep.currentCurve?.target ?? 0.0} A / ${this.testStep.voltageCurve?.target ?? 0.0} V"),
                    _CurveTestStepState.voltageRamp =>
                      const Text("Incremento della tensione in corso..."),
                    _CurveTestStepState.currentRamp =>
                      const Text("Incremento della corrente in corso..."),
                    _CurveTestStepState.done => model.canProceed()
                        ? const SizedBox()
                        : const Text("Valori fuori dai limiti richiesti!"),
                  },
                ]),
                state == _CurveTestStepState.done
                    ? Text(this.testStep.finalDescription)
                    : Text(this.testStep.description),
              ]),
          const SizedBox(height: 32),
          if (state != _CurveTestStepState.done &&
              this.testStep.imagePaths.isNotEmpty)
            Expanded(flex: 2, child: _imageWrap(this.testStep.imagePaths)),
          if (state == _CurveTestStepState.done &&
              this.testStep.checkParameters.isPresent)
            _CheckTestStepView(this.testStep.checkParameters.value)
        ],
      )),
      const SizedBox(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _cancelButton(context),
        switch (state) {
          _CurveTestStepState.ready => _proceedButton(() async {
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
          _CurveTestStepState.done => _proceedButton(model.canProceed()
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
