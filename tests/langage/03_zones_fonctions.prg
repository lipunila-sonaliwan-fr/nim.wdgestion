procedure TEST
  faire P avec "a", 2
  globale G = 7
  ? "G", G, SESSION.G
  liberer G
  ? "G libéré", type(G)
  sql "create table a (x integer); insert into a values (1),(2),(3); create table b (y varchar); insert into b values ('u'),('v')"
  utiliser a
  utiliser b alias bb
  selectionner a
  aller bas
  ? "a bas", x, "bb->y", bb->y, numenr(), nbenr("BB"), alias()
  sauter
  ? "fdf", fdf(), "x vide", type(x)
  aller 2
  ? "aller 2", x
  localiser pour x > 1
  continuer
  ? "continuer", x, trouve()
  continuer
  ? "encore", fdf(), trouve()
  sql "insert into a values (10)"
  rafraichir
  ? "rafraichi", nbenr()
  compter pour x >= 3 dans n
  ? "compter", n
  fermer bb
  ? "bb fermé", type(bb)
  statut 201
  entete "X-Essai", "oui"
  t = {10, 20, 30}
  pour chaque v dans t
    ?? v, ""
  suivant
  ?
  pour i = 10 a 1 pas -3
    ?? i, ""
  suivant
  ?
  ? enregistrement().X, json(enregistrement()), contient(t, 20), decouper("a;b;c", ";")[2]
  ? 'json "texte" < >', html("<b>&</b>"), url("é à")
  ? max(3, 9, 2), min(3, 9, 2), arrondi(2.345, 2), entier(-2.7), mod(-7, 3), -7 % 3
  x = 5
  x -= 2
  ? "x", x, 2 ^ 3 ^ 2, -2 ^ 2, "abc" $ "xxabcxx", "b" < "a"
  ? .v. .et. .f., .non. .f., nul = nul, 1 <> 2, 1 # 1
retourner
procedure P
  parametres a, b
  ? "parametres", a, b
retourner
