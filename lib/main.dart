import 'package:flutter/material.dart';
import 'package:mks_eol/controller/app.dart';
import 'package:logging/logging.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  //ModbusAppLogger(Level.FINE);
  final version = (await PackageInfo.fromPlatform()).version;

  runApp(App(version));
}
