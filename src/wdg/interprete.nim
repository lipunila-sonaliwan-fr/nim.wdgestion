# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - interpréteur

import std/[tables, strutils, math, json, os, times, unicode, random, uri, algorithm, locks, monotimes, sysrand]
import valeurs, ast, parseur, base, crypto

type
  Zone* = ref object
    alias*, table*: string
    colCle*: string              # colonne clé (clé primaire ou rowid).
    colonnes*: seq[string]       # noms réels.
    colMaj*: seq[string]         # noms en majuscules.
    ordre*, filtre*: string
    cles*: seq[Val]
    pos*: int                    # 0..cles.len (cles.len = fin de fichier).
    bof*: bool
    trouve*: bool
    efface: bool
    cache: seq[Val]
    cacheOk: bool
    condLoc: Node

  Session* = ref object
    id*: string                  # identifiant secret (cookie).
    pub*: string                 # identifiant public (écran de suivi).
    vars*: LTable                # la table SESSION (variables globales).
    zones*: OrderedTable[string, Zone]
    courante*: string
    ouverture*: float            # date de création (epoch).
    dernierAcces*: float
    ip*: string
    registre*: Registre          # tables créées par la session (ramasse-miettes).
    # concurrence (protégé par le verrou des sessions du serveur).
    occupee*: bool               # une requête de la session est en cours.
    enAttente*: int              # requêtes de la session qui attendent leur tour.
    fermee*: bool                # fermée pendant une requête : démolie à la fin de celle-ci.
    # résumé lisible sans toucher aux variables (écran de suivi).
    nbRequetes*: int
    utilisateur*: string
    valide*: string
    procEnCours*: string
    debutEnCours*: float

  Cadre = ref object
    vars: Table[string, Val]
    args: seq[Val]

  Ctl = enum cNormal, cSortir, cBoucler, cRetour

  Contexte* = ref object
    session*: Session
    sortie*: string
    statut*: int
    entetes*: seq[(string, string)]
    redirection*: string
    deconnexion*: bool
    pile: seq[Cadre]
    retour: Val
    pas: int
    profondeur: int
    procs: Procedures            # instantané des procédures au début de la requête.
    limite: MonoTime             # échéance de la requête.

  Procedures* = ref object
    t*: Table[string, ProcDef]

  PageCompilee = ref object
    date: Time
    corps: seq[Node]

  Moteur* = ref object
    procs: Procedures            # remplacé d'un bloc au rechargement (verrou).
    dossierPage*, dossierProg*: string
    cachePages: Table[string, PageCompilee]
    pasMax*: int
    dureeMax*: float             # secondes par requête (0 = illimité).

var moteur*: Moteur
var verrouMoteur: Lock
initLock(verrouMoteur)
var rng {.threadvar.}: Rand
var rngPret {.threadvar.}: bool

proc procedures*(): Procedures =
  withLock verrouMoteur:
    result = moteur.procs

proc remplacerProcs*(p: Table[string, ProcDef]) =
  let nouv = Procedures(t: p)
  withLock verrouMoteur:
    moteur.procs = nouv

proc nbProcedures*(): int = procedures().t.len
proc procExiste*(nom: string): bool = procedures().t.hasKey(nom)

const profondeurMax = 200

# outils

proc errN(n: Node, msg: string): ref ErreurWDG =
  if n == nil: erreur(msg)
  else: erreur(msg, n.ligne, nomFichier(n.fic))

proc cadre(c: Contexte): Cadre {.inline.} = c.pile[^1]

proc eval(c: Contexte, n: Node): Val
proc exec(c: Contexte, b: seq[Node]): Ctl
proc appeler*(c: Contexte, f: Val, args: seq[Val], n: Node): Val
proc texteDe*(c: Contexte, v: Val): string
proc champZone(c: Contexte, z: Zone, i: int): Val

proc metaMethode(v: Val, nom: string): Val =
  if v.kind == vTable and v.t.meta != nil:
    result = lireBrut(v.t.meta, ch(nom))
    if result.kind == vNul: result = lireBrut(v.t.meta, ch(nom.toLowerAscii))
  else: result = nul()

proc appelable(v: Val): bool =
  v.kind == vProc or (v.kind == vTable and metaMethode(v, "__CALL").kind != vNul)

# tables + métaméthodes

proc indexer(c: Contexte, obj, key: Val, n: Node, prof = 0): Val =
  if prof > 50: raise errN(n, "__index : chaîne de métatables trop longue (cycle ?)")
  case obj.kind
  of vTable:
    let r = lireBrut(obj.t, key)
    if r.kind != vNul: return r
    let h = metaMethode(obj, "__INDEX")
    case h.kind
    of vNul: return nul()
    of vTable: return indexer(c, h, key, n, prof + 1)
    else: return appeler(c, h, @[obj, key], n)
  of vNul:
    raise errN(n, "indexation d'une valeur nulle (clef '" & enTexte(key) & "')")
  else:
    raise errN(n, "indexation impossible d'une valeur de type " & nomType(obj) &
               " (clef '" & enTexte(key) & "')")

proc affecterIndex(c: Contexte, obj, key, val: Val, n: Node, prof = 0) =
  if prof > 50: raise errN(n, "__newindex : chaîne de métatables trop longue (cycle ?)")
  if obj.kind != vTable:
    raise errN(n, "affectation indexée sur une valeur de type " & nomType(obj) & " (table attendue)")
  if key.kind == vNul: raise errN(n, "clef de table nulle")
  if obj.t.meta != nil and lireBrut(obj.t, key).kind == vNul:
    let h = metaMethode(obj, "__NEWINDEX")
    if h.kind == vTable:
      affecterIndex(c, h, key, val, n, prof + 1); return
    elif h.kind != vNul:
      discard appeler(c, h, @[obj, key, val], n); return
  ecrireBrut(obj.t, key, val)

# variables

proc zoneCourante(c: Contexte): Zone =
  let s = c.session
  if s.courante != "" and s.zones.hasKey(s.courante): s.zones[s.courante] else: nil

proc lireVar(c: Contexte, nom: string, n: Node): Val =
  if c.pile.len > 0:
    let f = c.cadre
    if f.vars.hasKey(nom): return f.vars[nom]
  if nom == "SESSION": return tab(c.session.vars)
  let z = c.zoneCourante
  if z != nil:
    let i = z.colMaj.find(nom)
    if i >= 0: return champZone(c, z, i)
  let v = lireBrut(c.session.vars, ch(nom))
  if v.kind != vNul: return v
  if c.procs.t.hasKey(nom): return procv(nom)
  nul()

