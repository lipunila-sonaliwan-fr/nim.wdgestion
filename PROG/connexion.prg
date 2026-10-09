&& Session par défaut : { VALIDE = "CONNEXION" }.
&& Tant que VALIDE vaut "CONNEXION", toute requête aboutit ici.
&& Les paramètres NOM et MDP reçoivent les champs du formulaire de même nom.
&& Le serveur limite lui-même le nombre de tentatives par adresse IP.
procedure CONNEXION(nom, mdp)
  && sans « locale », r serait une variable globale, donc rangée dans SESSION
  locale message = "", empreinte = nul, r
  si REQUETE.METHODE = "POST"
    sql "select mdp from utilisateurs where nom = ?" avec nom dans r
    si #r = 1
      empreinte = r[1].MDP
    finsi
    && verifiermdp calcule toujours un hachage complet, même pour un compte inconnu :
    && le temps de réponse ne révèle pas si l'identifiant existe.
    si verifiermdp(mdp, empreinte)
      faire OUVRIRSESSION avec nom
      retourner
    finsi
    message = "Identifiant ou mot de passe incorrect."
  finsi
  envoyer connexion avec message = message, titre = "Connexion"
retourner

&& Donne à la session les droits du compte, ou seulement le changement de
&& mot de passe si celui-ci est provisoire.
procedure OUVRIRSESSION(nom)
  locale r
  sql "select droits, accepte, changer from utilisateurs where nom = ?" avec nom dans r
  SESSION.UTILISATEUR = nom
  si r[1].CHANGER
    SESSION.ACCEPTE = "MOTDEPASSE,DECONNEXION"
    SESSION.VALIDE = "CHANGEMENT"           && session active mais restreinte
    rediriger "/MOTDEPASSE"
  sinon
    SESSION.ACCEPTE = r[1].ACCEPTE          && procédures autorisées (CSV)
    SESSION.VALIDE = r[1].DROITS            && la session devient active
    si estnul(SESSION.CADDIE)
      SESSION.CADDIE = NOUVEAUCADDIE()
    finsi
    rediriger "/ACCUEIL"
  finsi
retourner

procedure MOTDEPASSE(ancien, nouveau, confirmation)
  locale message = ""
  locale force = SESSION.VALIDE = "CHANGEMENT"
  si REQUETE.METHODE = "POST"
    locale empreinte = valeursql("select mdp from utilisateurs where nom = ?", SESSION.UTILISATEUR)
    faire cas
      cas non verifiermdp(ancien, empreinte)
        message = "Mot de passe actuel incorrect."
      cas longueur(nouveau) < 12
        message = "Le nouveau mot de passe doit faire au moins 12 caractères."
      cas nouveau == ancien
        message = "Le nouveau mot de passe doit être différent de l'actuel."
      cas nouveau <> confirmation
        message = "La confirmation ne correspond pas."
      autrement
        sql "update utilisateurs set mdp = ?, changer = false where nom = ?" ;
            avec hachermdp(nouveau), SESSION.UTILISATEUR
        faire OUVRIRSESSION avec SESSION.UTILISATEUR
        retourner
    fincas
  finsi
  envoyer motdepasse avec message = message, force = force, titre = "Mot de passe"
retourner

procedure DECONNEXION
  deconnecter
  rediriger "/"
retourner
