# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - serveur HTTP/1.1 à fils d'exécution
#
# Un fil d'écoute par adresse accepte les connexions et les dépose dans une file ;
# un groupe de fils de travail les traite (lecture de la requête, appel du
# gestionnaire, écriture de la réponse, keep-alive). Chaque fil possède sa connexion
# réseau en cours et sa connexion DuckDB : leur libération est déterministe.
# Délais de lecture/écriture et limite de connexions par IP protègent des clients lents.

import std/[net, nativesockets, strutils, tables, locks, atomics, times, selectors, monotimes]
when defined(posix):
  import std/posix

type
  RequeteHttp* = object
    methode*, cible*, chemin*, requete*, version*: string
    entetes*: seq[(string, string)]                               # noms en minuscules.
    corps*: string
    ip*: string                                                   # adresse du pair TCP.
    octets*: int                                                  # taille reçue (approximative : lignes + corps).

  Reponse* = object
    code*: int
    entetes*: seq[(string, string)]
    corps*: string

  Gestionnaire* = proc (r: RequeteHttp): Reponse {.nimcall, gcsafe.}
  RappelFil* = proc (indice: int) {.nimcall, gcsafe.}
  RappelTrafic* = proc (recus, envoyes: int) {.nimcall, gcsafe.}

  ConfigHttp* = object
    fils*: int                                                    # fils de travail.
    tailleMax*: int                                               # corps maximal (octets).
    delaiEntetes*: int                                            # ms pour recevoir une requête complète (hors corps).
    delaiInactivite*: int                                         # ms d'attente d'une requête sur une connexion ouverte (keep-alive).
    delaiEcriture*: int                                           # ms pour envoyer une réponse.
    connexionsParIp*: int                                         # connexions simultanées par adresse.
    requetesParConnexion*: int

  Connexion = object
    fd: SocketHandle

  Ecoute = object
    sock: Socket
    adresse: string
    port: int

var arretDemande*: Atomic[bool]
var connexionsActives*: Atomic[int]
var filsOccupes*: Atomic[int]

var
  config: ConfigHttp
  gestionnaire: Gestionnaire
  surDebutFil, surFinFil: RappelFil
  surTrafic: RappelTrafic
  fileConnexions: Channel[Connexion]
  ecoutes: seq[Ecoute]
  filsTravail: seq[Thread[int]]
  filsEcoute: seq[Thread[int]]
  verrouIp: Lock
  parIp: Table[string, int]

initLock(verrouIp)

proc entete*(r: RequeteHttp, nom: string): string =
  let n = nom.toLowerAscii
  for (k, v) in r.entetes:
    if k == n: return v
  ""

proc raison(code: int): string =
  case code
  of 100: "Continue"
  of 200: "OK"
  of 201: "Created"
  of 204: "No Content"
  of 301: "Moved Permanently"
  of 302: "Found"
  of 303: "See Other"
  of 304: "Not Modified"
  of 400: "Bad Request"
  of 403: "Forbidden"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 408: "Request Timeout"
  of 409: "Conflict"
  of 413: "Payload Too Large"
  of 429: "Too Many Requests"
  of 431: "Request Header Fields Too Large"
  of 500: "Internal Server Error"
  of 501: "Not Implemented"
  of 503: "Service Unavailable"
  else: "Status"

# lecture

type ErreurHttp = object of CatchableError
  code: int

proc echecHttp(code: int, msg: string): ref ErreurHttp =
  result = newException(ErreurHttp, msg)
  result.code = code

proc lireLigne(sock: Socket, delaiMs: int, total: var int): string =
  var l: string
  sock.readLine(l, timeout = delaiMs, maxLength = 8192)
  if l.len == 0: raise echecHttp(0, "connexion fermée")
  total += l.len
  if total > 65536: raise echecHttp(431, "en-têtes trop volumineux")
  if l == "\r\n": return ""
  l