proc ecrireVar(c: Contexte, nom: string, v: Val, n: Node) =
  if c.pile.len > 0 and c.cadre.vars.hasKey(nom):
    c.cadre.vars[nom] = v
  elif nom == "SESSION":
    raise errN(n, "la table SESSION ne peut pas être remplacée")
  else:
    ecrireBrut(c.session.vars, ch(nom), v)

proc affecter(c: Contexte, cible: Node, v: Val) =
  case cible.kind
  of eIdent: ecrireVar(c, cible.s, v, cible)
  of eIndex: affecterIndex(c, eval(c, cible.k[0]), eval(c, cible.k[1]), v, cible)
  else: raise errN(cible, "cible d'affectation invalide")

# texte / comparaisons

proc texteDe*(c: Contexte, v: Val): string =
  if v.kind == vTable:
    let h = metaMethode(v, "__TOSTRING")
    if h.kind != vNul: return enTexte(appeler(c, h, @[v], nil))
  enTexte(v)

proc nombre(v: Val, n: Node, op: string): float =
  var ok: bool
  result = versNombre(v, ok)
  if not ok:
    raise errN(n, "opération '" & op & "' : nombre attendu, " & nomType(v) &
               (if v.kind == vChaine: " \"" & v.s & "\"" else: "") & " reçu")

proc arith(c: Contexte, op: string, a, b: Val, n: Node): Val =
  if a.kind == vTable or b.kind == vTable:
    let nomM = case op
               of "+": "__ADD"
               of "-": "__SUB"
               of "*": "__MUL"
               of "/": "__DIV"
               of "%": "__MOD"
               of "^": "__POW"
               else: "__CONCAT"
    var h = metaMethode(a, nomM)
    if h.kind == vNul: h = metaMethode(b, nomM)
    if h.kind == vNul: raise errN(n, "opération '" & op & "' impossible sur une table (métaméthode " & nomM.toLowerAscii & " absente)")
    return appeler(c, h, @[a, b], n)
  if op == "..":
    return ch(texteDe(c, a) & texteDe(c, b))
  if op == "+" and (a.kind == vChaine or b.kind == vChaine):
    return ch(texteDe(c, a) & texteDe(c, b))
  let x = nombre(a, n, op)
  let y = nombre(b, n, op)
  case op
  of "+": num(x + y)
  of "-": num(x - y)
  of "*": num(x * y)
  of "/":
    if y == 0: raise errN(n, "division par zéro")
    num(x / y)
  of "%":
    if y == 0: raise errN(n, "modulo par zéro")
    num(x - floor(x / y) * y)
  of "^": num(pow(x, y))
  else: raise errN(n, "opérateur inconnu " & op)

proc comparer(c: Contexte, op: string, a, b: Val, n: Node): bool =
  case op
  of "==", "<>":
    var r = egalBrut(a, b)
    if not r and a.kind == vTable and b.kind == vTable:
      var h = metaMethode(a, "__EQ")
      if h.kind == vNul: h = metaMethode(b, "__EQ")
      if h.kind != vNul: r = vrai(appeler(c, h, @[a, b], n))
    return (if op == "==": r else: not r)
  of "$":
    return texteDe(c, b).contains(texteDe(c, a))
  else: discard
  if a.kind == vNum and b.kind == vNum:
    case op
    of "<": return a.n < b.n
    of ">": return a.n > b.n
    of "<=": return a.n <= b.n
    else: return a.n >= b.n
  if a.kind == vChaine and b.kind == vChaine:
    case op
    of "<": return a.s < b.s
    of ">": return a.s > b.s
    of "<=": return a.s <= b.s
    else: return a.s >= b.s
  if a.kind == vTable or b.kind == vTable:
    # a > b  <=>  b < a
    let (x, y, nomM) = case op
      of "<": (a, b, "__LT")
      of ">": (b, a, "__LT")
      of "<=": (a, b, "__LE")
      else: (b, a, "__LE")
    var h = metaMethode(x, nomM)
    if h.kind == vNul: h = metaMethode(y, nomM)
    if h.kind != vNul: return vrai(appeler(c, h, @[x, y], n))
  raise errN(n, "comparaison '" & op & "' impossible entre " & nomType(a) & " et " & nomType(b))

#  procédures

proc appelerProc(c: Contexte, d: ProcDef, args: seq[Val], n: Node,
                 extra: openArray[(string, Val)] = []): Val =
  if c.profondeur >= profondeurMax:
    raise errN(n, "profondeur d'appel maximale atteinte (récursion infinie ?)")
  let f = Cadre(args: args)
  for i, p in d.params:
    f.vars[p] = (if i < args.len: args[i] else: nul())
  for (k, v) in extra: f.vars[k] = v
  c.pile.add f
  inc c.profondeur
  c.retour = nul()
  try:
    let ctl = exec(c, d.corps)
    result = (if ctl == cRetour: c.retour else: nul())
  finally:
    c.retour = nul()
    dec c.profondeur
    discard c.pile.pop

proc appeler*(c: Contexte, f: Val, args: seq[Val], n: Node): Val =
  case f.kind
  of vProc:
    if not c.procs.t.hasKey(f.p): raise errN(n, "procédure inconnue : " & f.p)
    appelerProc(c, c.procs.t[f.p], args, n)
  of vTable:
    let h = metaMethode(f, "__CALL")
    if h.kind == vNul: raise errN(n, "appel d'une table sans métaméthode __call")
    appeler(c, h, @[f] & args, n)
  else:
    raise errN(n, "appel impossible d'une valeur de type " & nomType(f))

proc fonctionIntegree(c: Contexte, nom: string, a: seq[Val], n: Node): Val

proc appelerNom(c: Contexte, nom: string, args: seq[Val], n: Node): Val =
  if c.pile.len > 0 and c.cadre.vars.hasKey(nom):
    let v = c.cadre.vars[nom]
    if appelable(v): return appeler(c, v, args, n)
  if c.procs.t.hasKey(nom):
    return appelerProc(c, c.procs.t[nom], args, n)
  let g = lireBrut(c.session.vars, ch(nom))
  if appelable(g): return appeler(c, g, args, n)
  fonctionIntegree(c, nom, args, n)

# zones de travail (tables SQL)

proc exigeZone(c: Contexte, n: Node): Zone =
  result = c.zoneCourante
  if result == nil: raise errN(n, "aucune table ouverte dans la zone courante (instruction 'utiliser')")

