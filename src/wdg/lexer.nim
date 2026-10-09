# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - analyse lexicale (programmes .prg et pages à balises <% %>)

import std/[strutils, unicode]
import valeurs

type
  TK* = enum
    tkIdent, tkNum, tkChaine, tkOp, tkFinLigne, tkFin,
    tkTexte,      # texte brut d'une page
    tkEcho,       # <%=  (échappé HTML)
    tkEchoBrut    # <%== (brut)

  Jeton* = object
    kind*: TK
    texte*: string     # texte tel qu'écrit (identifiants, opérateurs, chaînes)
    maj*: string       # identifiant normalisé en majuscules
    n*: float
    ligne*: int

const motsPointes = ["et", "ou", "non", "v", "f", "t", "vrai", "faux", "nul", "and", "or", "not"]

proc estDebutIdent(c: char): bool {.inline.} =
  c in {'a'..'z', 'A'..'Z', '_'} or ord(c) >= 128
proc estIdent(c: char): bool {.inline.} =
  c in {'a'..'z', 'A'..'Z', '_', '0'..'9'} or ord(c) >= 128

proc analyser*(src: string, fichier: string, ligneDepart = 1,
               jetons: var seq[Jeton]) =
  # Ajoute à `jetons` les jetons de `src`. Les fins de ligne deviennent des
  # séparateurs d'instructions (sauf entre parenthèses/crochets/accolades ou
  # après un « ; » final, marque de continuation dBase).
  var i = 0
  var ligne = ligneDepart
  var profondeur = 0
  var debutInstr = true          # vrai si l'on est en début d'instruction.
  let n = src.len

  template ajoute(j: Jeton) =
    jetons.add j
    debutInstr = false
  template finLigne() =
    if profondeur == 0 and jetons.len > 0 and jetons[^1].kind != tkFinLigne:
      jetons.add Jeton(kind: tkFinLigne, ligne: ligne)
    if profondeur == 0: debutInstr = true
  template err(msg: string) =
    raise erreur(msg, ligne, fichier)

  while i < n:
    let c = src[i]
    # blancs et fins de ligne.
    if c == '\n':
      finLigne()
      inc ligne; inc i; continue
    if c in {' ', '\t', '\r'}:
      inc i; continue
    # commentaires.
    if c == '*' and debutInstr:
      while i < n and src[i] != '\n': inc i
      continue
    if (c == '&' and i+1 < n and src[i+1] == '&') or
       (c == '/' and i+1 < n and src[i+1] == '/'):
      while i < n and src[i] != '\n': inc i
      continue
    # " ; " : continuation si fin de ligne, séparateur sinon.
    if c == ';':
      var j = i + 1
      while j < n and src[j] in {' ', '\t', '\r'}: inc j
      if j < n and src[j] == '&' and j+1 < n and src[j+1] == '&':
        while j < n and src[j] != '\n': inc j
      if j >= n or src[j] == '\n':
        # continuation : on saute la fin de ligne.
        i = j
        if i < n: (inc ligne; inc i)
        continue
      if profondeur > 0:
        ajoute Jeton(kind: tkOp, texte: ";", ligne: ligne)
      else:
        finLigne()
      inc i
      continue
    # nombres.
    if c in {'0'..'9'}:
      var j = i
      while j < n and src[j] in {'0'..'9'}: inc j
      if j+1 < n and src[j] == '.' and src[j+1] in {'0'..'9'}:
        inc j
        while j < n and src[j] in {'0'..'9'}: inc j
      if j < n and src[j] in {'e', 'E'}:
        var k = j + 1
        if k < n and src[k] in {'+', '-'}: inc k
        if k < n and src[k] in {'0'..'9'}:
          j = k
          while j < n and src[j] in {'0'..'9'}: inc j
      let t = src[i ..< j]
      ajoute Jeton(kind: tkNum, texte: t, n: parseFloat(t), ligne: ligne)
      i = j
      continue
    # chaînes "..." '...'.
    if c in {'"', '\''}:
      var s = ""
      var j = i + 1
      var ferme = false
      while j < n:
        let d = src[j]
        if d == c: ferme = true; break
        if d == '\n': err("chaîne non terminée")
        if d == '\\' and j+1 < n:
          let e = src[j+1]
          case e
          of 'n': s.add '\n'
          of 't': s.add '\t'
          of 'r': s.add '\r'
          of '\\': s.add '\\'
          of '"': s.add '"'
          of '\'': s.add '\''
          else: s.add '\\'; s.add e
          j += 2
          continue
        s.add d
        inc j
      if not ferme: err("chaîne non terminée")
      ajoute Jeton(kind: tkChaine, texte: s, ligne: ligne)
      i = j + 1
      continue
    # chaînes longues [[ ... ]] (multilignes, sans échappement).
    if c == '[' and i+1 < n and src[i+1] == '[':
      let fin = src.find("]]", i+2)
      if fin < 0: err("chaîne longue [[ ... ]] non terminée")
      var s = src[i+2 ..< fin]
      if s.startsWith("\n"): s = s[1..^1]
      let l0 = ligne
      ligne += src[i ..< fin].count('\n')
      ajoute Jeton(kind: tkChaine, texte: s, ligne: l0)
      i = fin + 2
      continue
    # mots pointés .et. .ou. .non. .v. .f. ...
    if c == '.' and i+1 < n and src[i+1] in {'a'..'z', 'A'..'Z'}:
      var j = i + 1
      while j < n and src[j] in {'a'..'z', 'A'..'Z'}: inc j
      if j < n and src[j] == '.':
        let mot = src[i+1 ..< j].toLowerAscii
        if mot in motsPointes:
          let m = case mot
                  of "v", "t", "vrai": "vrai"
                  of "f", "faux": "faux"
                  of "and": "et"
                  of "or": "ou"
                  of "not": "non"
                  else: mot
          ajoute Jeton(kind: tkIdent, texte: m, maj: m.toUpperAscii, ligne: ligne)
          i = j + 1
          continue
    # identifiants.
    if estDebutIdent(c):
      var j = i
      while j < n and estIdent(src[j]): inc j
      var t = src[i ..< j]
      if t == "à": t = "a"
      ajoute Jeton(kind: tkIdent, texte: t, maj: unicode.toUpper(t), ligne: ligne)
      i = j
      continue
    # opérateurs.
    var op = ""
    if i+2 < n and src[i ..< i+3] == "...": op = "..."
    elif i+1 < n:
      let deux = src[i ..< i+2]
      if deux in ["==", "<>", "!=", "<=", ">=", "->", "..", "**", "??", "+=", "-="]:
        op = deux
    if op == "":
      if c in {'+', '-', '*', '/', '%', '^', '(', ')', '[', ']', '{', '}', ',', ':',
               '=', '<', '>', '#', '$', '.', '?', '@'}:
        op = $c
      else:
        err("caractère inattendu : '" & $c & "'")
    case op
    of "(", "[", "{": inc profondeur
    of ")", "]", "}":
      if profondeur > 0: dec profondeur
    else: discard
    ajoute Jeton(kind: tkOp, texte: op, ligne: ligne)
    i += op.len
  finLigne()

