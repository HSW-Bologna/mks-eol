import 'package:flutter/material.dart';
import 'package:mks_eol/controller/app.dart';
import 'package:logging/logging.dart';
import 'package:modbus_client/modbus_client.dart';

void main() {
  ModbusAppLogger(Level.FINE);

  runApp(const App());
}