proc colCleSql(z: Zone): string =
  if z.colCle == "rowid": "rowid" else: citer(z.colCle)

proc chargerCles(z: Zone) =
  var sql = "select " & colCleSql(z) & " from " & citer(z.table)
  if z.filtre != "": sql &= " where " & z.filtre
  sql &= " order by " & (if z.ordre != "": z.ordre else: colCleSql(z))
  let r = requete(sql)
  z.cles.setLen(0)
  for l in r.lignes: z.cles.add l[0]
  z.cacheOk = false
  if z.pos > z.cles.len: z.pos = z.cles.len

proc ouvrirZone(c: Contexte, table, alias, ordre, filtre: string, n: Node) =
  if not identSqlValide(table): raise errN(n, "nom de table invalide : " & table)
  let info = requete("select name, pk from pragma_table_info('" & table & "')")
  if info.lignes.len == 0: raise errN(n, "table inconnue : " & table)
  let z = Zone(table: table, alias: alias, ordre: ordre, filtre: filtre)
  var pks: seq[string]
  for l in info.lignes:
    z.colonnes.add l[0].s
    z.colMaj.add unicode.toUpper(l[0].s)
    if l[1].kind == vLog and l[1].b: pks.add l[0].s
  z.colCle = (if pks.len == 1: pks[0] else: "rowid")
  try: chargerCles(z)
  except ErreurWDG as e: raise errN(n, e.msg)
  c.session.zones[alias] = z
  c.session.courante = alias

proc enregistrement(c: Contexte, z: Zone): seq[Val] =
  if z.pos < 0 or z.pos >= z.cles.len:
    return newSeq[Val](z.colonnes.len)
  if not z.cacheOk:
    var cols: seq[string]
    for col in z.colonnes: cols.add citer(col)
    let r = requete("select " & cols.join(", ") & " from " & citer(z.table) &
                    " where " & colCleSql(z) & " = ?", [z.cles[z.pos]])
    z.cache = (if r.lignes.len > 0: r.lignes[0] else: newSeq[Val](z.colonnes.len))
    z.cacheOk = true
  z.cache

proc champZone(c: Contexte, z: Zone, i: int): Val = enregistrement(c, z)[i]

proc colonneReelle(z: Zone, nom: string, n: Node): string =
  let i = z.colMaj.find(unicode.toUpper(nom))
  if i < 0: raise errN(n, "champ inconnu dans " & z.table & " : " & nom)
  z.colonnes[i]

proc deplacer(z: Zone, pos: int) =
  z.efface = false
  z.cacheOk = false
  z.bof = false
  if pos < 0:
    z.pos = 0; z.bof = true
  elif pos > z.cles.len: z.pos = z.cles.len
  else: z.pos = pos

proc chercherDepuis(c: Contexte, z: Zone, debut: int, cond: Node) =
  var p = debut
  while p < z.cles.len:
    deplacer(z, p)
    inc c.pas
    if vrai(eval(c, cond)):
      z.trouve = true
      return
    inc p
  deplacer(z, z.cles.len)
  z.trouve = false

proc zoneParAlias(c: Contexte, a: seq[Val], i: int, n: Node): Zone =
  if a.len > i and a[i].kind != vNul:
    let nom = unicode.toUpper(enTexte(a[i]))
    if not c.session.zones.hasKey(nom): raise errN(n, "alias inconnu : " & nom)
    return c.session.zones[nom]
  exigeZone(c, n)

# pages

proc trouverPage(nom: string, n: Node): string =
  if nom.len == 0 or nom.contains("..") or nom.contains('\\') or nom.startsWith("/") or nom.contains('\0'):
    raise errN(n, "nom de page invalide : " & nom)
  let base = moteur.dossierPage
  for cand in [nom, nom & ".html", nom & ".htm", nom & ".page"]:
    let p = base / cand
    if fileExists(p): return p
  # recherche insensible à la casse
  let (dir, fic) = splitPath(nom)
  let rep = base / dir
  if dirExists(rep):
    for k, p in walkDir(rep):
      if k notin {pcFile, pcLinkToFile}: continue
      let (_, nm, ext) = splitFile(p)
      if cmpIgnoreCase(nm, fic) == 0 or cmpIgnoreCase(nm & ext, fic) == 0: return p
  raise errN(n, "page introuvable : " & nom)

proc compilerPage*(chemin: string): seq[Node] =
  let t = getLastModificationTime(chemin)
  withLock verrouMoteur:
    let p = moteur.cachePages.getOrDefault(chemin)
    if p != nil and p.date == t: return p.corps
  # compilation hors verrou (les autres requêtes ne sont pas bloquées).
  let rel = relativePath(chemin, parentDir(moteur.dossierPage))
  result = analyserPageSource(readFile(chemin), rel)
  let p = PageCompilee(date: t, corps: result)
  withLock verrouMoteur:
    moteur.cachePages[chemin] = p

proc viderCachePages*() =
  withLock verrouMoteur:
    moteur.cachePages.clear()

proc envoyerPage(c: Contexte, nom: string, noms: seq[string], vals: seq[Val], n: Node) =
  let chemin = trouverPage(nom, n)
  let corps = compilerPage(chemin)
  if c.profondeur >= profondeurMax: raise errN(n, "imbrication de pages trop profonde")
  let f = Cadre()
  for i, k in noms: f.vars[k] = vals[i]
  c.pile.add f
  inc c.profondeur
  try:
    discard exec(c, corps)
  finally:
    dec c.profondeur
    discard c.pile.pop
    c.retour = nul()

# évaluation

