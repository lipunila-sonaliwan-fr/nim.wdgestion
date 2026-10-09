# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - valeurs et tables (façon Lua)
#
# Une valeur est : nul, logique, nombre, chaîne, table ou référence de procédure.
# Les tables reprennent le modèle de Lua : partie « tableau » (indices 1..n)
# + partie « dictionnaire » (clefs quelconques, ordre d'insertion conservé)
# + métatable optionnelle.

import std/[tables, strutils, math, json, unicode, sets, atomics]

# comptage des tables
# Chaque table porte un « témoin » dont la destruction décrémente le compteur global :
# le nombre de tables vivantes est donc exact et permet de vérifier l'absence de fuite.

var tablesVivantes*: Atomic[int]

type
  Temoin = object
    actif: bool

proc `=destroy`(t: Temoin) =
  if t.actif: discard tablesVivantes.fetchSub(1)
proc `=copy`(a: var Temoin, b: Temoin) {.error: "une table ne se copie pas".}

type
  VKind* = enum
    vNul, vLog, vNum, vChaine, vTable, vProc

  LTable* = ref LTableObj
  LTableObj* = object
    arr*: seq[Val]                                                # indices 1..arr.len.
    hash*: OrderedTable[string, (Val, Val)]                       # clef encodée -> (clef, valeur).
    meta*: LTable
    temoin: Temoin

  Val* = object
    case kind*: VKind
    of vNul: discard
    of vLog: b*: bool
    of vNum: n*: float
    of vChaine: s*: string
    of vTable: t*: LTable
    of vProc: p*: string                                          # nom (majuscules) de la procédure.

  ErreurWDG* = object of CatchableError
    ligne*: int
    fichier*: string

proc erreur*(msg: string, ligne = 0, fichier = ""): ref ErreurWDG =
  result = newException(ErreurWDG, msg)
  result.ligne = ligne
  result.fichier = fichier

# constructeurs

proc nul*(): Val {.inline.} = Val(kind: vNul)
proc lg*(b: bool): Val {.inline.} = Val(kind: vLog, b: b)
proc num*(f: float): Val {.inline.} = Val(kind: vNum, n: f)
proc num*(i: int): Val {.inline.} = Val(kind: vNum, n: i.float)
proc ch*(s: string): Val {.inline.} = Val(kind: vChaine, s: s)
proc tab*(t: LTable): Val {.inline.} = Val(kind: vTable, t: t)
proc procv*(nom: string): Val {.inline.} = Val(kind: vProc, p: nom)
# registre des tables
# Les tables Lua peuvent former des cycles (t.__index = t), que le comptage de
# références (--mm:atomicArc) ne libère pas seul. Toute table créée pendant le
# traitement d'une requête est inscrite au registre de la session ; en fin de requête,
# `ramasser` démolit celles qui ne sont plus accessibles depuis la table SESSION.

type Registre* = ref object
  tables*: seq[LTable]

var registreCourant* {.threadvar.}: Registre

proc nouvelleTable*(): LTable =
  result = LTable(temoin: Temoin(actif: true))
  discard tablesVivantes.fetchAdd(1)
  if registreCourant != nil: registreCourant.tables.add result

proc demolir*(t: LTable) =
  # Vide une table : ses liens sont rompus, les cycles qui passaient par elle aussi.
  t.arr.setLen(0)
  t.hash.clear()
  t.meta = nil

proc estNul*(v: Val): bool {.inline.} = v.kind == vNul

# texte

proc fmtNum*(f: float): string =
  if f.isNaN: return "nan"
  if f == Inf: return "inf"
  if f == NegInf: return "-inf"
  if f == floor(f) and abs(f) < 1e15:
    return $int64(f)
  result = $f

proc nomType*(v: Val): string =
  case v.kind
  of vNul: "nul"
  of vLog: "logique"
  of vNum: "nombre"
  of vChaine: "chaine"
  of vTable: "table"
  of vProc: "procedure"

proc enTexte*(v: Val): string =
  # Conversion « brute » en texte (sans métaméthode __tostring).
  case v.kind
  of vNul: ""
  of vLog: (if v.b: "vrai" else: "faux")
  of vNum: fmtNum(v.n)
  of vChaine: v.s
  of vTable: "table: 0x" & toHex(cast[uint](v.t))
  of vProc: "procedure: " & v.p

