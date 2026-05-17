// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'huddle_drift_database.dart';

// ignore_for_file: type=lint
class $AppDbShardsTable extends AppDbShards
    with TableInfo<$AppDbShardsTable, AppDbShard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppDbShardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shardKeyMeta =
      const VerificationMeta('shardKey');
  @override
  late final GeneratedColumn<String> shardKey = GeneratedColumn<String>(
      'shard_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [shardKey, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_db_shards';
  @override
  VerificationContext validateIntegrity(Insertable<AppDbShard> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('shard_key')) {
      context.handle(_shardKeyMeta,
          shardKey.isAcceptableOrUnknown(data['shard_key']!, _shardKeyMeta));
    } else if (isInserting) {
      context.missing(_shardKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shardKey};
  @override
  AppDbShard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppDbShard(
      shardKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}shard_key'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $AppDbShardsTable createAlias(String alias) {
    return $AppDbShardsTable(attachedDatabase, alias);
  }
}

class AppDbShard extends DataClass implements Insertable<AppDbShard> {
  final String shardKey;
  final String payload;
  const AppDbShard({required this.shardKey, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['shard_key'] = Variable<String>(shardKey);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  AppDbShardsCompanion toCompanion(bool nullToAbsent) {
    return AppDbShardsCompanion(
      shardKey: Value(shardKey),
      payload: Value(payload),
    );
  }

  factory AppDbShard.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppDbShard(
      shardKey: serializer.fromJson<String>(json['shardKey']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shardKey': serializer.toJson<String>(shardKey),
      'payload': serializer.toJson<String>(payload),
    };
  }

  AppDbShard copyWith({String? shardKey, String? payload}) => AppDbShard(
        shardKey: shardKey ?? this.shardKey,
        payload: payload ?? this.payload,
      );
  AppDbShard copyWithCompanion(AppDbShardsCompanion data) {
    return AppDbShard(
      shardKey: data.shardKey.present ? data.shardKey.value : this.shardKey,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppDbShard(')
          ..write('shardKey: $shardKey, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(shardKey, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppDbShard &&
          other.shardKey == this.shardKey &&
          other.payload == this.payload);
}

class AppDbShardsCompanion extends UpdateCompanion<AppDbShard> {
  final Value<String> shardKey;
  final Value<String> payload;
  final Value<int> rowid;
  const AppDbShardsCompanion({
    this.shardKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppDbShardsCompanion.insert({
    required String shardKey,
    required String payload,
    this.rowid = const Value.absent(),
  })  : shardKey = Value(shardKey),
        payload = Value(payload);
  static Insertable<AppDbShard> custom({
    Expression<String>? shardKey,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shardKey != null) 'shard_key': shardKey,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppDbShardsCompanion copyWith(
      {Value<String>? shardKey, Value<String>? payload, Value<int>? rowid}) {
    return AppDbShardsCompanion(
      shardKey: shardKey ?? this.shardKey,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shardKey.present) {
      map['shard_key'] = Variable<String>(shardKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppDbShardsCompanion(')
          ..write('shardKey: $shardKey, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalKvEntriesTable extends LocalKvEntries
    with TableInfo<$LocalKvEntriesTable, LocalKvEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalKvEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryKeyMeta =
      const VerificationMeta('entryKey');
  @override
  late final GeneratedColumn<String> entryKey = GeneratedColumn<String>(
      'entry_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [entryKey, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_kv_entries';
  @override
  VerificationContext validateIntegrity(Insertable<LocalKvEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_key')) {
      context.handle(_entryKeyMeta,
          entryKey.isAcceptableOrUnknown(data['entry_key']!, _entryKeyMeta));
    } else if (isInserting) {
      context.missing(_entryKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryKey};
  @override
  LocalKvEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalKvEntry(
      entryKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entry_key'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $LocalKvEntriesTable createAlias(String alias) {
    return $LocalKvEntriesTable(attachedDatabase, alias);
  }
}

class LocalKvEntry extends DataClass implements Insertable<LocalKvEntry> {
  final String entryKey;
  final String payload;
  const LocalKvEntry({required this.entryKey, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_key'] = Variable<String>(entryKey);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  LocalKvEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalKvEntriesCompanion(
      entryKey: Value(entryKey),
      payload: Value(payload),
    );
  }

  factory LocalKvEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalKvEntry(
      entryKey: serializer.fromJson<String>(json['entryKey']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryKey': serializer.toJson<String>(entryKey),
      'payload': serializer.toJson<String>(payload),
    };
  }

  LocalKvEntry copyWith({String? entryKey, String? payload}) => LocalKvEntry(
        entryKey: entryKey ?? this.entryKey,
        payload: payload ?? this.payload,
      );
  LocalKvEntry copyWithCompanion(LocalKvEntriesCompanion data) {
    return LocalKvEntry(
      entryKey: data.entryKey.present ? data.entryKey.value : this.entryKey,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalKvEntry(')
          ..write('entryKey: $entryKey, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryKey, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalKvEntry &&
          other.entryKey == this.entryKey &&
          other.payload == this.payload);
}

class LocalKvEntriesCompanion extends UpdateCompanion<LocalKvEntry> {
  final Value<String> entryKey;
  final Value<String> payload;
  final Value<int> rowid;
  const LocalKvEntriesCompanion({
    this.entryKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalKvEntriesCompanion.insert({
    required String entryKey,
    required String payload,
    this.rowid = const Value.absent(),
  })  : entryKey = Value(entryKey),
        payload = Value(payload);
  static Insertable<LocalKvEntry> custom({
    Expression<String>? entryKey,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryKey != null) 'entry_key': entryKey,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalKvEntriesCompanion copyWith(
      {Value<String>? entryKey, Value<String>? payload, Value<int>? rowid}) {
    return LocalKvEntriesCompanion(
      entryKey: entryKey ?? this.entryKey,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryKey.present) {
      map['entry_key'] = Variable<String>(entryKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalKvEntriesCompanion(')
          ..write('entryKey: $entryKey, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HuddleDriftDb extends GeneratedDatabase {
  _$HuddleDriftDb(QueryExecutor e) : super(e);
  $HuddleDriftDbManager get managers => $HuddleDriftDbManager(this);
  late final $AppDbShardsTable appDbShards = $AppDbShardsTable(this);
  late final $LocalKvEntriesTable localKvEntries = $LocalKvEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [appDbShards, localKvEntries];
}

typedef $$AppDbShardsTableCreateCompanionBuilder = AppDbShardsCompanion
    Function({
  required String shardKey,
  required String payload,
  Value<int> rowid,
});
typedef $$AppDbShardsTableUpdateCompanionBuilder = AppDbShardsCompanion
    Function({
  Value<String> shardKey,
  Value<String> payload,
  Value<int> rowid,
});

class $$AppDbShardsTableFilterComposer
    extends Composer<_$HuddleDriftDb, $AppDbShardsTable> {
  $$AppDbShardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get shardKey => $composableBuilder(
      column: $table.shardKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$AppDbShardsTableOrderingComposer
    extends Composer<_$HuddleDriftDb, $AppDbShardsTable> {
  $$AppDbShardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get shardKey => $composableBuilder(
      column: $table.shardKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$AppDbShardsTableAnnotationComposer
    extends Composer<_$HuddleDriftDb, $AppDbShardsTable> {
  $$AppDbShardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get shardKey =>
      $composableBuilder(column: $table.shardKey, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$AppDbShardsTableTableManager extends RootTableManager<
    _$HuddleDriftDb,
    $AppDbShardsTable,
    AppDbShard,
    $$AppDbShardsTableFilterComposer,
    $$AppDbShardsTableOrderingComposer,
    $$AppDbShardsTableAnnotationComposer,
    $$AppDbShardsTableCreateCompanionBuilder,
    $$AppDbShardsTableUpdateCompanionBuilder,
    (
      AppDbShard,
      BaseReferences<_$HuddleDriftDb, $AppDbShardsTable, AppDbShard>
    ),
    AppDbShard,
    PrefetchHooks Function()> {
  $$AppDbShardsTableTableManager(_$HuddleDriftDb db, $AppDbShardsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppDbShardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppDbShardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppDbShardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> shardKey = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppDbShardsCompanion(
            shardKey: shardKey,
            payload: payload,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String shardKey,
            required String payload,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppDbShardsCompanion.insert(
            shardKey: shardKey,
            payload: payload,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppDbShardsTableProcessedTableManager = ProcessedTableManager<
    _$HuddleDriftDb,
    $AppDbShardsTable,
    AppDbShard,
    $$AppDbShardsTableFilterComposer,
    $$AppDbShardsTableOrderingComposer,
    $$AppDbShardsTableAnnotationComposer,
    $$AppDbShardsTableCreateCompanionBuilder,
    $$AppDbShardsTableUpdateCompanionBuilder,
    (
      AppDbShard,
      BaseReferences<_$HuddleDriftDb, $AppDbShardsTable, AppDbShard>
    ),
    AppDbShard,
    PrefetchHooks Function()>;
typedef $$LocalKvEntriesTableCreateCompanionBuilder = LocalKvEntriesCompanion
    Function({
  required String entryKey,
  required String payload,
  Value<int> rowid,
});
typedef $$LocalKvEntriesTableUpdateCompanionBuilder = LocalKvEntriesCompanion
    Function({
  Value<String> entryKey,
  Value<String> payload,
  Value<int> rowid,
});

class $$LocalKvEntriesTableFilterComposer
    extends Composer<_$HuddleDriftDb, $LocalKvEntriesTable> {
  $$LocalKvEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entryKey => $composableBuilder(
      column: $table.entryKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$LocalKvEntriesTableOrderingComposer
    extends Composer<_$HuddleDriftDb, $LocalKvEntriesTable> {
  $$LocalKvEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entryKey => $composableBuilder(
      column: $table.entryKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$LocalKvEntriesTableAnnotationComposer
    extends Composer<_$HuddleDriftDb, $LocalKvEntriesTable> {
  $$LocalKvEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entryKey =>
      $composableBuilder(column: $table.entryKey, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$LocalKvEntriesTableTableManager extends RootTableManager<
    _$HuddleDriftDb,
    $LocalKvEntriesTable,
    LocalKvEntry,
    $$LocalKvEntriesTableFilterComposer,
    $$LocalKvEntriesTableOrderingComposer,
    $$LocalKvEntriesTableAnnotationComposer,
    $$LocalKvEntriesTableCreateCompanionBuilder,
    $$LocalKvEntriesTableUpdateCompanionBuilder,
    (
      LocalKvEntry,
      BaseReferences<_$HuddleDriftDb, $LocalKvEntriesTable, LocalKvEntry>
    ),
    LocalKvEntry,
    PrefetchHooks Function()> {
  $$LocalKvEntriesTableTableManager(
      _$HuddleDriftDb db, $LocalKvEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalKvEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalKvEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalKvEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> entryKey = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalKvEntriesCompanion(
            entryKey: entryKey,
            payload: payload,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String entryKey,
            required String payload,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalKvEntriesCompanion.insert(
            entryKey: entryKey,
            payload: payload,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalKvEntriesTableProcessedTableManager = ProcessedTableManager<
    _$HuddleDriftDb,
    $LocalKvEntriesTable,
    LocalKvEntry,
    $$LocalKvEntriesTableFilterComposer,
    $$LocalKvEntriesTableOrderingComposer,
    $$LocalKvEntriesTableAnnotationComposer,
    $$LocalKvEntriesTableCreateCompanionBuilder,
    $$LocalKvEntriesTableUpdateCompanionBuilder,
    (
      LocalKvEntry,
      BaseReferences<_$HuddleDriftDb, $LocalKvEntriesTable, LocalKvEntry>
    ),
    LocalKvEntry,
    PrefetchHooks Function()>;

class $HuddleDriftDbManager {
  final _$HuddleDriftDb _db;
  $HuddleDriftDbManager(this._db);
  $$AppDbShardsTableTableManager get appDbShards =>
      $$AppDbShardsTableTableManager(_db, _db.appDbShards);
  $$LocalKvEntriesTableTableManager get localKvEntries =>
      $$LocalKvEntriesTableTableManager(_db, _db.localKvEntries);
}
