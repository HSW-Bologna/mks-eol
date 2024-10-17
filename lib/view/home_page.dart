import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';

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

        final pageCubit = context.read<_PageCubit>();

        return Scaffold(
            body: SizedBox.expand(
                child: Padding(
          padding: const EdgeInsets.all(16),
          child: _statusMessage(),
        )));
      }));
}

Widget _statusMessage() =>
    BlocBuilder<ViewUpdater, Model>(builder: (context, model) {
      if (model.isWaitingForConfiguration()) {
        return const Text("Attendere...");
      } else if (model.isThereAConfigurationError()) {
        return Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              const Text("Configurazione errata!"),
              const SizedBox(height: 32),
              ElevatedButton(
                  onPressed: () {
                    context.read<ViewUpdater>().loadTestConfiguration();
                  },
                  child: const Padding(
                      padding: EdgeInsets.all(8), child: Text("Riprova")))
            ]));
      } else if (model.isThereAConnectionError()) {
        return Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              Text(
                  "Problema di comunicazione con i dispositivi: ${model.ports.value.failure}"),
              const SizedBox(height: 32),
              ElevatedButton(
                  onPressed: () {
                    context.read<ViewUpdater>().findPorts();
                  },
                  child: const Padding(
                      padding: EdgeInsets.all(8), child: Text("Riprova")))
            ]));
      } else if (model.ports.isEmpty) {
        return const Text("Connessione in corso...");
      } else {
        return const Text("Attendere...");
      }
    });