proc eval(c: Contexte, n: Node): Val =
  case n.kind
  of eNombre: num(n.n)
  of eChaine: ch(n.s)
  of eLog: lg(n.b)
  of eNul: nul()
  of eIdent:
    if n.s2 == "@":
      if not c.procs.t.hasKey(n.s): raise errN(n, "procédure inconnue : " & n.s)
      procv(n.s)
    else: lireVar(c, n.s, n)
  of eIndex: indexer(c, eval(c, n.k[0]), eval(c, n.k[1]), n)
  of eAlias:
    if n.s == "M" and not c.session.zones.hasKey("M"):
      # m->nom : variable mémoire (ignore les champs de la zone courante), comme en dBase.
      if c.pile.len > 0 and c.cadre.vars.hasKey(n.s2): return c.cadre.vars[n.s2]
      if n.s2 == "SESSION": return tab(c.session.vars)
      return lireBrut(c.session.vars, ch(n.s2))
    if not c.session.zones.hasKey(n.s): raise errN(n, "alias inconnu : " & n.s)
    let z = c.session.zones[n.s]
    let i = z.colMaj.find(n.s2)
    if i < 0: raise errN(n, "champ inconnu " & n.s & "->" & n.s2)
    champZone(c, z, i)
  of eAppel:
    var args: seq[Val]
    for i in 1 ..< n.k.len: args.add eval(c, n.k[i])
    let f = n.k[0]
    if f.kind == eIdent and f.s2 != "@": appelerNom(c, f.s, args, n)
    else: appeler(c, eval(c, f), args, n)
  of eMethode:
    let obj = eval(c, n.k[0])
    let m = indexer(c, obj, ch(n.s), n)
    if m.kind == vNul: raise errN(n, "méthode inconnue : " & n.s)
    var args = @[obj]
    for i in 1 ..< n.k.len: args.add eval(c, n.k[i])
    appeler(c, m, args, n)
  of eUnaire:
    let v = eval(c, n.k[0])
    case n.s
    of "non": lg(not vrai(v))
    of "-":
      if v.kind == vTable:
        let h = metaMethode(v, "__UNM")
        if h.kind == vNul: raise errN(n, "négation impossible d'une table (__unm absente)")
        appeler(c, h, @[v, v], n)
      else: num(-nombre(v, n, "-"))
    else: # "#"
      case v.kind
      of vChaine: num(v.s.runeLen)
      of vTable:
        let h = metaMethode(v, "__LEN")
        if h.kind != vNul: appeler(c, h, @[v], n) else: num(longueur(v.t))
      else: raise errN(n, "'#' : table ou chaîne attendue, " & nomType(v) & " reçu")
  of eBinaire:
    let a = eval(c, n.k[0])
    let b = eval(c, n.k[1])
    case n.s
    of "==", "<>", "<", ">", "<=", ">=", "$": lg(comparer(c, n.s, a, b, n))
    else: arith(c, n.s, a, b, n)
  of eEt:
    let a = eval(c, n.k[0])
    if not vrai(a): a else: eval(c, n.k[1])
  of eOu:
    let a = eval(c, n.k[0])
    if vrai(a): a else: eval(c, n.k[1])
  of eSiSinon:
    if vrai(eval(c, n.k[0])): eval(c, n.k[1]) else: eval(c, n.k[2])
  of eTable:
    let t = nouvelleTable()
    var i = 1
    var j = 0
    while j < n.k.len:
      let v = eval(c, n.k[j+1])
      if n.k[j] == nil:
        if v.kind != vNul: ecrireBrut(t, num(i), v)
        inc i
      else:
        let k = eval(c, n.k[j])
        if k.kind == vNul: raise errN(n, "clef de table nulle")
        ecrireBrut(t, k, v)
      j += 2
    tab(t)
  else:
    raise errN(n, "expression invalide")

# exécution

proc execInstr(c: Contexte, n: Node): Ctl

proc verifierEcheance(c: Contexte, n: Node) =
  if c.pas > moteur.pasMax:
    raise errN(n, "limite de " & $moteur.pasMax & " instructions atteinte (boucle infinie ?)")
  if (c.pas and 1023) == 0 and moteur.dureeMax > 0 and getMonoTime() > c.limite:
    raise errN(n, "limite de durée atteinte (" & $moteur.dureeMax & " s)")

proc exec(c: Contexte, b: seq[Node]): Ctl =
  for n in b:
    inc c.pas
    verifierEcheance(c, n)
    var ctl: Ctl
    try:
      ctl = execInstr(c, n)
    except ErreurWDG as e:
      if e.ligne == 0:
        e.ligne = n.ligne
        e.fichier = nomFichier(n.fic)
      raise
    if ctl != cNormal: return ctl
  cNormal

proc boucle(c: Contexte, corps: seq[Node], n: Node, sortie: var bool): Ctl =
  # Exécute un tour de boucle ; renvoie cRetour s'il faut remonter.
  inc c.pas
  verifierEcheance(c, n)
  case exec(c, corps)
  of cSortir: sortie = true; cNormal
  of cRetour: sortie = true; cRetour
  else: cNormal