proc analyserProgramme*(src, fichier: string): seq[Jeton] =
  var res: seq[Jeton]            # pas de `result` partiel si une erreur remonte (atomicArc).
  analyser(src, fichier, 1, res)
  res.add Jeton(kind: tkFin, ligne: (if res.len > 0: res[^1].ligne else: 1))
  result = res

proc analyserPage*(src, fichier: string): seq[Jeton] =
  var res: seq[Jeton]            # pas de `result` partiel si une erreur remonte (atomicArc).
  # Découpe une page :  texte  <% code %>  <%= expr %>  <%== expr %>  <%-- commentaire --%>
  var i = 0
  var ligne = 1
  let n = src.len
  while i < n:
    let d = src.find("<%", i)
    let finTexte = if d < 0: n else: d
    if finTexte > i:
      let t = src[i ..< finTexte]
      res.add Jeton(kind: tkTexte, texte: t, ligne: ligne)
      res.add Jeton(kind: tkFinLigne, ligne: ligne)
      ligne += t.count('\n')
    if d < 0: break
    # commentaire.
    if src.continuesWith("<%--", d):
      let f = src.find("--%>", d + 4)
      if f < 0: raise erreur("commentaire <%-- non terminé", ligne, fichier)
      ligne += src[d ..< f].count('\n')
      i = f + 4
      continue
    let f = src.find("%>", d + 2)
    if f < 0: raise erreur("balise <% non terminée", ligne, fichier)
    var debut = d + 2
    var genre = tkFinLigne
    if src.continuesWith("==", debut): genre = tkEchoBrut; debut += 2
    elif src.continuesWith("=", debut): genre = tkEcho; debut += 1
    let code = src[debut ..< f]
    if genre != tkFinLigne:
      res.add Jeton(kind: genre, ligne: ligne)
    var tmp: seq[Jeton]
    analyser(code, fichier, ligne, tmp)
    # on retire les fins de ligne d'une expression <%= %> (une seule expression).
    for j in tmp:
      if genre != tkFinLigne and j.kind == tkFinLigne: continue
      res.add j
    if res.len == 0 or res[^1].kind != tkFinLigne:
      res.add Jeton(kind: tkFinLigne, ligne: ligne)
    ligne += src[d ..< f].count('\n')
    i = f + 2
    # une balise de code seule sur sa ligne n'ajoute pas de ligne vide.
    if genre == tkFinLigne:
      var j = i
      while j < n and src[j] in {' ', '\t', '\r'}: inc j
      if j < n and src[j] == '\n':
        # seulement si la balise débutait la ligne (hors blancs).
        var k = d - 1
        while k >= 0 and src[k] in {' ', '\t'}: dec k
        if k < 0 or src[k] == '\n':
          i = j + 1
          inc ligne
  res.add Jeton(kind: tkFin, ligne: ligne)
  result = res