proc lireRequete(sock: Socket, ip: string, r: var RequeteHttp): bool =
  # Renvoie faux si le client a fermé proprement.
  var total = 0
  var ligne: string
  try:
    ligne = lireLigne(sock, config.delaiEntetes, total)
  except ErreurHttp as e:
    if e.code == 0: return false
    raise
  let p = ligne.split(' ')
  if p.len != 3 or not p[2].startsWith("HTTP/1.") or not p[1].startsWith("/"):
    raise echecHttp(400, "ligne de requête invalide")
  r = RequeteHttp(methode: p[0], cible: p[1], version: p[2], ip: ip)
  let q = r.cible.find('?')
  if q >= 0:
    r.chemin = r.cible[0 ..< q]
    r.requete = r.cible[q+1 .. ^1]
  else:
    r.chemin = r.cible
  while true:
    let l = lireLigne(sock, config.delaiEntetes, total)
    if l.len == 0: break
    let d = l.find(':')
    if d <= 0: raise echecHttp(400, "en-tête invalide")
    if r.entetes.len >= 100: raise echecHttp(431, "trop d'en-têtes")
    r.entetes.add (l[0 ..< d].strip.toLowerAscii, l[d+1 .. ^1].strip)
  if r.entete("transfer-encoding").len > 0:
    raise echecHttp(501, "Transfer-Encoding non pris en charge")
  let lg = r.entete("content-length")
  if lg.len > 0:
    var n: int
    try: n = parseInt(lg)
    except ValueError: raise echecHttp(400, "Content-Length invalide")
    if n < 0: raise echecHttp(400, "Content-Length invalide")
    if n > config.tailleMax: raise echecHttp(413, "corps trop volumineux")
    if n > 0:
      if r.entete("expect").toLowerAscii == "100-continue":
        sock.send("HTTP/1.1 100 Continue\r\n\r\n")
      r.corps = newString(n)
      let delai = max(30_000, n div 50)       # au moins 50 ko/s
      let lu = sock.recv(r.corps, n, delai)
      if lu != n: raise echecHttp(400, "corps incomplet")
  elif r.methode == "POST":
    discard   # POST sans corps : accepté (corps vide)
  r.octets = total + r.corps.len
  true

# écriture

proc envoyerReponse(sock: Socket, r: Reponse, tete: bool, garder: bool): int =
  var h = "HTTP/1.1 " & $r.code & " " & raison(r.code) & "\r\n"
  var typ = false
  for (k, v) in r.entetes:
    h.add k & ": " & v & "\r\n"
  h.add "Content-Length: " & $r.corps.len & "\r\n"
  h.add "Date: " & now().utc.format("ddd, dd MMM yyyy HH:mm:ss 'GMT'") & "\r\n"
  h.add(if garder: "Connection: keep-alive\r\n" else: "Connection: close\r\n")
  h.add "\r\n"
  discard typ
  if tete or r.code == 304 or r.corps.len == 0:
    sock.send(h)
    return h.len
  if r.corps.len < 65536:
    sock.send(h & r.corps)
  else:
    sock.send(h)
    sock.send(r.corps)
  h.len + r.corps.len

proc reglerDelaiEcriture(fd: SocketHandle, ms: int) =
  when defined(posix):
    var tv = Timeval(tv_sec: posix.Time(ms div 1000), tv_usec: Suseconds((ms mod 1000) * 1000))
    discard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, addr tv, sizeof(tv).SockLen)
  else:
    var v = int32(ms)
    discard setsockopt(fd, SOL_SOCKET.cint, 0x1005.cint, cast[pointer](addr v), sizeof(v).SockLen)

# connexions
# Une connexion appartient à un seul acteur à la fois : le fil de veille (attente
# d'une requête, sans consommer de fil de travail) ou un fil de travail (traitement).

type
  Conn = ref object
    sock: Socket
    fd: SocketHandle
    ip: string
    nbRequetes: int

var
  verrouConns: Lock
  conns: Table[int, Conn]        # toutes les connexions ouvertes.
  fileVeille: Channel[int]       # connexions à surveiller (envoyées au fil de veille).
  reveilVeille: SelectEvent
  filVeille: Thread[void]

