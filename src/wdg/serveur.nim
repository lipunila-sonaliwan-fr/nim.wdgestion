# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - serveur web : routage, droits, exécution des procédures
#
# Chaque requête est traitée par un fil du module http (plusieurs requêtes en
# parallèle). La session est empruntée en exclusivité le temps de la requête
# (module sessions) ; les tables créées sont ramassées à la fin (finRequete).

import std/[json, os, strutils, tables, times, uri, mimetypes, cookies, strtabs, locks, monotimes, atomics]
import commun, interprete, valeurs, base, editeur, http, sessions, stats, suivi

var mimes = newMimetypes()

proc journal(msg: string) =
  echo now().format("HH:mm:ss"), "  ", msg

# pages d'erreur

proc pageErreur(code: int, titre, detail: string): string =
  "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\"><title>" & $code & " " & titre &
  "</title><style>body{font:16px system-ui,sans-serif;background:#f6f5f2;color:#222;margin:0;" &
  "display:grid;place-items:center;min-height:100vh}main{max-width:40rem;padding:2rem}" &
  "h1{font-size:3rem;margin:0;color:#9b2c2c}pre{white-space:pre-wrap;background:#fff;border:1px solid #ddd;" &
  "padding:1rem;border-radius:6px;font-size:.9rem}</style></head><body><main><h1>" & $code &
  "</h1><p>" & echapperHtml(titre) & "</p>" &
  (if detail.len > 0: "<pre>" & echapperHtml(detail) & "</pre>" else: "") & "</main></body></html>"

proc valide(s: Session): string = enTexte(lireBrut(s.vars, ch("VALIDE")))
proc estParDefaut(s: Session): bool = valide(s).strip.toUpperAscii == "CONNEXION"
proc aDroit(s: Session, droit: string): bool = droit in csv(valide(s))

proc cookieSession(id: string, expire = false): string =
  result = nomCookie & "=" & id & "; Path=/; HttpOnly; SameSite=Lax"
  if cfg.cookieSecurise: result &= "; Secure"
  if expire: result &= "; Max-Age=0"

# tentatives de connexion

type Essais = object
  nombre: int
  debut: float
  bloqueJusqua: float

var essais: Table[string, Essais]# tentatives de connexion par IP.
var verrouEssais: Lock
initLock(verrouEssais)

proc nettoyerEssais() =
  let t = epochTime()
  withLock verrouEssais:
    var vieux: seq[string]
    for ip, e in essais:
      if t - e.debut > cfg.blocage and t > e.bloqueJusqua: vieux.add ip
    for ip in vieux: essais.del(ip)

proc ipClient(req: RequeteHttp): string =
  # Adresse du client ; derrière un mandataire de confiance : dernière entrée de X-Forwarded-For.
  result = req.ip
  if result in cfg.proxies:
    let xff = req.entete("X-Forwarded-For")
    if xff.len > 0:
      let p = xff.split(',')[^1].strip
      if p.len > 0 and p.len <= 45: result = p

proc enregistrerIncident*(ip: string) =
  try:
    discard requete("insert into incidents values (?, now(), now(), 1) on conflict (ip) do update " &
                    "set dernier = now(), nombre = incidents.nombre + 1", [ch(ip)])
  except ErreurWDG as e:
    journal "! incident non enregistré : " & e.msg

proc refus(s: Session, ip, quoi: string): Reponse =
  # Procédure non autorisée : 403, suppression de la session, IP mémorisée.
  fermer(s)
  enregistrerIncident(ip)
  journal "403 " & ip & " " & quoi & " (session supprimée)"
  result = reponse(403, pageErreur(403, "Accès refusé", ""))
  result.entetes.add ("Set-Cookie", cookieSession("", expire = true))

# fils : emplacements (chien de garde).

type Emplacement = object
  actif: bool
  debut: MonoTime
  conn: pointer
  interrompu: bool

var emplacements: seq[Emplacement]
var verrouEmplacements: Lock
initLock(verrouEmplacements)
var indiceFil {.threadvar.}: int

proc debutFil(i: int) {.nimcall, gcsafe.} =
  indiceFil = i

proc finFil(i: int) {.nimcall, gcsafe.} =
  fermerConnFil()                # chaque fil ferme sa connexion DuckDB.

