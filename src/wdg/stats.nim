# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - mesures de charge (écran /SUIVI)

import std/[locks, tables, json, times, strutils]
when defined(posix):
  import std/posix

const tailleTop = 100

type
  Agregat* = object
    nombre*: int
    total*, mini*, maxi*: float
    octets*: int64

  Evenement* = object
    duree*: float
    date*: float
    nom*: string
    detail*: string

var
  verrouStats: Lock
  agregatsProcs: Table[string, Agregat]
  agregatsStatiques: Table[string, Agregat]
  topProcs, topSql: seq[Evenement]
  tempsSql: float
  nbSql, erreursSql: int
  octetsRecus, octetsEnvoyes: int64
  nbRequetes: int64
  debutMesures*: float
  demarrageServeur*: float

var contexteFil* {.threadvar.}: string                            # « PROC · utilisateur » : rattache le SQL à son appelant.

initLock(verrouStats)
debutMesures = epochTime()
demarrageServeur = epochTime()

proc ajouter(a: var Agregat, d: float, octets = 0) =
  if a.nombre == 0 or d < a.mini: a.mini = d
  if d > a.maxi: a.maxi = d
  a.total += d
  inc a.nombre
  a.octets += octets

proc ajouterTop(top: var seq[Evenement], e: Evenement) =
  if top.len >= tailleTop and e.duree <= top[^1].duree: return
  var i = top.len
  while i > 0 and top[i-1].duree < e.duree: dec i
  top.insert(e, i)
  if top.len > tailleTop: top.setLen(tailleTop)

proc noterProc*(nom: string, duree: float, detail: string) =
  withLock verrouStats:
    agregatsProcs.mgetOrPut(nom, Agregat()).ajouter(duree)
    ajouterTop(topProcs, Evenement(duree: duree, date: epochTime(), nom: nom, detail: detail))

proc noterStatique*(chemin: string, duree: float, octets: int) =
  withLock verrouStats:
    agregatsStatiques.mgetOrPut(chemin, Agregat()).ajouter(duree, octets)

proc noterSql*(sql: string, duree: float, erreur: bool) {.nimcall, gcsafe.} =
  var texte = sql.splitWhitespace.join(" ")
  if texte.len > 400: texte = texte[0 ..< 400] & "…"
  {.cast(gcsafe).}:
    let ctx = contexteFil
    withLock verrouStats:
      tempsSql += duree
      inc nbSql
      if erreur: inc erreursSql
      ajouterTop(topSql, Evenement(duree: duree, date: epochTime(), nom: texte, detail: ctx))

proc noterTrafic*(recus, envoyes: int) {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    withLock verrouStats:
      octetsRecus += recus
      octetsEnvoyes += envoyes
      if recus > 0: inc nbRequetes

proc razStats*() =
  withLock verrouStats:
    agregatsProcs.clear()
    agregatsStatiques.clear()
    topProcs.setLen(0)
    topSql.setLen(0)
    tempsSql = 0
    nbSql = 0
    erreursSql = 0
    octetsRecus = 0
    octetsEnvoyes = 0
    nbRequetes = 0
    debutMesures = epochTime()

# système

proc tempsCpu*(): (float, float) =
  # (utilisateur, système) en secondes pour tout le processus.
  when defined(posix):
    var ru: Rusage
    if getrusage(RUSAGE_SELF, addr ru) == 0:
      return (ru.ru_utime.tv_sec.float + ru.ru_utime.tv_usec.float / 1e6,
              ru.ru_stime.tv_sec.float + ru.ru_stime.tv_usec.float / 1e6)
  (-1.0, -1.0)

proc memoireResidente*(): int64 =
  # Mémoire résidente (octets) ; -1 si indisponible.
  when defined(linux):
    try:
      for l in lines("/proc/self/status"):
        if l.startsWith("VmRSS:"):
          return parseBiggestInt(l.splitWhitespace()[1]) * 1024
    except CatchableError: discard
  elif defined(posix):
    var ru: Rusage
    if getrusage(RUSAGE_SELF, addr ru) == 0:
      return int64(ru.ru_maxrss) # macOS : pic, en octets
  -1

# export JSON

proc versJson(a: Agregat, nom: string, avecOctets = false): JsonNode =
  result = %*{"nom": nom, "nombre": a.nombre, "min": a.mini, "max": a.maxi,
              "moyenne": (if a.nombre > 0: a.total / a.nombre.float else: 0.0), "total": a.total}
  if avecOctets: result["octets"] = %a.octets

proc versJson(e: Evenement): JsonNode =
  %*{"duree": e.duree, "date": e.date, "nom": e.nom, "detail": e.detail}

proc chargeJson*(): JsonNode =
  let (u, s) = tempsCpu()
  withLock verrouStats:
    result = %*{
      "maintenant": epochTime(), "demarrage": demarrageServeur, "debutMesures": debutMesures,
      "cpuUtilisateur": u, "cpuSysteme": s, "memoire": memoireResidente(),
      "tempsSql": tempsSql, "nbSql": nbSql, "erreursSql": erreursSql,
      "octetsRecus": octetsRecus, "octetsEnvoyes": octetsEnvoyes, "requetes": nbRequetes}

proc mesuresJson*(): JsonNode =
  withLock verrouStats:
    var p = newJArray()
    for nom, a in agregatsProcs: p.add versJson(a, nom)
    var st = newJArray()
    for nom, a in agregatsStatiques: st.add versJson(a, nom, true)
    var tp = newJArray()
    for e in topProcs: tp.add versJson(e)
    var ts = newJArray()
    for e in topSql: ts.add versJson(e)
    result = %*{"procedures": p, "statiques": st, "topProcedures": tp, "topSql": ts}