proc vrai*(v: Val): bool {.inline.} =
  # Comme en Lua : seuls nul et faux sont "faux".
  case v.kind
  of vNul: false
  of vLog: v.b
  else: true

proc egalBrut*(a, b: Val): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vNul: true
  of vLog: a.b == b.b
  of vNum: a.n == b.n
  of vChaine: a.s == b.s
  of vTable: a.t == b.t
  of vProc: a.p == b.p

# tables

proc clefEnc*(k: Val): string =
  case k.kind
  of vNum: "n" & fmtNum(k.n)
  of vChaine: "s" & k.s
  of vLog: (if k.b: "b1" else: "b0")
  of vTable: "t" & $cast[uint](k.t)
  of vProc: "p" & k.p
  of vNul: raise erreur("clef de table nulle")

proc indiceTableau(k: Val): int {.inline.} =
  # Renvoie l'indice entier (>=1) si la clef est un entier positif, sinon 0.
  if k.kind == vNum and k.n >= 1 and k.n == floor(k.n) and k.n < 1e15:
    return int(k.n)
  0

proc normaliser(t: LTable) =
  # Migre vers la partie tableau les clefs n+1, n+2... présentes dans le dictionnaire.
  while t.hash.len > 0:
    let e = "n" & $(t.arr.len + 1)
    if t.hash.hasKey(e):
      let v = t.hash[e][1]
      t.hash.del(e)
      t.arr.add v
    else: break

proc lireBrut*(t: LTable, k: Val): Val =
  if k.kind == vNul: return nul()
  let i = indiceTableau(k)
  if i > 0 and i <= t.arr.len: return t.arr[i-1]
  let e = clefEnc(k)
  if t.hash.hasKey(e): return t.hash[e][1]
  nul()

proc lireBrut*(t: LTable, k: string): Val {.inline.} = lireBrut(t, ch(k))

proc ecrireBrut*(t: LTable, k: Val, v: Val) =
  if k.kind == vNul: raise erreur("clef de table nulle")
  if k.kind == vNum and k.n.isNaN: raise erreur("clef de table invalide (nan)")
  let i = indiceTableau(k)
  if i > 0:
    if i <= t.arr.len:
      if v.kind == vNul:
        if i == t.arr.len:
          t.arr.setLen(i-1)
        else:
          # la suite passe dans le dictionnaire.
          for j in i ..< t.arr.len:
            t.hash["n" & $(j+1)] = (num(j+1), t.arr[j])
          t.arr.setLen(i-1)
      else:
        t.arr[i-1] = v
      return
    elif i == t.arr.len + 1 and v.kind != vNul:
      t.hash.del("n" & $i)
      t.arr.add v
      normaliser(t)
      return
  let e = clefEnc(k)
  if v.kind == vNul: t.hash.del(e)
  else: t.hash[e] = (k, v)

proc ecrireBrut*(t: LTable, k: string, v: Val) {.inline.} = ecrireBrut(t, ch(k), v)

proc longueur*(t: LTable): int {.inline.} = t.arr.len

proc nbElements*(t: LTable): int = t.arr.len + t.hash.len

proc insererA*(t: LTable, pos: int, v: Val) =
  # table.insert(t, pos, v).
  if v.kind == vNul: return
  if pos < 1 or pos > t.arr.len + 1:
    raise erreur("position d'insertion hors limites : " & $pos)
  t.arr.insert(v, pos-1)
  t.hash.del("n" & $(t.arr.len)) # la clef n+1 éventuelle est écrasée par le décalage.
  normaliser(t)

proc ajouterFin*(t: LTable, v: Val) = insererA(t, t.arr.len + 1, v)

proc retirerA*(t: LTable, pos: int): Val =
  # table.remove(t, pos).
  if t.arr.len == 0: return nul()
  if pos < 1 or pos > t.arr.len:
    raise erreur("position de retrait hors limites : " & $pos)
  result = t.arr[pos-1]
  t.arr.delete(pos-1)