proc marquerExecution(actif: bool) =
  {.cast(gcsafe).}:
    let p = if actif: pointeurConn(connCourante()) else: nil
    withLock verrouEmplacements:
      if indiceFil < emplacements.len:
        emplacements[indiceFil] = Emplacement(actif: actif, debut: getMonoTime(), conn: p)

# lecture de la requête

proc ajouterChamp(t: LTable, multiples: var seq[string], k: string, v: Val) =
  let cle = ch(k.toUpperAscii)
  let ancien = lireBrut(t, cle)
  if ancien.kind == vNul:
    ecrireBrut(t, cle, v)
  elif k.toUpperAscii in multiples:
    ancien.t.arr.add v
  else:
    let l = nouvelleTable()
    l.arr.add ancien
    l.arr.add v
    ecrireBrut(t, cle, tab(l))
    multiples.add k.toUpperAscii

proc parametreEntete(entete, nom: string): string =
  for p in entete.split(';'):
    let x = p.strip
    if x.toLowerAscii.startsWith(nom & "="):
      result = x[nom.len + 1 .. ^1].strip(chars = {'"', ' '})

proc lireMultipart(corps, frontiere: string, t: LTable, multiples: var seq[string]) =
  let delim = "--" & frontiere
  var i = corps.find(delim)
  while i >= 0:
    var debut = i + delim.len
    if corps.continuesWith("--", debut): break
    if corps.continuesWith("\r\n", debut): debut += 2
    let finEntetes = corps.find("\r\n\r\n", debut)
    if finEntetes < 0: break
    let suivant = corps.find("\r\n" & delim, finEntetes + 4)
    if suivant < 0: break
    let entetes = corps[debut ..< finEntetes]
    let donnees = corps[finEntetes + 4 ..< suivant]
    var nom, fichier, typ: string
    for l in entetes.split("\r\n"):
      let ll = l.toLowerAscii
      if ll.startsWith("content-disposition:"):
        nom = parametreEntete(l, "name")
        fichier = parametreEntete(l, "filename")
      elif ll.startsWith("content-type:"):
        typ = l[13 .. ^1].strip
    if nom.len > 0:
      if fichier.len > 0 or typ.len > 0:
        let f = nouvelleTable()
        ecrireBrut(f, "NOM", ch(fichier))
        ecrireBrut(f, "TYPE", ch(typ))
        ecrireBrut(f, "TAILLE", num(donnees.len))
        ecrireBrut(f, "CONTENU", ch(donnees))
        ajouterChamp(t, multiples, nom, tab(f))
      else:
        ajouterChamp(t, multiples, nom, ch(donnees))
    i = suivant + 2

proc lireChampsDans(req: RequeteHttp, result: LTable) =
  # (paramètre nommé result : le corps reprend le code d'origine).
  var multiples: seq[string]
  for (k, v) in decodeQuery(req.requete):
    ajouterChamp(result, multiples, k, ch(v))
  if req.methode == "POST" and req.corps.len > 0:
    let typ = req.entete("Content-Type")
    let tl = typ.toLowerAscii
    if tl.startsWith("application/x-www-form-urlencoded"):
      for (k, v) in decodeQuery(req.corps):
        ajouterChamp(result, multiples, k, ch(v))
    elif tl.startsWith("multipart/form-data"):
      lireMultipart(req.corps, parametreEntete(typ, "boundary"), result, multiples)
    elif tl.startsWith("application/json"):
      try:
        let j = parseJson(req.corps)
        if j.kind == JObject:
          for k, v in j: ajouterChamp(result, multiples, k, depuisJson(v))
      except JsonParsingError, ValueError: discard
    else:
      ecrireBrut(result, "CORPS", ch(req.corps))

proc lireChamps(req: RequeteHttp): LTable =
  let t = nouvelleTable()
  lireChampsDans(req, t)
  t

