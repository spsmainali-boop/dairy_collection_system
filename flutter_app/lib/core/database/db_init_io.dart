// Used on Android/iOS/Desktop. Web uses db_init_web.dart instead —
// selected automatically via conditional import in db_init.dart.
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<Database> openAppDatabase(
    Future<void> Function(Database db, int version) onCreate) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = join(dir.path, 'dairy_collection.db');
  return openDatabase(path, version: 1, onCreate: onCreate);
}