proc execInstr(c: Contexte, n: Node): Ctl =
  case n.kind
  of sTexte: c.sortie.add n.s
  of sEcho:
    let s = texteDe(c, eval(c, n.k[0]))
    c.sortie.add(if n.b: s else: echapperHtml(s))
  of sAfficher:
    var parts: seq[string]
    for e in n.k: parts.add texteDe(c, eval(c, e))
    c.sortie.add parts.join(" ")
    if n.b: c.sortie.add "\n"
  of sAffecte:
    let v = eval(c, n.k[0])
    for i in 1 ..< n.k.len: affecter(c, n.k[i], v)
  of sAjoutAffecte:
    let v = eval(c, n.k[0])
    let cur = eval(c, n.k[1])
    affecter(c, n.k[1], arith(c, n.s, cur, v, n))
  of sExpr: discard eval(c, n.k[0])
  of sSi:
    for i, cond in n.k:
      if vrai(eval(c, cond)): return exec(c, n.blocs[i])
    if n.blocs.len > n.k.len: return exec(c, n.blocs[^1])
  of sTantQue:
    var fin = false
    while not fin and vrai(eval(c, n.k[0])):
      if boucle(c, n.blocs[0], n, fin) == cRetour: return cRetour
  of sPour:
    let debut = nombre(eval(c, n.k[0]), n, "pour")
    let finV = nombre(eval(c, n.k[1]), n, "pour")
    let pas = if n.k.len > 2: nombre(eval(c, n.k[2]), n, "pour") else: 1.0
    if pas == 0: raise errN(n, "pas nul dans 'pour'")
    c.cadre.vars[n.s] = num(debut)
    var fin = false
    while not fin:
      let i = nombre(c.cadre.vars.getOrDefault(n.s, num(finV + pas)), n, "pour")
      if (pas > 0 and i > finV) or (pas < 0 and i < finV): break
      if boucle(c, n.blocs[0], n, fin) == cRetour: return cRetour
      let j = nombre(c.cadre.vars.getOrDefault(n.s, num(i)), n, "pour")
      c.cadre.vars[n.s] = num(j + pas)
  of sPourChaque:
    let v = eval(c, n.k[0])
    if v.kind == vNul: return
    if v.kind != vTable: raise errN(n, "'pour chaque' : table attendue, " & nomType(v) & " reçu")
    var fin = false
    for (k, x) in paires(v.t):
      if n.noms.len == 1:
        c.cadre.vars[n.noms[0]] = x
      else:
        c.cadre.vars[n.noms[0]] = k
        c.cadre.vars[n.noms[1]] = x
      if boucle(c, n.blocs[0], n, fin) == cRetour: return cRetour
      if fin: break
  of sSortir: return cSortir
  of sBoucler: return cBoucler
  of sCas:
    for i, cond in n.k:
      if vrai(eval(c, cond)): return exec(c, n.blocs[i])
    if n.b: return exec(c, n.blocs[^1])
  of sFaire:
    var args: seq[Val]
    for e in n.k: args.add eval(c, e)
    discard appelerNom(c, n.s, args, n)
  of sRetour:
    c.retour = (if n.k.len > 0: eval(c, n.k[0]) else: nul())
    return cRetour
  of sLocale:
    for i, nom in n.noms:
      c.cadre.vars[nom] = (if n.k[i] != nil: eval(c, n.k[i]) else: nul())
  of sGlobale:
    for i, nom in n.noms:
      c.cadre.vars.del(nom)
      if n.k[i] != nil: ecrireBrut(c.session.vars, ch(nom), eval(c, n.k[i]))
  of sParametres:
    let args = c.cadre.args
    for i, nom in n.noms:
      c.cadre.vars[nom] = (if i < args.len: args[i] else: nul())
  of sEnvoyer:
    let nom = texteDe(c, eval(c, n.k[0]))
    var vals: seq[Val]
    for i in 1 ..< n.k.len: vals.add eval(c, n.k[i])
    envoyerPage(c, nom, n.noms, vals, n)
  of sRediriger:
    let u = texteDe(c, eval(c, n.k[0]))
    if u.contains({'\r', '\n'}): raise errN(n, "redirection invalide")
    c.redirection = u
    if c.statut < 300 or c.statut >= 400: c.statut = 302
  of sStatut:
    let s = int(nombre(eval(c, n.k[0]), n, "statut"))
    if s < 100 or s > 599: raise errN(n, "statut HTTP invalide : " & $s)
    c.statut = s
  of sEntete:
    let k = texteDe(c, eval(c, n.k[0]))
    let v = texteDe(c, eval(c, n.k[1]))
    if k.contains({'\r', '\n', ':'}) or v.contains({'\r', '\n'}) or k.len == 0:
      raise errN(n, "entête HTTP invalide")
    if cmpIgnoreCase(k, "set-cookie") == 0 and v.toLowerAscii.contains("wdg_session"):
      raise errN(n, "le cookie de session est réservé")
    c.entetes.add (k, v)
  of sNouvelleTable:
    var v = tab(nouvelleTable())
    if n.k.len > 1:
      v = eval(c, n.k[1])
      if v.kind != vTable: raise errN(n, "'nouvelle table' : valeur initiale non table")
    affecter(c, n.k[0], v)
  of sSupprimerTable:
    let cible = n.k[0]
    if cible.kind == eIdent:
      if c.cadre.vars.hasKey(cible.s): c.cadre.vars.del(cible.s)
      elif cible.s == "SESSION": raise errN(n, "la table SESSION ne peut pas être supprimée")
      else: ecrireBrut(c.session.vars, ch(cible.s), nul())
    else:
      affecter(c, cible, nul())
  of sInserer:
    let v = eval(c, n.k[0])
    let t = eval(c, n.k[1])
    if t.kind != vTable: raise errN(n, "'inserer' : table attendue, " & nomType(t) & " reçu")
    case n.s
    of "position":
      try: insererA(t.t, int(nombre(eval(c, n.k[2]), n, "position")), v)
      except ErreurWDG as e: raise errN(n, e.msg)
    of "clef": affecterIndex(c, t, eval(c, n.k[2]), v, n)
    else: ajouterFin(t.t, v)
  of sRetirer:
    let t = eval(c, n.k[0])
    if t.kind != vTable: raise errN(n, "'retirer' : table attendue, " & nomType(t) & " reçu")
    var r: Val
    case n.s
    of "position":
      try: r = retirerA(t.t, int(nombre(eval(c, n.k[1]), n, "position")))
      except ErreurWDG as e: raise errN(n, e.msg)
    of "clef":
      let k = eval(c, n.k[1])
      r = lireBrut(t.t, k)
      ecrireBrut(t.t, k, nul())
    else: r = retirerA(t.t, longueur(t.t))
    if n.k[2] != nil: affecter(c, n.k[2], r)
  of sAssocier:
    let t = eval(c, n.k[0])
    if t.kind != vTable: raise errN(n, "association de procédure : table attendue, " & nomType(t) & " reçu")
    if not c.procs.t.hasKey(n.s): raise errN(n, "procédure inconnue : " & n.s)
    ecrireBrut(t.t, ch(n.s2), procv(n.s))
  of sFixerMeta:
    let t = eval(c, n.k[0])
    let m = eval(c, n.k[1])
    if t.kind != vTable: raise errN(n, "fixermetatable : table attendue")
    if m.kind == vNul: t.t.meta = nil
    elif m.kind == vTable: t.t.meta = m.t
    else: raise errN(n, "fixermetatable : la métatable doit être une table ou nul")
  of sSql:
    let sql = texteDe(c, eval(c, n.k[0]))
    var params: seq[Val]
    for i in 2 ..< n.k.len: params.add eval(c, n.k[i])
    let r = requete(sql, params)
    if n.k[1] != nil: affecter(c, n.k[1], enTable(r))
  of sErreur:
    raise errN(n, texteDe(c, eval(c, n.k[0])))
  of sEssayer:
    let profPile = c.pile.len
    let prof = c.profondeur
    try:
      return exec(c, n.blocs[0])
    except ErreurWDG as e:
      c.pile.setLen(profPile)
      c.profondeur = prof
      if e.msg.startsWith("limite de "): raise
      if n.blocs.len > 1:
        if n.s != "": c.cadre.vars[n.s] = ch(e.msg)
        return exec(c, n.blocs[1])
  of sDeconnecter: c.deconnexion = true
  of sLiberer:
    for nom in n.noms:
      if c.cadre.vars.hasKey(nom): c.cadre.vars.del(nom)
      else: ecrireBrut(c.session.vars, ch(nom), nul())
  # zones de travail.
  of sUtiliser:
    if n.k[0] == nil:
      let s = c.session
      if s.courante != "": s.zones.del(s.courante)
      s.courante = ""
    else:
      let table = texteDe(c, eval(c, n.k[0]))
      let alias = if n.s != "": n.s else: unicode.toUpper(table)
      let ordre = if n.k[1] != nil: texteDe(c, eval(c, n.k[1])) else: ""
      let filtre = if n.k[2] != nil: texteDe(c, eval(c, n.k[2])) else: ""
      ouvrirZone(c, table, alias, ordre, filtre, n)
  of sSelectionner:
    let a = unicode.toUpper(texteDe(c, eval(c, n.k[0])))
    if not c.session.zones.hasKey(a): raise errN(n, "alias inconnu : " & a)
    c.session.courante = a
  of sFermer:
    let s = c.session
    if n.s == "*": s.zones.clear(); s.courante = ""
    else:
      let a = if n.s == "": s.courante else: n.s
      s.zones.del(a)
      if s.courante == a: s.courante = ""
  of sAller:
    let z = exigeZone(c, n)
    case n.s
    of "haut": deplacer(z, 0)
    of "bas": deplacer(z, max(0, z.cles.len - 1))
    else:
      let p = int(nombre(eval(c, n.k[0]), n, "aller"))
      deplacer(z, (if p < 1 or p > z.cles.len: z.cles.len else: p - 1))
  of sSauter:
    let z = exigeZone(c, n)
    let d = if n.k.len > 0: int(nombre(eval(c, n.k[0]), n, "sauter")) else: 1
    deplacer(z, z.pos + d)
  of sAjouter:
    let z = exigeZone(c, n)
    var cols, marques: seq[string]
    var vals: seq[Val]
    for i, nom in n.noms:
      cols.add citer(colonneReelle(z, nom, n))
      marques.add "?"
      vals.add eval(c, n.k[i])
    var sql = "insert into " & citer(z.table) &
              (if cols.len == 0: " default values" else: " (" & cols.join(", ") & ") values (" & marques.join(", ") & ")")
    var cle: Val
    if z.colCle != "rowid":
      sql &= " returning " & citer(z.colCle)
      let r = requete(sql, vals)
      cle = r.lignes[0][0]
    else:
      discard requete(sql, vals)
      cle = requete("select max(rowid) from " & citer(z.table)).lignes[0][0]
    z.cles.add cle
    deplacer(z, z.cles.len - 1)
  of sRemplacer:
    let z = exigeZone(c, n)
    if z.pos >= z.cles.len: raise errN(n, "'remplacer' en fin de fichier (aucun enregistrement courant)")
    var sets: seq[string]
    var vals: seq[Val]
    var nouvelleCle = nul()
    for i, nom in n.noms:
      let col = colonneReelle(z, nom, n)
      sets.add citer(col) & " = ?"
      let v = eval(c, n.k[i])
      vals.add v
      if col == z.colCle: nouvelleCle = v
    vals.add z.cles[z.pos]
    discard requete("update " & citer(z.table) & " set " & sets.join(", ") &
                    " where " & colCleSql(z) & " = ?", vals)
    if nouvelleCle.kind != vNul: z.cles[z.pos] = nouvelleCle
    z.cacheOk = false
  of sEffacer:
    let z = exigeZone(c, n)
    if z.pos >= z.cles.len: raise errN(n, "'effacer' en fin de fichier (aucun enregistrement courant)")
    discard requete("delete from " & citer(z.table) & " where " & colCleSql(z) & " = ?",
                    [z.cles[z.pos]])
    z.cles.delete(z.pos)
    z.cacheOk = false
    z.efface = true
  of sLocaliser:
    let z = exigeZone(c, n)
    z.condLoc = n.k[0]
    chercherDepuis(c, z, 0, n.k[0])
  of sContinuer:
    let z = exigeZone(c, n)
    if z.condLoc == nil: raise errN(n, "'continuer' sans 'localiser' préalable")
    chercherDepuis(c, z, z.pos + 1, z.condLoc)
  of sChercher:
    let z = exigeZone(c, n)
    if z.ordre == "": raise errN(n, "'chercher' nécessite une table ouverte avec 'ordre'")
    var col = z.ordre.split(',')[0].strip
    let bas = col.toLowerAscii
    if bas.endsWith(" desc"): col = col[0 ..< col.len-5].strip
    elif bas.endsWith(" asc"): col = col[0 ..< col.len-4].strip
    let v = eval(c, n.k[0])
    var sql = "select " & colCleSql(z) & " from " & citer(z.table) & " where (" & col & ") = ?"
    if z.filtre != "": sql &= " and (" & z.filtre & ")"
    sql &= " order by " & z.ordre & " limit 1"
    let r = requete(sql, [v])
    z.trouve = false
    if r.lignes.len > 0:
      let cle = r.lignes[0][0]
      for i, k in z.cles:
        if egalBrut(k, cle):
          deplacer(z, i); z.trouve = true; break
    if not z.trouve: deplacer(z, z.cles.len)
  of sParcourir:
    let z = exigeZone(c, n)
    deplacer(z, 0)
    var fin = false
    while not fin and z.pos < z.cles.len:
      let alias = c.session.courante
      c.session.courante = z.alias
      let ok = n.k[0] == nil or vrai(eval(c, n.k[0]))
      c.session.courante = alias
      if ok:
        if boucle(c, n.blocs[0], n, fin) == cRetour: return cRetour
        if fin: break
      if z.efface: z.efface = false; z.cacheOk = false
      else: deplacer(z, z.pos + 1)
  of sCompter:
    let z = exigeZone(c, n)
    var total = 0
    if n.k[0] == nil: total = z.cles.len
    else:
      let sauve = z.pos
      for p in 0 ..< z.cles.len:
        deplacer(z, p)
        inc c.pas
        if vrai(eval(c, n.k[0])): inc total
      deplacer(z, sauve)
    affecter(c, n.k[1], num(total))
  of sRafraichir:
    let z = exigeZone(c, n)
    chargerCles(z)
  else:
    raise errN(n, "instruction non exécutable")
  cNormal