proc infoRequete(req: RequeteHttp, champs: LTable, ip: string): LTable =
  result = nouvelleTable()
  ecrireBrut(result, "METHODE", ch(req.methode))
  ecrireBrut(result, "CHEMIN", ch(req.chemin))
  ecrireBrut(result, "REQUETE", ch(req.requete))
  ecrireBrut(result, "IP", ch(ip))
  ecrireBrut(result, "PARAMS", tab(champs))
  let e = nouvelleTable()
  for (k, v) in req.entetes:
    if k != "cookie": ecrireBrut(e, ch(k.toUpperAscii), ch(v))
  ecrireBrut(result, "ENTETES", tab(e))
  let ck = nouvelleTable()
  for k, v in parseCookies(req.entete("Cookie")):
    if k != nomCookie: ecrireBrut(ck, ch(k.toUpperAscii), ch(v))   # clefs en MAJUSCULES, comme PARAMS
  ecrireBrut(result, "COOKIES", tab(ck))

# fichiers statiques (BLOB)

proc fichierStatique(chemin: string): string =
  let p = cheminSur(dossierBlob, chemin)
  if p != "" and fileExists(p): p else: ""

proc servirStatique(req: RequeteHttp, p: string): Reponse =
  let t0 = getMonoTime()
  let modif = getLastModificationTime(p).utc.format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
  if req.entete("If-Modified-Since") == modif:
    result = Reponse(code: 304)
  else:
    let ext = splitFile(p).ext
    var typ = mimes.getMimetype(if ext.len > 0: ext[1 .. ^1] else: "", "application/octet-stream")
    if typ.startsWith("text/") or typ in ["application/javascript", "application/json", "image/svg+xml"]:
      typ &= "; charset=utf-8"
    result = reponse(200, readFile(p), typ)
    result.entetes.add ("Last-Modified", modif)
    result.entetes.add ("Cache-Control", "no-cache")
  noterStatique(relativePath(p, dossierBlob).replace('\\', '/'),
                float((getMonoTime() - t0).inNanoseconds) / 1e9, result.corps.len)

# exécution d'une procédure

proc executerProc(s: Session, nom: string, req: RequeteHttp, ip: string): Reponse =
  let t0 = getMonoTime()
  let util = enTexte(lireBrut(s.vars, ch("UTILISATEUR")))
  contexteFil = nom & (if util.len > 0: " · " & util else: "")
  commencer(s, nom)
  marquerExecution(true)
  var c: Contexte
  try:
    let champs = lireChamps(req)
    c = executer(s, nom, champs, infoRequete(req, champs, ip))
    result = Reponse(code: c.statut, corps: c.sortie)
    var typeDefini = false
    for (k, v) in c.entetes:
      if cmpIgnoreCase(k, "Content-Type") == 0: typeDefini = true
      result.entetes.add (k, v)
    if not typeDefini: result.entetes.add ("Content-Type", "text/html; charset=utf-8")
    if c.redirection.len > 0: result.entetes.add ("Location", c.redirection)
    if c.deconnexion: fermer(s)
  except ErreurWDG as e:
    let lieu = (if e.fichier.len > 0: e.fichier & ":" & $e.ligne & " : " else: "")
    journal "500 " & ip & " " & nom & " - " & lieu & e.msg
    let detail = if cfg.details or aDroit(s, "EDITION"): lieu & e.msg else: ""
    result = reponse(500, pageErreur(500, "Erreur d'exécution", detail))
  except Exception as e:
    # erreur interne inattendue (y compris un Defect) : la requête échoue, le fil survit
    journal "500 " & ip & " " & nom & " - erreur interne : " & e.msg
    let detail = if cfg.details or aDroit(s, "EDITION"): "erreur interne : " & e.msg else: ""
    result = reponse(500, pageErreur(500, "Erreur interne", detail))
  finally:
    marquerExecution(false)
    contexteFil = ""
    noterProc(nom, float((getMonoTime() - t0).inNanoseconds) / 1e9,
              (if util.len > 0: util & " · " else: "") & ip & " · " & $result.code)

# routage

proc estNomProc(s: string): bool =
  if s.len == 0 or s.len > 64 or s[0] notin {'A'..'Z', 'a'..'z', '_'}: return false
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}: return false
  true

