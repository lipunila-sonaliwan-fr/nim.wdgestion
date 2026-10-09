&& Catalogue : la table SQL « produits » est ouverte comme une zone de travail
&& dBase (utiliser / parcourir / chercher / remplacer / ajouter / effacer).

procedure ACCUEIL
  utiliser produits ordre "libelle"
  envoyer accueil avec titre = "Catalogue"
retourner

&& Réservée aux comptes dont ACCEPTE contient PRODUITS
procedure PRODUITS(action, id, libelle, prix, stock)
  utiliser produits ordre "id"
  faire cas
    cas action = "ajouter"
      si non vide(libelle)
        ajouter libelle par libelle, prix par valeur(prix), stock par valeur(stock)
      finsi
    cas action = "stock"
      chercher valeur(id)
      si trouve()
        remplacer stock par valeur(stock)
      finsi
    cas action = "effacer"
      chercher valeur(id)
      si trouve()
        effacer
      finsi
  fincas
  si non estnul(action)
    rediriger "/PRODUITS"
    retourner
  finsi
  aller haut
  envoyer produits avec titre = "Gestion des produits"
retourner

procedure INCIDENTS
  locale liste
  sql "select ip, premier::varchar as premier, dernier::varchar as dernier, nombre from incidents order by dernier desc" dans liste
  envoyer incidents avec titre = "Incidents (accès refusés)", liste = liste
retourner
