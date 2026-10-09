# Vérifie que l'analyse (réussie ou en erreur) ne perd pas de mémoire.
# Le compilateur Nim (--mm:atomicArc, versions 2.2.4 à 2.2.10 au moins) ne libère pas
# un `result` déjà rempli, ni un objet ref en cours de construction, quand une exception
# sort de la procédure : le parseur est écrit pour éviter ces formes.
import wdg/[valeurs, parseur, lexer, stats]
var echecs = 0
let bon = "procedure A\n  si x = 1\n    t = {a = 1, b = {2, 3}}\n    ? souschaine(\"abc\", 1, 2) + t.a\n  sinon\n    ? 1\n  finsi\nretourner\n"
let mauvais = "procedure A\n  si x = 1\n    t = {a = 1, b = {2, 3}}\n    ? souschaine(\"abc\", 1, 2) + t.a\n  sinon\n    ? 1 +\nretourner\n"
template mesure(nom: string, corps: untyped) =
  for i in 1..2000: corps
  let m0 = memoireResidente()
  for i in 1..50000: corps
  let delta = (memoireResidente() - m0) div 1024
  echo (if delta < 1024: "ok    " else: (inc echecs; "ÉCHEC ")), nom, " : +", delta, " Ko / 50 000"
mesure("lexer seul"): discard analyserProgramme(mauvais, "x")
mesure("analyse réussie"): discard analyserSource(bon, "x")
mesure("analyse en erreur"):
  try: discard analyserSource(mauvais, "x")
  except ErreurWDG: discard
mesure("erreur dès la 1re ligne"):
  try: discard analyserSource("procedure\n", "x")
  except ErreurWDG: discard
mesure("expression en erreur"):
  try: discard analyserSource("procedure A\n  x = (1 +\nretourner\n", "x")
  except ErreurWDG: discard

if echecs > 0: quit(1)
