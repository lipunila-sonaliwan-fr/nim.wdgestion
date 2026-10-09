# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026

# Low-level C interface (Wrapper Pragmas sur libduckdb)

const
  duckdbLib = when defined(windows):
                "./winOS/libduckdb.dll"
              elif defined(macosx):
                "./macOS/libduckdb.dylib"
              else:
                "./linOS/libduckdb.so"

type
  DuckDBState* {.size: sizeof(cint).} = enum
    DuckDBSuccess = 0
    DuckDBError = 1

  DuckDBType* {.size: sizeof(cint).} = enum
    DuckDBTypeInvalid = 0
    DuckDBTypeBoolean = 1
    DuckDBTypeTinyInt = 2
    DuckDBTypeSmallInt = 3
    DuckDBTypeInteger = 4
    DuckDBTypeBigInt = 5
    DuckDBTypeUTinyInt = 6
    DuckDBTypeUSmallInt = 7
    DuckDBTypeUInteger = 8
    DuckDBTypeUBigInt = 9
    DuckDBTypeFloat = 10
    DuckDBTypeDouble = 11
    DuckDBTypeTimestamp = 12
    DuckDBTypeDate = 13
    DuckDBTypeTime = 14
    DuckDBTypeInterval = 15
    DuckDBTypeHugeInt = 16
    DuckDBTypeVarchar = 17
    DuckDBTypeBlob = 18

  # Dynamic Handle Structures
  DuckDBDatabaseObj {.pure.} = object
  DuckDBConnectionObj {.pure.} = object
  DuckDBPreparedStatementObj {.pure.} = object
  DuckDBAppenderObj {.pure.} = object

  DuckDBDatabase* = ptr DuckDBDatabaseObj
  DuckDBConnection* = ptr DuckDBConnectionObj
  DuckDBPreparedStatement* = ptr DuckDBPreparedStatementObj
  DuckDBAppender* = ptr DuckDBAppenderObj

  DuckDBColumn* {.importc: "duckdb_column", header: "duckdb.h", bycopy.} = object
    deprecated_data*: pointer
    deprecated_nullmask*: ptr bool
    deprecated_type*: DuckDBType
    deprecated_name*: cstring
    internal_data*: pointer

  DuckDBResult* {.importc: "duckdb_result", header: "duckdb.h", bycopy.} = object
    deprecated_column_count*: uint64
    deprecated_row_count*: uint64
    deprecated_rows_changed*: uint64
    deprecated_columns*: ptr DuckDBColumn
    deprecated_error_message*: cstring
    internal_data*: pointer

  DuckDBLogicalType* = pointer
  DuckDBDataChunk* = pointer
  DuckDBVector* = pointer

# API Functions (Import C)
{.push dynlib: duckdbLib, cdecl.}

proc duckdb_open*(path: cstring, out_database: ptr DuckDBDatabase): DuckDBState {.importc.}
proc duckdb_close*(database: ptr DuckDBDatabase) {.importc.}
proc duckdb_connect*(database: DuckDBDatabase, out_connection: ptr DuckDBConnection): DuckDBState {.importc.}
proc duckdb_disconnect*(connection: ptr DuckDBConnection) {.importc.}

proc duckdb_query*(connection: DuckDBConnection, query: cstring, out_result: ptr DuckDBResult): DuckDBState {.importc.}
proc duckdb_destroy_result*(result: ptr DuckDBResult) {.importc.}

proc duckdb_column_name*(result: ptr DuckDBResult, col: uint64): cstring {.importc.}
proc duckdb_column_type*(result: ptr DuckDBResult, col: uint64): DuckDBType {.importc.}
proc duckdb_column_count*(result: ptr DuckDBResult): uint64 {.importc.}
proc duckdb_row_count*(result: ptr DuckDBResult): uint64 {.importc.}
proc duckdb_result_error*(result: ptr DuckDBResult): cstring {.importc.}

# Prepared Statements
proc duckdb_prepare*(connection: DuckDBConnection, query: cstring, out_prepared: ptr DuckDBPreparedStatement): DuckDBState {.importc.}
proc duckdb_destroy_prepare*(prepared: ptr DuckDBPreparedStatement) {.importc.}
proc duckdb_bind_boolean*(prepared: DuckDBPreparedStatement, idx: uint64, val: bool): DuckDBState {.importc.}
proc duckdb_bind_int32*(prepared: DuckDBPreparedStatement, idx: uint64, val: int32): DuckDBState {.importc.}
proc duckdb_bind_int64*(prepared: DuckDBPreparedStatement, idx: uint64, val: int64): DuckDBState {.importc.}
proc duckdb_bind_double*(prepared: DuckDBPreparedStatement, idx: uint64, val: float64): DuckDBState {.importc.}
proc duckdb_bind_varchar*(prepared: DuckDBPreparedStatement, idx: uint64, val: cstring): DuckDBState {.importc.}
proc duckdb_bind_null*(prepared: DuckDBPreparedStatement, idx: uint64): DuckDBState {.importc.}
proc duckdb_execute_prepared*(prepared: DuckDBPreparedStatement, out_result: ptr DuckDBResult): DuckDBState {.importc.}

# Extractors per-cell
proc duckdb_value_boolean*(result: ptr DuckDBResult, col, row: uint64): bool {.importc.}
proc duckdb_value_int8*(result: ptr DuckDBResult, col, row: uint64): int8 {.importc.}
proc duckdb_value_int16*(result: ptr DuckDBResult, col, row: uint64): int16 {.importc.}
proc duckdb_value_int32*(result: ptr DuckDBResult, col, row: uint64): int32 {.importc.}
proc duckdb_value_int64*(result: ptr DuckDBResult, col, row: uint64): int64 {.importc.}
proc duckdb_value_float*(result: ptr DuckDBResult, col, row: uint64): float32 {.importc.}
proc duckdb_value_double*(result: ptr DuckDBResult, col, row: uint64): float64 {.importc.}
proc duckdb_value_varchar*(result: ptr DuckDBResult, col, row: uint64): cstring {.importc.}
proc duckdb_value_is_null*(result: ptr DuckDBResult, col, row: uint64): bool {.importc.}

