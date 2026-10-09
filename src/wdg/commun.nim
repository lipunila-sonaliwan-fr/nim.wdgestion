# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - configuration et état partagé du serveur

import std/[json, os, strutils, sysrand]
import http
export http.Reponse

type
  Config* = object
    ecoutes*: seq[(string, int)] # (adresse, port).
    statique*: string            # dossier des fichiers statiques (BLOB).
    base*: string                # base DuckDB.
    expiration*: float           # durée d'inactivité d'une session (secondes).
    tailleMax*: int              # taille maximale d'un corps de requête.
    pasMax*: int                 # nombre maximal d'instructions par requête.
    cookieSecurise*: bool        # cookie « Secure » (HTTPS en frontal).
    details*: bool               # détail des erreurs visible par tous (développement).
    cdnCodemirror*: string       # base des fichiers CodeMirror 5.65.16 de l'éditeur.
    essaisMax*: int              # requêtes POST anonymes (tentatives de connexion) par IP et par fenêtre.
    blocage*: float              # durée de la fenêtre et du blocage (secondes).
    anonymesParIp*: int          # sessions non connectées conservées par IP.
    sessionsMax*: int            # sessions au total.
    accesFichiersSql*: bool      # laisser le SQL lire/écrire des fichiers après DEMARRAGE.
    proxies*: seq[string]        # adresses des mandataires de confiance (X-Forwarded-For).
    fils*: int                   # fils d'exécution (requêtes traitées en parallèle).
    dureeMax*: float             # durée maximale d'une requête (secondes, 0 = illimitée).
    connexionsParIp*: int        # connexions TCP simultanées par adresse.
    fichierConfig*: string       # chemin du fichier JSON (pour enregistrer les réglages).

var
  cfg*: Config
  racine*, dossierBlob*, dossierPage*, dossierProg*: string

const nomCookie* = "WDG_SESSION"

proc nouvelId*(): string =
  # Identifiant de session : 128 bits aléatoires (source cryptographique).
  var octets: array[16, byte]
  if not urandom(octets): raise newException(OSError, "générateur aléatoire indisponible")
  for b in octets: result.add toHex(b.int, 2).toLowerAscii

proc analyserEcoute(e: string, portDefaut: int): (string, int) =
  # "127.0.0.1", "127.0.0.1:8080", "[::1]:8080", "::1".
  if e.startsWith("["):
    let f = e.find(']')
    let adr = e[1 ..< f]
    if f + 1 < e.len and e[f+1] == ':': return (adr, parseInt(e[f+2 .. ^1]))
    return (adr, portDefaut)
  if e.count(':') == 1:
    let p = e.split(':')
    return (p[0], parseInt(p[1]))
  (e, portDefaut)

