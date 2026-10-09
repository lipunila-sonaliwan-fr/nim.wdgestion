# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - sessions partagées entre les fils d'exécution
#
# Règles :
#  - la table des sessions est protégée par un verrou ;
#  - une session n'est utilisée que par un fil à la fois (drapeau `occupee`) :
#    deux requêtes de la même session s'exécutent l'une après l'autre (au plus
#    `attenteMax` en attente, au-delà : 429), deux sessions différentes en parallèle ;
#  - une session fermée pendant qu'elle est occupée (déconnexion, 403, écran de suivi)
#    est marquée `fermee` puis démolie par son fil à la fin de la requête ;
#  - démolir une session libère toutes ses tables (cycles compris).

import std/[locks, tables, times, strutils, json, algorithm]
import commun, interprete, valeurs

const attenteMax = 4

var
  verrouSessions: Lock
  condSessions: Cond
  sessions: Table[string, Session]                                # identifiant secret -> session.

initLock(verrouSessions)
initCond(condSessions)

proc texteVar(s: Session, clef: string): string =
  let v = lireBrut(s.vars, ch(clef))
  if v.kind in {vChaine, vNum, vLog}: enTexte(v) else: ""

proc estAnonyme(s: Session): bool = s.valide.strip.toUpperAscii == "CONNEXION"

# fermeture (verrou tenu)

proc fermerVerrouTenu(s: Session) =
  if sessions.getOrDefault(s.id) == s: sessions.del(s.id)
  if not s.fermee:
    s.fermee = true
    if not s.occupee: detruireSession(s)
  broadcast(condSessions)

proc limiterSessions(ip: string): bool =
  # Au plus `anonymesParIp` sessions non connectées par IP (les plus anciennes
  # sont oubliées) et `sessionsMax` au total. Faux si le serveur est plein.
  var siennes, anonymes: seq[(float, Session)]
  for _, s in sessions:
    if estAnonyme(s) and not s.occupee and s.enAttente == 0:
      anonymes.add (s.dernierAcces, s)
      if s.ip == ip: siennes.add (s.dernierAcces, s)
  if siennes.len >= cfg.anonymesParIp:
    siennes.sort(proc (a, b: (float, Session)): int = cmp(a[0], b[0]))
    for i in 0 .. siennes.len - cfg.anonymesParIp: fermerVerrouTenu(siennes[i][1])
  if sessions.len >= cfg.sessionsMax:
    anonymes.sort(proc (a, b: (float, Session)): int = cmp(a[0], b[0]))
    var i = 0
    while sessions.len >= cfg.sessionsMax and i < anonymes.len:
      if not anonymes[i][1].fermee: fermerVerrouTenu(anonymes[i][1])
      inc i
  sessions.len < cfg.sessionsMax

# acquisition / libération

type Acquisition* = object
  session*: Session
  nouvelle*: bool
  code*: int                     # 0 : session acquise ; 429 : trop de requêtes en attente ; 503 : saturé.

proc acquerir*(cookieId, ip: string): Acquisition =
  # Donne au fil appelant l'usage exclusif de la session du cookie (ou d'une
  # nouvelle session par défaut). Peut attendre la fin d'une requête de la même session.
  withLock verrouSessions:
    while true:
      var s = if cookieId.len > 0: sessions.getOrDefault(cookieId) else: nil
      if s != nil and not s.occupee and s.enAttente == 0 and
         epochTime() - s.dernierAcces > cfg.expiration:
        fermerVerrouTenu(s)
        s = nil
      if s == nil:
        if not limiterSessions(ip): return Acquisition(code: 503)
        registreCourant = nil
        s = nouvelleSession(nouvelId(), nouvelId()[0 ..< 12])
        ecrireBrut(s.vars, ch("VALIDE"), ch("CONNEXION"))         # session par défaut.
        s.valide = "CONNEXION"
        s.ip = ip
        s.occupee = true
        sessions[s.id] = s
        return Acquisition(session: s, nouvelle: true)
      if not s.occupee:
        s.occupee = true
        return Acquisition(session: s)
      if s.enAttente >= attenteMax: return Acquisition(code: 429)
      inc s.enAttente
      wait(condSessions, verrouSessions)
      dec s.enAttente

proc commencer*(s: Session, procedure: string) =
  withLock verrouSessions:
    s.procEnCours = procedure
    s.debutEnCours = epochTime()

proc liberer*(s: Session) =
  # Fin de requête : résumé pour le suivi, puis la session redevient disponible (ou est démolie si elle a été fermée entre-temps).
  let util = if s.fermee: s.utilisateur else: texteVar(s, "UTILISATEUR")
  let val = if s.fermee: s.valide else: texteVar(s, "VALIDE")
  withLock verrouSessions:
    s.utilisateur = util
    s.valide = val
    s.procEnCours = ""
    s.dernierAcces = epochTime()
    inc s.nbRequetes
    s.occupee = false
    if s.fermee: detruireSession(s)
    broadcast(condSessions)

proc fermer*(s: Session) =
  withLock verrouSessions: fermerVerrouTenu(s)

proc active*(s: Session): bool =
  withLock verrouSessions:
    result = not s.fermee and sessions.getOrDefault(s.id) == s

