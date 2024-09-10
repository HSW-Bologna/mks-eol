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
import 'package:modbus_client/modbus_client.dart';

class App extends StatelessWidget {
  const App({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      title: "Test MKS",
      home: BlocProvider(
        create: (_) {
          final cubit = ViewUpdater();
          cubit.loadTestConfiguration();
          cubit.findPorts();

          Timer.periodic(const Duration(seconds: 1), (_) {
            cubit.updateState();
          });
          return cubit;
        },
        child: Builder(builder: (context) {
          final model = context.watch<ViewUpdater>().state;

          if (model.isConnected()) {
            return const TestSequencePage();
          } else {
            return const HomePage();
          }
        }),
      ),
    );
  }
}