proc router(req: RequeteHttp, s: Session, nouvelle: bool, ip, nom: string, segs: seq[string]): Reponse =
  # Exécute la requête pour la session acquise.
  let idAvant = s.id
  let defautAvant = estParDefaut(s)
  if defautAvant:
    # session non encore validée : CONNEXION est appelée quel que soit le chemin.
    # Chaque POST anonyme compte comme une tentative de connexion (limitée par IP).
    if req.methode == "POST":
      let t = epochTime()
      var bloque = 0.0
      var vientDeBloquer = false
      withLock verrouEssais:
        var e = essais.getOrDefault(ip)
        if e.bloqueJusqua > t: bloque = e.bloqueJusqua - t
        else:
          if t - e.debut > cfg.blocage: e = Essais(debut: t)
          inc e.nombre
          if e.nombre > cfg.essaisMax:
            e.bloqueJusqua = t + cfg.blocage
            bloque = cfg.blocage
            vientDeBloquer = true
          essais[ip] = e
      if bloque > 0:
        if vientDeBloquer:
          enregistrerIncident(ip)
          journal "429 " & ip & " bloquée " & $int(cfg.blocage / 60) & " min (" & $cfg.essaisMax &
                  " tentatives de connexion)"
        if nouvelle: fermer(s)
        result = reponse(429, pageErreur(429, "Trop de tentatives de connexion. Réessayez dans " &
                         $(int(bloque / 60) + 1) & " minute(s).", ""))
        result.entetes.add ("Retry-After", $int(bloque + 1))
        return
    result = executerProc(s, "CONNEXION", req, ip)
    if active(s) and not estParDefaut(s):
      withLock verrouEssais: essais.del(ip)                       # connexion réussie : compteur remis à zéro.
  else:
    let up = nom.toUpperAscii
    if up in ["EDIT", "SUIVI"]:
      let droit = if up == "EDIT": "EDITION" else: "SUIVI"
      if not aDroit(s, droit): return refus(s, ip, "/" & up)
      var params = initTable[string, string]()
      for (k, v) in decodeQuery(req.requete): params[k] = v
      let sous = if segs.len > 1: "/" & segs[1 .. ^1].join("/") else: ""
      let csrf = req.entete("X-WDG") == "1"
      let t0 = getMonoTime()
      let util = enTexte(lireBrut(s.vars, ch("UTILISATEUR")))
      commencer(s, "/" & up & sous)
      result = if up == "EDIT": traiterEdit(req.methode, sous, params, req.corps, csrf)
               else: traiterSuivi(req.methode, sous, params, s, csrf)
      noterProc("/" & up & sous, float((getMonoTime() - t0).inNanoseconds) / 1e9,
                (if util.len > 0: util & " · " else: "") & ip & " · " & $result.code)
    else:
      if segs.len > 1: return reponse(404, pageErreur(404, "Ressource introuvable", ""))
      let accepte = csv(enTexte(lireBrut(s.vars, ch("ACCEPTE"))))
      var cible = up
      if cible == "":
        if accepte.len == 0: return reponse(404, pageErreur(404, "Aucune procédure d'accueil (ACCEPTE vide)", ""))
        cible = accepte[0]
      elif cible notin accepte:
        return refus(s, ip, "/" & nom)
      if not procExiste(cible):
        journal "500 " & ip & " procédure " & cible & " listée dans ACCEPTE mais non définie"
        return reponse(500, pageErreur(500, "Procédure non définie : " & cible, ""))
      result = executerProc(s, cible, req, ip)

  # cookie de session
  if not active(s):
    result.entetes.add ("Set-Cookie", cookieSession("", expire = true))    # déconnexion.
  else:
    var id = s.id
    if defautAvant and not estParDefaut(s):
      id = changerId(s)          # la session vient d'être validée : anti-fixation de session.
    if nouvelle or id != idAvant:
      result.entetes.add ("Set-Cookie", cookieSession(id))

