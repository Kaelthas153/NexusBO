import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:nexusbo/services/database/tables/articles_table.dart';

/// Gestor de la base de datos SQLite local (`nexusbo.db`).
///
/// Características:
/// - Conexión única (singleton) protegida contra aperturas concurrentes.
/// - Soporte estructurado para migraciones mediante [databaseVersion] y [_onUpgrade].
class AppDatabase {
  AppDatabase._internal({String? customDatabasePath})
    : _customDatabasePath = customDatabasePath;

  /// Instancia principal de producción (`nexusbo.db`).
  static final AppDatabase instance = AppDatabase._internal();

  /// Constructor auxiliar para pruebas aisladas con ruta personalizada o en memoria.
  factory AppDatabase.forTesting({required String databasePath}) {
    return AppDatabase._internal(customDatabasePath: databasePath);
  }

  static const String databaseName = 'nexusbo.db';

  /// Versión 2: agrega `image_urls_json` en `articles` para soportar múltiples
  /// imágenes por noticia sin perder datos existentes de la versión 1.
  static const int databaseVersion = 2;

  final String? _customDatabasePath;
  Database? _database;
  Future<Database>? _openingFuture;

  /// Obtiene la instancia activa de [Database], abriéndola una única vez si
  /// todavía no ha sido inicializada.
  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final inProgress = _openingFuture;
    if (inProgress != null) {
      return inProgress;
    }

    final future = _initDatabase();
    _openingFuture = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      _openingFuture = null;
    }
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (_customDatabasePath != null) {
      path = _customDatabasePath;
    } else {
      final databasesDir = await getDatabasesPath();
      path = p.join(databasesDir, databaseName);
    }

    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute(ArticlesTable.createTableSql);
    for (final indexSql in ArticlesTable.createIndexesSql) {
      batch.execute(indexSql);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final tableInfo = await db.rawQuery(
        'PRAGMA table_info(${ArticlesTable.tableName})',
      );
      final hasImageUrlsCol = tableInfo.any(
        (col) => col['name'] == ArticlesTable.colImageUrlsJson,
      );
      if (!hasImageUrlsCol) {
        await db.execute(ArticlesTable.alterTableAddImageUrlsJsonSql);
        await db.execute(ArticlesTable.backfillImageUrlsJsonFromImageUrlSql);
      }
    }
  }

  /// Cierra la conexión actual de forma segura.
  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
