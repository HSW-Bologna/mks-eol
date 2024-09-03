import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';

typedef _CurveTestStepState = ({
  bool dcInput,
  int index,
  List<TextEditingController> currentControllers
});

extension Impl on _CurveTestStepView {}

class _CurveTestStepCubit extends Cubit<_CurveTestStepState> {
  _CurveTestStepCubit()
      : super((
          dcInput: false,
          index: 0,
          currentControllers: [0.2, 0.4, 0.6, 0.8, 1]
              .map((current) => TextEditingController(text: "$current"))
              .toList()
        ));

  void next() {
    this.emit((
      dcInput: true,
      index: this.state.index + 1,
      currentControllers: this.state.currentControllers
    ));
  }

  void off() {
    this.emit((
      dcInput: false,
      index: 0,
      currentControllers: this.state.currentControllers
    ));
  }

  void on() {
    this.emit((
      dcInput: true,
      index: 0,
      currentControllers: this.state.currentControllers
    ));
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
  const _TestSequenceView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ViewUpdater>().state;

    return Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox.expand(
          child: switch (model.getTestStep()) {
            DescriptiveTestStep step => _DescriptiveTestStepView(step),
            CurveTestStep step => _CurveTestStepView(step),
          },
        ));
  }
}

class _DescriptiveTestStepView extends StatelessWidget {
  final DescriptiveTestStep testStep;

  const _DescriptiveTestStepView(this.testStep, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 4,
          child: Center(
              child:
                  Text(this.testStep.description, textAlign: TextAlign.center)),
        ),
        Expanded(
          flex: 4,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(
              onPressed: () => context.read<ViewUpdater>().nextStep(),
              child: const Icon(Icons.check),
            )
          ]),
        ),
      ],
    ));
  }
}

class _CurveTestStepView extends StatelessWidget {
  final CurveTestStep testStep;

  const _CurveTestStepView(this.testStep, {super.key});

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
                            color: state.dcInput ? Colors.orange : Colors.grey),
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

              if (!state.dcInput) {
                stateCubit.on();
                await viewUpdater.setCurrent(
                    double.parse(state.currentControllers[state.index].text));
                await viewUpdater.dcInput(true);
              } else if (state.index < state.currentControllers.length - 1) {
                stateCubit.next();
                final state = stateCubit.state;
                await viewUpdater.setCurrent(
                    double.parse(state.currentControllers[state.index].text));
              } else {
                await viewUpdater.dcInput(false);
                await viewUpdater.setCurrent(0);
                viewUpdater.nextStep();
                stateCubit.off();
              }
            },
            child: Icon(state.index < state.currentControllers.length - 1
                ? Icons.skip_next
                : Icons.check))
      ],
    ));
  }
}
