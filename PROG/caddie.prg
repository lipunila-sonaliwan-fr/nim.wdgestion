&& Le caddie est une table façon Lua :
&&   - des méthodes associées par  t:procedure NOM comme clef
&&     (le premier argument reçu est la table elle-même) ;
&&   - une métatable (fixermetatable) pour #caddie et l'affichage.

fonction NOUVEAUCADDIE
  locale c = {lignes = {}}
  c:procedure CADDIE_AJOUTER comme ajouter
  c:procedure CADDIE_RETIRER comme retirer
  c:procedure CADDIE_TOTAL comme total
  fixermetatable c, {__len = @CADDIE_NOMBRE, __tostring = @CADDIE_TEXTE}
retourner c

procedure CADDIE_AJOUTER(soi, id)
  pour chaque l dans soi.lignes
    si l.ID = id
      l.QTE = l.QTE + 1
      retourner
    finsi
  suivant
  locale p
  sql "select libelle, prix from produits where id = ?" avec id dans p
  si #p = 1
    inserer {id = id, libelle = p[1].LIBELLE, prix = p[1].PRIX, qte = 1} dans soi.lignes
  finsi
retourner

procedure CADDIE_RETIRER(soi, id)
  pour i = 1 a #soi.lignes
    si soi.lignes[i].ID = id
      soi.lignes[i].QTE -= 1
      si soi.lignes[i].QTE <= 0
        retirer de soi.lignes position i
      finsi
      sortir
    finsi
  suivant
retourner

procedure CADDIE_TOTAL(soi)
  locale t = 0
  pour chaque l dans soi.lignes
    t += l.PRIX * l.QTE
  suivant
retourner t

procedure CADDIE_NOMBRE(soi)
  locale n = 0
  pour chaque l dans soi.lignes
    n += l.QTE
  suivant
retourner n

procedure CADDIE_TEXTE(soi)
retourner #soi .. " article(s) · " .. chaine(soi:total(), 1, 2) .. " €"

&& Appelée par les formulaires POST du catalogue (champ plus ou moins).
&& Une modification n'est jamais faite par un simple lien GET : un autre site
&& ne peut pas la déclencher (cookie SameSite=Lax).
procedure CADDIE(plus, moins)
  si REQUETE.METHODE <> "POST"
    rediriger "/ACCUEIL"
    retourner
  finsi
  si non estnul(plus)
    SESSION.CADDIE:ajouter(valeur(plus))
  sinonsi non estnul(moins)
    SESSION.CADDIE:retirer(valeur(moins))
  finsi
  rediriger "/ACCUEIL"
retourner