iterator paires*(t: LTable): (Val, Val) =
  # Partie tableau d'abord, puis dictionnaire dans l'ordre d'insertion.
  # Traitement sur une copie pour tolérer les modifications pendant le parcours (sinon aïe...).
  let arr = t.arr
  for i, v in arr: yield (num(i+1), v)
  var h: seq[(Val, Val)]
  for _, kv in t.hash: h.add kv
  for kv in h: yield kv

proc copieSimple*(t: LTable): LTable =
  result = nouvelleTable()
  result.arr = t.arr
  result.hash = t.hash
  result.meta = t.meta

# JSON

proc versJson*(v: Val, profondeur = 0): JsonNode =
  if profondeur > 100: raise erreur("json : structure trop profonde (cycle ?)")
  case v.kind
  of vNul: newJNull()
  of vLog: newJBool(v.b)
  of vNum:
    if v.n == floor(v.n) and abs(v.n) < 9e15: newJInt(int64(v.n)) else: newJFloat(v.n)
  of vChaine: newJString(v.s)
  of vProc: newJString("procedure:" & v.p)
  of vTable:
    if v.t.hash.len == 0 and v.t.arr.len > 0:
      var a = newJArray()
      for x in v.t.arr: a.add versJson(x, profondeur+1)
      a
    else:
      var o = newJObject()
      for (k, x) in paires(v.t):
        o[enTexte(k)] = versJson(x, profondeur+1)
      o

proc depuisJson*(j: JsonNode, majuscules = true): Val =
  case j.kind
  of JNull: nul()
  of JBool: lg(j.getBool)
  of JInt: num(j.getBiggestInt.float)
  of JFloat: num(j.getFloat)
  of JString: ch(j.getStr)
  of JArray:
    let t = nouvelleTable()
    for x in j: t.arr.add depuisJson(x, majuscules)
    # les nuls ne peuvent pas figurer dans la partie tableau.
    var propre: seq[Val]
    for x in t.arr:
      if x.kind != vNul: propre.add x
    t.arr = propre
    tab(t)
  of JObject:
    let t = nouvelleTable()
    for k, x in j:
      let kk = if majuscules: unicode.toUpper(k) else: k
      ecrireBrut(t, ch(kk), depuisJson(x, majuscules))
    tab(t)

# conversions.

proc versNombre*(v: Val, ok: var bool): float =
  ok = true
  case v.kind
  of vNum: return v.n
  of vChaine:
    var s = v.s.strip
    if s.len == 0: ok = false; return 0
    # virgule décimale à la française : "12,5" -> 12.5 (si la chaîne ne contient pas de point)
    if ',' in s and '.' notin s and s.count(',') == 1: s = s.replace(',', '.')
    try: return parseFloat(s)
    except ValueError: ok = false; return 0
  of vLog: return (if v.b: 1.0 else: 0.0)
  else:
    ok = false
    return 0

proc echapperHtml*(s: string): string =
  result = newStringOfCap(s.len + 8)
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

# ramasse-miettes

proc marquer*(racines: openArray[Val], vus: var HashSet[pointer]) =
  # Marque toutes les tables accessibles depuis `racines` (parcours itératif).
  var pile: seq[LTable]
  for v in racines:
    if v.kind == vTable: pile.add v.t
  while pile.len > 0:
    let t = pile.pop()
    if t == nil or vus.containsOrIncl(cast[pointer](t)): continue
    if t.meta != nil: pile.add t.meta
    for x in t.arr:
      if x.kind == vTable: pile.add x.t
    for _, kv in t.hash:
      if kv[0].kind == vTable: pile.add kv[0].t
      if kv[1].kind == vTable: pile.add kv[1].t

proc ramasser*(reg: Registre, racines: openArray[Val]): int =
  # Démolit les tables du registre inaccessibles depuis les racines ;
  # le registre ne garde que les tables vivantes. Renvoie le nombre de tables démolies.
  if reg == nil: return 0
  var vus = initHashSet[pointer]()
  marquer(racines, vus)
  var garde: seq[LTable]
  for t in reg.tables:
    if cast[pointer](t) in vus: garde.add t
    else:
      demolir(t)
      inc result
  reg.tables = garde

proc toutDemolir*(reg: Registre) =
  # Fin de vie d'une session : toutes ses tables sont démolies.
  if reg == nil: return
  for t in reg.tables: demolir(t)
  reg.tables.setLen(0)