proc changerId*(s: Session): string =
  # Nouvel identifiant secret (anti-fixation de session).
  withLock verrouSessions:
    if sessions.getOrDefault(s.id) == s: sessions.del(s.id)
    s.id = nouvelId()
    sessions[s.id] = s
    result = s.id

# entretien et écran de suivi

proc nettoyerSessions*(): int =
  # Ferme les sessions inactives depuis plus que la durée configurée.
  withLock verrouSessions:
    let t = epochTime()
    var mortes: seq[Session]
    for _, s in sessions:
      if not s.occupee and s.enAttente == 0 and t - s.dernierAcces > cfg.expiration: mortes.add s
    for s in mortes: fermerVerrouTenu(s)
    result = mortes.len

proc fermerInactives*(secondes: float, sauf: Session): int =
  withLock verrouSessions:
    let t = epochTime()
    var cibles: seq[Session]
    for _, s in sessions:
      if s != sauf and not s.occupee and t - s.dernierAcces > secondes: cibles.add s
    for s in cibles: fermerVerrouTenu(s)
    result = cibles.len

proc fermerPub*(pub: string): bool =
  withLock verrouSessions:
    for _, s in sessions:
      if s.pub == pub:
        fermerVerrouTenu(s)
        return true

proc fixerExpiration*(secondes: float) =
  withLock verrouSessions: cfg.expiration = secondes

proc expiration*(): float =
  withLock verrouSessions: result = cfg.expiration

proc nbSessions*(): (int, int) =
  # (total, non connectées).
  withLock verrouSessions:
    for _, s in sessions:
      inc result[0]
      if estAnonyme(s): inc result[1]

proc listeJson*(moi: Session): JsonNode =
  result = newJArray()
  withLock verrouSessions:
    let t = epochTime()
    for _, s in sessions:
      result.add %*{
        "pub": s.pub, "moi": s == moi, "utilisateur": s.utilisateur, "ip": s.ip,
        "valide": s.valide, "anonyme": estAnonyme(s),
        "ouverture": s.ouverture, "duree": t - s.ouverture,
        "inactivite": (if s.occupee: 0.0 else: t - s.dernierAcces),
        "occupee": s.occupee, "procedure": s.procEnCours,
        "depuis": (if s.occupee: t - s.debutEnCours else: 0.0),
        "requetes": s.nbRequetes, "enAttente": s.enAttente,
        "tables": (if s.occupee: -1 else: s.registre.tables.len)}

proc valJson(v: Val, ids: var Table[pointer, int], budget: var int, prof: int): JsonNode =
  case v.kind
  of vNul: %*{"t": "nul"}
  of vLog: %*{"t": "logique", "v": v.b}
  of vNum: %*{"t": "nombre", "v": v.n}
  of vProc: %*{"t": "procedure", "v": v.p}
  of vChaine:
    let s = if v.s.len > 2000: v.s[0 ..< 2000] & "…" else: v.s
    %*{"t": "chaine", "v": s, "n": v.s.len}
  of vTable:
    let p = cast[pointer](v.t)
    if ids.hasKey(p): return %*{"t": "ref", "id": ids[p]}
    let id = ids.len + 1
    ids[p] = id
    dec budget
    var r = %*{"t": "table", "id": id, "n": nbElements(v.t)}
    if budget <= 0 or prof > 40:
      r["tronque"] = %true
      return r
    var elems = newJArray()
    for (k, x) in paires(v.t):
      if budget <= 0:
        r["tronque"] = %true
        break
      elems.add %[valJson(k, ids, budget, prof + 1), valJson(x, ids, budget, prof + 1)]
    r["elements"] = elems
    if v.t.meta != nil: r["meta"] = valJson(tab(v.t.meta), ids, budget, prof + 1)
    r

proc contenuJson*(pub: string): JsonNode =
  # Contenu d'une session ; la session est empruntée le temps de la lecture.
  var s: Session = nil
  withLock verrouSessions:
    for _, x in sessions:
      if x.pub == pub: s = x
    if s == nil: return %*{"erreur": "session introuvable"}
    if s.occupee: return %*{"erreur": "session occupée par une requête, réessayez"}
    s.occupee = true
  try:
    var ids = initTable[pointer, int]()
    var budget = 5000
    var zones = newJArray()
    for alias, z in s.zones:
      zones.add %*{"alias": alias, "table": z.table, "position": z.pos + 1, "enregistrements": z.cles.len,
                   "ordre": z.ordre, "filtre": z.filtre, "courante": alias == s.courante}
    result = %*{"pub": s.pub, "session": valJson(tab(s.vars), ids, budget, 0), "zones": zones,
                "tables": s.registre.tables.len}
  finally:
    withLock verrouSessions:
      s.occupee = false
      if s.fermee: detruireSession(s)
      broadcast(condSessions)

proc toutesFermer*(): int =
  # Arrêt du serveur (plus aucun fil de travail) : démolit toutes les sessions.
  withLock verrouSessions:
    var toutes: seq[Session]
    for _, s in sessions: toutes.add s
    for s in toutes:
      s.occupee = false
      fermerVerrouTenu(s)
    result = toutes.len
