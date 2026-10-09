# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - éditeur intégré (/EDIT), réservé aux sessions dont VALIDE contient EDITION

import std/[json, os, strutils, tables, algorithm, times, unicode]
import commun, interprete, parseur, valeurs

const pageEditeur = staticRead("editeur.html")

proc decouperChemin(chemin: string): (string, string) =
  # "PAGE/sous/x.html" -> (dossier racine, "sous/x.html") ; ("", "") si racine inconnue.
  let c = chemin.strip(chars = {'/'})
  let i = c.find('/')
  let tete = (if i < 0: c else: c[0 ..< i]).toUpperAscii
  let rel = if i < 0: "" else: c[i+1 .. ^1]
  case tete
  of "BLOB": (dossierBlob, rel)
  of "PAGE": (dossierPage, rel)
  of "PROG": (dossierProg, rel)
  else: ("", "")

proc resoudre(chemin: string, racineAutorisee = false): string =
  let (base, rel) = decouperChemin(chemin)
  if base == "": return ""
  if rel == "" and not racineAutorisee: return ""
  cheminSur(base, rel)

proc racineDe(chemin: string): string =
  chemin.strip(chars = {'/'}).split('/')[0].toUpperAscii

proc arbre(): JsonNode =
  result = newJArray()
  for (nom, dir) in [("BLOB", dossierBlob), ("PAGE", dossierPage), ("PROG", dossierProg)]:
    var elems: seq[JsonNode]
    var tous: seq[(string, bool, BiggestInt, string)]
    for p in walkDirRec(dir, yieldFilter = {pcFile, pcDir}, relative = true):
      let abs = dir / p
      let estDossier = dirExists(abs)
      let taille = if estDossier: 0.BiggestInt else: (try: getFileSize(abs) except OSError: 0)
      let modif = try: getLastModificationTime(abs).format("yyyy-MM-dd HH:mm") except OSError: ""
      tous.add (p.replace('\\', '/'), estDossier, taille, modif)
    tous.sort(proc (a, b: (string, bool, BiggestInt, string)): int = cmp(a[0].toLower, b[0].toLower))
    for (p, d, t, m) in tous:
      elems.add %*{"chemin": nom & "/" & p, "dossier": d, "taille": t, "modif": m}
    result.add %*{"nom": nom, "elements": elems}

proc erreurJson(e: ref ErreurWDG): JsonNode =
  %*{"fichier": e.fichier, "ligne": e.ligne, "message": e.msg}

proc verifier(chemin, contenu: string): JsonNode =
  result = newJArray()
  let r = racineDe(chemin)
  let ext = splitFile(chemin).ext.toLowerAscii
  try:
    if r == "PROG" and ext == ".prg":
      discard analyserSource(contenu, chemin)
    elif r == "PAGE":
      discard analyserPageSource(contenu, chemin)
  except ErreurWDG as e:
    result.add erreurJson(e)

proc recharger*(): JsonNode =
  # Recharge toutes les procédures de PROG ; conserve l'ancienne version en cas d'erreur.
  result = newJArray()
  try:
    let p = chargerProgrammes(dossierProg)
    if not p.hasKey("CONNEXION"):
      result.add %*{"fichier": "PROG", "ligne": 0,
                    "message": "procédure CONNEXION absente : rechargement refusé (l'ancienne version reste active)"}
    else:
      remplacerProcs(p)
  except ErreurWDG as e:
    result.add erreurJson(e)
  except OSError as e:
    result.add %*{"fichier": "PROG", "ligne": 0, "message": e.msg}

proc ok(extra: JsonNode = nil): Reponse =
  var j = %*{"ok": true}
  if extra != nil:
    for k, v in extra: j[k] = v
  reponseJson(200, j)

proc echec(code: int, msg: string): Reponse =
  reponseJson(code, %*{"ok": false, "message": msg})

