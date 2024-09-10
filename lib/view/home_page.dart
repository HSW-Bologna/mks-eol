import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';

typedef _PageState = ({
  TextEditingController holdingRegisterValueController,
  TextEditingController coilValueController,
  int holdingRegisterAddress,
  int holdingRegisterValue,
  int coilAddress,
  int coilValue,
});

extension Impl on _PageState {
  _PageState copyWith({
    int? holdingRegisterAddress,
    int? holdingRegisterValue,
    int? coilAddress,
    int? coilValue,
  }) =>
      (
        holdingRegisterValueController: this.holdingRegisterValueController,
        coilValueController: this.coilValueController,
        holdingRegisterAddress:
            holdingRegisterAddress ?? this.holdingRegisterAddress,
        holdingRegisterValue: holdingRegisterValue ?? this.holdingRegisterValue,
        coilAddress: coilAddress ?? this.coilAddress,
        coilValue: coilValue ?? this.coilValue,
      );
}

class _PageCubit extends Cubit<_PageState> {
  _PageCubit()
      : super((
          holdingRegisterValueController: TextEditingController(),
          coilValueController: TextEditingController(),
          holdingRegisterAddress: 0,
          holdingRegisterValue: 0,
          coilAddress: 0,
          coilValue: 0
        ));

  void updateHoldingRegisterAddress(String string) {
    final update = int.tryParse(string);
    if (update != null) {
      this.emit(this.state.copyWith(holdingRegisterAddress: update));
    }
  }

  void updateHoldingRegisterValue(String string) {
    final update = int.tryParse(string);
    if (update != null) {
      this.emit(this.state.copyWith(holdingRegisterValue: update));
    }
  }

  void updateCoilAddress(String string) {
    final update = int.tryParse(string);
    if (update != null) {
      this.emit(this.state.copyWith(coilAddress: update));
    }
  }

  void updateCoilValue(String string) {
    final update = int.tryParse(string);
    if (update != null) {
      this.emit(this.state.copyWith(coilValue: update));
    }
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => _PageCubit(),
        child: Builder(builder: (context) {
          final model = context.watch<ViewUpdater>().state;

          final registerOperation = (
            TextEditingController controller,
            String label,
            void Function(String?, String?) onChange,
            void Function() onRead,
            void Function() onWrite,
          ) =>
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                      child: TextField(
                    decoration: InputDecoration(labelText: "$label address"),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => onChange(value, null),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ], // Only numbers can be entered
                  )),
                  Expanded(
                      child: TextField(
                    controller: controller,
                    decoration: InputDecoration(labelText: "$label value"),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => onChange(null, value),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ], // Only numbers can be entered
                  )),
                  ElevatedButton(onPressed: onRead, child: const Text("Read")),
                  ElevatedButton(
                      onPressed: onWrite, child: const Text("Write")),
                ],
              );

          final pageCubit = context.read<_PageCubit>();

          return Scaffold(
            body: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (model.ports.isPresent) ...[
                      Text(
                          "Ricerca dei dispositivi fallita: ${model.ports.value.failure}"),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: () =>
                              context.read<ViewUpdater>().findPorts(),
                          child: const Text("Riprova")),
                    ],
                    if (model.ports.isEmpty) ...[
                      const Text("Caricamento"),
                    ],
                    /*DropdownMenu<String>(
                      initialSelection: model.connectedPort.orElseNull,
                      onSelected: (String? value) {
                        if (value != null) {
                          context.read<ViewUpdater>().connectToPort(value);
                        }
                      },
                      dropdownMenuEntries: model.serialPorts
                          .map<DropdownMenuEntry<String>>((String value) {
                        return DropdownMenuEntry<String>(
                            value: value, label: value);
                      }).toList(),
                    ),*/
                  ]),
            ),
          );
        }),
      );
}
