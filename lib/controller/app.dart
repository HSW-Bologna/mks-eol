import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:mks_eol/controller/view_updater.dart';
import 'package:mks_eol/model/model.dart';
import 'package:mks_eol/services/logger.dart';
import 'package:mks_eol/view/home_page.dart';
import 'package:mks_eol/view/test_sequence_page.dart';
import 'package:mks_eol/view/theme.dart';

class App extends StatelessWidget {
  final String version;

  const App(this.version, {super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      title: "Test MKS ${this.version}",
      home: BlocProvider(
        create: (_) {
          final cubit = ViewUpdater();
          cubit.loadTestConfiguration().then((_) {
            cubit.findPorts();
          });

          Timer.periodic(const Duration(seconds: 1), (_) {
            cubit.updateState();
          });
          return cubit;
        },
        child: Builder(builder: (context) {
          final model = context.watch<ViewUpdater>().state;

          return Stack(children: [
            Align(
              alignment: Alignment.center,
              child: (model.isConnected() && model.isConfigured())
                  ? const TestSequencePage()
                  : const HomePage(),
            ),
            Align(
                alignment: Alignment.topRight,
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      this.version,
                      style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          decoration: TextDecoration.none),
                    ))),
          ]);
        }),
      ),
    );
  }
}
