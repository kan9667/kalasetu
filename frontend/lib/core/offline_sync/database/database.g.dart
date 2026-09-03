// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $QueueItemsTable extends QueueItems with TableInfo<$QueueItemsTable, QueueItem>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$QueueItemsTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _idMeta = const VerificationMeta('id');
@override
late final GeneratedColumn<int> id = GeneratedColumn<int>('id', aliasedName, false, hasAutoIncrement: true, type: DriftSqlType.int, requiredDuringInsert: false, defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
static const VerificationMeta _localIdMeta = const VerificationMeta('localId');
@override
late final GeneratedColumn<String> localId = GeneratedColumn<String>('local_id', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true, defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
static const VerificationMeta _typeMeta = const VerificationMeta('type');
@override
late final GeneratedColumnWithTypeConverter<QueueItemType, int> type = GeneratedColumn<int>('type', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: true).withConverter<QueueItemType>($QueueItemsTable.$convertertype);
static const VerificationMeta _localFilePathMeta = const VerificationMeta('localFilePath');
@override
late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>('local_file_path', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _productDraftIdMeta = const VerificationMeta('productDraftId');
@override
late final GeneratedColumn<String> productDraftId = GeneratedColumn<String>('product_draft_id', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _statusMeta = const VerificationMeta('status');
@override
late final GeneratedColumnWithTypeConverter<QueueStatus, int> status = GeneratedColumn<int>('status', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: false, defaultValue: Constant(QueueStatus.pending.index)).withConverter<QueueStatus>($QueueItemsTable.$converterstatus);
static const VerificationMeta _retryCountMeta = const VerificationMeta('retryCount');
@override
late final GeneratedColumn<int> retryCount = GeneratedColumn<int>('retry_count', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: false, defaultValue: const Constant(0));
static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
@override
late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>('created_at', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta('lastAttemptAt');
@override
late final GeneratedColumn<DateTime> lastAttemptAt = GeneratedColumn<DateTime>('last_attempt_at', aliasedName, true, type: DriftSqlType.dateTime, requiredDuringInsert: false);
static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
@override
late final GeneratedColumn<String> jobId = GeneratedColumn<String>('job_id', aliasedName, true, type: DriftSqlType.string, requiredDuringInsert: false);
static const VerificationMeta _errorMessageMeta = const VerificationMeta('errorMessage');
@override
late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>('error_message', aliasedName, true, type: DriftSqlType.string, requiredDuringInsert: false);
static const VerificationMeta _resultJsonMeta = const VerificationMeta('resultJson');
@override
late final GeneratedColumn<String> resultJson = GeneratedColumn<String>('result_json', aliasedName, true, type: DriftSqlType.string, requiredDuringInsert: false);
@override
List<GeneratedColumn> get $columns => [id, localId, type, localFilePath, productDraftId, status, retryCount, createdAt, lastAttemptAt, jobId, errorMessage, resultJson];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'queue_items';
@override
VerificationContext validateIntegrity(Insertable<QueueItem> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('id')) {
context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));}if (data.containsKey('local_id')) {
context.handle(_localIdMeta, localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));} else if (isInserting) {
context.missing(_localIdMeta);
}
context.handle(_typeMeta, const VerificationResult.success());if (data.containsKey('local_file_path')) {
context.handle(_localFilePathMeta, localFilePath.isAcceptableOrUnknown(data['local_file_path']!, _localFilePathMeta));} else if (isInserting) {
context.missing(_localFilePathMeta);
}
if (data.containsKey('product_draft_id')) {
context.handle(_productDraftIdMeta, productDraftId.isAcceptableOrUnknown(data['product_draft_id']!, _productDraftIdMeta));} else if (isInserting) {
context.missing(_productDraftIdMeta);
}
context.handle(_statusMeta, const VerificationResult.success());if (data.containsKey('retry_count')) {
context.handle(_retryCountMeta, retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta));}if (data.containsKey('created_at')) {
context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));} else if (isInserting) {
context.missing(_createdAtMeta);
}
if (data.containsKey('last_attempt_at')) {
context.handle(_lastAttemptAtMeta, lastAttemptAt.isAcceptableOrUnknown(data['last_attempt_at']!, _lastAttemptAtMeta));}if (data.containsKey('job_id')) {
context.handle(_jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));}if (data.containsKey('error_message')) {
context.handle(_errorMessageMeta, errorMessage.isAcceptableOrUnknown(data['error_message']!, _errorMessageMeta));}if (data.containsKey('result_json')) {
context.handle(_resultJsonMeta, resultJson.isAcceptableOrUnknown(data['result_json']!, _resultJsonMeta));}return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {id};
@override QueueItem map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return QueueItem(id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!, localId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}local_id'])!, type: $QueueItemsTable.$convertertype.fromSql(attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}type'])!), localFilePath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}local_file_path'])!, productDraftId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}product_draft_id'])!, status: $QueueItemsTable.$converterstatus.fromSql(attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}status'])!), retryCount: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!, createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!, lastAttemptAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}last_attempt_at']), jobId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}job_id']), errorMessage: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}error_message']), resultJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}result_json']), );
}
@override
$QueueItemsTable createAlias(String alias) {
return $QueueItemsTable(attachedDatabase, alias);}static JsonTypeConverter2<QueueItemType,int,int> $convertertype = const EnumIndexConverter<QueueItemType>(QueueItemType.values);static JsonTypeConverter2<QueueStatus,int,int> $converterstatus = const EnumIndexConverter<QueueStatus>(QueueStatus.values);}class QueueItem extends DataClass implements Insertable<QueueItem> 
{
final int id;
final String localId;
final QueueItemType type;
final String localFilePath;
final String productDraftId;
final QueueStatus status;
final int retryCount;
final DateTime createdAt;
final DateTime? lastAttemptAt;
final String? jobId;
final String? errorMessage;
final String? resultJson;
const QueueItem({required this.id, required this.localId, required this.type, required this.localFilePath, required this.productDraftId, required this.status, required this.retryCount, required this.createdAt, this.lastAttemptAt, this.jobId, this.errorMessage, this.resultJson});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['id'] = Variable<int>(id);
map['local_id'] = Variable<String>(localId);
{map['type'] = Variable<int>($QueueItemsTable.$convertertype.toSql(type));
}map['local_file_path'] = Variable<String>(localFilePath);
map['product_draft_id'] = Variable<String>(productDraftId);
{map['status'] = Variable<int>($QueueItemsTable.$converterstatus.toSql(status));
}map['retry_count'] = Variable<int>(retryCount);
map['created_at'] = Variable<DateTime>(createdAt);
if (!nullToAbsent || lastAttemptAt != null){map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
}if (!nullToAbsent || jobId != null){map['job_id'] = Variable<String>(jobId);
}if (!nullToAbsent || errorMessage != null){map['error_message'] = Variable<String>(errorMessage);
}if (!nullToAbsent || resultJson != null){map['result_json'] = Variable<String>(resultJson);
}return map; 
}
QueueItemsCompanion toCompanion(bool nullToAbsent) {
return QueueItemsCompanion(id: Value(id),localId: Value(localId),type: Value(type),localFilePath: Value(localFilePath),productDraftId: Value(productDraftId),status: Value(status),retryCount: Value(retryCount),createdAt: Value(createdAt),lastAttemptAt: lastAttemptAt == null && nullToAbsent ? const Value.absent() : Value(lastAttemptAt),jobId: jobId == null && nullToAbsent ? const Value.absent() : Value(jobId),errorMessage: errorMessage == null && nullToAbsent ? const Value.absent() : Value(errorMessage),resultJson: resultJson == null && nullToAbsent ? const Value.absent() : Value(resultJson),);
}
factory QueueItem.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return QueueItem(id: serializer.fromJson<int>(json['id']),localId: serializer.fromJson<String>(json['localId']),type: $QueueItemsTable.$convertertype.fromJson(serializer.fromJson<int>(json['type'])),localFilePath: serializer.fromJson<String>(json['localFilePath']),productDraftId: serializer.fromJson<String>(json['productDraftId']),status: $QueueItemsTable.$converterstatus.fromJson(serializer.fromJson<int>(json['status'])),retryCount: serializer.fromJson<int>(json['retryCount']),createdAt: serializer.fromJson<DateTime>(json['createdAt']),lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),jobId: serializer.fromJson<String?>(json['jobId']),errorMessage: serializer.fromJson<String?>(json['errorMessage']),resultJson: serializer.fromJson<String?>(json['resultJson']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'id': serializer.toJson<int>(id),'localId': serializer.toJson<String>(localId),'type': serializer.toJson<int>($QueueItemsTable.$convertertype.toJson(type)),'localFilePath': serializer.toJson<String>(localFilePath),'productDraftId': serializer.toJson<String>(productDraftId),'status': serializer.toJson<int>($QueueItemsTable.$converterstatus.toJson(status)),'retryCount': serializer.toJson<int>(retryCount),'createdAt': serializer.toJson<DateTime>(createdAt),'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),'jobId': serializer.toJson<String?>(jobId),'errorMessage': serializer.toJson<String?>(errorMessage),'resultJson': serializer.toJson<String?>(resultJson),};}QueueItem copyWith({int? id,String? localId,QueueItemType? type,String? localFilePath,String? productDraftId,QueueStatus? status,int? retryCount,DateTime? createdAt,Value<DateTime?> lastAttemptAt = const Value.absent(),Value<String?> jobId = const Value.absent(),Value<String?> errorMessage = const Value.absent(),Value<String?> resultJson = const Value.absent()}) => QueueItem(id: id ?? this.id,localId: localId ?? this.localId,type: type ?? this.type,localFilePath: localFilePath ?? this.localFilePath,productDraftId: productDraftId ?? this.productDraftId,status: status ?? this.status,retryCount: retryCount ?? this.retryCount,createdAt: createdAt ?? this.createdAt,lastAttemptAt: lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,jobId: jobId.present ? jobId.value : this.jobId,errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,resultJson: resultJson.present ? resultJson.value : this.resultJson,);QueueItem copyWithCompanion(QueueItemsCompanion data) {
return QueueItem(
id: data.id.present ? data.id.value : this.id,localId: data.localId.present ? data.localId.value : this.localId,type: data.type.present ? data.type.value : this.type,localFilePath: data.localFilePath.present ? data.localFilePath.value : this.localFilePath,productDraftId: data.productDraftId.present ? data.productDraftId.value : this.productDraftId,status: data.status.present ? data.status.value : this.status,retryCount: data.retryCount.present ? data.retryCount.value : this.retryCount,createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,lastAttemptAt: data.lastAttemptAt.present ? data.lastAttemptAt.value : this.lastAttemptAt,jobId: data.jobId.present ? data.jobId.value : this.jobId,errorMessage: data.errorMessage.present ? data.errorMessage.value : this.errorMessage,resultJson: data.resultJson.present ? data.resultJson.value : this.resultJson,);
}
@override
String toString() {return (StringBuffer('QueueItem(')..write('id: $id, ')..write('localId: $localId, ')..write('type: $type, ')..write('localFilePath: $localFilePath, ')..write('productDraftId: $productDraftId, ')..write('status: $status, ')..write('retryCount: $retryCount, ')..write('createdAt: $createdAt, ')..write('lastAttemptAt: $lastAttemptAt, ')..write('jobId: $jobId, ')..write('errorMessage: $errorMessage, ')..write('resultJson: $resultJson')..write(')')).toString();}
@override
 int get hashCode => Object.hash(id, localId, type, localFilePath, productDraftId, status, retryCount, createdAt, lastAttemptAt, jobId, errorMessage, resultJson);@override