# Memory management
proc duckdb_free*(ptr_val: pointer) {.importc.}

{.pop.}

# Nim Abstraction (High-Level API)

type
  DuckDBException* = object of CatchableError

  DB* = object
    dbPtr: DuckDBDatabase

  Conn* = object
    connPtr: DuckDBConnection

  Rows* = object
    resPtr*: ptr DuckDBResult
    colCount*: int
    rowCount*: int

  ValueKind* = enum
    vkNull, vkBool, vkInt, vkFloat, vkString

  Value* = object
    case kind*: ValueKind
    of vkNull: discard
    of vkBool: boolVal*: bool
    of vkInt: intVal*: int64
    of vkFloat: floatVal*: float64
    of vkString: strVal*: string

# Database & Connection
proc openDB*(path: string = ":memory:"): DB =
  var dbPtr: DuckDBDatabase
  if duckdb_open(path.cstring, addr dbPtr) == DuckDBError:
    raise newException(DuckDBException, "Failed to open DuckDB database at " & path)
  result = DB(dbPtr: dbPtr)

proc close*(db: var DB) =
  if db.dbPtr != nil:
    duckdb_close(addr db.dbPtr)

proc connect*(db: DB): Conn =
  var connPtr: DuckDBConnection
  if duckdb_connect(db.dbPtr, addr connPtr) == DuckDBError:
    raise newException(DuckDBException, "Failed to establish DuckDB connection.")
  result = Conn(connPtr: connPtr)

proc close*(conn: var Conn) =
  if conn.connPtr != nil:
    duckdb_disconnect(addr conn.connPtr)

# Rows Management
proc close*(rows: var Rows) =
  if rows.resPtr != nil:
    duckdb_destroy_result(rows.resPtr)
    dealloc(rows.resPtr)
    rows.resPtr = nil

proc exec*(conn: Conn, query: string) =
  var res: DuckDBResult
  if duckdb_query(conn.connPtr, query.cstring, addr res) == DuckDBError:
    let err = $duckdb_result_error(addr res)
    duckdb_destroy_result(addr res)
    raise newException(DuckDBException, "Query execution error: " & err)
  duckdb_destroy_result(addr res)

proc query*(conn: Conn, query: string): Rows =
  var resPtr = cast[ptr DuckDBResult](alloc0(sizeof(DuckDBResult)))
  if duckdb_query(conn.connPtr, query.cstring, resPtr) == DuckDBError:
    let err = $duckdb_result_error(resPtr)
    duckdb_destroy_result(resPtr)
    dealloc(resPtr)
    raise newException(DuckDBException, "Query error: " & err)

  result = Rows(
    resPtr: resPtr,
    colCount: duckdb_column_count(resPtr).int,
    rowCount: duckdb_row_count(resPtr).int
  )

proc columns*(rows: Rows): seq[string] =
  result = newSeq[string](rows.colCount)
  for i in 0 ..< rows.colCount:
    result[i] = $duckdb_column_name(rows.resPtr, i.uint64)

proc getValue*(rows: Rows, col, row: int): Value =
  let c = col.uint64
  let r = row.uint64

  if duckdb_value_is_null(rows.resPtr, c, r):
    return Value(kind: vkNull)

  let t = duckdb_column_type(rows.resPtr, c)
  case t
  of DuckDBTypeBoolean:
    Value(kind: vkBool, boolVal: duckdb_value_boolean(rows.resPtr, c, r))
  of DuckDBTypeTinyInt:
    Value(kind: vkInt, intVal: duckdb_value_int8(rows.resPtr, c, r).int64)
  of DuckDBTypeSmallInt:
    Value(kind: vkInt, intVal: duckdb_value_int16(rows.resPtr, c, r).int64)
  of DuckDBTypeInteger:
    Value(kind: vkInt, intVal: duckdb_value_int32(rows.resPtr, c, r).int64)
  of DuckDBTypeBigInt:
    Value(kind: vkInt, intVal: duckdb_value_int64(rows.resPtr, c, r))
  of DuckDBTypeFloat:
    Value(kind: vkFloat, floatVal: duckdb_value_float(rows.resPtr, c, r).float64)
  of DuckDBTypeDouble:
    Value(kind: vkFloat, floatVal: duckdb_value_double(rows.resPtr, c, r))
  else:
    let cStr = duckdb_value_varchar(rows.resPtr, c, r)
    if cStr == nil:
      Value(kind: vkNull)
    else:
      let s = $cStr
      duckdb_free(cStr)
      Value(kind: vkString, strVal: s)

# Line extraction iterator in the form of seq[Value]
iterator items*(rows: Rows): seq[Value] =
  for r in 0 ..< rows.rowCount:
    var rowValues = newSeq[Value](rows.colCount)
    for c in 0 ..< rows.colCount:
      rowValues[c] = rows.getValue(c, r)
    yield rowValues

# Display
proc `$`*(val: Value): string =
  case val.kind
  of vkNull: "NULL"
  of vkBool: $val.boolVal
  of vkInt: $val.intVal
  of vkFloat: $val.floatVal
  of vkString: val.strVal

when isMainModule:
  echo "Import this file by writing ``import duquack/sonaliwan/duckdb.min``."
  echo "Don't forget to provide the folders linOS, macOS and winOS alongiside your application."
