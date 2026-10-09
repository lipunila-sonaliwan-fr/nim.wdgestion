# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - accès DuckDB (s'appuie sur sonaliwan/duckdb)
#
# Ajoute les requêtes préparées (paramètres « ? ») et la conversion des
# résultats en valeurs wdGestion V (tables de lignes façon Lua).

import std/[strutils, unicode, math, json, monotimes, times]
import sonaliwan/duckdb
import valeurs

export duckdb.DB, duckdb.Conn, duckdb.openDB, duckdb.connect, duckdb.close, duckdb.exec

const
  libDuck = when defined(windows): "./winOS/libduckdb.dll"
            elif defined(macosx): "./macOS/libduckdb.dylib"
            else: "./linOS/libduckdb.so"

proc duckdb_nparams(p: DuckDBPreparedStatement): uint64 {.importc, dynlib: libDuck, cdecl.}
proc duckdb_prepare_error(p: DuckDBPreparedStatement): cstring {.importc, dynlib: libDuck, cdecl.}
proc duckdb_interrupt(c: DuckDBConnection) {.importc, dynlib: libDuck, cdecl.}

# connexions par fil.
# Une base (DuckDB gère la concurrence) et une connexion par fil d'exécution,
# ouverte à la première requête du fil et fermée à sa fin (fermerConnFil).

var baseGlobale*: DB
var connFil {.threadvar.}: Conn
var connOuverte {.threadvar.}: bool

proc connCourante*(): Conn =
  if not connOuverte:
    {.cast(gcsafe).}:
      connFil = baseGlobale.connect()
    connOuverte = true
  connFil

proc fermerConnFil*() =
  if connOuverte:
    connFil.close()
    connOuverte = false

proc pointeurConn*(c: Conn): pointer =
  cast[ptr pointer](unsafeAddr c)[]

proc interrompre*(p: pointer) =
  # Interrompt la requête en cours sur une connexion (appelable depuis un autre fil).
  if p != nil: duckdb_interrupt(cast[DuckDBConnection](p))

# Mesure : appelée après chaque requête SQL avec sa durée en secondes.
type RappelSql* = proc (sql: string, duree: float, erreur: bool) {.nimcall, gcsafe.}
var surSql*: RappelSql = nil

type
  Resultat* = object
    colonnes*: seq[string]       # noms tels que renvoyés par DuckDB.
    lignes*: seq[seq[Val]]

const typesNumeriquesTexte = {6, 7, 8, 9, 16, 19, 32}             # utinyint.. ubigint, hugeint, decimal, uhugeint.

proc versVal(rows: Rows, c, r: int): Val =
  let v = rows.getValue(c, r)
  case v.kind
  of vkNull: nul()
  of vkBool: lg(v.boolVal)
  of vkInt: num(v.intVal.float)
  of vkFloat: num(v.floatVal)
  of vkString:
    let t = ord(duckdb_column_type(rows.resPtr, c.uint64))
    if t in typesNumeriquesTexte:
      try: num(parseFloat(v.strVal))
      except ValueError: ch(v.strVal)
    else: ch(v.strVal)

proc lireRows(rows: var Rows): Resultat =
  result.colonnes = rows.columns
  for r in 0 ..< rows.rowCount:
    var l = newSeq[Val](rows.colCount)
    for c in 0 ..< rows.colCount:
      l[c] = versVal(rows, c, r)
    result.lignes.add l
  rows.close()

proc lier(p: DuckDBPreparedStatement, i: int, v: Val) =
  let idx = uint64(i)
  var st: DuckDBState
  case v.kind
  of vNul: st = duckdb_bind_null(p, idx)
  of vLog: st = duckdb_bind_boolean(p, idx, v.b)
  of vNum:
    if v.n == floor(v.n) and abs(v.n) < 9e15: st = duckdb_bind_int64(p, idx, int64(v.n))
    else: st = duckdb_bind_double(p, idx, v.n)
  of vChaine: st = duckdb_bind_varchar(p, idx, v.s.cstring)
  of vTable: st = duckdb_bind_varchar(p, idx, ($versJson(v)).cstring)
  of vProc: st = duckdb_bind_varchar(p, idx, v.p.cstring)
  if st == DuckDBError: raise erreur("sql : impossible de lier le paramètre " & $i)

