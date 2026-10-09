# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - écran de suivi (/SUIVI), réservé aux sessions dont VALIDE contient SUIVI

import std/[json, os, strutils, tables, atomics]
import commun, interprete, valeurs, sessions, stats, http

const pageSuivi = staticRead("suivi.html")

proc tailleBase(): int64 =
  for f in [cfg.base, cfg.base & ".wal"]:
    try:
      if fileExists(f): result += getFileSize(f)
    except OSError: discard

proc etat(moi: Session): JsonNode =
  result = chargeJson()
  let (total, anonymes) = nbSessions()
  result["tablesVivantes"] = %tablesVivantes.load
  result["sessions"] = %total
  result["sessionsAnonymes"] = %anonymes
  result["fils"] = %nbFils()
  result["filsOccupes"] = %filsOccupes.load
  result["connexions"] = %connexionsActives.load
  result["enFile"] = %connexionsEnFile()
  result["expiration"] = %(expiration() / 60)
  result["dureeMax"] = %cfg.dureeMax
  result["procedures"] = %nbProcedures()
  result["tailleBase"] = %tailleBase()
  result["listeSessions"] = listeJson(moi)

proc ok(extra: JsonNode = nil): Reponse =
  var j = %*{"ok": true}
  if extra != nil:
    for k, v in extra: j[k] = v
  reponseJson(200, j)

proc echec(code: int, msg: string): Reponse =
  reponseJson(code, %*{"ok": false, "message": msg})

proc nombre(params: Table[string, string], clef: string): float =
  try: parseFloat(params.getOrDefault(clef))
  except ValueError: -1.0

proc traiterSuivi*(methode, sous: string, params: Table[string, string],
                   moi: Session, csrfOk: bool): Reponse =
  if sous == "" or sous == "/":
    if methode != "GET": return echec(405, "méthode non autorisée")
    result = reponse(200, pageSuivi)
    result.entetes.add ("Cache-Control", "no-store")
    return
  if not csrfOk: return echec(403, "en-tête X-WDG manquant")
  case sous
  of "/etat": reponseJson(200, etat(moi))
  of "/mesures": reponseJson(200, mesuresJson())
  of "/session": reponseJson(200, contenuJson(params.getOrDefault("pub")))
  else:
    if methode != "POST": return echec(405, "POST attendu")
    case sous
    of "/fermer":
      if fermerPub(params.getOrDefault("pub")): ok() else: echec(404, "session introuvable")
    of "/fermerinactives":
      let m = nombre(params, "minutes")
      if m < 0: return echec(400, "nombre de minutes invalide")
      ok(%*{"fermees": fermerInactives(m * 60, moi)})
    of "/expiration":
      let m = nombre(params, "minutes")
      if m < 1 or m > 7 * 24 * 60: return echec(400, "durée invalide (1 minute à 7 jours)")
      fixerExpiration(m * 60)
      try: enregistrerReglage("expiration_minutes", %m)
      except CatchableError as e: return ok(%*{"avertissement": "non enregistré dans le fichier : " & e.msg})
      ok()
    of "/raz":
      razStats()
      ok()
    else: echec(404, "action inconnue")
