# Tests de non-régression du langage : chaque tests/langage/*.prg définit une
# procédure TEST dont la sortie est comparée au fichier .attendu correspondant.
#   nim c -r tests/t_langage.nim            (vérifie)
#   nim c -r tests/t_langage.nim --maj      (régénère les .attendu)

import std/[os, strutils, algorithm, atomics]
import wdg/[valeurs, interprete, base]

proc executerTest(fichier: string): string =
  let tmp = getTempDir() / "wdg_test_" & $getCurrentProcessId()
  removeDir(tmp)
  createDir(tmp / "PROG"); createDir(tmp / "PAGE")
  copyFile(fichier, tmp / "PROG" / "t.prg")
  baseGlobale = openDB(":memory:")
  moteur = Moteur(pasMax: 1_000_000, dossierPage: tmp / "PAGE")
  let s = nouvelleSession("t", "t")
  try:
    remplacerProcs(chargerProgrammes(tmp / "PROG"))
    debutRequete(s)
    result = executer(s, "TEST", nouvelleTable(), nouvelleTable()).sortie
  except ErreurWDG as e:
    result = "ERREUR " & e.fichier & ":" & $e.ligne & " " & e.msg & "\n"
  finRequete(s)
  detruireSession(s)
  fermerConnFil()
  baseGlobale.close()
  removeDir(tmp)

when isMainModule:
  let maj = "--maj" in commandLineParams()
  var echecs = 0
  var fichiers: seq[string]
  for f in walkFiles(currentSourcePath.parentDir / "langage" / "*.prg"): fichiers.add f
  fichiers.sort()
  for f in fichiers:
    let sortie = executerTest(f)
    let attendu = f.changeFileExt("attendu")
    if maj:
      writeFile(attendu, sortie)
      echo "maj   ", f.extractFilename
    elif fileExists(attendu) and readFile(attendu) == sortie:
      echo "ok    ", f.extractFilename
    else:
      inc echecs
      echo "ÉCHEC ", f.extractFilename, "\n--- obtenu :\n", sortie
  if tablesVivantes.load != 0:
    inc echecs
    echo "ÉCHEC tables non libérées : ", tablesVivantes.load
  if echecs > 0: quit(1)