bool operator ==(Object other) => identical(this, other) || (other is QueueItem && other.id == this.id && other.localId == this.localId && other.type == this.type && other.localFilePath == this.localFilePath && other.productDraftId == this.productDraftId && other.status == this.status && other.retryCount == this.retryCount && other.createdAt == this.createdAt && other.lastAttemptAt == this.lastAttemptAt && other.jobId == this.jobId && other.errorMessage == this.errorMessage && other.resultJson == this.resultJson);
}class QueueItemsCompanion extends UpdateCompanion<QueueItem> {
final Value<int> id;
final Value<String> localId;
final Value<QueueItemType> type;
final Value<String> localFilePath;
final Value<String> productDraftId;
final Value<QueueStatus> status;
final Value<int> retryCount;
final Value<DateTime> createdAt;
final Value<DateTime?> lastAttemptAt;
final Value<String?> jobId;
final Value<String?> errorMessage;
final Value<String?> resultJson;
const QueueItemsCompanion({this.id = const Value.absent(),this.localId = const Value.absent(),this.type = const Value.absent(),this.localFilePath = const Value.absent(),this.productDraftId = const Value.absent(),this.status = const Value.absent(),this.retryCount = const Value.absent(),this.createdAt = const Value.absent(),this.lastAttemptAt = const Value.absent(),this.jobId = const Value.absent(),this.errorMessage = const Value.absent(),this.resultJson = const Value.absent(),});
QueueItemsCompanion.insert({this.id = const Value.absent(),required String localId,required QueueItemType type,required String localFilePath,required String productDraftId,this.status = const Value.absent(),this.retryCount = const Value.absent(),required DateTime createdAt,this.lastAttemptAt = const Value.absent(),this.jobId = const Value.absent(),this.errorMessage = const Value.absent(),this.resultJson = const Value.absent(),}): localId = Value(localId), type = Value(type), localFilePath = Value(localFilePath), productDraftId = Value(productDraftId), createdAt = Value(createdAt);
static Insertable<QueueItem> custom({Expression<int>? id, 
Expression<String>? localId, 
Expression<int>? type, 
Expression<String>? localFilePath, 
Expression<String>? productDraftId, 
Expression<int>? status, 
Expression<int>? retryCount, 
Expression<DateTime>? createdAt, 
Expression<DateTime>? lastAttemptAt, 
Expression<String>? jobId, 
Expression<String>? errorMessage, 
Expression<String>? resultJson, 
}) {
return RawValuesInsertable({if (id != null)'id': id,if (localId != null)'local_id': localId,if (type != null)'type': type,if (localFilePath != null)'local_file_path': localFilePath,if (productDraftId != null)'product_draft_id': productDraftId,if (status != null)'status': status,if (retryCount != null)'retry_count': retryCount,if (createdAt != null)'created_at': createdAt,if (lastAttemptAt != null)'last_attempt_at': lastAttemptAt,if (jobId != null)'job_id': jobId,if (errorMessage != null)'error_message': errorMessage,if (resultJson != null)'result_json': resultJson,});
}QueueItemsCompanion copyWith({Value<int>? id, Value<String>? localId, Value<QueueItemType>? type, Value<String>? localFilePath, Value<String>? productDraftId, Value<QueueStatus>? status, Value<int>? retryCount, Value<DateTime>? createdAt, Value<DateTime?>? lastAttemptAt, Value<String?>? jobId, Value<String?>? errorMessage, Value<String?>? resultJson}) {
return QueueItemsCompanion(id: id ?? this.id,localId: localId ?? this.localId,type: type ?? this.type,localFilePath: localFilePath ?? this.localFilePath,productDraftId: productDraftId ?? this.productDraftId,status: status ?? this.status,retryCount: retryCount ?? this.retryCount,createdAt: createdAt ?? this.createdAt,lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,jobId: jobId ?? this.jobId,errorMessage: errorMessage ?? this.errorMessage,resultJson: resultJson ?? this.resultJson,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (id.present) {
map['id'] = Variable<int>(id.value);}
if (localId.present) {
map['local_id'] = Variable<String>(localId.value);}
if (type.present) {
map['type'] = Variable<int>($QueueItemsTable.$convertertype.toSql(type.value));}
if (localFilePath.present) {
map['local_file_path'] = Variable<String>(localFilePath.value);}
if (productDraftId.present) {
map['product_draft_id'] = Variable<String>(productDraftId.value);}
if (status.present) {
map['status'] = Variable<int>($QueueItemsTable.$converterstatus.toSql(status.value));}
if (retryCount.present) {
map['retry_count'] = Variable<int>(retryCount.value);}
if (createdAt.present) {
map['created_at'] = Variable<DateTime>(createdAt.value);}
if (lastAttemptAt.present) {
map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);}
if (jobId.present) {
map['job_id'] = Variable<String>(jobId.value);}
if (errorMessage.present) {
map['error_message'] = Variable<String>(errorMessage.value);}
if (resultJson.present) {
map['result_json'] = Variable<String>(resultJson.value);}
return map; 
}
@override
String toString() {return (StringBuffer('QueueItemsCompanion(')..write('id: $id, ')..write('localId: $localId, ')..write('type: $type, ')..write('localFilePath: $localFilePath, ')..write('productDraftId: $productDraftId, ')..write('status: $status, ')..write('retryCount: $retryCount, ')..write('createdAt: $createdAt, ')..write('lastAttemptAt: $lastAttemptAt, ')..write('jobId: $jobId, ')..write('errorMessage: $errorMessage, ')..write('resultJson: $resultJson')..write(')')).toString();}
}
abstract class _$OfflineSyncDatabase extends GeneratedDatabase{
_$OfflineSyncDatabase(QueryExecutor e): super(e);
$OfflineSyncDatabaseManager get managers => $OfflineSyncDatabaseManager(this);
late final $QueueItemsTable queueItems = $QueueItemsTable(this);
@override
Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
@override
List<DatabaseSchemaEntity> get allSchemaEntities => [queueItems];
}
typedef $$QueueItemsTableCreateCompanionBuilder = QueueItemsCompanion Function({Value<int> id,required String localId,required QueueItemType type,required String localFilePath,required String productDraftId,Value<QueueStatus> status,Value<int> retryCount,required DateTime createdAt,Value<DateTime?> lastAttemptAt,Value<String?> jobId,Value<String?> errorMessage,Value<String?> resultJson,});
typedef $$QueueItemsTableUpdateCompanionBuilder = QueueItemsCompanion Function({Value<int> id,Value<String> localId,Value<QueueItemType> type,Value<String> localFilePath,Value<String> productDraftId,Value<QueueStatus> status,Value<int> retryCount,Value<DateTime> createdAt,Value<DateTime?> lastAttemptAt,Value<String?> jobId,Value<String?> errorMessage,Value<String?> resultJson,});
class $$QueueItemsTableFilterComposer extends Composer<
        _$OfflineSyncDatabase,
        $QueueItemsTable> {
        $$QueueItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<int> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get localId => $composableBuilder(
      column: $table.localId,
      builder: (column) => 
      ColumnFilters(column));
      
          ColumnWithTypeConverterFilters<QueueItemType,QueueItemType,int> get type => $composableBuilder(
      column: $table.type,
      builder: (column) => 
      ColumnWithTypeConverterFilters(column));
      
ColumnFilters<String> get localFilePath => $composableBuilder(
      column: $table.localFilePath,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get productDraftId => $composableBuilder(
      column: $table.productDraftId,
      builder: (column) => 
      ColumnFilters(column));
      
          ColumnWithTypeConverterFilters<QueueStatus,QueueStatus,int> get status => $composableBuilder(
      column: $table.status,
      builder: (column) => 
      ColumnWithTypeConverterFilters(column));
      
ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get jobId => $composableBuilder(
      column: $table.jobId,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get resultJson => $composableBuilder(
      column: $table.resultJson,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$QueueItemsTableOrderingComposer extends Composer<
        _$OfflineSyncDatabase,
        $QueueItemsTable> {
        $$QueueItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get localId => $composableBuilder(
      column: $table.localId,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get localFilePath => $composableBuilder(
      column: $table.localFilePath,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get productDraftId => $composableBuilder(
      column: $table.productDraftId,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get jobId => $composableBuilder(
      column: $table.jobId,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get resultJson => $composableBuilder(
      column: $table.resultJson,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$QueueItemsTableAnnotationComposer extends Composer<
        _$OfflineSyncDatabase,
        $QueueItemsTable> {
        $$QueueItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<int> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => column);
      
GeneratedColumn<String> get localId => $composableBuilder(
      column: $table.localId,
      builder: (column) => column);
      
          GeneratedColumnWithTypeConverter<QueueItemType,int> get type => $composableBuilder(
      column: $table.type,
      builder: (column) => column);
      
GeneratedColumn<String> get localFilePath => $composableBuilder(
      column: $table.localFilePath,
      builder: (column) => column);
      
GeneratedColumn<String> get productDraftId => $composableBuilder(
      column: $table.productDraftId,
      builder: (column) => column);
      
          GeneratedColumnWithTypeConverter<QueueStatus,int> get status => $composableBuilder(
      column: $table.status,
      builder: (column) => column);
      
GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => column);
      
GeneratedColumn<String> get jobId => $composableBuilder(
      column: $table.jobId,
      builder: (column) => column);
      
GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => column);
      
GeneratedColumn<String> get resultJson => $composableBuilder(
      column: $table.resultJson,
      builder: (column) => column);
      
        }
      class $$QueueItemsTableTableManager extends RootTableManager    <_$OfflineSyncDatabase,
    $QueueItemsTable,
    QueueItem,
    $$QueueItemsTableFilterComposer,
    $$QueueItemsTableOrderingComposer,
    $$QueueItemsTableAnnotationComposer,
    $$QueueItemsTableCreateCompanionBuilder,
    $$QueueItemsTableUpdateCompanionBuilder,
    (QueueItem,BaseReferences<_$OfflineSyncDatabase,$QueueItemsTable,QueueItem>),
    QueueItem,
    PrefetchHooks Function()
    > {
    $$QueueItemsTableTableManager(_$OfflineSyncDatabase db, $QueueItemsTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$QueueItemsTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$QueueItemsTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$QueueItemsTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<int> id = const Value.absent(),Value<String> localId = const Value.absent(),Value<QueueItemType> type = const Value.absent(),Value<String> localFilePath = const Value.absent(),Value<String> productDraftId = const Value.absent(),Value<QueueStatus> status = const Value.absent(),Value<int> retryCount = const Value.absent(),Value<DateTime> createdAt = const Value.absent(),Value<DateTime?> lastAttemptAt = const Value.absent(),Value<String?> jobId = const Value.absent(),Value<String?> errorMessage = const Value.absent(),Value<String?> resultJson = const Value.absent(),})=> QueueItemsCompanion(id: id,localId: localId,type: type,localFilePath: localFilePath,productDraftId: productDraftId,status: status,retryCount: retryCount,createdAt: createdAt,lastAttemptAt: lastAttemptAt,jobId: jobId,errorMessage: errorMessage,resultJson: resultJson,),
        createCompanionCallback: ({Value<int> id = const Value.absent(),required String localId,required QueueItemType type,required String localFilePath,required String productDraftId,Value<QueueStatus> status = const Value.absent(),Value<int> retryCount = const Value.absent(),required DateTime createdAt,Value<DateTime?> lastAttemptAt = const Value.absent(),Value<String?> jobId = const Value.absent(),Value<String?> errorMessage = const Value.absent(),Value<String?> resultJson = const Value.absent(),})=> QueueItemsCompanion.insert(id: id,localId: localId,type: type,localFilePath: localFilePath,productDraftId: productDraftId,status: status,retryCount: retryCount,createdAt: createdAt,lastAttemptAt: lastAttemptAt,jobId: jobId,errorMessage: errorMessage,resultJson: resultJson,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$QueueItemsTableProcessedTableManager = ProcessedTableManager    <_$OfflineSyncDatabase,
    $QueueItemsTable,
    QueueItem,
    $$QueueItemsTableFilterComposer,
    $$QueueItemsTableOrderingComposer,
    $$QueueItemsTableAnnotationComposer,
    $$QueueItemsTableCreateCompanionBuilder,
    $$QueueItemsTableUpdateCompanionBuilder,
    (QueueItem,BaseReferences<_$OfflineSyncDatabase,$QueueItemsTable,QueueItem>),
    QueueItem,
    PrefetchHooks Function()
    >;class $OfflineSyncDatabaseManager {
final _$OfflineSyncDatabase _db;
$OfflineSyncDatabaseManager(this._db);
$$QueueItemsTableTableManager get queueItems => $$QueueItemsTableTableManager(_db, _db.queueItems);
}
