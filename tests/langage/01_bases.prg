procedure TEST
  x = 3
  locale y = x * 2 + 1
  ? "y =", y, "x^2=", x ^ 2, 7 % 3, "a" + 1, "b" .. 2
  si y > 5 et non (x = 4)
    ? "grand"
  sinonsi y = 0
    ? "zero"
  sinon
    ? "petit"
  finsi
  pour i = 1 a 3
    ?? i
  suivant
  ?
  nouvelle table t
  inserer "a" dans t
  inserer "b" dans t
  inserer "z" dans t position 1
  t.nom = "Dupont"
  t["clef libre"] = 42
  ? #t, t[1], t[3], t.nom, t["clef libre"], joindre(t, "-")
  retirer de t position 1 dans r
  ? "retiré", r, #t
  pour chaque k, v dans t
    ?? k .. "=" .. v .. " "
  suivant
  ?
  faire cas
    cas x = 1
      ? "un"
    cas x = 3
      ? "trois"
    autrement
      ? "autre"
  fincas
  n = 0
  tantque vrai
    n = n + 1
    si n > 4
      sortir
    finsi
  fintantque
  ? "n", n, session.N, SESSION.X
  ? fact(10), majuscule("été"), souschaine("bonjour", 4, 3), position("j", "bonjour"), chaine(3.14159, 8, 2)
  stocker 5 dans a, b
  ? a + b, vide(""), vide(t), type(t), type(nul), sisinon(a > 1, "oui", 1/0)
  supprimer table t
  ? type(t)
retourner

fonction fact(n)
  si n <= 1
    retourner 1
  finsi
retourner n * fact(n - 1)