# fonctions intégrées

proc arg(a: seq[Val], i: int): Val {.inline.} =
  if i < a.len: a[i] else: nul()

proc fonctionIntegree(c: Contexte, nom: string, a: seq[Val], n: Node): Val =
  template txt(i: int): string = texteDe(c, arg(a, i))
  template nb(i: int): float = nombre(arg(a, i), n, nom.toLowerAscii)
  template nbDef(i: int, d: float): float =
    (if i < a.len and a[i].kind != vNul: nombre(a[i], n, nom.toLowerAscii) else: d)
  template tbl(i: int): LTable =
    (let v = arg(a, i); if v.kind != vTable: raise errN(n, nom.toLowerAscii & " : table attendue en argument " & $(i+1)); v.t)
  template exige(k: int) =
    if a.len < k: raise errN(n, nom.toLowerAscii & " : " & $k & " argument(s) attendu(s)")

  case nom
  # chaînes.
  of "MAJUSCULE": ch(unicode.toUpper(txt(0)))
  of "MINUSCULE": ch(unicode.toLower(txt(0)))
  of "ROGNER": ch(txt(0).strip)
  of "ROGNERG": ch(txt(0).strip(trailing = false))
  of "ROGNERD": ch(txt(0).strip(leading = false))
  of "LONGUEUR":
    let v = arg(a, 0)
    if v.kind == vTable: num(longueur(v.t)) else: num(txt(0).runeLen)
  of "SOUSCHAINE":
    exige(2)
    let r = txt(0).toRunes
    let d = max(1, int(nb(1)))
    let l = int(nbDef(2, float(r.len)))
    if d > r.len or l <= 0: ch("") else: ch($r[d-1 ..< min(r.len, d-1+l)])
  of "GAUCHE":
    let r = txt(0).toRunes
    ch($r[0 ..< clamp(int(nb(1)), 0, r.len)])
  of "DROITE":
    let r = txt(0).toRunes
    let l = clamp(int(nb(1)), 0, r.len)
    ch($r[r.len - l ..< r.len])
  of "POSITION":
    exige(2)
    let i = txt(1).find(txt(0))
    if i < 0: num(0) else: num(txt(1)[0 ..< i].runeLen + 1)
  of "CHAINE", "TEXTE":
    let v = arg(a, 0)
    if v.kind != vNum or a.len < 2: ch(texteDe(c, v))
    else:
      let larg = int(nb(1))
      let dec = int(nbDef(2, 0))
      let t = if dec <= 0: $int64(round(v.n)) else: formatFloat(v.n, ffDecimal, dec)
      ch(t.align(larg))
  of "VALEUR", "NOMBRE":
    var ok: bool
    let f = versNombre(arg(a, 0), ok)
    if ok: num(f) elif nom == "NOMBRE": nul() else: num(0)
  of "ESPACE": ch(spaces(max(0, int(nb(0)))))
  of "REPLIQUER": ch(txt(0).repeat(max(0, int(nb(1)))))
  of "REMPLACERTEXTE":
    exige(3)
    ch(txt(0).replace(txt(1), txt(2)))
  of "CONTIENT":
    let v = arg(a, 0)
    if v.kind == vTable:
      for (_, x) in paires(v.t):
        if egalBrut(x, arg(a, 1)): return lg(true)
      lg(false)
    else: lg(txt(0).contains(txt(1)))
  of "COMMENCEPAR": lg(txt(0).startsWith(txt(1)))
  of "FINITPAR": lg(txt(0).endsWith(txt(1)))
  of "DECOUPER":
    let t = nouvelleTable()
    let sep = if a.len > 1: txt(1) else: ","
    if txt(0).len > 0:
      for p in (if sep == "": @[txt(0)] else: txt(0).split(sep)): t.arr.add ch(p)
    tab(t)
  of "JOINDRE":
    let t = tbl(0)
    var parts: seq[string]
    for v in t.arr: parts.add texteDe(c, v)
    ch(parts.join(if a.len > 1: txt(1) else: ""))
  of "HTML": ch(echapperHtml(txt(0)))
  of "URL": ch(encodeUrl(txt(0), usePlus = false))
  # nombres.
  of "ABS": num(abs(nb(0)))
  of "ENTIER": num(trunc(nb(0)))
  of "ARRONDI":
    let p = pow(10.0, nbDef(1, 0))
    num(round(nb(0) * p) / p)
  of "RACINE":
    let x = nb(0)
    if x < 0: raise errN(n, "racine d'un nombre négatif")
    num(sqrt(x))
  of "MOD":
    let y = nb(1)
    if y == 0: raise errN(n, "modulo par zéro")
    num(nb(0) - floor(nb(0) / y) * y)
  of "MAX", "MIN":
    exige(1)
    var r = arg(a, 0)
    for i in 1 ..< a.len:
      let plus = comparer(c, ">", a[i], r, n)
      if (nom == "MAX" and plus) or (nom == "MIN" and not plus and not egalBrut(a[i], r)): r = a[i]
    r
  of "ALEATOIRE":
    if not rngPret:
      var graine: array[8, byte]
      discard urandom(graine)
      rng = initRand(cast[int64](graine))
      rngPret = true
    if a.len == 0: num(rng.rand(1.0)) else: num(float(rng.rand(max(1, int(nb(0))) - 1) + 1))
  # types / logique.
  of "TYPE": ch(nomType(arg(a, 0)))
  of "ESTNUL": lg(arg(a, 0).kind == vNul)
  of "VIDE":
    let v = arg(a, 0)
    case v.kind
    of vNul: lg(true)
    of vLog: lg(not v.b)
    of vNum: lg(v.n == 0)
    of vChaine: lg(v.s.strip.len == 0)
    of vTable: lg(nbElements(v.t) == 0)
    of vProc: lg(false)
  # dates.
  of "DATE": ch(now().format("yyyy-MM-dd"))
  of "HEURE": ch(now().format("HH:mm:ss"))
  of "MAINTENANT": ch(now().format("yyyy-MM-dd HH:mm:ss"))
  of "HORODATAGE": num(epochTime())
  # tables.
  of "TAILLE": num(longueur(tbl(0)))
  of "NBELEMENTS": num(nbElements(tbl(0)))
  of "CLEFS", "VALEURS":
    let t = nouvelleTable()
    for (k, v) in paires(tbl(0)): t.arr.add(if nom == "CLEFS": k else: v)
    tab(t)
  of "ACLEF": lg(lireBrut(tbl(0), arg(a, 1)).kind != vNul)
  of "COPIER": tab(copieSimple(tbl(0)))
  of "FIXERMETATABLE":
    let t = tbl(0)
    let m = arg(a, 1)
    if m.kind == vNul: t.meta = nil
    elif m.kind == vTable: t.meta = m.t
    else: raise errN(n, "fixermetatable : la métatable doit être une table ou nul")
    arg(a, 0)
  of "OBTENIRMETATABLE":
    let v = arg(a, 0)
    if v.kind == vTable and v.t.meta != nil: tab(v.t.meta) else: nul()
  of "LIREBRUT": lireBrut(tbl(0), arg(a, 1))
  of "ECRIREBRUT":
    ecrireBrut(tbl(0), arg(a, 1), arg(a, 2)); arg(a, 0)
  of "INSERER":
    let t = tbl(0)
    try:
      if a.len > 2: insererA(t, int(nb(2)), arg(a, 1)) else: ajouterFin(t, arg(a, 1))
    except ErreurWDG as e: raise errN(n, e.msg)
    arg(a, 0)
  of "RETIRER":
    let t = tbl(0)
    try: retirerA(t, int(nbDef(1, float(longueur(t)))))
    except ErreurWDG as e: raise errN(n, e.msg)
  of "TRIER":
    let t = tbl(0)
    let f = arg(a, 1)
    if f.kind != vNul and not appelable(f): raise errN(n, "trier : procédure de comparaison attendue")
    t.arr.sort(proc (x, y: Val): int =
      if f.kind != vNul:
        if vrai(appeler(c, f, @[x, y], n)): -1
        elif vrai(appeler(c, f, @[y, x], n)): 1
        else: 0
      elif comparer(c, "<", x, y, n): -1
      elif comparer(c, "<", y, x, n): 1
      else: 0)
    arg(a, 0)
  of "APPELER":
    exige(1)
    appeler(c, a[0], a[1 .. ^1], n)
  # JSON.
  of "JSON":
    try: ch($versJson(arg(a, 0)))
    except ErreurWDG as e: raise errN(n, e.msg)
  of "DEJSON":
    try: depuisJson(parseJson(txt(0)))
    except JsonParsingError, ValueError: raise errN(n, "dejson : JSON invalide")
  # SQL.
  of "REQUETE":
    exige(1)
    enTable(requete(txt(0), a[1 .. ^1]))
  of "VALEURSQL":
    exige(1)
    let r = requete(txt(0), a[1 .. ^1])
    if r.lignes.len > 0 and r.lignes[0].len > 0: r.lignes[0][0] else: nul()
  of "HACHAGE":
    requete("select sha256(?)", [ch(txt(0))]).lignes[0][0]
  of "HACHERMDP":
    exige(1)
    ch(hacherMdp(txt(0)))
  of "VERIFIERMDP":
    # calcul complet même si l'empreinte est nulle (pas d'indice sur l'existence du compte).
    lg(verifierMdp(txt(0), (if arg(a, 1).kind == vChaine: arg(a, 1).s else: "")))
  of "MDPALEATOIRE":
    ch(mdpAleatoire(int(nbDef(0, 16))))
  of "UUID":
    requete("select gen_random_uuid()::varchar").lignes[0][0]
  # zones de travail.
  of "FDF":
    let z = zoneParAlias(c, a, 0, n)
    lg(z.pos >= z.cles.len)
  of "DDF": lg(zoneParAlias(c, a, 0, n).bof)
  of "NUMENR":
    let z = zoneParAlias(c, a, 0, n)
    num(if z.pos >= z.cles.len: z.cles.len + 1 else: z.pos + 1)
  of "NBENR": num(zoneParAlias(c, a, 0, n).cles.len)
  of "TROUVE": lg(zoneParAlias(c, a, 0, n).trouve)
  of "ALIAS": ch(c.session.courante)
  of "CHAMP":
    let z = zoneParAlias(c, a, 1, n)
    let i = z.colMaj.find(unicode.toUpper(txt(0)))
    if i < 0: raise errN(n, "champ inconnu dans " & z.table & " : " & txt(0))
    champZone(c, z, i)
  of "ENREGISTREMENT":
    let z = zoneParAlias(c, a, 0, n)
    let r = enregistrement(c, z)
    let t = nouvelleTable()
    for i, col in z.colMaj: ecrireBrut(t, ch(col), r[i])
    tab(t)
  else:
    raise errN(n, "procédure ou fonction inconnue : " & nom.toLowerAscii)