proc traiterEdit*(methode, sous: string, params: Table[string, string],
                  corps: string, csrfOk: bool): Reponse =
  if sous == "" or sous == "/":
    if methode != "GET": return echec(405, "méthode non autorisée")
    const cdn = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16"
    result = reponse(200, if cfg.cdnCodemirror.len > 0: pageEditeur.replace(cdn, cfg.cdnCodemirror) else: pageEditeur)
    result.entetes.add ("Cache-Control", "no-store")
    return
  # toutes les actions de l'API exigent l'en-tête X-WDG (protection CSRF).
  if not csrfOk: return echec(403, "en-tête X-WDG manquant")
  let chemin = params.getOrDefault("chemin")
  case sous
  of "/arbre":
    return reponseJson(200, %*{"racines": arbre(), "procedures": nbProcedures()})
  of "/lire":
    let p = resoudre(chemin)
    if p == "" or not fileExists(p): return echec(404, "fichier introuvable : " & chemin)
    let c = readFile(p)
    let binaire = c.contains('\0') or validateUtf8(c) != -1
    return reponseJson(200, %*{"chemin": chemin, "binaire": binaire,
                               "contenu": (if binaire: "" else: c), "taille": c.len})
  of "/verifier":
    if methode != "POST": return echec(405, "POST attendu")
    return reponseJson(200, %*{"erreurs": verifier(chemin, corps)})
  of "/ecrire", "/televerser":
    if methode != "POST": return echec(405, "POST attendu")
    let p = resoudre(chemin)
    if p == "" or dirExists(p): return echec(400, "chemin invalide : " & chemin)
    if sous == "/televerser" and fileExists(p) and params.getOrDefault("ecraser") != "1":
      return echec(409, "le fichier existe déjà : " & chemin)
    try:
      createDir(parentDir(p))
      writeFile(p, corps)
    except OSError, IOError:
      return echec(500, "écriture impossible : " & getCurrentExceptionMsg())
    var erreurs = verifier(chemin, corps)
    let r = racineDe(chemin)
    if r == "PROG":
      let e2 = recharger()
      if erreurs.len == 0: erreurs = e2
    elif r == "PAGE":
      viderCachePages()
    return ok(%*{"erreurs": erreurs})
  of "/dossier":
    if methode != "POST": return echec(405, "POST attendu")
    let p = resoudre(chemin)
    if p == "" or fileExists(p): return echec(400, "chemin invalide : " & chemin)
    try: createDir(p)
    except OSError: return echec(500, getCurrentExceptionMsg())
    return ok()
  of "/supprimer":
    if methode != "POST": return echec(405, "POST attendu")
    let p = resoudre(chemin)
    if p == "": return echec(400, "chemin invalide (les dossiers racines ne peuvent être supprimés)")
    try:
      if dirExists(p): removeDir(p)
      elif fileExists(p): removeFile(p)
      else: return echec(404, "introuvable : " & chemin)
    except OSError: return echec(500, getCurrentExceptionMsg())
    var erreurs = newJArray()
    if racineDe(chemin) == "PROG": erreurs = recharger()
    else: viderCachePages()
    return ok(%*{"erreurs": erreurs})
  of "/renommer":
    if methode != "POST": return echec(405, "POST attendu")
    let de = params.getOrDefault("de")
    let vers = params.getOrDefault("vers")
    if racineDe(de) != racineDe(vers): return echec(400, "déplacement entre dossiers racines interdit")
    let a = resoudre(de)
    let b = resoudre(vers)
    if a == "" or b == "": return echec(400, "chemin invalide")
    if fileExists(b) or dirExists(b): return echec(409, "la destination existe déjà")
    try:
      createDir(parentDir(b))
      if dirExists(a): moveDir(a, b) else: moveFile(a, b)
    except OSError: return echec(500, getCurrentExceptionMsg())
    var erreurs = newJArray()
    if racineDe(de) == "PROG": erreurs = recharger()
    else: viderCachePages()
    return ok(%*{"erreurs": erreurs})
  of "/recharger":
    if methode != "POST": return echec(405, "POST attendu")
    let e = recharger()
    viderCachePages()
    return ok(%*{"erreurs": e, "procedures": nbProcedures()})
  else:
    return echec(404, "action inconnue")
