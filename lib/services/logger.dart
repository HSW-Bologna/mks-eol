import 'package:logger/logger.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    printEmojis: false,
    printTime: true,
    noBoxingByDefault: true,
    errorMethodCount: 128,
  ),
);