proc traiter(req: RequeteHttp): Reponse {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    let ip = ipClient(req)
    let chemin = decodeUrl(req.chemin, decodePlus = false)
    if req.methode notin ["GET", "POST", "HEAD"]:
      result = reponse(405, pageErreur(405, "Méthode non autorisée", ""))
    elif req.methode != "POST" and chemin.strip(chars = {'/'}).len > 0 and fichierStatique(chemin) != "":
      # fichiers statiques (dossier BLOB uniquement), sans session.
      result = servirStatique(req, fichierStatique(chemin))
    else:
      # nom de procédure : premier segment du chemin.
      let segs = chemin.strip(chars = {'/'}).split('/')
      let nom = segs[0]
      if nom.len > 0 and not estNomProc(nom):
        result = reponse(404, pageErreur(404, "Ressource introuvable", ""))
      else:
        # session (cookie) empruntée en exclusivité ; à défaut : session par défaut.
        let id = parseCookies(req.entete("Cookie")).getOrDefault(nomCookie)
        let a = acquerir(id, ip)
        case a.code
        of 503:
          result = reponse(503, pageErreur(503, "Serveur saturé, réessayez plus tard", ""))
          result.entetes.add ("Retry-After", "60")
        of 429:
          result = reponse(429, pageErreur(429, "Trop de requêtes simultanées pour cette session", ""))
          result.entetes.add ("Retry-After", "2")
        else:
          let s = a.session
          s.ip = ip
          debutRequete(s)
          try:
            result = router(req, s, a.nouvelle, ip, nom, segs)
          except Exception as e:
            journal "! erreur interne : " & e.msg
            result = reponse(500, pageErreur(500, "Erreur interne", ""))
          finally:
            annulerTransactionOuverte()
            finRequete(s)        # ramasse les tables inaccessibles (cycles compris).
            liberer(s)
    result.entetes.add ("X-Content-Type-Options", "nosniff")
    var cadre = false
    for (k, _) in result.entetes:
      if cmpIgnoreCase(k, "X-Frame-Options") == 0: cadre = true
    if not cadre: result.entetes.add ("X-Frame-Options", "SAMEORIGIN")
    result.entetes.add ("Referrer-Policy", "same-origin")
    if cfg.cookieSecurise: result.entetes.add ("Strict-Transport-Security", "max-age=31536000")

# chien de garde

var filGarde: Thread[void]

proc garde() {.thread.} =
  # Interrompt le SQL des requêtes qui dépassent la durée maximale et
  # ferme régulièrement les sessions expirées.
  {.cast(gcsafe).}:
    var dernier = getMonoTime()
    while not arretDemande.load:
      sleep(250)
      if cfg.dureeMax > 0:
        let limite = initDuration(milliseconds = int(cfg.dureeMax * 1000) + 1000)
        withLock verrouEmplacements:
          for e in emplacements.mitems:
            if e.actif and not e.interrompu and getMonoTime() - e.debut > limite:
              interrompre(e.conn)
              e.interrompu = true
      if getMonoTime() - dernier > initDuration(seconds = 30):
        dernier = getMonoTime()
        let n = nettoyerSessions()
        nettoyerEssais()
        if n > 0: journal $n & " session(s) expirée(s) fermée(s)"

# démarrage / arrêt

proc lancer*() =
  for (adr, port) in cfg.ecoutes:
    if not cfg.cookieSecurise and adr notin ["127.0.0.1", "::1", "localhost"]:
      echo "ATTENTION : écoute sur ", adr, " sans HTTPS : mots de passe et cookies circulent en clair.",
           " Placez un mandataire HTTPS devant le serveur (voir LISEZMOI) et activez \"cookie_securise\"."
    try:
      ecouter(adr, port)
    except OSError as e:
      echo "ERREUR : impossible d'écouter sur ", adr, ":", port, " (", e.msg, ")"
      quit(1)
    echo "Écoute : http://", (if adr.contains(':'): "[" & adr & "]" else: adr), ":", port, "/"
  emplacements.setLen(cfg.fils)
  demarrer(ConfigHttp(fils: cfg.fils, tailleMax: cfg.tailleMax, delaiEntetes: 10_000,
                      delaiInactivite: 5_000, delaiEcriture: 30_000,
                      connexionsParIp: cfg.connexionsParIp, requetesParConnexion: 1000),
           traiter, debutFil, finFil, noterTrafic)
  createThread(filGarde, garde)
  echo "Fils     : ", cfg.fils, " (durée maximale d'une requête : ",
       (if cfg.dureeMax > 0: $cfg.dureeMax & " s" else: "illimitée"), ")"

proc attendreArret*() =
  # Bloque jusqu'à une demande d'arrêt (Ctrl+C, SIGTERM), puis arrête tout "proprement".
  while not arretDemande.load: sleep(200)
  echo "\nArrêt demandé : fin des requêtes en cours..."
  arreter()
  joinThread(filGarde)
  let n = toutesFermer()
  echo "Sessions fermées : ", n
