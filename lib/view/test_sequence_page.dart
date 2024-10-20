import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';

class TestSequencePage extends StatelessWidget {
  const TestSequencePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _TestSequenceView(),
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
              if (testStep != null && testStep is FinalTestStep) {
                final callback = _testStepCallback(testStep, context);
                if (callback != null) {
                  callback();
                }
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

class _CheckTestStepView extends StatefulWidget {
  final CheckParameters parameters;
  final ElectronicLoad electronicLoad;

  const _CheckTestStepView(this.parameters, this.electronicLoad);

  @override
  State<_CheckTestStepView> createState() => _CheckTestStepState();
}

class _CheckTestStepState extends State<_CheckTestStepView> {
  final List<TextEditingController> ternaryControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController()
  ];
  final TextEditingController powerController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;
    OutlineInputBorder getOutline(bool condition) => OutlineInputBorder(
        borderSide:
            BorderSide(width: 4, color: condition ? Colors.green : Colors.red));

    final ternaryOutline = getOutline(model.isTernaryCheckOk() &&
        this.ternaryControllers[0].text.isNotEmpty &&
        this.ternaryControllers[1].text.isNotEmpty &&
        this.ternaryControllers[2].text.isNotEmpty);
    final powerOutline = getOutline(
        model.isPowerCheckOk() && this.powerController.text.isNotEmpty);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Column(children: [
          Text(
              "I seguenti valori devono essere entro ${this.widget.parameters.maxVariance} l'uno dall'altro"),
          Wrap(
              spacing: 32,
              runSpacing: 32,
              children: List.generate(3, (index) {
                return SizedBox(
                    width: 200,
                    child: TextField(
                      controller: this.ternaryControllers[index],
                      decoration: InputDecoration(
                        border: ternaryOutline,
                        enabledBorder: ternaryOutline,
                        focusedBorder: ternaryOutline,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                            RegExp(r'(^-?\d*\.?\d*)'))
                      ],
                      onChanged: (value) {
                        final viewUpdater = context.read<ViewUpdater>();
                        final doubleValue = double.tryParse(value);

                        if (doubleValue != null) {
                          this.setState(() {
                            this.ternaryControllers[index].text = value;
                          });
                          viewUpdater.updateVarianceValue(index, doubleValue);
                        }
                      },
                    ));
              })),
        ])),
        Expanded(
          child: Column(children: [
            Text(
                "Il rapporto tra la potenza (${model.getPower(this.widget.electronicLoad).toStringAsFixed(2)}) e il seguente valore (${model.getPowerCheckRatio().toStringAsFixed(2)}) deve essere tra ${this.widget.parameters.minValue.toStringAsFixed(2)} e 1.00"),
            SizedBox(
                width: 200,
                child: TextField(
                  controller: this.powerController,
                  decoration: InputDecoration(
                    border: powerOutline,
                    enabledBorder: powerOutline,
                    focusedBorder: powerOutline,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'(^-?\d*\.?\d*)'))
                  ],
                  onChanged: (value) {
                    final viewUpdater = context.read<ViewUpdater>();
                    final doubleValue = double.tryParse(value);

                    if (doubleValue != null) {
                      this.setState(() {
                        this.powerController.text = value;
                      });
                      viewUpdater.updateDifferenceValue(doubleValue);
                    }
                  },
                )),
          ]),
        ),
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
          _bottom(this.testStep, context, skippable: this.testStep.skippable)
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
        if (this.testStep.imagePaths.isNotEmpty)
          Expanded(flex: 1, child: _imageWrap(this.testStep.imagePaths)),
        if (!this.testStep.imagePaths.isNotEmpty) const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _cancelButton(context),
            if (this.testStep.skippable)
              _skipButton(
                  () => context.read<ViewUpdater>().moveToNextStep(skip: true)),
            _proceedButton(_testStepCallback(this.testStep, context),
                text: model.curveTestStepState == CurveTestStepState.ready
                    ? "Start"
                    : null),
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
    final model = context.watch<ViewUpdater>().state;

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
          const SizedBox(height: 32),
          Column(children: [
            switch (model.curveTestStepState) {
              CurveTestStepState.ready => Text(
                  "Test di raggiungimento ${this.testStep.currentCurve?.target ?? 0.0} A / ${this.testStep.voltageCurve?.target ?? 0.0} V"),
              CurveTestStepState.voltageRamp =>
                const Text("Incremento della tensione in corso..."),
              CurveTestStepState.currentRamp =>
                const Text("Incremento della corrente in corso..."),
              CurveTestStepState.done => const SizedBox(),
            },
          ]),
          model.curveTestStepState == CurveTestStepState.done
              ? Text(this.testStep.finalDescription)
              : Text(this.testStep.description),
          const SizedBox(height: 32),
          if (model.curveTestStepState != CurveTestStepState.done &&
              this.testStep.imagePaths.isNotEmpty)
            Expanded(flex: 2, child: _imageWrap(this.testStep.imagePaths)),
          if (model.curveTestStepState == CurveTestStepState.done &&
              this.testStep.checkParameters.isPresent)
            Expanded(
                flex: 2,
                child: _CheckTestStepView(this.testStep.checkParameters.value,
                    this.testStep.electronicLoad))
        ],
      )),
      const SizedBox(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _cancelButton(context),
        if (this.testStep.skippable)
          _skipButton(
              () => context.read<ViewUpdater>().moveToNextStep(skip: true)),
        _proceedButton(_testStepCallback(this.testStep, context)),
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

Widget _proceedButton(void Function()? onClick, {String? text}) =>
    ElevatedButton(
        onPressed: onClick,
        child: Padding(
            padding: const EdgeInsets.all(8), child: Text(text ?? "Prosegui")));

Widget _skipButton(void Function()? onClick) => ElevatedButton(
    onPressed: onClick,
    child: const Padding(padding: EdgeInsets.all(8), child: Text("Salta")));

Widget _cancelButton(BuildContext context) {
  return ElevatedButton(
      onPressed: () async {
        await _abort(context);
      },
      child:
          const Padding(padding: EdgeInsets.all(8), child: Text("Interrompi")));
}

Widget _bottom(
  TestStep testStep,
  BuildContext context, {
  bool skippable = false,
}) =>
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _cancelButton(context),
        if (skippable)
          _skipButton(
              () => context.read<ViewUpdater>().moveToNextStep(skip: true)),
        _proceedButton(_testStepCallback(testStep, context)),
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

void Function()? _testStepCallback(TestStep testStep, BuildContext context) {
  switch (testStep) {
    case PwmTestStep testStep:
      return () async {
        final viewUpdater = context.read<ViewUpdater>();

        if (viewUpdater.state.pwmState == PwmState.ready) {
          viewUpdater.startPwm(
              testStep.electronicLoad, testStep.voltage, testStep.current);
        } else {
          viewUpdater.moveToNextStep();
        }
      };
    case LoadTestStep testStep:
      {
        final model = context.watch<ViewUpdater>().state;
        final state = model.curveTestStepState;

        final electronicLoad = testStep.electronicLoad;

        return switch (state) {
          CurveTestStepState.ready => () async {
              final viewUpdater = context.read<ViewUpdater>();

              if (testStep.currentCurve != null) {
                await viewUpdater.currentCurve(
                  electronicLoad,
                  testStep.currentCurve!.target,
                  testStep.currentCurve!.step,
                  testStep.currentCurve!.period,
                );
              }
              if (testStep.voltageCurve != null) {
                await viewUpdater.voltageCurve(
                  electronicLoad,
                  testStep.voltageCurve!.target,
                  testStep.voltageCurve!.step,
                  testStep.voltageCurve!.period,
                );
              }
            },
          CurveTestStepState.done => model.canProceed()
              ? () async {
                  final viewUpdater = context.read<ViewUpdater>();

                  await viewUpdater.moveToNextStep();
                }
              : null,
          _ => null,
        };
      }
    case DescriptiveTestStep _:
      return () => context.read<ViewUpdater>().moveToNextStep();
    case FinalTestStep _:
      return null;
  }
}
