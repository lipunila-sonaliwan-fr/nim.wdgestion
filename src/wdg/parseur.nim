# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - analyse syntaxique

import valeurs, lexer, ast

type
  Parseur = object
    j: seq[Jeton]
    p: int
    fic: int
    fichier: string

const motsInstructions = [
  "si", "tantque", "pour", "sortir", "boucler", "faire", "parametres",
  "locale", "local", "globale", "retourner", "retour", "stocker", "envoyer",
  "inclure", "rediriger", "statut", "entete", "nouvelle", "supprimer",
  "inserer", "retirer", "fixermetatable", "sql", "utiliser", "selectionner",
  "fermer", "aller", "sauter", "ajouter", "remplacer", "effacer", "localiser",
  "continuer", "chercher", "parcourir", "compter", "deconnecter", "liberer",
  "erreur", "essayer", "rafraichir",
  # mots de structure (erreur s'ils apparaissent hors de leur construction).
  "sinon", "sinonsi", "finsi", "fintantque", "suivant", "finpour", "cas",
  "autrement", "fincas", "finparcourir", "capturer", "finessayer",
  "procedure", "fonction", "finprocedure", "finfonction"]

# outils

proc cur(P: Parseur): Jeton {.inline.} = P.j[P.p]
proc suivant(P: Parseur, d = 1): Jeton {.inline.} =
  P.j[min(P.p + d, P.j.len - 1)]
proc avance(P: var Parseur) {.inline.} =
  if P.p < P.j.len - 1: inc P.p

proc err(P: Parseur, msg: string) =
  raise erreur(msg, P.cur.ligne, P.fichier)

proc estMot(j: Jeton, mot: string): bool {.inline.} =
  j.kind == tkIdent and j.texte == mot
proc estOp(j: Jeton, op: string): bool {.inline.} =
  j.kind == tkOp and j.texte == op

proc noeud(P: Parseur, k: NK, ligne = -1): Node =
  Node(kind: k, ligne: (if ligne < 0: P.cur.ligne else: ligne), fic: P.fic)

proc decrire(j: Jeton): string =
  case j.kind
  of tkFinLigne: "fin de ligne"
  of tkFin: "fin du fichier"
  of tkChaine: "\"" & j.texte & "\""
  of tkTexte: "texte de page"
  of tkEcho, tkEchoBrut: "<%="
  else: "'" & j.texte & "'"

proc attendOp(P: var Parseur, op: string) =
  if not P.cur.estOp(op): P.err("'" & op & "' attendu au lieu de " & decrire(P.cur))
  P.avance

proc attendMot(P: var Parseur, mot: string) =
  if not P.cur.estMot(mot): P.err("'" & mot & "' attendu au lieu de " & decrire(P.cur))
  P.avance

proc ident(P: var Parseur): Jeton =
  var res: Jeton     # pas de `result` partiel si une erreur remonte (atomicArc).
  if P.cur.kind != tkIdent: P.err("identifiant attendu au lieu de " & decrire(P.cur))
  res = P.cur
  P.avance
  result = res

proc finInstr(P: var Parseur) =
  if P.cur.kind == tkFin: return
  if P.cur.kind != tkFinLigne:
    P.err("fin d'instruction attendue au lieu de " & decrire(P.cur))
  while P.cur.kind == tkFinLigne: P.avance

proc sauteLignes(P: var Parseur) =
  while P.cur.kind == tkFinLigne: P.avance

proc finDeLigne(P: Parseur): bool {.inline.} =
  P.cur.kind in {tkFinLigne, tkFin}

# expressions

proc expr(P: var Parseur): Node

proc args(P: var Parseur): seq[Node] =
  var res: seq[Node]             # pas de `result` partiel si une erreur remonte (atomicArc).
  P.attendOp("(")
  if not P.cur.estOp(")"):
    res.add P.expr
    while P.cur.estOp(","):
      P.avance
      res.add P.expr
  P.attendOp(")")
  result = res

