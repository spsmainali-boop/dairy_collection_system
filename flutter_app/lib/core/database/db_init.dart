// Conditional export: the `dart.library.html` check picks the web
// implementation when compiling for Flutter Web, and the IO implementation
// (sqflite + path_provider) everywhere else (Android/iOS/Desktop).
export 'db_init_io.dart' if (dart.library.html) 'db_init_web.dart';