proc requeteBrute(conn: Conn, sql: string, params: openArray[Val]): Resultat =
  if params.len == 0:
    var rows: Rows
    try: rows = conn.query(sql)
    except CatchableError as e:
      raise erreur("sql : " & e.msg.replace("Query error: ", ""))
    return lireRows(rows)
  let cp = cast[ptr DuckDBConnection](unsafeAddr conn)[]
  var prep: DuckDBPreparedStatement
  if duckdb_prepare(cp, sql.cstring, addr prep) == DuckDBError:
    let m = $duckdb_prepare_error(prep)
    duckdb_destroy_prepare(addr prep)
    raise erreur("sql : " & m)
  defer: duckdb_destroy_prepare(addr prep)
  let attendus = duckdb_nparams(prep).int
  if attendus != params.len:
    raise erreur("sql : " & $attendus & " paramètre(s) attendu(s), " & $params.len & " fourni(s)")
  for i, v in params: lier(prep, i + 1, v)
  let resPtr = cast[ptr DuckDBResult](alloc0(sizeof(DuckDBResult)))
  if duckdb_execute_prepared(prep, resPtr) == DuckDBError:
    let m = $duckdb_result_error(resPtr)
    duckdb_destroy_result(resPtr)
    dealloc(resPtr)
    raise erreur("sql : " & m)
  var rows = Rows(resPtr: resPtr, colCount: duckdb_column_count(resPtr).int,
                  rowCount: duckdb_row_count(resPtr).int)
  lireRows(rows)

proc enTable*(r: Resultat): Val =
  # Résultat => table de lignes ; chaque ligne est une table (clefs en MAJUSCULES).
  let t = nouvelleTable()
  var noms: seq[string]
  for c in r.colonnes: noms.add unicode.toUpper(c)
  for l in r.lignes:
    let ligne = nouvelleTable()
    for i, v in l: ecrireBrut(ligne, ch(noms[i]), v)
    t.arr.add tab(ligne)
  tab(t)

proc identSqlValide*(s: string): bool =
  # Nom de table (éventuellement schema.table) : lettres, chiffres, _ et .
  if s.len == 0 or s.len > 128: return false
  if s[0] notin {'a'..'z', 'A'..'Z', '_'}: return false
  for c in s:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '.'}: return false
  true

proc citer*(nom: string): string =
  # Identifiant SQL entre guillemets (schema.table => "schema"."table").
  var parts: seq[string]
  for p in nom.split('.'): parts.add "\"" & p.replace("\"", "\"\"") & "\""
  parts.join(".")

proc annulerTransactionOuverte*() =
  # Fin de requête : une transaction laissée ouverte (begin sans commit ni rollback)
  # est annulée, pour ne pas peser sur les requêtes suivantes servies par ce fil.
  # Sans transaction active, DuckDB refuse le rollback : l'erreur est ignorée.
  if not connOuverte: return
  var res: DuckDBResult
  let cp = cast[ptr DuckDBConnection](unsafeAddr connFil)[]
  discard duckdb_query(cp, "rollback", addr res)
  duckdb_destroy_result(addr res)

proc requete*(conn: Conn, sql: string, params: openArray[Val] = []): Resultat =
  # Exécute une requête ; avec paramètres => requête préparée (protège des injections).
  # La durée est transmise au module de statistiques.
  let t0 = getMonoTime()
  var ok = false
  try:
    result = requeteBrute(conn, sql, params)
    ok = true
  finally:
    let rappel = surSql
    if rappel != nil:
      rappel(sql, float((getMonoTime() - t0).inNanoseconds) / 1e9, not ok)

proc requete*(sql: string, params: openArray[Val] = []): Resultat =
  # Requête sur la connexion du fil courant.
  requete(connCourante(), sql, params)
