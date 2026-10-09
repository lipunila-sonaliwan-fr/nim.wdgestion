# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - arbre syntaxique

type
  NK* = enum
    # expressions.
    eNombre, eChaine, eLog, eNul, eIdent, eIndex, eAppel, eMethode, eUnaire,
    eBinaire, eEt, eOu, eTable, eAlias, eSiSinon
    # instructions.
    sAffecte, sExpr, sSi, sTantQue, sPour, sPourChaque, sSortir, sBoucler,
    sCas, sFaire, sAfficher, sRetour, sLocale, sGlobale, sParametres,
    sEnvoyer, sRediriger, sStatut, sEntete, sNouvelleTable, sSupprimerTable,
    sInserer, sRetirer, sAssocier, sFixerMeta, sSql, sUtiliser, sSelectionner,
    sFermer, sAller, sSauter, sAjouter, sRemplacer, sEffacer, sLocaliser,
    sContinuer, sChercher, sParcourir, sCompter, sDeconnecter, sLiberer,
    sTexte, sEcho, sErreur, sEssayer, sRafraichir, sAjoutAffecte

  Node* = ref object
    kind*: NK
    s*: string                   # nom, opérateur, texte.
    s2*: string
    n*: float
    b*: bool
    k*: seq[Node]                # enfants (expressions).
    blocs*: seq[seq[Node]]
    noms*: seq[string]
    ligne*: int
    fic*: int                    # indice dans la liste des fichiers sources.

  ProcDef* = ref object
    nom*: string                 # majuscules.
    params*: seq[string]         # majuscules.
    corps*: seq[Node]
    fichier*: string
    ligne*: int

import std/locks

var fichiersSources: seq[string] = @[]
var verrouFichiers: Lock
initLock(verrouFichiers)

proc indiceFichier*(nom: string): int =
  withLock verrouFichiers:
    let i = fichiersSources.find(nom)
    if i >= 0: return i
    fichiersSources.add nom
    return fichiersSources.len - 1

proc nomFichier*(i: int): string =
  withLock verrouFichiers:
    if i >= 0 and i < fichiersSources.len: return fichiersSources[i]
  "?"