initLock(verrouConns)

proc fermerConn(fd: int) =
  var c: Conn
  withLock verrouConns:
    c = conns.getOrDefault(fd)
    conns.del(fd)
  if c == nil: return
  try: c.sock.close()
  except CatchableError: discard
  withLock verrouIp:
    let k = parIp.getOrDefault(c.ip) - 1
    if k <= 0: parIp.del(c.ip) else: parIp[c.ip] = k
  discard connexionsActives.fetchSub(1)

proc mettreEnVeille(fd: int) =
  fileVeille.send(fd)
  reveilVeille.trigger()

proc traiterConnexion(fd: int) =
  # Traite les requêtes disponibles puis rend la connexion au fil de veille.
  var c: Conn
  withLock verrouConns: c = conns.getOrDefault(fd)
  if c == nil: return
  var garder = false
  try:
    while true:
      var r: RequeteHttp
      var rep: Reponse
      try:
        if not lireRequete(c.sock, c.ip, r): break
      except ErreurHttp as e:
        rep = Reponse(code: e.code, corps: e.msg & "\n",
                      entetes: @[("Content-Type", "text/plain; charset=utf-8")])
        let env = envoyerReponse(c.sock, rep, false, false)
        if surTrafic != nil: surTrafic(0, env)
        break
      except TimeoutError:
        break
      inc c.nbRequetes
      let conn = r.entete("connection").toLowerAscii
      garder = (if r.version == "HTTP/1.1": conn != "close" else: conn == "keep-alive") and
               c.nbRequetes < config.requetesParConnexion and not arretDemande.load
      discard filsOccupes.fetchAdd(1)
      try:
        rep = gestionnaire(r)
      except Exception as e:
        echo "  ! erreur interne : ", e.msg
        rep = Reponse(code: 500, corps: "Erreur interne\n",
                      entetes: @[("Content-Type", "text/plain; charset=utf-8")])
      finally:
        discard filsOccupes.fetchSub(1)
      let env = envoyerReponse(c.sock, rep, r.methode == "HEAD", garder)
      if surTrafic != nil: surTrafic(r.octets, env)
      if not garder: break
      if not c.sock.hasDataBuffered: break                        # requêtes en pipeline : traitées tout de suite.
  except Exception:
    garder = false                                                # client parti, délai d'écriture dépassé...
  if garder and not arretDemande.load: mettreEnVeille(fd)
  else: fermerConn(fd)

proc filTravail(indice: int) {.thread.} =
  {.cast(gcsafe).}:
    if surDebutFil != nil: surDebutFil(indice)
    while true:
      let c = fileConnexions.recv()
      if c.fd == osInvalidSocket: break                           # signal d'arrêt.
      traiterConnexion(c.fd.int)
    if surFinFil != nil: surFinFil(indice)

proc veille() {.thread.} =
  # Surveille les connexions en attente de requête (keep-alive, nouvelles connexions)
  # et les confie à un fil de travail dès qu'elles ont quelque chose à lire.
  {.cast(gcsafe).}:
    let sel = newSelector[int]()
    sel.registerEvent(reveilVeille, -1)
    var echeances: Table[int, MonoTime]
    var dernierControle = getMonoTime()
    while not arretDemande.load:
      for ev in sel.select(250):
        if ev.fd == -1 or Event.User in ev.events:
          var (ok, fd) = fileVeille.tryRecv()
          while ok:
            try:
              sel.registerHandle(fd, {Event.Read}, fd)
              echeances[fd] = getMonoTime() + initDuration(milliseconds = config.delaiInactivite)
            except CatchableError:
              fermerConn(fd)
            (ok, fd) = fileVeille.tryRecv()
        else:
          let fd = sel.getData(ev.fd)
          sel.unregister(ev.fd)
          echeances.del(fd)
          if Event.Error in ev.events: fermerConn(fd)
          else: fileConnexions.send(Connexion(fd: SocketHandle(fd)))
      let t = getMonoTime()
      if t - dernierControle > initDuration(milliseconds = 500):
        dernierControle = t
        var mortes: seq[int]
        for fd, e in echeances:
          if t > e: mortes.add fd
        for fd in mortes:
          sel.unregister(fd)
          echeances.del(fd)
          fermerConn(fd)
    for fd in echeances.keys: fermerConn(fd)
    sel.close()

