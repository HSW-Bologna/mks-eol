import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
                    DropdownMenu<String>(
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
                    ),
                    if (model.isConnected()) ...[
                      registerOperation(
                        pageCubit.state.holdingRegisterValueController,
                        "Holding register",
                        (address, value) {
                          if (address != null) {
                            context
                                .read<_PageCubit>()
                                .updateHoldingRegisterAddress(address);
                          }
                          if (value != null) {
                            pageCubit.updateHoldingRegisterValue(value);
                          }
                        },
                        () async {
                          final register = await context
                              .read<ViewUpdater>()
                              .readHoldingRegister(
                                  pageCubit.state.holdingRegisterAddress);
                          pageCubit.state.holdingRegisterValueController.text =
                              register.toString();
                        },
                        () => context.read<ViewUpdater>().writeHoldingRegister(
                            pageCubit.state.holdingRegisterAddress,
                            pageCubit.state.holdingRegisterValue),
                      ),
                      registerOperation(
                        pageCubit.state.coilValueController,
                        "Coil",
                        (address, value) {
                          if (address != null) {
                            context
                                .read<_PageCubit>()
                                .updateCoilAddress(address);
                          }
                          if (value != null) {
                            pageCubit.updateCoilValue(value);
                          }
                        },
                        () async {
                          final register = await context
                              .read<ViewUpdater>()
                              .readCoil(pageCubit.state.holdingRegisterAddress);
                          pageCubit.state.coilValueController.text =
                              register ? 0xFF00.toString() : "0";
                        },
                        () => context.read<ViewUpdater>().writeCoil(
                            pageCubit.state.coilAddress,
                            pageCubit.state.coilValue > 0),
                      ),
                      Text(
                          "State:\nVoltage: ${model.machineState.voltage}\nCurrent ${model.machineState.current}\n Power ${model.machineState.power}"),
                    ],
                  ]),
            ),
          );
        }),
      );
}
