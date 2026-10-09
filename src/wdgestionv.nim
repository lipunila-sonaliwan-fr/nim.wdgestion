# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - serveur web à interpréteur wdGestion V
# Tables SQL DuckDB, table façon Lua, pages à balises <% %> et langage Lexis+ (en français !).
#
# Utilise la bibliothèque sonaliwan/duckdb (duQuack) de Jean-Marc "jihem" Quéré. [ → Quelqu'un d'appréciable 😀 et en plus il était d'accord...🤣 ]

import std/[os, strutils, atomics]
import wdg/[commun, interprete, base, serveur, valeurs, stats, http]
when defined(posix):
  import std/posix

const version = "5.0.8"

echo """
               _   ___           _    _              __   __
  __ __ __  __| | / __| ___  ___| |_ (_) ___  _ _    \ \ / /
  \ V  V / / _` || (_ |/ -_)(_-<|  _|| |/ _ \| ' \    \ V /
   \_/\_/  \__,_| \___|\___|/__/ \__||_|\___/|_||_|    \_/   """ & version & """

   wdGestion V/FR - serveur web intégrant l'interpréteur Lexis+ sur DuckDB
   © 2026 Jean‑Marc "jihem"Quéré, sonaliwan.fr
"""

proc arret(msg: string) =
  echo "ERREUR : ", msg
  quit(1)

proc surSignal(sig: cint) {.noconv.} =
  # Ctrl+C ou SIGTERM : demande d'arrêt (traitée par le fil principal)
  arretDemande.store(true)

proc main() =
  let nomProgramme = splitFile(getAppFilename()).name
  try:
    chargerConfig(nomProgramme)
  except CatchableError as e:
    arret("configuration illisible : " & e.msg)

  # --- dossiers obligatoires
  for (nom, d) in [("PROG", dossierProg), ("PAGE", dossierPage), ("BLOB (fichiers statiques)", dossierBlob)]:
    if not dirExists(d): arret("dossier " & nom & " introuvable : " & d)

  # --- base DuckDB : une base, une connexion par fil (ouverte à la demande)
  try:
    baseGlobale = openDB(cfg.base)
    moteur = Moteur(dossierPage: dossierPage, dossierProg: dossierProg,
                    pasMax: cfg.pasMax, dureeMax: cfg.dureeMax)
    discard requete("create table if not exists incidents (ip varchar primary key, " &
                    "premier timestamptz, dernier timestamptz, nombre integer)")
  except CatchableError as e:
    arret("base DuckDB " & cfg.base & " : " & e.msg)
  echo "Base     : ", cfg.base

  # --- procédures
  try:
    remplacerProcs(chargerProgrammes(dossierProg))
  except ErreurWDG as e:
    arret(e.fichier & ":" & $e.ligne & " : " & e.msg)
  if not procExiste("CONNEXION"):
    arret("la procédure CONNEXION est introuvable dans " & dossierProg)
  echo "Sources  : ", nbProcedures(), " procédure(s) chargée(s) depuis ", dossierProg
  echo "Statique : ", dossierBlob

  # --- procédure DEMARRAGE facultative (création des tables, données initiales...)
  if procExiste("DEMARRAGE"):
    let s = nouvelleSession("demarrage", "demarrage")
    try:
      debutRequete(s)
      let c = executer(s, "DEMARRAGE", nouvelleTable(), nouvelleTable())
      if c.sortie.strip.len > 0: echo c.sortie.strip
      echo "DEMARRAGE exécutée"
    except ErreurWDG as e:
      arret("DEMARRAGE : " & e.fichier & ":" & $e.ligne & " : " & e.msg)
    finally:
      finRequete(s)
      detruireSession(s)

  # --- verrouillage : le SQL des procédures ne peut plus toucher au système de fichiers
  #     (read_csv, COPY, ATTACH, INSTALL...) ni rouvrir cet accès ; vaut pour toutes les connexions
  if not cfg.accesFichiersSql:
    try:
      discard requete("SET enable_external_access = false")
      discard requete("SET lock_configuration = true")
      echo "Sécurité : accès SQL aux fichiers désactivé (acces_fichiers_sql = false)"
    except CatchableError as e:
      arret("verrouillage DuckDB impossible : " & e.msg)
  else:
    echo "ATTENTION : acces_fichiers_sql = true, le SQL des procédures peut lire et écrire des fichiers"
  fermerConnFil()                 # le fil principal ne sert plus de requêtes
  surSql = noterSql
  razStats()

  when defined(posix):
    signal(SIGINT, surSignal)
    signal(SIGTERM, surSignal)
  else:
    setControlCHook(proc () {.noconv.} = arretDemande.store(true))

  lancer()
  attendreArret()                 # rend la main quand tous les fils sont arrêtés
  baseGlobale.close()
  echo "Tables restantes : ", tablesVivantes.load, " · base fermée. Arrêt du serveur."

when isMainModule:
  main()