proc tableCons(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.noeud(eTable)
  P.attendOp("{")
  while not P.cur.estOp("}"):
    if P.cur.estOp("["):
      P.avance
      let k = P.expr
      P.attendOp("]")
      P.attendOp("=")
      res.k.add k
      res.k.add P.expr
    elif P.cur.kind == tkIdent and P.suivant.estOp("="):
      let c = P.noeud(eChaine)
      c.s = P.cur.maj
      P.avance; P.avance
      res.k.add c
      res.k.add P.expr
    else:
      res.k.add nil
      res.k.add P.expr
    if P.cur.estOp(",") or P.cur.estOp(";"): P.avance
    elif not P.cur.estOp("}"): P.err("',' ou '}' attendu dans la table au lieu de " & decrire(P.cur))
  P.attendOp("}")
  result = res

proc primaire(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  let t = P.cur
  case t.kind
  of tkNum:
    res = P.noeud(eNombre); res.n = t.n; P.avance
  of tkChaine:
    res = P.noeud(eChaine); res.s = t.texte; P.avance
  of tkIdent:
    case t.texte
    of "vrai": res = P.noeud(eLog); res.b = true; P.avance
    of "faux": res = P.noeud(eLog); res.b = false; P.avance
    of "nul": res = P.noeud(eNul); P.avance
    else:
      if t.maj == "SISINON" and P.suivant.estOp("("):
        res = P.noeud(eSiSinon)
        P.avance
        res.k = P.args
        if res.k.len != 3: P.err("sisinon(condition, valeur_si_vrai, valeur_si_faux) attend 3 arguments")
      else:
        res = P.noeud(eIdent); res.s = t.maj; res.s2 = t.texte; P.avance
  of tkOp:
    if t.texte == "(":
      P.avance
      res = P.expr
      P.attendOp(")")
    elif t.texte == "{":
      res = P.tableCons
    elif t.texte == "@":
      # @NOM : référence explicite à une procédure.
      P.avance
      let id = P.ident
      res = P.noeud(eIdent); res.s = id.maj; res.s2 = "@"
    else:
      P.err("expression attendue au lieu de " & decrire(t))
  else:
    P.err("expression attendue au lieu de " & decrire(t))
  result = res

proc postfixe(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.primaire
  while true:
    let t = P.cur
    if t.estOp("."):
      P.avance
      let id = P.ident
      let c = P.noeud(eChaine); c.s = id.maj
      let n = P.noeud(eIndex); n.k = @[res, c]
      res = n
    elif t.estOp("["):
      P.avance
      let e = P.expr
      P.attendOp("]")
      let n = P.noeud(eIndex); n.k = @[res, e]
      res = n
    elif t.estOp("("):
      let n = P.noeud(eAppel)
      let suite = P.args
      n.k = @[res] & suite
      res = n
    elif t.estOp(":"):
      if P.suivant.estMot("procedure"): break                     # association t:procedure NOM.
      P.avance
      let id = P.ident
      let n = P.noeud(eMethode); n.s = id.maj
      let suite = P.args
      n.k = @[res] & suite
      res = n
    elif t.estOp("->"):
      if res.kind != eIdent: P.err("'->' doit suivre un alias de zone")
      P.avance
      let id = P.ident
      let n = P.noeud(eAlias); n.s = res.s; n.s2 = id.maj
      res = n
    else: break
  result = res

proc unaire(P: var Parseur): Node

proc puissance(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.postfixe
  if P.cur.estOp("^") or P.cur.estOp("**"):
    let n = P.noeud(eBinaire); n.s = "^"
    P.avance
    let droite = P.unaire
    n.k = @[res, droite]
    res = n
  result = res

proc unaire(P: var Parseur): Node =
  let t = P.cur
  if t.estOp("-") or t.estOp("#"):
    let n = P.noeud(eUnaire); n.s = t.texte
    P.avance
    let seul = P.unaire
    n.k = @[seul]
    return n
  if t.estOp("+"):
    P.avance
    return P.unaire
  P.puissance

proc multiplicatif(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.unaire
  while P.cur.kind == tkOp and P.cur.texte in ["*", "/", "%"]:
    let n = P.noeud(eBinaire); n.s = P.cur.texte
    P.avance
    let droite = P.unaire
    n.k = @[res, droite]
    res = n
  result = res

proc additif(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.multiplicatif
  while P.cur.kind == tkOp and P.cur.texte in ["+", "-"]:
    let n = P.noeud(eBinaire); n.s = P.cur.texte
    P.avance
    let droite = P.multiplicatif
    n.k = @[res, droite]
    res = n
  result = res

proc concat(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.additif
  if P.cur.estOp(".."):
    let n = P.noeud(eBinaire); n.s = ".."
    P.avance
    let droite = P.concat
    n.k = @[res, droite]
    res = n
  result = res

proc comparaison(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.concat
  while P.cur.kind == tkOp and P.cur.texte in ["=", "==", "<>", "!=", "#", "<", ">", "<=", ">=", "$"]:
    var op = P.cur.texte
    if op == "=": op = "=="
    if op in ["!=", "#"]: op = "<>"
    let n = P.noeud(eBinaire); n.s = op
    P.avance
    let droite = P.concat
    n.k = @[res, droite]
    res = n
  result = res

proc negation(P: var Parseur): Node =
  if P.cur.estMot("non"):
    let n = P.noeud(eUnaire); n.s = "non"
    P.avance
    let seul = P.negation
    n.k = @[seul]
    return n
  P.comparaison

proc conjonction(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.negation
  while P.cur.estMot("et"):
    let n = P.noeud(eEt)
    P.avance
    let droite = P.negation
    n.k = @[res, droite]
    res = n
  result = res

proc expr(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  res = P.conjonction
  while P.cur.estMot("ou"):
    let n = P.noeud(eOu)
    P.avance
    let droite = P.conjonction
    n.k = @[res, droite]
    res = n
  result = res

proc listeExpr(P: var Parseur): seq[Node] =
  var res: seq[Node]             # pas de `result` partiel si une erreur remonte (atomicArc).
  res.add P.expr
  while P.cur.estOp(","):
    P.avance
    res.add P.expr
  result = res

proc cible(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  # Cible d'affectation : variable, t.champ, t[clef].
  res = P.postfixe
  if res.kind notin {eIdent, eIndex}:
    P.err("cible d'affectation invalide")
  result = res

proc nomOuExpr(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  # Un identifiant seul est pris comme nom littéral ; sinon expression.
  if P.cur.kind == tkIdent and not P.suivant.estOp(".") and not P.suivant.estOp("(") and
     not P.suivant.estOp("["):
    res = P.noeud(eChaine); res.s = P.cur.texte
    P.avance
  else:
    res = P.expr
  result = res

# instructions

proc instruction(P: var Parseur): Node
proc bloc(P: var Parseur, fins: openArray[string]): seq[Node] =
  var res: seq[Node]             # pas de `result` partiel si une erreur remonte (atomicArc).
  while true:
    P.sauteLignes
    if P.cur.kind == tkFin: return res
    if P.cur.kind == tkIdent and P.cur.texte in fins: return res
    res.add P.instruction
  result = res

proc fermeBloc(P: var Parseur, mot: string, ouvrant: Node, nomOuvrant: string) =
  if not P.cur.estMot(mot):
    raise erreur("'" & mot & "' manquant pour '" & nomOuvrant & "' (ligne " & $ouvrant.ligne & ")",
                 P.cur.ligne, P.fichier)
  P.avance

proc instruction(P: var Parseur): Node =
  var res: Node                  # pas de `result` partiel si une erreur remonte (atomicArc).
  let t = P.cur
  case t.kind
  of tkTexte:
    res = P.noeud(sTexte); res.s = t.texte
    P.avance; P.finInstr; return res
  of tkEcho, tkEchoBrut:
    res = P.noeud(sEcho); res.b = t.kind == tkEchoBrut
    P.avance
    let seul = P.expr
    res.k = @[seul]
    P.finInstr; return res
  of tkOp:
    if t.texte in ["?", "??"]:
      res = P.noeud(sAfficher); res.b = t.texte == "?"
      P.avance
      if not P.finDeLigne: res.k = P.listeExpr
      P.finInstr; return res
  of tkIdent:
    if t.texte in motsInstructions and
       not (t.texte in ["fixermetatable", "inserer", "retirer", "erreur"] and P.suivant.estOp("(")) and
       not P.suivant.estOp("=") and not P.suivant.estOp("."):
      res = P.noeud(sExpr)       # remplacé ci-dessous.
      let mot = t.texte
      P.avance
      case mot
      of "si":
        res = P.noeud(sSi, t.ligne)
        res.k.add P.expr; P.finInstr
        res.blocs.add P.bloc(["sinonsi", "sinon", "finsi"])
        while true:
          if P.cur.estMot("sinonsi"):
            P.avance
            res.k.add P.expr; P.finInstr
            res.blocs.add P.bloc(["sinonsi", "sinon", "finsi"])
          elif P.cur.estMot("sinon") and P.suivant.estMot("si"):
            P.avance; P.avance
            res.k.add P.expr; P.finInstr
            res.blocs.add P.bloc(["sinonsi", "sinon", "finsi"])
          elif P.cur.estMot("sinon"):
            P.avance; P.finInstr
            res.blocs.add P.bloc(["finsi"])
            break
          else: break
        P.fermeBloc("finsi", res, "si")
      of "tantque":
        res = P.noeud(sTantQue, t.ligne)
        res.k.add P.expr; P.finInstr
        res.blocs.add P.bloc(["fintantque"])
        P.fermeBloc("fintantque", res, "tantque")
      of "faire":
        if P.cur.estMot("tantque"):
          P.avance
          res = P.noeud(sTantQue, t.ligne)
          res.k.add P.expr; P.finInstr
          res.blocs.add P.bloc(["fintantque"])
          P.fermeBloc("fintantque", res, "faire tantque")
        elif P.cur.estMot("cas"):
          P.avance; P.finInstr
          res = P.noeud(sCas, t.ligne)
          P.sauteLignes
          while P.cur.estMot("cas"):
            P.avance
            res.k.add P.expr; P.finInstr
            res.blocs.add P.bloc(["cas", "autrement", "fincas"])
          if P.cur.estMot("autrement"):
            P.avance; P.finInstr
            res.b = true
            res.blocs.add P.bloc(["fincas"])
          P.fermeBloc("fincas", res, "faire cas")
        else:
          res = P.noeud(sFaire, t.ligne)
          res.s = P.ident.maj
          if P.cur.estMot("avec"):
            P.avance
            res.k = P.listeExpr
      of "pour":
        if P.cur.estMot("chaque"):
          P.avance
          res = P.noeud(sPourChaque, t.ligne)
          res.noms.add P.ident.maj
          if P.cur.estOp(","):
            P.avance
            res.noms.add P.ident.maj
          P.attendMot("dans")
          res.k.add P.expr; P.finInstr
          res.blocs.add P.bloc(["suivant", "finpour"])
          if not (P.cur.estMot("suivant") or P.cur.estMot("finpour")):
            P.fermeBloc("suivant", res, "pour chaque")
          P.avance
          if P.cur.kind == tkIdent: P.avance
        else:
          res = P.noeud(sPour, t.ligne)
          res.s = P.ident.maj
          P.attendOp("=")
          res.k.add P.expr
          if not (P.cur.estMot("a") or P.cur.estMot("jusqua")):
            P.err("'a' (ou 'jusqua') attendu dans 'pour'")
          P.avance
          res.k.add P.expr
          if P.cur.estMot("pas"):
            P.avance
            res.k.add P.expr
          P.finInstr
          res.blocs.add P.bloc(["suivant", "finpour"])
          if not (P.cur.estMot("suivant") or P.cur.estMot("finpour")):
            P.fermeBloc("suivant", res, "pour")
          P.avance
          if P.cur.kind == tkIdent: P.avance
      of "sortir": res = P.noeud(sSortir, t.ligne)
      of "boucler": res = P.noeud(sBoucler, t.ligne)
      of "parametres":
        res = P.noeud(sParametres, t.ligne)
        res.noms.add P.ident.maj
        while P.cur.estOp(","):
          P.avance
          res.noms.add P.ident.maj
      of "locale", "local", "globale":
        res = P.noeud(if mot == "globale": sGlobale else: sLocale, t.ligne)
        while true:
          res.noms.add P.ident.maj
          if P.cur.estOp("="):
            P.avance
            res.k.add P.expr
          else:
            res.k.add nil
          if P.cur.estOp(","): P.avance
          else: break
      of "retourner", "retour":
        res = P.noeud(sRetour, t.ligne)
        if not P.finDeLigne: res.k.add P.expr
      of "stocker":
        res = P.noeud(sAffecte, t.ligne)
        res.k.add P.expr
        P.attendMot("dans")
        res.k.add P.cible
        while P.cur.estOp(","):
          P.avance
          res.k.add P.cible
      of "envoyer", "inclure":
        res = P.noeud(sEnvoyer, t.ligne)
        res.k.add P.nomOuExpr
        if P.cur.estMot("avec"):
          P.avance
          while true:
            res.noms.add P.ident.maj
            P.attendOp("=")
            res.k.add P.expr
            if P.cur.estOp(","): P.avance
            else: break
      of "rediriger":
        res = P.noeud(sRediriger, t.ligne); res.k.add P.expr
      of "statut":
        res = P.noeud(sStatut, t.ligne); res.k.add P.expr
      of "entete":
        res = P.noeud(sEntete, t.ligne)
        res.k.add P.expr
        P.attendOp(",")
        res.k.add P.expr
      of "nouvelle":
        P.attendMot("table")
        res = P.noeud(sNouvelleTable, t.ligne); res.k.add P.cible
        if P.cur.estOp("="):
          P.avance
          res.k.add P.expr
      of "supprimer":
        P.attendMot("table")
        res = P.noeud(sSupprimerTable, t.ligne); res.k.add P.cible
      of "inserer":
        res = P.noeud(sInserer, t.ligne)
        res.k.add P.expr
        P.attendMot("dans")
        res.k.add P.postfixe
        if P.cur.estMot("position") or P.cur.estMot("clef") or P.cur.estMot("cle"):
          res.s = (if P.cur.texte == "position": "position" else: "clef")
          P.avance
          res.k.add P.expr
      of "retirer":
        res = P.noeud(sRetirer, t.ligne)
        if P.cur.estMot("de") or P.cur.estMot("du"): P.avance
        res.k.add P.postfixe
        res.k.add nil
        res.k.add nil
        if P.cur.estMot("position") or P.cur.estMot("clef") or P.cur.estMot("cle"):
          res.s = (if P.cur.texte == "position": "position" else: "clef")
          P.avance
          res.k[1] = P.expr
        if P.cur.estMot("dans"):
          P.avance
          res.k[2] = P.cible
      of "fixermetatable":
        res = P.noeud(sFixerMeta, t.ligne)
        res.k.add P.expr
        P.attendOp(",")
        res.k.add P.expr
      of "sql":
        res = P.noeud(sSql, t.ligne)
        res.k.add P.expr
        res.k.add nil
        if P.cur.estMot("avec"):
          P.avance
          res.k.add P.listeExpr
        if P.cur.estMot("dans"):
          P.avance
          res.k[1] = P.cible
      of "utiliser":
        res = P.noeud(sUtiliser, t.ligne)
        res.k = @[nil, nil, nil]
        if not P.finDeLigne:
          res.k[0] = P.nomOuExpr
          while not P.finDeLigne:
            if P.cur.estMot("alias"):
              P.avance; res.s = P.ident.maj
            elif P.cur.estMot("ordre"):
              P.avance; res.k[1] = P.expr
            elif P.cur.estMot("filtre"):
              P.avance; res.k[2] = P.expr
            else: P.err("'alias', 'ordre' ou 'filtre' attendu au lieu de " & decrire(P.cur))
      of "selectionner":
        res = P.noeud(sSelectionner, t.ligne); res.k.add P.nomOuExpr
      of "fermer":
        res = P.noeud(sFermer, t.ligne)
        if P.cur.estMot("tout"): res.s = "*"; P.avance
        elif P.cur.kind == tkIdent: res.s = P.ident.maj
      of "aller":
        res = P.noeud(sAller, t.ligne)
        if P.cur.estMot("haut") or P.cur.estMot("debut"): res.s = "haut"; P.avance
        elif P.cur.estMot("bas") or P.cur.estMot("fin"): res.s = "bas"; P.avance
        else: res.k.add P.expr
      of "sauter":
        res = P.noeud(sSauter, t.ligne)
        if not P.finDeLigne: res.k.add P.expr
      of "ajouter", "remplacer":
        res = P.noeud(if mot == "ajouter": sAjouter else: sRemplacer, t.ligne)
        if mot == "ajouter" and P.cur.estMot("vide"): P.avance
        if mot == "ajouter" and P.cur.estMot("avec"): P.avance
        if mot == "remplacer" or not P.finDeLigne:
          while true:
            res.noms.add P.ident.maj
            P.attendMot("par")
            res.k.add P.expr
            if P.cur.estOp(","): P.avance
            else: break
      of "effacer": res = P.noeud(sEffacer, t.ligne)
      of "continuer": res = P.noeud(sContinuer, t.ligne)
      of "deconnecter": res = P.noeud(sDeconnecter, t.ligne)
      of "rafraichir": res = P.noeud(sRafraichir, t.ligne)
      of "localiser":
        res = P.noeud(sLocaliser, t.ligne)
        if P.cur.estMot("pour"): P.avance
        res.k.add P.expr
      of "chercher":
        res = P.noeud(sChercher, t.ligne); res.k.add P.expr
      of "parcourir":
        res = P.noeud(sParcourir, t.ligne)
        if P.cur.estMot("pour"):
          P.avance
          res.k.add P.expr
        else: res.k.add nil
        P.finInstr
        res.blocs.add P.bloc(["finparcourir"])
        P.fermeBloc("finparcourir", res, "parcourir")
      of "compter":
        res = P.noeud(sCompter, t.ligne)
        res.k = @[nil, nil]
        if P.cur.estMot("pour"):
          P.avance
          res.k[0] = P.expr
        P.attendMot("dans")
        res.k[1] = P.cible
      of "liberer":
        res = P.noeud(sLiberer, t.ligne)
        res.noms.add P.ident.maj
        while P.cur.estOp(","):
          P.avance
          res.noms.add P.ident.maj
      of "erreur":
        res = P.noeud(sErreur, t.ligne); res.k.add P.expr
      of "essayer":
        res = P.noeud(sEssayer, t.ligne)
        P.finInstr
        res.blocs.add P.bloc(["capturer", "finessayer"])
        if P.cur.estMot("capturer"):
          P.avance
          if P.cur.kind == tkIdent: res.s = P.ident.maj
          P.finInstr
          res.blocs.add P.bloc(["finessayer"])
        P.fermeBloc("finessayer", res, "essayer")
      of "procedure", "fonction":
        raise erreur("'" & mot & "' inattendu : procédure imbriquée ou bloc non fermé", t.ligne, P.fichier)
      else:
        raise erreur("'" & mot & "' inattendu ici (bloc non ouvert ?)", t.ligne, P.fichier)
      P.finInstr
      return res
  else: discard

  # affectation, appel, association de procédure.
  let ligne = t.ligne
  let e = P.postfixe
  if P.cur.estOp("="):
    if e.kind notin {eIdent, eIndex}: P.err("cible d'affectation invalide")
    P.avance
    res = P.noeud(sAffecte, ligne)
    let gauche = P.expr
    res.k = @[gauche, e]
  elif P.cur.estOp("+=") or P.cur.estOp("-="):
    if e.kind notin {eIdent, eIndex}: P.err("cible d'affectation invalide")
    res = P.noeud(sAjoutAffecte, ligne); res.s = P.cur.texte[0..0]
    P.avance
    let gauche = P.expr
    res.k = @[gauche, e]
  elif P.cur.estOp(":") and P.suivant.estMot("procedure"):
    P.avance; P.avance
    res = P.noeud(sAssocier, ligne)
    res.k = @[e]
    res.s = P.ident.maj
    res.s2 = res.s
    if P.cur.estMot("comme"):
      P.avance
      if P.cur.kind == tkChaine: res.s2 = P.cur.texte; P.avance
      else: res.s2 = P.ident.maj
  elif e.kind in {eAppel, eMethode}:
    res = P.noeud(sExpr, ligne)
    res.k = @[e]
  else:
    raise erreur("instruction inconnue ou incomplète" &
                 (if t.kind == tkIdent: " : '" & t.texte & "'" else: ""), ligne, P.fichier)
  P.finInstr
  result = res

#  points d'entrée

proc analyserSource*(src, fichier: string): seq[ProcDef] =
  var res: seq[ProcDef]          # pas de `result` partiel si une erreur remonte (atomicArc).
  var P = Parseur(j: analyserProgramme(src, fichier), fic: indiceFichier(fichier), fichier: fichier)
  while true:
    P.sauteLignes
    if P.cur.kind == tkFin: break
    if P.cur.estMot("procedure") or P.cur.estMot("fonction"):
      let ligne = P.cur.ligne
      P.avance
      let nom = P.ident.maj      # évalué avant la construction (atomicArc).
      let d = ProcDef(nom: nom, fichier: fichier, ligne: ligne)
      if P.cur.estOp("("):
        P.avance
        if not P.cur.estOp(")"):
          d.params.add P.ident.maj
          while P.cur.estOp(","):
            P.avance
            d.params.add P.ident.maj
        P.attendOp(")")
      P.finInstr
      d.corps = P.bloc(["procedure", "fonction", "finprocedure", "finfonction"])
      if P.cur.estMot("finprocedure") or P.cur.estMot("finfonction"):
        P.avance
        P.finInstr
      res.add d
    else:
      P.err("instruction hors procédure (attendu : procedure NOM)")
  result = res

proc analyserPageSource*(src, fichier: string): seq[Node] =
  var res: seq[Node]             # pas de `result` partiel si une erreur remonte (atomicArc).
  var P = Parseur(j: analyserPage(src, fichier), fic: indiceFichier(fichier), fichier: fichier)
  res = P.bloc([])
  if P.cur.kind != tkFin:
    P.err("'" & P.cur.texte & "' inattendu")
  result = res