# chargement / points d'entrée

proc chargerProgrammes*(dossier: string): Table[string, ProcDef] =
  # Charge (récursivement) tous les fichiers .prg du dossier. Lève ErreurWDG.
  var procs: Table[string, ProcDef]
  var fichiers: seq[string]
  for p in walkDirRec(dossier):
    if p.toLowerAscii.endsWith(".prg"): fichiers.add p
  fichiers.sort()
  for p in fichiers:
    let rel = relativePath(p, parentDir(dossier))
    for d in analyserSource(readFile(p), rel):
      if procs.hasKey(d.nom):
        let a = procs[d.nom]
        raise erreur("procédure " & d.nom & " définie deux fois (" & a.fichier & ":" & $a.ligne & ")",
                     d.ligne, d.fichier)
      procs[d.nom] = d
  result = procs

proc nouvelleSession*(id, pub: string): Session =
  let t = epochTime()
  result = Session(id: id, pub: pub, vars: nouvelleTable(), ouverture: t, dernierAcces: t,
                   registre: Registre())

proc debutRequete*(s: Session) =
  # Les tables créées désormais par ce fil appartiennent à la session.
  registreCourant = s.registre

proc finRequete*(s: Session) =
  # Ramasse les tables devenues inaccessibles (cycles compris).
  registreCourant = nil
  discard ramasser(s.registre, [tab(s.vars)])