proc chargerConfig*(nomProgramme: string) =
  # Lit <nom de l'exécutable>.json dans le dossier courant (valeurs par défaut sinon).
  racine = getCurrentDir()
  cfg = Config(statique: racine / "BLOB", base: racine / (nomProgramme & ".duckdb"),
               expiration: 30 * 60, tailleMax: 16 * 1024 * 1024, pasMax: 5_000_000,
               essaisMax: 10, blocage: 15 * 60, anonymesParIp: 20, sessionsMax: 10_000,
               fils: 16, dureeMax: 30, connexionsParIp: 64)
  var port = 8080
  var adresses = @["127.0.0.1"]
  let fic = racine / (nomProgramme & ".json")
  cfg.fichierConfig = fic
  if fileExists(fic):
    let j = parseFile(fic)
    if j.hasKey("port"): port = j["port"].getInt
    if j.hasKey("adresses"):
      adresses = @[]
      for a in j["adresses"]: adresses.add a.getStr
    elif j.hasKey("adresse"): adresses = @[j["adresse"].getStr]
    if j.hasKey("statique"):
      let s = j["statique"].getStr
      cfg.statique = if s.isAbsolute: s else: racine / s
    if j.hasKey("base"):
      let b = j["base"].getStr
      cfg.base = if b == ":memory:" or b.isAbsolute: b else: racine / b
    if j.hasKey("expiration_minutes"): cfg.expiration = j["expiration_minutes"].getFloat * 60
    if j.hasKey("taille_max_corps"): cfg.tailleMax = j["taille_max_corps"].getInt
    if j.hasKey("instructions_max"): cfg.pasMax = j["instructions_max"].getInt
    if j.hasKey("cookie_securise"): cfg.cookieSecurise = j["cookie_securise"].getBool
    if j.hasKey("details_erreurs"): cfg.details = j["details_erreurs"].getBool
    if j.hasKey("cdn_codemirror"): cfg.cdnCodemirror = j["cdn_codemirror"].getStr.strip(leading = false, chars = {'/'})
    if j.hasKey("connexion_essais_max"): cfg.essaisMax = j["connexion_essais_max"].getInt
    if j.hasKey("connexion_blocage_minutes"): cfg.blocage = j["connexion_blocage_minutes"].getFloat * 60
    if j.hasKey("sessions_anonymes_par_ip"): cfg.anonymesParIp = max(1, j["sessions_anonymes_par_ip"].getInt)
    if j.hasKey("sessions_max"): cfg.sessionsMax = max(10, j["sessions_max"].getInt)
    if j.hasKey("acces_fichiers_sql"): cfg.accesFichiersSql = j["acces_fichiers_sql"].getBool
    if j.hasKey("fils"): cfg.fils = clamp(j["fils"].getInt, 1, 256)
    if j.hasKey("duree_max_secondes"): cfg.dureeMax = max(0.0, j["duree_max_secondes"].getFloat)
    if j.hasKey("connexions_par_ip"): cfg.connexionsParIp = max(1, j["connexions_par_ip"].getInt)
    if j.hasKey("proxies_de_confiance"):
      for p in j["proxies_de_confiance"]: cfg.proxies.add p.getStr
    echo "Configuration : ", fic
  else:
    echo "Configuration : ", fic, " absent, valeurs par défaut"
  for a in adresses: cfg.ecoutes.add analyserEcoute(a, port)
  dossierBlob = cfg.statique.normalizedPath
  dossierPage = racine / "PAGE"
  dossierProg = racine / "PROG"

proc csv*(v: string): seq[string] =
  # Liste CSV normalisée en majuscules.
  for p in v.split(','):
    let x = p.strip.toUpperAscii
    if x.len > 0: result.add x

proc cheminSur*(base, rel: string): string =
  # Résout `rel` sous `base` ; renvoie "" si le chemin sort de `base`
  # (.., chemin absolu, lien symbolique pointant ailleurs...).
  if rel.contains('\0') or rel.contains('\\'): return ""
  var parts: seq[string]
  for p in rel.split('/'):
    if p.len == 0 or p == ".": continue
    if p == "..": return ""
    for ch in p:
      if ord(ch) < 32: return ""
    parts.add p
  let baseAbs = try: expandFilename(base) except OSError: return ""
  var cible = baseAbs
  for p in parts: cible = cible / p
  # résolution des liens existants : la partie existante doit rester sous la base.
  var existant = cible
  while not (fileExists(existant) or dirExists(existant)) and existant.len > baseAbs.len:
    existant = parentDir(existant)
  let reel = try: expandFilename(existant) except OSError: return ""
  if reel != baseAbs and not reel.startsWith(baseAbs & DirSep): return ""
  cible

proc reponse*(code: int, corps: string, typ = "text/html; charset=utf-8"): Reponse =
  Reponse(code: code, corps: corps, entetes: @[("Content-Type", typ)])

proc reponseJson*(code: int, j: JsonNode): Reponse =
  reponse(code, $j, "application/json; charset=utf-8")

proc enregistrerReglage*(clef: string, valeur: JsonNode) =
  # Met à jour une clef du fichier de configuration (les autres sont conservées).
  var j = newJObject()
  if fileExists(cfg.fichierConfig):
    try: j = parseFile(cfg.fichierConfig)
    except CatchableError: discard
  j[clef] = valeur
  writeFile(cfg.fichierConfig, j.pretty & "\n")
