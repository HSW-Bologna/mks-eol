import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';

typedef _CurveTestStepState = ({
  int index,
  List<TextEditingController> currentControllers
});

class _CurveTestStepCubit extends Cubit<_CurveTestStepState> {
  _CurveTestStepCubit()
      : super((
          index: 0,
          currentControllers: [0.2, 0.4, 0.6, 0.8, 1]
              .map((current) => TextEditingController(text: "$current"))
              .toList()
        ));

  _CurveTestStepState moveToNextStep() {
    this.emit((
      index: this.state.index + 1,
      currentControllers: this.state.currentControllers
    ));
    return this.state;
  }

  void resetStep() {
    this.emit((index: 0, currentControllers: this.state.currentControllers));
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
            CurrentTestStep step => _CurveTestStepView(step),
            null => const Center(child: Text("Loading...")),
          },
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
  final CurrentTestStep testStep;

  const _CurveTestStepView(this.testStep);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<_CurveTestStepCubit>().state;
    final model = context.watch<ViewUpdater>().state;

    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          direction: Axis.horizontal,
          spacing: 32,
          runAlignment: WrapAlignment.center,
          runSpacing: 32,
          children: state.currentControllers.indexed.map((args) {
            final i = args.$1;
            final currentController = args.$2;

            return Container(
                decoration: i == state.index
                    ? BoxDecoration(
                        border: Border.all(
                            width: 4.0,
                            color: model.machineState.dcInput
                                ? Colors.orange
                                : Colors.grey),
                      )
                    : null,
                child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                        width: 96,
                        height: 56,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          controller: currentController,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}')),
                          ], // Only numbers can be entered
                        ))));
          }).toList(),
        ),
        const SizedBox(height: 32),
        Text(
            "State:\nVoltage: ${model.getVoltage()} V\nCurrent ${model.getAmperes()} A\n Power ${model.machineState.power}"),
        const SizedBox(height: 32),
        ElevatedButton(
            onPressed: () async {
              final stateCubit = context.read<_CurveTestStepCubit>();
              final viewUpdater = context.read<ViewUpdater>();

              if (!viewUpdater.state.machineState.dcInput) {
                await viewUpdater.startCurrentTest(
                    double.parse(state.currentControllers[state.index].text));
              } else if (state.index < state.currentControllers.length - 1) {
                final state = stateCubit.moveToNextStep();
                await viewUpdater.setCurrent(
                    double.parse(state.currentControllers[state.index].text));
              } else {
                await viewUpdater.stopCurrentTest();
                stateCubit.resetStep();
              }
            },
            child: Icon(state.index < state.currentControllers.length - 1
                ? Icons.skip_next
                : Icons.check))
      ],
    ));
  }
}
