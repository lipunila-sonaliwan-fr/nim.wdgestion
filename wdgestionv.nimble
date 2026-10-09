# Package

version       = "1.0.0"
author        = "Jean-Marc \"jihem\" QUERE"
description   = "Serveur web à interpréteur wdGestion V (français) sur DuckDB"
license       = "CC BY-NC-SA 4.0"
srcDir        = "src"
installExt    = @["nim", "html", "h"]
bin           = @["wdgestionv"]

# Dependencies

requires "nim >= 2.2.4"

task test, "Tests du langage, du hachage des mots de passe et des fuites du parseur":
  exec "nim c -r --hints:off tests/t_langage.nim"
  exec "nim c -r -d:release --hints:off tests/t_crypto.nim"
  exec "nim c -r -d:release --hints:off tests/t_fuites_parseur.nim"

task banc, "Banc multitâche : concurrence, fuites, charge, arrêt propre (après nimble build)":
  exec "python3 tests/concurrence.py"