proc filEcoute(indice: int) {.thread.} =
  {.cast(gcsafe).}:
    let e = ecoutes[indice]
    let fd = e.sock.getFd
    while not arretDemande.load:
      var l = @[fd]
      if selectRead(l, 250) <= 0: continue
      var client: Socket
      var adresse: string
      try:
        e.sock.acceptAddr(client, adresse, flags = {})
      except CatchableError:
        continue
      var ip = adresse
      if ip.startsWith("::ffff:"): ip = ip[7 .. ^1]
      var refuse = false
      withLock verrouIp:
        let k = parIp.getOrDefault(ip)
        if k >= config.connexionsParIp: refuse = true
        else: parIp[ip] = k + 1
      if refuse:
        try:
          client.send("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        except CatchableError: discard
        client.close()
        continue
      discard connexionsActives.fetchAdd(1)
      reglerDelaiEcriture(client.getFd, config.delaiEcriture)
      let c = Conn(sock: client, fd: client.getFd, ip: ip)
      withLock verrouConns: conns[c.fd.int] = c
      mettreEnVeille(c.fd.int)   # attend la première requête sans occuper de fil.
    e.sock.close()

# interface

proc ecouter*(adresse: string, port: int) =
  # Ouvre une adresse d'écoute (lève OSError si impossible).
  let dom = if adresse.contains(':'): Domain.AF_INET6 else: Domain.AF_INET
  let s = newSocket(dom, SOCK_STREAM, IPPROTO_TCP, buffered = true)
  s.setSockOpt(OptReuseAddr, true)
  s.bindAddr(Port(port), adresse)
  s.listen(256)
  ecoutes.add Ecoute(sock: s, adresse: adresse, port: port)

proc demarrer*(c: ConfigHttp, g: Gestionnaire, debutFil, finFil: RappelFil, trafic: RappelTrafic) =
  config = c
  gestionnaire = g
  surDebutFil = debutFil
  surFinFil = finFil
  surTrafic = trafic
  when defined(posix):
    signal(SIGPIPE, SIG_IGN)
  fileConnexions.open()
  fileVeille.open()
  reveilVeille = newSelectEvent()
  createThread(filVeille, veille)
  filsTravail.setLen(c.fils)
  for i in 0 ..< c.fils: createThread(filsTravail[i], filTravail, i)
  filsEcoute.setLen(ecoutes.len)
  for i in 0 ..< ecoutes.len: createThread(filsEcoute[i], filEcoute, i)

proc arreter*() =
  # Arrêt propre : plus de nouvelles connexions, fin des requêtes en cours,
  # fils rejoints, toutes les connexions fermées.
  arretDemande.store(true)
  joinThreads(filsEcoute)
  joinThread(filVeille)
  for i in 0 ..< filsTravail.len:
    fileConnexions.send(Connexion(fd: osInvalidSocket))
  joinThreads(filsTravail)
  # connexions restées dans les files (course avec l'arrêt).
  while true:
    let (ok, c) = fileConnexions.tryRecv()
    if not ok: break
    if c.fd != osInvalidSocket: fermerConn(c.fd.int)
  while true:
    let (ok, fd) = fileVeille.tryRecv()
    if not ok: break
    fermerConn(fd)
  var restantes: seq[int]
  withLock verrouConns:
    for fd in conns.keys: restantes.add fd
  for fd in restantes: fermerConn(fd)
  fileConnexions.close()
  fileVeille.close()
  reveilVeille.close()

proc nbFils*(): int = filsTravail.len
proc connexionsEnFile*(): int = fileConnexions.peek()
