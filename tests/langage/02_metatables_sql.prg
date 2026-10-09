procedure TEST
  * --- métatables et méthodes
  nouvelle table Vecteur
  Vecteur.__index = Vecteur
  Vecteur:procedure VNORME comme norme
  Vecteur.__tostring = @VTXT
  Vecteur.__eq = @VEGAL
  Vecteur.__lt = @VINF
  Vecteur.__add = @VADD
  a = vnew(1, 2)
  b = vnew(3, 4)
  ? "norme", b:norme(), "somme", a + b, a == vnew(1,2), a < b, b < a
  defaut = {couleur = "rouge"}
  objet = fixermetatable({}, {__index = defaut})
  ? objet.couleur, lirebrut(objet, "COULEUR"), type(obtenirmetatable(objet))
  journal = {}
  proxy = {}
  fixermetatable proxy, {__newindex = @TRACE}
  proxy.x = 5
  ? "journal", joindre(journal, ";"), lirebrut(proxy, "X")
  appelable = fixermetatable({}, {__call = @APPEL})
  ? appelable(10, 20)
  t = {5, 3, 9, 1}
  trier(t)
  ? joindre(t, ",")
  trier(t, @DECROISSANT)
  ? joindre(t, ","), json({1, 2, {a = vrai}}), dejson('{"nom":"x","l":[1,2]}').L[2]
  * --- SQL
  sql "create table clients (id integer primary key, nom varchar, age integer)"
  sql "insert into clients values (?, ?, ?), (2, 'Martin', 40), (3, 'Durand', 17)" avec 1, "Dupont", 33
  sql "select * from clients where age > ? order by nom" avec 18 dans r
  pour chaque l dans r
    ?? l.NOM, l.age, "|"
  suivant
  ?
  ? "total", valeursql("select sum(age) from clients"), "sha", gauche(hachage("abc"), 8)
  * --- zones
  utiliser clients ordre "nom"
  ? "nb", nbenr(), "pos", numenr(), nom, fdf()
  parcourir pour age >= 18
    ?? nom, ""
  finparcourir
  ?
  chercher "Martin"
  ? "trouvé", trouve(), nom, age, clients->id
  remplacer age par age + 1
  ? "age maj", age
  ajouter id par 4, nom par "Bernard", age par 51
  ? "ajouté", nom, nbenr()
  localiser pour age < 20
  ? "localisé", nom
  aller haut
  effacer
  compter dans total
  ? "après effacement", total, valeursql("select count(*) from clients")
  essayer
    x = 1 / 0
  capturer msg
    ? "erreur capturée :", msg
  finessayer
  sql "create table notes (texte varchar)"
  utiliser notes
  ajouter vide
  remplacer texte par "bonjour"
  ajouter texte par "salut"
  parcourir
    ?? numenr(), texte, ";"
  finparcourir
  ?
retourner

fonction vnew(x, y)
  locale v = {x = x, y = y}
  fixermetatable v, Vecteur
retourner v

procedure VNORME(soi)
retourner racine(soi.x ^ 2 + soi.y ^ 2)

procedure VADD(a, b)
retourner vnew(a.x + b.x, a.y + b.y)

procedure VTXT(v)
retourner "(" + v.x + "," + v.y + ")"

procedure VEGAL(a, b)
retourner a.x = b.x et a.y = b.y

procedure VINF(a, b)
retourner a:norme() < b:norme()

procedure TRACE(t, k, v)
  inserer k .. "=" .. v dans journal
  ecrirebrut(t, k, v)
retourner

procedure APPEL(soi, a, b)
retourner a * b

procedure DECROISSANT(a, b)
retourner a > b