proc detruireSession*(s: Session) =
  # Libère tout ce que possède la session.
  registreCourant = nil
  toutDemolir(s.registre)
  demolir(s.vars)
  s.zones.clear()
  s.courante = ""

proc executer*(s: Session, nomProc: string, champs: LTable, infoRequete: LTable): Contexte =
  # Exécute une procédure en réponse à une requête du navigateur.
  # Les paramètres de la procédure reçoivent les champs GET/POST de même nom ;
  # la variable locale REQUETE décrit la requête.
  # Le contexte est une variable locale, affectée à `result` seulement en cas de succès :
  # une valeur déjà placée dans `result` n'est pas libérée si une exception sort de la
  # procédure (comportement du compilateur en --mm:atomicArc).
  let c = Contexte(session: s, statut: 200, procs: procedures())
  c.limite = getMonoTime() + initDuration(milliseconds = int(moteur.dureeMax * 1000))
  let d = c.procs.t[nomProc]
  var args: seq[Val]
  for p in d.params: args.add lireBrut(champs, ch(p))
  # variable locale (et non tableau temporaire en argument) : détruite même si
  # la procédure se termine par une erreur.
  let extra = [("REQUETE", tab(infoRequete))]
  discard appelerProc(c, d, args, nil, extra)
  result = c
