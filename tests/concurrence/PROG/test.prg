&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Application de test du banc tests/concurrence.py
procedure CONNEXION(nom)
  si REQUETE.METHODE = "POST"
    SESSION.UTILISATEUR = nom
    SESSION.ACCEPTE = "ACCUEIL,LONG,SQLLONG,COMPTEUR,CYCLES,AJOUT,RECURSION"
    SESSION.VALIDE = sisinon(nom = "admin", "UTILISATEUR,SUIVI,EDITION", "UTILISATEUR")
    SESSION.N = 0
    SESSION.PANIER = {}
    rediriger "/ACCUEIL"
    retourner
  finsi
  ? "connexion"
retourner

procedure ACCUEIL
  ? "accueil", SESSION.UTILISATEUR
retourner

&& calcul pur pendant `secondes`
procedure LONG(secondes)
  locale t0 = horodatage(), n = 0
  tantque horodatage() - t0 < valeur(secondes)
    n += 1
  fintantque
  ? "fini", n
retourner

&& requête SQL très longue (doit être interrompue par duree_max_secondes)
procedure SQLLONG
  ? valeursql("select sum(a.range * b.range) from range(300000) a, range(300000) b")
retourner

&& lecture / attente / écriture : sans sérialisation par session, des incréments se perdraient
procedure COMPTEUR
  locale v = SESSION.N
  locale t0 = horodatage()
  tantque horodatage() - t0 < 0.05
  fintantque
  SESSION.N = v + 1
  ? SESSION.N
retourner

&& tables cycliques temporaires + une table cyclique gardée en session (remplacée à chaque appel)
procedure CYCLES(n)
  pour i = 1 a valeur(n)
    locale t = {}
    t.moi = t
    fixermetatable t, {__index = t}
  suivant
  locale g = {}
  g.moi = g
  SESSION.GARDE = g
  ? "ok"
retourner

procedure AJOUT(id)
  inserer valeur(id) dans SESSION.PANIER
  ? #SESSION.PANIER
retourner

procedure RECURSION(n)
  ? PROFOND(valeur(n))
retourner

fonction PROFOND(n)
  si n <= 0
    retourner 0
  finsi
retourner 1 + PROFOND(n - 1)
