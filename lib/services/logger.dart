import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    printEmojis: false,
    printTime: true,
    noBoxingByDefault: true,
    errorMethodCount: 128,
  ),
  //output: AppFileOutput(),
);


class AppFileOutput extends LogOutput {
  AppFileOutput();

  late File file;

  @override
  void output(OutputEvent event) async {
    late File file = File('mks-eol.log');
    
    for (var line in event.lines) {
      await file.writeAsString("${line.toString()}\n", mode: FileMode.writeOnlyAppend);
      debugPrint(line); //print to console as well
    }
  }
}