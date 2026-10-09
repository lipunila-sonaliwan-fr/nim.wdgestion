# Lexis+ - Documentation du langage

Oct 9, 2026 · @jihem

> **Lexis+ - Développez naturellement vos applications métier**

Lexis+ est un langage de programmation en français, héritier de dBase, pour écrire des applications web de gestion : les instructions se lisent comme des phrases (`si`, `pour chaque`, `utiliser`, `envoyer`), les données vivent dans une base SQL DuckDB, les pages HTML se remplissent avec des balises `<% %>`, et les tables façon Lua structurent tout le reste. Ce document l'enseigne pas à pas, puis sert de référence complète.

**Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr** SIRET : 130333198000013 · Contact : metalab (at) sonaliwan.fr

## Sommaire

1. Présentation
2. Premiers pas
3. Bases du langage
4. Variables et portée
5. Opérateurs et expressions
6. Structures de contrôle
7. Procédures et fonctions
8. Les tables
9. Méthodes et métatables
10. Base de données : SQL direct
11. Zones de travail
12. Pages et balises
13. Dialogue avec le navigateur
14. Sessions, droits et sécurité
15. Tutoriel complet : gestion des contacts
16. Référence des instructions
17. Référence des fonctions intégrées
18. Erreurs courantes et dépannage
19. Annexes et mentions légales

**Comment lire ce document.** Les chapitres 2 à 15 se lisent dans l'ordre : chaque notion est introduite par un exemple à recopier, suivi de ce qu'il affiche. Les chapitres 16 à 19 servent de référence. Dans les exemples, `?` affiche une ligne dans la page produite ; le résultat est donné en commentaire `&& →`.

## 1. Présentation

Lexis+ permet d'écrire une application de gestion complète - écrans, règles métier, données, droits d'accès - avec un seul langage, en français, sans compilation ni outil à installer sur les postes : un navigateur suffit.

### Philosophie

- **Lisible par le métier.** Les instructions sont des mots français en minuscules : `si … sinon … finsi`, `pour chaque ligne dans commandes`, `remplacer stock par stock - 1`. Un responsable fonctionnel peut relire une règle de gestion.
- **Hérité de dBase.** Les habitudes des développeurs dBase/Clipper sont conservées : `?` pour afficher, zones de travail (`utiliser`, `parcourir`, `chercher`), champs lisibles directement. Mais les fichiers DBF sont remplacés par de vraies tables SQL.
- **Moderne là où il le faut.** Les tables façon Lua (listes, dictionnaires, objets avec méthodes et métatables), le SQL complet de DuckDB et des pages HTML à balises.
- **Sûr par défaut.** Chaque utilisateur a sa session isolée ; il n'atteint que les procédures explicitement autorisées ; toute tentative d'accès non prévu ferme sa session et est journalisée.

### Ce que l'on construit

Une application Lexis+ est un dossier contenant trois sous-dossiers :

| Dossier | Contenu | Exemple |
| --- | --- | --- |
| `PROG` | les procédures (fichiers `.prg`, plusieurs procédures par fichier) | `PROG/clients.prg` |
| `PAGE` | les pages HTML à balises `<% %>` | `PAGE/liste_clients.html` |
| `BLOB` | les fichiers statiques servis tels quels (CSS, images, scripts) | `BLOB/style.css` |

Le serveur **wdGestion V** exécute ce dossier : il reçoit les requêtes du navigateur, retrouve la session de l'utilisateur, appelle la procédure demandée, laquelle lit ou modifie la base DuckDB puis envoie une page.

### Le cycle d'une requête

1. Le navigateur demande `/CLIENTS` (un lien ou un formulaire).
2. Le serveur identifie la session grâce à son cookie et vérifie que `CLIENTS` figure dans la liste des procédures autorisées de cette session (`SESSION.ACCEPTE`).
3. La procédure `CLIENTS` s'exécute ; ses paramètres reçoivent les champs du formulaire de même nom.
4. Elle interroge la base (`sql …` ou `utiliser clients`) et prépare des valeurs.
5. Elle appelle `envoyer liste_clients avec …` : la page `PAGE/liste_clients.html` est exécutée et son HTML part vers le navigateur.

Plusieurs utilisateurs sont servis en parallèle ; les requêtes d'un même utilisateur passent l'une après l'autre, ce qui garantit la cohérence de ses données de session sans que le développeur ait à s'en soucier.

## 2. Premiers pas

En sept étapes, on obtient une page qui salue l'utilisateur par son prénom. Tout l'exemple a été exécuté tel quel.

### Étape 1 - Préparer le dossier

Créez un dossier `bonjour` contenant l'exécutable `wdgestionv`, le dossier de la bibliothèque DuckDB de votre système (`linOS`, `macOS` ou `winOS`) et trois sous-dossiers vides :

```
bonjour/
├── wdgestionv
├── linOS/            (ou macOS/, winOS/)
├── PROG/
├── PAGE/
└── BLOB/
```

Les trois dossiers sont obligatoires : sans eux, le serveur refuse de démarrer.

### Étape 2 - Configurer (facultatif)

Créez `wdgestionv.json` (même nom que l'exécutable) pour choisir le port et la base :

```json
{
  "port": 8080,
  "base": "bonjour.duckdb"
}
```

Sans ce fichier, le serveur écoute sur `127.0.0.1:8080` et crée `wdgestionv.duckdb`.

### Étape 3 - Écrire la procédure

Toute application commence par la procédure `CONNEXION` : c'est elle qui accueille un visiteur qui n'est pas encore identifié. Créez `PROG/accueil.prg` :

```
&& Première application Lexis+
procedure CONNEXION(prenom)
  locale message = ""
  si non vide(prenom)
    message = "Bonjour " + prenom + " !"
  finsi
  envoyer bienvenue avec message = message
retourner
```

Ligne à ligne :

1. `&&` commence un commentaire.
2. `procedure CONNEXION(prenom)` déclare la procédure ; le paramètre `prenom` reçoit automatiquement le champ `prenom` envoyé par le navigateur (`?prenom=Marie`), ou `nul` s'il est absent.
3. `locale message = ""` crée une variable propre à cette exécution.
4. `vide(prenom)` est vrai pour `nul` ou une chaîne vide ; `non` l'inverse.
5. `+` entre chaînes concatène.
6. `envoyer bienvenue avec message = message` exécute la page `PAGE/bienvenue.html` en lui transmettant la valeur `message`.
7. `retourner` termine la procédure.

### Étape 4 - Écrire la page

Créez `PAGE/bienvenue.html` :

```html
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Bienvenue</title></head>
<body>
  <h1>Ma première application Lexis+</h1>
  <% si non vide(message) %>
    <p><strong><%= message %></strong></p>
  <% finsi %>
  <form method="get">
    <label>Votre prénom : <input name="prenom"></label>
    <button>Saluer</button>
  </form>
  <p>Il est <%= heure() %>.</p>
</body>
</html>
```

`<% … %>` contient du code Lexis+ ; ici un `si` qui encadre du HTML. `<%= … %>` insère une valeur dans la page, **échappée** (les caractères `< > & "` sont neutralisés).

### Étape 5 - Lancer le serveur

Depuis le dossier `bonjour` :

```
./wdgestionv
```

La console confirme le chargement :

```
Configuration : /…/bonjour/wdgestionv.json
Base     : /…/bonjour/bonjour.duckdb
Sources  : 1 procédure(s) chargée(s) depuis /…/bonjour/PROG
Statique : /…/bonjour/BLOB
Sécurité : accès SQL aux fichiers désactivé (acces_fichiers_sql = false)
Écoute : http://127.0.0.1:8080/
```

### Étape 6 - Essayer

Ouvrez `http://127.0.0.1:8080/`, tapez "Marie" et validez. La page affiche **Bonjour Marie !**. Essayez maintenant le prénom `<b>x</b>` : la page affiche le texte littéral `<b>x</b>`, sans mise en gras - c'est l'échappement automatique de `<%= %>` qui protège contre l'injection de HTML.

### Étape 7 - Modifier

- Une **page** modifiée est recompilée automatiquement à la requête suivante : rechargez simplement le navigateur.
- Une **procédure** modifiée doit être rechargée : enregistrez-la depuis l'éditeur intégré `/EDIT` (rechargement immédiat) ou redémarrez le serveur (`Ctrl+C` puis `./wdgestionv`).
- Une erreur de syntaxe dans `PROG` empêche le démarrage et est signalée avec le fichier et la ligne, par exemple `ERREUR : PROG/accueil.prg:4 : 'finsi' manquant pour 'si' (ligne 3)`.

Cette application n'a pas d'identification : tant que la session reste "anonyme", toute adresse aboutit à `CONNEXION`. Le chapitre 14 montre comment ouvrir l'accès à d'autres procédures après connexion.

## 3. Bases du langage

Un programme Lexis+ est une suite d'instructions, une par ligne, écrites en minuscules ; les noms que vous choisissez sont insensibles à la casse.

### 3.1 Écriture

| Règle | Exemple | Effet |
| --- | --- | --- |
| Une instruction par ligne | `x = 1` |  |
| Plusieurs sur une ligne | `x = 1; y = 2` | `;` au milieu d'une ligne sépare |
| Continuation | `? 1 + ;` puis `2` à la ligne suivante | `;` en fin de ligne prolonge l'instruction |
| Mots du langage | `si`, `pour`, `envoyer` | toujours en **minuscules** |
| Vos noms | `Prenom`, `prenom`, `PRENOM` | désignent la **même** variable |
| Accents | `élève = 3` | autorisés dans les noms |

Les noms sont convertis en majuscules : `t.nom` et `t.NOM` désignent la clef `"NOM"`. Les mots du langage, eux, ne sont reconnus qu'en minuscules : `SI` serait un nom de variable.

Toute instruction vit dans une procédure. Un fichier `.prg` contient une ou plusieurs procédures, chacune commençant par `procedure NOM` (ou `fonction NOM`) et finissant au `procedure` suivant, à `finprocedure` ou à la fin du fichier.

### 3.2 Commentaires

```
* une ligne qui commence par une étoile est un commentaire
? "bonjour"     && commentaire en fin de ligne (style dBase)
? "bonjour"     // commentaire en fin de ligne (style C)
```

Dans une page, `<%-- … --%>` est un commentaire qui n'apparaît pas dans le HTML envoyé.

### 3.3 Valeurs et types

Toute valeur appartient à l'un de six types ; `type(v)` renvoie son nom.

| Type | `type()` | Littéraux | Remarques |
| --- | --- | --- | --- |
| Nul | `"nul"` | `nul` | absence de valeur ; variable jamais affectée ; s'affiche vide |
| Logique | `"logique"` | `vrai`, `faux`, `.v.`, `.f.`, `.t.` |  |
| Nombre | `"nombre"` | `42`, `3.14`, `-7`, `1e3` | un seul type numérique (réel double précision) ; un entier s'affiche sans décimale |
| Chaîne | `"chaine"` | `"double"`, `'simple'`, `[[multiligne]]` | UTF-8 ; échappements `\n \t \" \' \\` |
| Table | `"table"` | `{}`, `{1, 2}`, `{nom = "x"}` | liste, dictionnaire ou objet (chapitre 8) |
| Procédure | `"procedure"` | `@NOM` | référence à une procédure (chapitre 7) |

Exemple :

```
procedure TEST
  ? 42, 3.14, -7, 1e3          && → 42 3.14 -7 1000
  ? "ligne\tà tab"             && → ligne   à tab
  ? [[chaîne
sur deux lignes]]              && → (deux lignes)
  ? vrai, .f., nul             && → vrai faux
  ? type(1), type("a"), type({}), type(@TEST)
                               && → nombre chaine table procedure
retourner
```

`? a, b, c` affiche les valeurs séparées par une espace puis passe à la ligne ; `?? a` affiche sans passer à la ligne.

Les chaînes longues `[[ … ]]` ne traitent aucun échappement et peuvent s'étendre sur plusieurs lignes : elles sont idéales pour le SQL.

### 3.4 Vrai et faux

Comme en Lua, **seuls `nul` et `faux` sont faux**. Le nombre `0` et la chaîne vide `""` sont vrais :

```
? sisinon(0, "vrai", "faux")     && → vrai
? sisinon("", "vrai", "faux")    && → vrai
```

Pour tester une valeur "vide" au sens métier, utilisez `vide(v)` : vrai pour `nul`, `faux`, `0`, une chaîne vide ou une table sans élément.

### 3.5 Conversions automatiques

| Expression | Résultat | Règle |
| --- | --- | --- |
| `"a" + 1` | `"a1"` | `+` concatène dès qu'un côté est une chaîne |
| `1 + "2"` | `"12"` | idem : attention aux saisies de formulaire |
| `"3" * "4"` | `12` | `- * / % ^` convertissent les chaînes numériques |
| `valeur("2") + 1` | `3` | convertir explicitement une saisie avant de calculer |
| `"x" * 2` | erreur | `nombre attendu, chaine "x" reçu` |
| `1/3` | `0.3333333333333333` | affichage complet ; `arrondi(1/3, 2)` → `0.33` |

Les champs de formulaire arrivent toujours sous forme de chaînes : convertissez-les avec `valeur()` avant tout calcul.

## 4. Variables et portée

Une variable est **locale** si elle est déclarée (`locale`, paramètre, variable de boucle, argument de page) ; sinon elle est **globale** et vit dans la table `SESSION` de l'utilisateur, donc d'une requête à l'autre.

### 4.1 Les trois sortes de variables

| Sorte | Créée par | Durée de vie | Visible depuis |
| --- | --- | --- | --- |
| Locale | `locale x`, paramètres, `pour i`, `pour chaque v`, arguments de `envoyer … avec` | la procédure ou la page en cours | elle seule |
| Globale (de session) | toute affectation d'un nom non déclaré, `globale X = …` | toute la session de l'utilisateur | toutes les procédures et pages de cette session |
| Champ | `utiliser table` | tant que la zone est ouverte | lecture directe par son nom |

Chaque utilisateur a sa propre table `SESSION` : deux utilisateurs connectés en même temps ne voient jamais les variables l'un de l'autre.

### 4.2 Pas à pas

```
procedure TEST
  locale compteur = 0          && locale : disparaît à la fin de TEST
  total = 100                  && non déclarée : globale, rangée dans SESSION.TOTAL
  ? compteur, total, SESSION.TOTAL      && → 0 100 100
  faire AJOUTER
  ? total, type(temp)                   && → 101 nul
retourner

procedure AJOUTER
  total = total + 1            && modifie la globale SESSION.TOTAL
  locale temp = "jetable"      && invisible pour l'appelant
retourner
```

1. `locale compteur = 0` crée une variable qui n'existe que dans `TEST`.
2. `total = 100` n'est déclarée nulle part : elle devient `SESSION.TOTAL` et sera encore là à la prochaine requête de l'utilisateur.
3. `AJOUTER` lit et modifie cette globale ; sa locale `temp` reste invisible pour `TEST` (`type(temp)` vaut `"nul"`).

### 4.3 Déclarer

```
locale a, b = 2, c = {}        && plusieurs locales, valeur initiale facultative (nul sinon)
globale REMISE = 5             && écrit explicitement SESSION.REMISE
stocker 0 dans a, b, c         && affectation multiple (STORE … TO … de dBase)
liberer REMISE                 && efface la variable (RELEASE de dBase)
```

### 4.4 Ordre de recherche d'un nom

Quand un nom est lu, Lexis+ cherche dans cet ordre :

1. les variables locales de la procédure ou de la page en cours ;
2. les champs de l'enregistrement courant de la zone de travail sélectionnée ;
3. la table `SESSION` ;
4. les procédures du même nom (le nom vaut alors une référence de procédure) ;
5. sinon : `nul` (aucune erreur).

Comme en dBase, **un champ masque une variable globale de même nom**. La notation `m->nom` lit la variable en ignorant les champs :

```
utiliser articles              && la table a un champ PRIX valant 10
prix = 99                      && crée la globale SESSION.PRIX
? prix, m->prix                && → 10 99
```

### 4.5 Les pages ont leurs propres locales

Une page ne voit pas les locales de la procédure qui l'envoie : seulement les arguments transmis, les globales et les champs.

```
procedure TEST
  locale compteur = 0
  total = 101
  envoyer montre avec titre = "Rapport"
retourner
```

Avec `PAGE/montre.html` :

```html
titre=<%= titre %> local=<%= type(compteur) %> global=<%= TOTAL %>
```

produit `titre=Rapport local=nul global=101`.

### 4.6 Le piège principal : la globale involontaire

Une variable de travail oubliée sans `locale` est rangée dans la session et y reste jusqu'à la déconnexion :

```
procedure RECHERCHE(nom)
  sql "select * from clients where nom = ?" avec nom dans r    && ✗ r devient SESSION.R
  …
```

Écrivez toujours :

```
procedure RECHERCHE(nom)
  locale r
  sql "select * from clients where nom = ?" avec nom dans r    && ✓ r est locale
```

Conséquences d'un oubli : mémoire consommée pour rien, valeurs d'une requête précédente qui ressurgissent, et données visibles dans l'écran de suivi `/SUIVI` (onglet Sessions → Voir), qui permet justement de repérer ces oublis. Seules exceptions : les variables de boucle (`pour i`, `pour chaque v`) sont automatiquement locales.

## 5. Opérateurs et expressions

Les opérateurs reprennent ceux de dBase (y compris `$` et les formes pointées `.et.`) et ceux de Lua (`..`, `#`) ; tous les résultats ci-dessous ont été obtenus en exécutant les exemples.

### 5.1 Arithmétique

| Opérateur | Sens | Exemple | Résultat |
| --- | --- | --- | --- |
| `+` | addition (concaténation si un côté est une chaîne) | `7 + 2` | `9` |
| `-` | soustraction | `7 - 2` | `5` |
| `*` | multiplication | `7 * 2` | `14` |
| `/` | division réelle | `7 / 2` | `3.5` |
| `%` | reste (au sens de Lua, du signe du diviseur) | `7 % 2` · `-7 % 3` | `1` · `2` |
| `^` ou `**` | puissance | `2 ^ 3` | `8` |
| `-x` | opposé | `-2 ^ 2` | `-4` (la puissance passe avant) |

Une division ou un modulo par zéro déclenche l'erreur `division par zéro`.

### 5.2 Chaînes

| Opérateur | Sens | Exemple | Résultat |
| --- | --- | --- | --- |
| `..` | concaténation (convertit les nombres ; `nul` devient vide) | `"n°" .. 5` | `"n°5"` |
| `+` | concaténation façon dBase | `"a" + "b"` | `"ab"` |
| `#` | longueur en caractères (UTF-8) | `#"été"` | `3` |
| `$` | "est contenu dans" | `"lu" $ "lundi"` | `vrai` |

### 5.3 Comparaisons

| Opérateur | Sens | Exemple | Résultat |
| --- | --- | --- | --- |
| `=` ou `==` | égal | `1 = 1` | `vrai` |
| `<>`, `!=` ou `#` | différent | `1 <> 2` | `vrai` |
| `<` `>` `<=` `>=` | ordre (nombres entre eux, chaînes entre elles) | `"abc" < "abd"` | `vrai` |

Dans une expression, `=` compare ; il n'affecte qu'en début d'instruction (`x = 1`). Comparer un nombre et une chaîne avec `<` est une erreur (`comparaison '<' impossible entre nombre et chaine`) ; l'égalité, elle, renvoie simplement `faux`. Deux tables sont égales si c'est la même table (ou selon leur métaméthode `__eq`).

### 5.4 Logique

| Opérateur | Formes | Exemple | Résultat |
| --- | --- | --- | --- |
| et | `et`, `.et.`, `.and.` | `vrai et faux` | `faux` |
| ou | `ou`, `.ou.`, `.or.` | `vrai ou faux` | `vrai` |
| non | `non`, `.non.`, `.not.` | `non vrai` | `faux` |

`et` et `ou` s'arrêtent dès que le résultat est connu et renvoient l'opérande décisif, ce qui donne un idiome pratique pour les valeurs par défaut :

```
? nul ou "défaut"          && → défaut
? "valeur" ou "défaut"     && → valeur
? faux et 1/0             && → faux (1/0 n'est jamais calculé)
```

`sisinon(condition, a, b)` est l'équivalent de `IIF` : seule la branche retenue est évaluée.

### 5.5 Affectations composées

```
x = 10
x += 5         && 15
x -= 3         && 12
s = "a"
s += "b"       && "ab"
```

### 5.6 Priorité (de la plus faible à la plus forte)

1. `ou`
2. `et`
3. `non`
4. comparaisons `= == <> != # < > <= >= $`
5. concaténation `..` (associative à droite)
6. `+ -`
7. `* / %`
8. unaires `-` et `#`
9. puissance `^ **` (associative à droite)
10. accès : `t.champ`, `t[clef]`, appel `f(x)`, méthode `t:m(x)`, champ d'alias `alias->champ`

Exemples vérifiés : `2 + 3 * 4` → `14` ; `(2 + 3) * 4` → `20` ; `2 ^ 3 ^ 2` → `512` ; `1 + 2 = 3 et 2 * 2 = 4` → `vrai`. En cas de doute, ajoutez des parenthèses.

## 6. Structures de contrôle

Chaque structure s'ouvre par un mot et se ferme par son mot de fin (`si` … `finsi`, `tantque` … `fintantque`) ; un oubli est signalé avec la ligne d'ouverture, par exemple `'finsi' manquant pour 'si' (ligne 3)`.

### 6.1 Alternative : si

```
note = 14
si note >= 16
  ? "Très bien"
sinonsi note >= 12
  ? "Bien"                 && → affiché
sinon si note >= 10        && "sinon si" en deux mots est accepté
  ? "Passable"
sinon
  ? "Insuffisant"
finsi
```

Les conditions sont testées dans l'ordre ; seule la première vraie s'exécute. `sinonsi` et `sinon` sont facultatifs.

### 6.2 Choix multiple : faire cas

```
jour = "samedi"
faire cas
  cas jour = "samedi" ou jour = "dimanche"
    ? "Week-end"           && → affiché
  cas jour = "lundi"
    ? "Début de semaine"
  autrement
    ? "Semaine"
fincas
```

Chaque `cas` porte sa propre condition (comme `DO CASE` en dBase) : on peut donc y mélanger des tests de nature différente. `autrement` est facultatif.

### 6.3 Boucle tant que

```
n = 1
tantque n < 100
  n = n * 2
fintantque
? "n =", n                 && → n = 128
```

`faire tantque cond` … `fintantque` est la forme dBase, identique.

### 6.4 Boucle pour

```
pour i = 1 a 5             && a, à ou jusqua
  ?? i, ""
suivant                    && → 1 2 3 4 5

pour i = 10 jusqua 0 pas -5
  ?? i, ""
finpour                    && → 10 5 0
```

- Le pas vaut 1 par défaut ; il peut être négatif ou décimal, jamais nul.
- La fin de boucle s'écrit `suivant`, `suivant i` ou `finpour`.
- La variable de boucle est locale ; après `pour i = 1 a 2` elle vaut `3`.
- Les bornes sont calculées une seule fois, au départ.

### 6.5 Parcourir une table : pour chaque

Avec une seule variable, on obtient les **valeurs** ; avec deux, la **clef** puis la **valeur** :

```
saisons = {"printemps", "été", "automne", "hiver"}
pour chaque s dans saisons
  ?? s, ""
suivant                    && → printemps été automne hiver

prix = {pain = 1.2, lait = 0.95}
pour chaque produit, montant dans prix
  ? produit, "coûte", montant
suivant
&& → PAIN coûte 1.2
&& → LAIT coûte 0.95
```

L'ordre est garanti : d'abord les éléments numérotés 1, 2, 3… puis les autres clefs dans leur ordre d'insertion. Les clefs écrites comme des noms (`pain`) sont en majuscules (`PAIN`). Modifier la table pendant le parcours est sans danger : on parcourt l'état de départ.

### 6.6 Sortir et passer au tour suivant

```
pour i = 1 a 10
  si i % 2 = 0
    boucler                && passe au tour suivant (LOOP)
  finsi
  si i > 7
    sortir                 && quitte la boucle (EXIT)
  finsi
  ?? i, ""
suivant                    && → 1 3 5 7
```

`sortir` et `boucler` agissent sur la boucle la plus proche (`pour`, `pour chaque`, `tantque`, `parcourir`). `retourner` quitte la procédure entière, même depuis une boucle :

```
fonction CHERCHE(liste, valeur)
  pour i = 1 a #liste
    si liste[i] = valeur
      retourner i
    finsi
  suivant
retourner 0

&& CHERCHE(saisons, "automne") → 3
```

### 6.7 Erreurs : essayer, capturer, erreur

```
essayer
  x = 10 / 0
  ? "jamais affiché"
capturer message
  ? "Erreur interceptée :", message    && → Erreur interceptée : division par zéro
finessayer

essayer
  erreur "stock insuffisant pour l'article 42"
capturer m
  ? m                      && → stock insuffisant pour l'article 42
finessayer
```

- `erreur "texte"` déclenche une erreur avec votre message.
- `capturer nom` reçoit le message dans une variable locale ; le nom est facultatif.
- Une erreur non capturée arrête la requête : l'utilisateur reçoit une page "500 Erreur d'exécution", avec le détail (fichier, ligne, message) seulement s'il a le droit `EDITION`. La console du serveur journalise toujours le détail.
- Le dépassement de la limite d'instructions ou de durée (boucle infinie) ne peut pas être capturé : il arrête toujours la requête.

### 6.8 Garde-fous

| Limite | Valeur par défaut | Message |
| --- | --- | --- |
| Instructions par requête | 5 000 000 (`instructions_max`) | `limite de 5000000 instructions atteinte (boucle infinie ?)` |
| Durée d'une requête | 30 s (`duree_max_secondes`) | `limite de durée atteinte (30.0 s)` |
| Profondeur d'appel | 200 appels imbriqués | `profondeur d'appel maximale atteinte (récursion infinie ?)` |

## 7. Procédures et fonctions

Une procédure regroupe des instructions sous un nom ; elle peut recevoir des paramètres et renvoyer une valeur. `procedure` et `fonction` sont synonymes : le second mot signale simplement au lecteur qu'une valeur est renvoyée.

### 7.1 Définir et appeler

```
fonction TTC(ht, taux)
  si estnul(taux)
    taux = 20                  && taux par défaut
  finsi
retourner arrondi(ht * (1 + taux / 100), 2)
```

| Appel | Résultat |
| --- | --- |
| `? TTC(100)` | `120` |
| `? TTC(100, 5.5)` | `105.5` |
| `? ttc(1)` ou `? Ttc(1)` | `1.2` (noms insensibles à la casse) |

Règles :

- Un paramètre non fourni vaut `nul` ; un argument en trop est ignoré.
- Les paramètres sont des variables locales : les modifier ne change rien chez l'appelant. Une table passée en paramètre est en revanche partagée (on passe la table elle-même, pas une copie).
- `retourner valeur` renvoie une valeur ; `retourner` seul, ou la fin de la procédure, renvoie `nul`.
- Un même nom de procédure ne peut être défini qu'une fois dans tout `PROG` ; un doublon empêche le chargement (`procédure TTC définie deux fois`).
- Une procédure à vous qui porte le nom d'une fonction intégrée la remplace : évitez `MAJUSCULE`, `DATE`, etc.

### 7.2 Trois façons d'appeler

```
x = TTC(100)                     && dans une expression
faire SALUER avec "Ana", "Paris" && instruction, style dBase (DO … WITH)
SALUER("Léo")                    && instruction, style fonction
```

### 7.3 La forme dBase : parametres

Au lieu de déclarer les paramètres entre parenthèses, on peut les recevoir avec `parametres` :

```
procedure SALUER
  parametres nom, ville
  ? "Bonjour", nom, sisinon(estnul(ville), "(ville inconnue)", "de " + ville)
retourner

&& faire SALUER avec "Ana", "Paris" → Bonjour Ana de Paris
&& faire SALUER avec "Léo"          → Bonjour Léo (ville inconnue)
```

### 7.4 Récursion

```
fonction FACT(n)
  si n <= 1
    retourner 1
  finsi
retourner n * FACT(n - 1)

&& FACT(10) → 3628800
```

La profondeur est limitée à 200 appels imbriqués ; au-delà, l'erreur `profondeur d'appel maximale atteinte` arrête la requête. Pour les traitements de masse, préférez une boucle ou une requête SQL.

### 7.5 Procédures comme valeurs

`@NOM` désigne la procédure elle-même. On peut la ranger dans une variable, la passer en argument ou l'associer à une table (chapitre 9) :

```
f = @TTC
? type(f), f(50)                 && → procedure 60
? appeler(@TTC, 10, 10)          && → 11

fonction DOUBLE(x)
retourner x * 2

fonction APPLIQUER(liste, transformation)
  locale resultat = {}
  pour chaque v dans liste
    inserer transformation(v) dans resultat
  suivant
retourner joindre(resultat, ", ")

&& APPLIQUER({1, 2, 3}, @DOUBLE) → 2, 4, 6
```

Le même principe sert à `trier(t, @COMPARER)` (ordre personnalisé) et aux métaméthodes.

### 7.6 Procédures appelées par le navigateur

Une procédure dont le nom figure dans `SESSION.ACCEPTE` peut être appelée par l'adresse `/NOM`. Ses paramètres reçoivent alors les champs du formulaire ou de l'URL portant le même nom (insensible à la casse), sous forme de chaînes, et la variable locale `REQUETE` décrit la requête (chapitre 13). Les autres procédures restent internes : le navigateur ne peut pas les atteindre.

Deux procédures ont un rôle réservé :

| Nom | Rôle |
| --- | --- |
| `CONNEXION` | obligatoire ; reçoit toute requête d'une session non identifiée |
| `DEMARRAGE` | facultative ; exécutée une fois au lancement du serveur (création des tables, données initiales) ; ce qu'elle affiche avec `?` apparaît dans la console |

## 8. Les tables

La table est l'unique structure de données de Lexis+ : selon l'usage, elle sert de liste numérotée à partir de 1, de dictionnaire (fiche avec des champs nommés) ou d'objet. Elle reprend exactement le modèle des tables de Lua.

### 8.1 Une liste, pas à pas

```
locale fruits = {"pomme", "poire", "kiwi"}
? fruits[1], fruits[3], #fruits, type(fruits[4])     && → pomme kiwi 3 nul

inserer "banane" dans fruits                 && ajout en fin
inserer "abricot" dans fruits position 1     && ajout en tête, le reste se décale
? joindre(fruits, ", ")      && → abricot, pomme, poire, kiwi, banane

locale enleve
retirer de fruits position 2 dans enleve     && retire "pomme" et le garde
? enleve, joindre(fruits, ", ")              && → pomme abricot, poire, kiwi, banane

retirer de fruits                            && retire le dernier
? joindre(fruits, ", ")      && → abricot, poire, kiwi
```

1. `{a, b, c}` crée une liste ; les indices commencent à **1**.
2. Un indice absent donne `nul`, sans erreur.
3. `#t` donne le nombre d'éléments de la partie liste.
4. `inserer … dans t [position n]` ajoute ; `retirer de t [position n] [dans var]` enlève et décale.

### 8.2 Une fiche (dictionnaire), pas à pas

```
nouvelle table client                        && client = {}
client.nom = "Durand"
client.ville = "Lyon"
? client.nom, client.ville                   && → Durand Lyon

locale c2 = {nom = "Martin", age = 42, [10] = "dix", ["clé libre"] = vrai}
? c2.age, c2[10], c2["clé libre"], nbelements(c2)   && → 42 dix vrai 4
```

- `t.nom` et `{nom = …}` utilisent la clef `"NOM"` (les noms passent en majuscules).
- `[expression] = valeur` dans le constructeur, ou `t[expression]`, accepte n'importe quelle clef : nombre, chaîne exacte, logique, table.
- `nbelements(t)` compte tous les éléments ; `#t` seulement la partie liste.

**Attention aux majuscules.** Les crochets utilisent la chaîne **exacte**, le point la convertit en majuscules :

```
client["ville"] = "Lyon"      && clef "ville"
? client.ville                && → (vide) : client.ville lit la clef "VILLE"
? client["VILLE"]             && → (vide)
? client["ville"]             && → Lyon
```

Règle simple : dans votre code, utilisez la notation pointée ; réservez les crochets aux clefs calculées, en MAJUSCULES (`t["VILLE"]`). Les lignes renvoyées par la base, les champs de formulaire et les objets JSON décodés ont tous leurs clefs en majuscules, pour que `ligne.nom` fonctionne directement.

### 8.3 Ajouter, lire, retirer une clef

```
inserer "France" dans client clef "PAYS"     && client["PAYS"] = "France"
? client.pays                                && → France
retirer de client clef "PAYS"                && supprime la clef
client.ville = nul                           && affecter nul supprime aussi la clef
? aclef(client, "VILLE"), aclef(client, "NOM")   && → faux vrai
```

### 8.4 Tables imbriquées

```
locale cmd = {numero = 12,
              lignes = {{article = "stylo", qte = 3},
                        {article = "cahier", qte = 1}}}
? cmd.lignes[2].article, #cmd.lignes        && → cahier 2
pour chaque l dans cmd.lignes
  ? l.article, l.qte
suivant
&& → stylo 3
&& → cahier 1
```

Une table peut s'écrire sur plusieurs lignes tant que l'accolade n'est pas fermée.

### 8.5 Partage et copie

Une variable contient une **référence** à la table : deux variables peuvent désigner la même.

```
locale a = {1, 2}
locale b = a                 && même table
inserer 3 dans b
? #a                         && → 3

locale c = copier(a)         && nouvelle table (copie de premier niveau)
inserer 4 dans c
? #a, #c                     && → 3 4
```

`copier` ne duplique que le premier niveau : les sous-tables restent partagées.

### 8.6 Trier, chercher, convertir

```
locale notes = {12, 8, 17, 14}
trier(notes)
? joindre(notes, " ")                 && → 8 12 14 17
trier(notes, @DECROISSANT)
? joindre(notes, " ")                 && → 17 14 12 8
? contient(notes, 17)                 && → vrai

fonction DECROISSANT(x, y)
retourner x > y                      && vrai si x doit passer avant y
```

| Fonction | Exemple | Résultat |
| --- | --- | --- |
| `clefs(t)` | `joindre(clefs(c2), " ")` | `NOM AGE 10 clé libre` |
| `valeurs(t)` | `valeurs({a = 1, b = 2})` | `{1, 2}` |
| `decouper(s, sep)` | `decouper("rouge;vert;bleu", ";")[2]` | `vert` |
| `joindre(t, sep)` | `joindre({1, 2}, "-")` | `1-2` |
| `json(t)` | `json(cmd)` | `{"NUMERO":12,"LIGNES":[{"ARTICLE":"stylo","QTE":3},…]}` |
| `dejson(s)` | `dejson('{"nom":"Ana","tags":["a","b"]}').TAGS[2]` | `b` |

### 8.7 À éviter : les trous

Affecter `nul` au milieu d'une liste la coupe : les éléments suivants ne comptent plus dans `#` ni dans `joindre`.

```
locale t = {1, 2, 3}
t[2] = nul
? #t                          && → 1
```

Pour enlever un élément d'une liste, utilisez toujours `retirer de t position n`.

### 8.8 Supprimer

`supprimer table client` efface la variable (elle vaut ensuite `nul`). La mémoire est récupérée automatiquement dès que plus rien ne référence la table, y compris pour des tables qui se référencent elles-mêmes (le serveur fait le ménage à la fin de chaque requête).

## 9. Méthodes et métatables

Une table devient un objet quand on lui associe des procédures (ses méthodes) et une métatable, qui définit son comportement : héritage, opérateurs, affichage, contrôle des affectations. C'est le mécanisme de Lua, avec des noms français.

### 9.1 Associer une méthode : t:procedure

```
locale panier = {total = 0}
panier:procedure PANIER_AJOUTER comme ajouter
panier:ajouter(12.5)
panier:ajouter(7.5)
? panier.total                      && → 20

procedure PANIER_AJOUTER(soi, montant)
  soi.total = soi.total + montant
retourner
```

1. `panier:procedure PANIER_AJOUTER comme ajouter` range la procédure dans la clef `AJOUTER` de la table (sans `comme`, la clef porte le nom de la procédure).
2. `panier:ajouter(12.5)` - avec **deux-points** - appelle la procédure en lui passant **la table elle-même en premier argument**, puis les autres.
3. Par convention, ce premier paramètre s'appelle `soi` (le `self` de Lua).

`panier.ajouter(x)` - avec un **point** - appelle la même procédure sans lui passer la table : utile pour une fonction rangée dans une table qui n'a pas besoin d'elle.

### 9.2 Une classe, pas à pas : le compte bancaire

Une "classe" est une table qui contient les méthodes et sert de métatable à ses objets ; sa clef `__index` dit où chercher ce qu'un objet ne possède pas lui-même.

**Étape 1 - la classe.**

```
procedure DEFINIR_COMPTE
  nouvelle table COMPTE
  COMPTE.__index = COMPTE                    && les objets cherchent leurs méthodes ici
  COMPTE.__tostring = @COMPTE_TEXTE          && affichage d'un compte
  COMPTE:procedure COMPTE_DEPOSER comme deposer
  COMPTE:procedure COMPTE_RETIRER comme retirer
  COMPTE:procedure COMPTE_RESUME comme resume
retourner
```

**Étape 2 - le constructeur.**

```
fonction NOUVEAU_COMPTE(titulaire, solde)
  locale c = {titulaire = titulaire, solde = solde}
  fixermetatable c, COMPTE
retourner c
```

**Étape 3 - les méthodes.**

```
procedure COMPTE_DEPOSER(soi, montant)
  soi.solde = soi.solde + montant
retourner

procedure COMPTE_RETIRER(soi, montant)
  si montant > soi.solde
    erreur "solde insuffisant (" + soi.solde + " €)"
  finsi
  soi.solde = soi.solde - montant
retourner

fonction COMPTE_RESUME(soi)
retourner soi.titulaire + " : " + soi.solde + " €"

fonction COMPTE_TEXTE(soi)
retourner "[Compte " + soi:resume() + "]"
```

**Étape 4 - l'utilisation.**

```
faire DEFINIR_COMPTE
locale c = NOUVEAU_COMPTE("Ana", 100)
c:deposer(50)
? c.titulaire, c.solde, c:resume()     && → Ana 150 Ana : 150 €
essayer
  c:retirer(1000)
capturer m
  ? "refus :", m                       && → refus : solde insuffisant (150 €)
finessayer
? c                                    && → [Compte Ana : 150 €]   (grâce à __tostring)
```

Quand on écrit `c:deposer(50)`, l'objet `c` ne possède pas de clef `DEPOSER` ; sa métatable `COMPTE` a un `__index` qui renvoie vers `COMPTE`, où la clef existe.

`COMPTE` est ici une variable globale : elle vit dans la session. Définissez vos classes à la connexion, ou à la demande : `si estnul(COMPTE)` puis `faire DEFINIR_COMPTE`.

### 9.3 Héritage

Un compte épargne est un compte avec un taux et une méthode de plus. Sa classe `EPARGNE` a elle-même pour métatable une table dont l'`__index` mène à `COMPTE` :

```
procedure DEFINIR_EPARGNE
  nouvelle table EPARGNE
  EPARGNE.__index = EPARGNE
  EPARGNE.__tostring = @COMPTE_TEXTE
  fixermetatable EPARGNE, {__index = COMPTE}     && ce qu'EPARGNE n'a pas, COMPTE l'a
  EPARGNE:procedure EPARGNE_INTERETS comme interets
retourner

fonction NOUVELLE_EPARGNE(titulaire, solde, taux)
  locale e = NOUVEAU_COMPTE(titulaire, solde)
  e.taux = taux
  fixermetatable e, EPARGNE
retourner e

procedure EPARGNE_INTERETS(soi)
  soi:deposer(arrondi(soi.solde * soi.taux / 100, 2))   && méthode héritée de COMPTE
retourner
```

```
faire DEFINIR_EPARGNE
locale e = NOUVELLE_EPARGNE("Léo", 1000, 2)
e:deposer(100)
e:interets()
? e, e.taux                              && → [Compte Léo : 1122 €] 2
? type(lirebrut(e, "DEPOSER")), type(e.deposer)   && → nul procedure
```

La recherche de `e.deposer` suit la chaîne : l'objet `e` (absent) → `EPARGNE` (absent) → `COMPTE` (trouvé). `lirebrut` lit une clef sans suivre la chaîne : `DEPOSER` n'appartient pas à `e` lui-même.

### 9.4 Redéfinir les opérateurs

Une métatable peut définir le sens des opérateurs pour ses objets :

```
fonction MONTANT(v)
  locale m = {v = v}
  fixermetatable m, {__add = @M_ADD, __lt = @M_LT, __eq = @M_EQ,
                     __len = @M_LEN, __unm = @M_NEG, __tostring = @M_TXT}
retourner m

fonction M_ADD(x, y)
retourner MONTANT(x.v + y.v)
fonction M_LT(x, y)
retourner x.v < y.v
fonction M_EQ(x, y)
retourner x.v = y.v
fonction M_LEN(x)
retourner longueur(chaine(x.v))
fonction M_NEG(x)
retourner MONTANT(-x.v)
fonction M_TXT(x)
retourner chaine(x.v, 1, 2) + " €"
```

```
locale a = MONTANT(10), b = MONTANT(32)
? a + b, a < b, a == MONTANT(10), #b, -a     && → 42.00 € vrai vrai 2 -10.00 €
```

### 9.5 Valeurs par défaut

Un `__index` qui est une table fournit les valeurs manquantes :

```
locale reglages = fixermetatable({}, {__index = {langue = "fr", theme = "clair"}})
reglages.theme = "sombre"
? reglages.langue, reglages.theme            && → fr sombre
```

`__index` peut aussi être une procédure `(table, clef)` qui calcule la valeur à la volée.

### 9.6 Contrôler les affectations : \_\_newindex

`__newindex` est appelé quand on affecte une clef **absente** de la table. Une fois la clef créée, les affectations suivantes ne passent plus par lui. Pour contrôler toutes les affectations, on garde la table vide et on range les données ailleurs (table "mandataire") :

```
fonction FICHE_CONTROLEE
  locale donnees = {}
retourner fixermetatable({}, {__index = donnees, __newindex = @VALIDER})

procedure VALIDER(t, clef, valeur)
  si clef = "AGE" et valeur < 0
    erreur "âge négatif"
  finsi
  ecrirebrut(obtenirmetatable(t).__index, clef, valeur)
retourner
```

```
locale fiche = FICHE_CONTROLEE()
fiche.age = 30
essayer
  fiche.age = -4
capturer m
  ? "refus :", m                    && → refus : âge négatif
finessayer
fiche.age = 31
? fiche.age                         && → 31
```

`ecrirebrut(t, clef, valeur)` écrit sans déclencher `__newindex` (sinon `VALIDER` s'appellerait lui-même indéfiniment).

### 9.7 Une table appelable : \_\_call

```
locale tva = fixermetatable({taux = 20}, {__call = @CALCUL_TVA})
? tva(100)                          && → 20

fonction CALCUL_TVA(soi, ht)
retourner ht * soi.taux / 100
```

### 9.8 Toutes les métaméthodes

| Clef de la métatable | Déclenchée par | Reçoit | Renvoie |
| --- | --- | --- | --- |
| `__index` | lecture d'une clef absente | table ou procédure `(t, clef)` | la valeur |
| `__newindex` | affectation d'une clef absente | table ou procédure `(t, clef, valeur)` | - |
| `__call` | `t(…)` | `(t, args…)` | le résultat |
| `__tostring` | `?`, `<%= %>`, `chaine()`, `texte()`, `joindre()` | `(t)` | une chaîne |
| `__len` | `#t` | `(t)` | un nombre |
| `__eq` | `=`, `==`, `<>` entre deux tables différentes | `(a, b)` | logique |
| `__lt` | `<` et `>` | `(a, b)` | logique |
| `__le` | `<=` et `>=` | `(a, b)` | logique |
| `__add` `__sub` `__mul` `__div` `__mod` `__pow` | `+ - * / % ^` | `(a, b)` | le résultat |
| `__unm` | `-t` | `(t)` | le résultat |
| `__concat` | `..` | `(a, b)` | le résultat |

Fonctions associées : `fixermetatable(t, mt)` (renvoie `t` ; `nul` retire la métatable), `obtenirmetatable(t)`, `lirebrut(t, clef)`, `ecrirebrut(t, clef, valeur)`. Les noms de métaméthodes s'écrivent comme en Lua (`__index`) et sont, comme toute clef pointée, ramenés en majuscules : les deux écritures fonctionnent.

`__tostring` ne suffit pas pour concaténer : `"valeur : " .. m` et `"valeur : " + m` déclenchent l'erreur `opération '..' impossible sur une table (métaméthode __concat absente)`. Écrivez `"valeur : " .. chaine(m)`, ou définissez `__concat`.

## 10. Base de données : SQL direct

Lexis+ parle le SQL complet de DuckDB : l'instruction `sql` exécute une requête, ses paramètres `?` reçoivent des valeurs Lexis+ en toute sécurité, et un résultat arrive sous forme de table de lignes.

### 10.1 Créer une table

La création se fait en général dans la procédure `DEMARRAGE`, exécutée au lancement du serveur :

```
procedure DEMARRAGE
  sql [[create table if not exists clients (
          id      integer primary key,
          nom     varchar not null,
          ville   varchar,
          ca      decimal(10,2),
          inscrit date,
          actif   boolean default true)]]
retourner
```

La chaîne longue `[[ … ]]` évite d'échapper les guillemets et permet d'écrire sur plusieurs lignes. Les commentaires SQL s'écrivent `--` à l'intérieur.

### 10.2 Insérer avec des paramètres

```
sql "insert into clients values (?, ?, ?, ?, ?, ?)" ;
    avec 1, "Durand", "Lyon", 1250.5, "2026-01-15", vrai
```

Chaque `?` reçoit, dans l'ordre, une valeur de la liste `avec`. Les valeurs ne sont jamais mélangées au texte SQL : une saisie contenant une apostrophe ou du code SQL est stockée telle quelle, sans danger. `nul` devient `NULL`.

**Règle de sécurité n°1 :** ne construisez jamais une requête en concaténant une saisie :

```
sql "select * from clients where nom = '" + nom + "'"        && ✗ injection SQL possible
sql "select * from clients where nom = ?" avec nom           && ✓
```

### 10.3 Lire : sql … dans

```
locale r
sql "select * from clients where ville = ? order by nom" avec "Lyon" dans r
? #r, "client(s) à Lyon"                && → 2 client(s) à Lyon
pour chaque c dans r
  ? c.id, c.nom, c.ca, c.inscrit, c.actif
suivant
&& → 1 Durand 1250.5 2026-01-15 vrai
&& → 3 Petit 3100 2025-11-20 vrai
```

- `r` est une liste de lignes ; chaque ligne est une table dont les clefs sont les noms de colonnes **en majuscules** (`c.nom` lit `NOM`).
- `#r` donne le nombre de lignes ; une requête sans résultat donne une liste vide.
- Pour renommer une colonne calculée, utilisez `as` : `count(*) as nb` donne `l.nb`.

### 10.4 Les fonctions requete et valeursql

```
? valeursql("select count(*) from clients")                              && → 3
? valeursql("select sum(ca) from clients where ville = ?", "Lyon")       && → 4350.5
? type(valeursql("select ville from clients where id = ?", 99))          && → nul

locale parVille = requete("select ville, count(*) as nb, sum(ca) as total " + ;
                          "from clients group by ville order by ville")
pour chaque l dans parVille
  ? l.ville, l.nb, l.total
suivant
&& → Brest 1 980
&& → Lyon 2 4350.5
```

| Forme | Renvoie | Usage |
| --- | --- | --- |
| `sql "…" [avec a, b] [dans var]` | rien, ou la liste de lignes dans `var` | instruction |
| `requete("…", a, b)` | la liste de lignes | dans une expression |
| `valeursql("…", a, b)` | la première colonne de la première ligne, ou `nul` | compter, totaliser, vérifier l'existence |

### 10.5 Correspondance des types

| Type SQL | Valeur Lexis+ | Exemple |
| --- | --- | --- |
| `integer`, `bigint`, `double`, `decimal`, `hugeint` | nombre | `1250.5` |
| `varchar`, `text` | chaîne | `"Durand"` |
| `boolean` | logique | `vrai` |
| `date`, `timestamp`, `time` | chaîne ISO | `"2026-01-15"` |
| `NULL` | `nul` |  |
| autres (`uuid`, `json`, listes…) | chaîne |  |

En paramètre, une date se passe sous forme de chaîne ISO (`"2026-01-15"`) : DuckDB la convertit. Une table Lexis+ passée en paramètre est envoyée sous forme de texte JSON.

### 10.6 Erreurs SQL

Toute erreur SQL devient une erreur Lexis+ capturable, préfixée par `sql :` :

```
essayer
  sql "insert into clients (id, nom) values (1, 'Doublon')"
capturer m
  ? m      && → sql : Constraint Error: Duplicate key "id: 1" violates primary key constraint
finessayer
```

Un nombre de valeurs différent du nombre de `?` est signalé : `sql : 1 paramètre(s) attendu(s), 2 fourni(s)`.

### 10.7 Transactions

Pour que plusieurs modifications réussissent ou échouent ensemble, encadrez-les d'une transaction, toujours dans un `essayer` :

```
essayer
  sql "begin transaction"
  sql "update clients set ca = ca - 100 where id = ?" avec 1
  sql "update clients set ca = ca + 100 where id = ?" avec 99
  si valeursql("select count(*) from clients where id = ?", 99) = 0
    erreur "client 99 inconnu : virement annulé"
  finsi
  sql "commit"
capturer m
  sql "rollback"
  ? m                                  && → client 99 inconnu : virement annulé
finessayer
? valeursql("select ca from clients where id = 1")     && → 1250.5 (inchangé)
```

Une transaction ne peut pas s'étendre sur plusieurs requêtes du navigateur. Si une procédure se termine en laissant une transaction ouverte (oubli du `commit`, erreur non capturée), le serveur l'annule automatiquement à la fin de la requête.

### 10.8 Ce que permet DuckDB

Tout le SQL de DuckDB est disponible : jointures, `group by`, fonctions de fenêtre, `string_agg`, CTE (`with`), `insert … returning`, `on conflict do update` (upsert), séquences, vues. Exemples vérifiés :

```
? valeursql("select string_agg(nom, ', ' order by ca desc) from clients where ca is not null")
                                       && → Petit, Durand, Martin
? json(requete("select id, nom from clients where id <= 2 order by id"))
                                       && → [{"ID":1,"NOM":"Durand"},{"ID":2,"NOM":"Martin"}]
```

Par sécurité, après `DEMARRAGE`, le SQL ne peut plus accéder au système de fichiers (`read_csv`, `COPY … TO`, `ATTACH`, `INSTALL` sont refusés : `Permission Error`). Les imports de fichiers se font donc dans `DEMARRAGE`, ou en autorisant explicitement l'accès (`"acces_fichiers_sql": true`, déconseillé).

### 10.9 Plusieurs instructions d'un coup

Sans paramètre, une seule chaîne peut contenir plusieurs instructions séparées par `;` :

```
sql [[create sequence if not exists seq_cmd;
      create table if not exists commandes (
        id integer primary key default nextval('seq_cmd'),
        client integer, montant decimal(10,2))]]
```

Avec des paramètres `?`, une seule instruction par appel.

## 11. Zones de travail

Les zones de travail reprennent la façon dBase de manipuler les données enregistrement par enregistrement : on ouvre une table SQL avec `utiliser`, on se déplace, et les champs de l'enregistrement courant se lisent comme des variables.

Tous les exemples utilisent cette table :

```
sql "create table articles (ref varchar primary key, libelle varchar, prix decimal(8,2), stock integer)"
sql [[insert into articles values ('A1','Stylo bleu',1.20,150), ('A2','Cahier A4',2.50,40),
      ('B7','Agrafeuse',12.90,3), ('C3','Classeur',4.10,0), ('D9','Gomme',0.80,75)]]
```

### 11.1 Ouvrir et lire

```
utiliser articles ordre "libelle"
? nbenr(), numenr(), libelle, prix, fdf()     && → 5 1 Agrafeuse 12.9 faux
```

- `utiliser table [alias nom] [ordre "colonnes SQL"] [filtre "condition SQL"]` ouvre la table et se place sur le premier enregistrement.
- L'alias par défaut est le nom de la table en majuscules (`ARTICLES`).
- Sans `ordre`, l'ordre est celui de la clef primaire.
- Les champs (`libelle`, `prix`…) se lisent directement.

### 11.2 Se déplacer

```
sauter                    && enregistrement suivant
? numenr(), libelle       && → 2 Cahier A4
aller bas                 && dernier
? libelle                 && → Stylo bleu
sauter
? fdf(), numenr(), type(libelle)   && → vrai 6 nul   (au-delà du dernier)
aller 2                   && n-ième enregistrement
? libelle                 && → Cahier A4
aller haut
sauter -1
? ddf(), libelle          && → vrai Agrafeuse   (avant le premier)
```

| Instruction | dBase | Effet |
| --- | --- | --- |
| `aller haut` (ou `aller debut`) | `GO TOP` | premier enregistrement |
| `aller bas` (ou `aller fin`) | `GO BOTTOM` | dernier |
| `aller n` | `GO n` | n-ième dans l'ordre courant |
| `sauter [n]` | `SKIP [n]` | avance (ou recule si n < 0) |

`fdf()` (fin de fichier, `EOF()`) et `ddf()` (début de fichier, `BOF()`) signalent qu'on est sorti de la table ; les champs valent alors `nul`.

### 11.3 Parcourir

```
parcourir
  ?? libelle, "|"
finparcourir                      && → Agrafeuse |Cahier A4 |Classeur |Gomme |Stylo bleu |

parcourir pour stock < 10
  ? "À commander :", ref, libelle, stock
finparcourir
&& → À commander : B7 Agrafeuse 3
&& → À commander : C3 Classeur 0
```

`parcourir` (`SCAN`) repart toujours du premier enregistrement ; `sortir` et `boucler` y fonctionnent comme dans une boucle.

### 11.4 Chercher

```
chercher "Gomme"                  && cherche dans la 1re colonne de l'ordre (libelle)
? trouve(), ref, prix             && → vrai D9 0.8
chercher "Inconnu"
? trouve(), fdf()                 && → faux vrai
```

`chercher` (`SEEK`) nécessite une table ouverte avec `ordre` ; la recherche porte sur la première colonne de l'ordre et se fait par une requête SQL (rapide même sur une grande table).

`localiser pour condition` (`LOCATE`) teste une condition Lexis+ quelconque, enregistrement par enregistrement ; `continuer` (`CONTINUE`) cherche le suivant :

```
localiser pour prix > 2
? libelle                         && → Agrafeuse
continuer
? libelle                         && → Cahier A4
continuer
? libelle                         && → Classeur
continuer
? trouve(), fdf()                 && → faux vrai
```

### 11.5 Modifier, ajouter, effacer

```
chercher "Cahier A4"
remplacer prix par prix * 1.1, stock par stock - 5
? prix, stock                     && → 2.75 35

ajouter ref par "E5", libelle par "Règle 30 cm", prix par 1.5, stock par 20
? numenr(), libelle, nbenr()      && → 6 Règle 30 cm 6

locale nbRupture
compter pour stock = 0 dans nbRupture
? nbRupture                       && → 1

parcourir pour stock = 0
  effacer
finparcourir
? nbenr()                         && → 5
```

- `remplacer champ par expression, …` met à jour l'enregistrement courant (une requête `update`). Les expressions sont calculées avec les anciennes valeurs.
- `ajouter champ par valeur, …` insère un enregistrement et s'y place ; `ajouter vide` (ou `ajouter` seul) insère un enregistrement avec les valeurs par défaut de la table. Une clef primaire sans valeur par défaut doit être fournie.
- `effacer` supprime **immédiatement** la ligne SQL (il n'y a pas de marque d'effacement ni de `PACK`) ; dans `parcourir`, le parcours continue correctement sur l'enregistrement suivant.
- `compter [pour condition] dans variable` (`COUNT … TO`).
- Un enregistrement ajouté se place en fin de parcours ; `rafraichir` relit la table et réapplique l'ordre et le filtre (utile aussi pour voir les modifications faites par d'autres utilisateurs).

### 11.6 Plusieurs zones

```
utiliser mouvements alias MVT     && devient la zone courante
? alias(), ref, qte               && → MVT A1 -10
selectionner articles             && revient à la zone ARTICLES
chercher "Stylo bleu"
? articles->stock, mvt->qte       && → 150 -10
? json(enregistrement())          && → {"REF":"A1","LIBELLE":"Stylo bleu","PRIX":1.2,"STOCK":150}
? champ("prix"), champ("qte", "MVT")    && → 1.2 -10
fermer mvt                        && ferme une zone (fermer seul : la zone courante)
fermer tout
```

`alias->champ` lit un champ d'une autre zone sans la sélectionner. Les fonctions `fdf`, `ddf`, `numenr`, `nbenr`, `trouve` acceptent un alias en argument : `fdf("MVT")`.

### 11.7 Filtre et ordre SQL

```
utiliser articles filtre "prix < 2" ordre "prix desc"
parcourir
  ?? libelle, prix, "|"
finparcourir                      && → Règle 30 cm 1.5 |Stylo bleu 1.2 |Gomme 0.8 |
```

`ordre` et `filtre` sont des fragments SQL écrits par le développeur ; n'y insérez jamais une saisie de l'utilisateur. Pour filtrer selon une saisie, utilisez `sql … avec` ou `localiser pour`.

### 11.8 Bon à savoir

- Les zones appartiennent à la session : une zone ouverte reste ouverte d'une requête à l'autre, avec sa position.
- L'enregistrement est repéré par la clef primaire de la table (une seule colonne) ; sans clef primaire, par le `rowid` interne de DuckDB. **Donnez une clef primaire à vos tables.**
- Les champs masquent les variables globales de même nom (chapitre 4 : `m->nom`).
- Pour des traitements de masse (mettre à jour 10 000 lignes), une seule requête `sql "update …"` est bien plus rapide qu'un `parcourir` + `remplacer`.

## 12. Pages et balises

Une page est un fichier HTML du dossier `PAGE` dans lequel du code Lexis+ s'insère entre balises ; elle est exécutée à chaque envoi et son résultat part vers le navigateur.

### 12.1 Les quatre balises

| Balise | Effet | Exemple |
| --- | --- | --- |
| `<% instructions %>` | exécute du code (aucune sortie par elle-même) | `<% si connecte %>` |
| `<%= expression %>` | insère la valeur **échappée** : `< > & " '` deviennent `&lt;` etc. | `<%= client.nom %>` |
| `<%== expression %>` | insère la valeur **brute**, sans échappement | `<%== blocHtmlDeConfiance %>` |
| `<%-- commentaire --%>` | ignoré, n'apparaît pas dans le HTML |  |

Utilisez **toujours** `<%= %>` pour une donnée saisie par un utilisateur ou lue en base : c'est ce qui empêche l'injection de HTML ou de JavaScript (XSS). Réservez `<%== %>` à du HTML que vous avez vous-même produit.

### 12.2 Une page pas à pas

La procédure prépare les données et envoie la page :

```
procedure CATALOGUE
  locale p
  sql "select * from produits order by libelle" dans p
  envoyer liste avec titre = "Catalogue", produits = p, note = "<em>prix TTC</em>"
retourner
```

La page `PAGE/liste.html` :

```html
<%-- Liste des produits : reçoit titre et produits --%>
<% inclure entete avec titre = titre %>
<h1><%= titre %></h1>
<% si #produits = 0 %>
<p>Aucun produit.</p>
<% sinon %>
<table>
<% pour chaque p dans produits %>
  <tr class="<%= sisinon(p.stock < 5, "rare", "") %>"><td><%= p.libelle %></td><td><%= chaine(p.prix, 1, 2) %> €</td></tr>
<% suivant %>
</table>
<p><%= #produits %> produit(s), note : <%== note %></p>
<% finsi %>
<% inclure pied %>
```

Avec deux produits en base, "Stylo \<rouge>" et "Agrafeuse", le HTML produit est :

```html
<header>CATALOGUE</header>
<h1>Catalogue</h1>
<table>
  <tr class="rare"><td>Agrafeuse</td><td>12.90 €</td></tr>
  <tr class=""><td>Stylo &lt;rouge&gt;</td><td>1.20 €</td></tr>
</table>
<p>2 produit(s), note : <em>prix TTC</em></p>
<footer>© 2026</footer>
```

Ce qu'il faut remarquer :

1. Les structures (`si`, `pour chaque`, `parcourir`…) **enjambent du HTML** : une balise ouvre la structure, une autre la ferme, et le HTML entre les deux est répété ou omis.
2. `<%= p.libelle %>` a neutralisé `<rouge>` ; `<%== note %>` a laissé passer `<em>`.
3. Une ligne qui ne contient qu'une balise `<% … %>` ne laisse pas de ligne vide dans le résultat.
4. `<%= %>` contient une **seule expression** ; `<% %>` peut contenir plusieurs instructions sur plusieurs lignes.

### 12.3 Envoyer et inclure

```
envoyer liste avec titre = "Catalogue", produits = p    && nom simple : PAGE/liste…
envoyer "rapports/mensuel" avec mois = 10              && chaîne : sous-dossier possible
locale nomPage = "PIED"
envoyer (nomPage)                                      && entre parenthèses : nom calculé
```

- `envoyer` et `inclure` sont synonymes ; on écrit plutôt `inclure` dans une page (en-tête, pied, fragment réutilisable).
- Chaque `nom = valeur` après `avec` devient une variable locale de la page. La page voit aussi les variables de session et les champs de la zone courante, mais **pas** les locales de la procédure qui l'envoie.
- Le fichier est cherché dans `PAGE` sous le nom exact, puis avec `.html`, `.htm`, `.page`, puis sans tenir compte des majuscules. Les noms contenant `..` sont refusés.
- Plusieurs `envoyer` successifs s'ajoutent les uns aux autres dans la réponse.
- Une page modifiée est recompilée automatiquement ; une erreur de syntaxe dans une page est signalée avec son nom et sa ligne (`PAGE/liste.html:12 : …`).

### 12.4 Gabarit commun : en-tête et pied

`PAGE/entete.html` :

```html
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <title><%= titre %> · Mon application</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <a href="/">Accueil</a>
  <% si non estnul(SESSION.UTILISATEUR) %>
    <span><%= SESSION.UTILISATEUR %> · <a href="/DECONNEXION">quitter</a></span>
  <% finsi %>
</header>
<main>
```

`PAGE/pied.html` :

```html
</main>
<footer>Lexis+ · <%= date() %></footer>
</body>
</html>
```

Toute page commence alors par `<% inclure entete avec titre = "…" %>` et finit par `<% inclure pied %>`. Le fichier `/style.css` est servi depuis `BLOB/style.css`.

### 12.5 Code dans les pages

Une page peut contenir n'importe quelle instruction : `locale`, calculs, `sql`, appels de procédures. `?` y écrit directement dans le HTML, **sans échappement**. Bonne pratique : faire les calculs et les requêtes dans la procédure, ne garder dans la page que la mise en forme (`si`, `pour chaque`, `<%= %>`).

### 12.6 Champs d'une zone dans une page

Si la procédure a ouvert une zone de travail, la page peut la parcourir et lire ses champs directement :

```html
<% parcourir %>
  <tr><td><%= libelle %></td><td><%= stock %></td></tr>
<% finparcourir %>
```

## 13. Dialogue avec le navigateur

Le navigateur appelle une procédure par son adresse (`/NOM`), lui transmet des champs (URL ou formulaire), et reçoit ce que la procédure produit : une page, du texte, du JSON, une redirection. Tous les exemples de ce chapitre ont été testés sur le serveur.

### 13.1 Adresses

| Adresse | Effet |
| --- | --- |
| `/` | première procédure listée dans `SESSION.ACCEPTE` (la page d'accueil) |
| `/FACTURES` | procédure `FACTURES` (majuscules ou minuscules indifférentes) si elle figure dans `ACCEPTE` |
| `/style.css`, `/images/logo.png` | fichier statique du dossier `BLOB` |
| `/EDIT`, `/SUIVI` | éditeur et écran de suivi intégrés (droits `EDITION`, `SUIVI`) |
| toute adresse, session non identifiée | procédure `CONNEXION` |

Une procédure absente de `ACCEPTE` provoque un refus 403 et la fermeture de la session (chapitre 14).

### 13.2 Recevoir des champs

Les paramètres d'une procédure reçoivent les champs de même nom, qu'ils viennent de l'URL (`?nom=…`) ou d'un formulaire `POST` :

```
procedure FORMULAIRE(nom, age, options)
  ? "nom =", nom, "· age + 1 =", valeur(age) + 1, "· type(options) =", type(options)
  si type(options) = "table"
    ? "options :", joindre(options, ", ")
  sinonsi non estnul(options)
    ? "une seule option :", options
  finsi
retourner
```

| Envoi | Affichage |
| --- | --- |
| `nom=Dupont&age=41&options=a&options=c` | `nom = Dupont · age + 1 = 42 · type(options) = table` puis `options : a, c` |
| `nom=Ana&age=30&options=b` | `nom = Ana · age + 1 = 31 · type(options) = chaine` puis `une seule option : b` |
| corps JSON `{"nom":"Léo","age":"9"}` | `nom = Léo · age + 1 = 10 · type(options) = nul` |

À retenir :

- Un champ reçu est une **chaîne** : convertissez avec `valeur()` avant de calculer.
- Un champ absent vaut `nul`.
- Un champ répété (cases à cocher de même nom, liste à choix multiples) arrive sous forme de **table** dès qu'il y a au moins deux valeurs, de chaîne sinon : testez `type()`.
- Formats acceptés : URL, `application/x-www-form-urlencoded`, `multipart/form-data` (avec fichiers), `application/json` (objet). Un autre type de corps arrive tel quel dans le champ `CORPS`.

### 13.3 Recevoir un fichier

```html
<form method="post" action="/ENVOI" enctype="multipart/form-data">
  <input name="titre"> <input type="file" name="document"> <button>Envoyer</button>
</form>
```

```
procedure ENVOI(document, titre)
  ? titre, document.nom, document.type, document.taille, gauche(document.contenu, 11)
retourner
&& → Rapport doc.txt text/plain 16 Bonjour le
```

Un fichier arrive sous forme de table : `NOM` (nom d'origine), `TYPE` (type MIME), `TAILLE` (octets), `CONTENU` (les octets, dans une chaîne). Taille maximale d'une requête : 16 Mo par défaut (`taille_max_corps`). Un fichier **texte** (CSV, TXT, JSON) peut être analysé directement (`decouper(document.contenu, "\n")`) ou stocké dans une colonne `varchar`. Un fichier **binaire** (image, PDF) ne peut pas être passé en paramètre SQL (`sql : impossible de lier le paramètre 1`) : déposez-le dans `BLOB` par l'éditeur `/EDIT`.

### 13.4 La variable REQUETE

Toute procédure appelée par le navigateur dispose de la variable locale `REQUETE` :

| Clef | Contenu | Exemple pour `GET /INFO?x=1&y=deux` |
| --- | --- | --- |
| `REQUETE.METHODE` | `"GET"`, `"POST"` ou `"HEAD"` | `GET` |
| `REQUETE.CHEMIN` | chemin demandé | `/INFO` |
| `REQUETE.REQUETE` | chaîne de requête brute | `x=1&y=deux` |
| `REQUETE.IP` | adresse du client | `127.0.0.1` |
| `REQUETE.PARAMS` | tous les champs reçus | `{"X":"1","Y":"deux"}` |
| `REQUETE.ENTETES` | en-têtes HTTP, noms en majuscules | `REQUETE.ENTETES["USER-AGENT"]` |
| `REQUETE.COOKIES` | cookies (hors cookie de session), noms en majuscules | `REQUETE.COOKIES.langue` |

`REQUETE.METHODE = "POST"` est le test habituel pour distinguer l'affichage d'un formulaire de sa soumission.

### 13.5 Répondre

| Instruction | Effet | Exemple |
| --- | --- | --- |
| `envoyer page avec …` | ajoute le HTML d'une page | chapitre 12 |
| `? valeurs` / `?? valeurs` | ajoute du texte brut (non échappé) | `?? json(t)` |
| `entete "Nom", "valeur"` | ajoute un en-tête HTTP | `entete "Content-Type", "application/json; charset=utf-8"` |
| `statut code` | code HTTP (200 par défaut) | `statut 404` |
| `rediriger "url"` | redirection (302 par défaut) | `rediriger "/ACCUEIL"` |
| `deconnecter` | ferme la session à la fin de la requête | chapitre 14 |

Le type par défaut est `text/html; charset=utf-8`. Le cookie de session est réservé : `entete "Set-Cookie"` peut poser d'autres cookies (`"langue=fr; Path=/; SameSite=Lax"`), jamais `WDG_SESSION`.

### 13.6 Une petite API JSON

```
procedure API(ville)
  locale reponse = {ville = ville, temperature = 21.5, prevision = {"soleil", "nuages"}}
  entete "Content-Type", "application/json; charset=utf-8"
  ?? json(reponse)
retourner
```

`GET /API?ville=Lyon` répond `{"VILLE":"Lyon","TEMPERATURE":21.5,"PREVISION":["soleil","nuages"]}`. Utilisez `??` (sans retour à la ligne) pour un JSON propre. Côté navigateur, l'appel se fait avec `fetch("/API?ville=Lyon", {credentials: "same-origin"})` : la procédure doit figurer dans `ACCEPTE` comme une autre.

### 13.7 Le schéma Post/Redirect/Get

Après une modification, redirigez vers la page d'affichage plutôt que d'envoyer directement une page : un rafraîchissement du navigateur ne renverra pas le formulaire une deuxième fois.

```
procedure ENREGISTRER(libelle)
  si REQUETE.METHODE <> "POST"
    rediriger "/LISTE"
    retourner
  finsi
  sql "insert into notes (texte) values (?)" avec libelle
  rediriger "/LISTE"
retourner
```

Toute action qui modifie des données doit exiger `POST` : un simple lien (GET) peut être déclenché depuis un autre site, un formulaire POST non (cookie `SameSite=Lax`).

## 14. Sessions, droits et sécurité

La sécurité d'une application Lexis+ repose sur deux variables de session que vous écrivez dans `CONNEXION` : `VALIDE` (les droits, en liste CSV) et `ACCEPTE` (les procédures autorisées, en liste CSV). Le serveur fait respecter le reste.

### 14.1 Le cycle de vie d'une session

1. **Arrivée.** Un visiteur sans session reçoit une session par défaut, qui ne contient qu'une variable : `VALIDE = "CONNEXION"`. Un cookie `WDG_SESSION` (identifiant aléatoire de 128 bits) l'y rattache.
2. **Anonyme.** Tant que `VALIDE` vaut `"CONNEXION"`, **toute** adresse appelle la procédure `CONNEXION`, quelle que soit l'adresse demandée.
3. **Connexion.** Dès que `CONNEXION` donne une autre valeur à `VALIDE`, la session devient active et reçoit un nouvel identifiant (protection contre la fixation de session).
4. **Active.** L'adresse `/NOM` n'exécute `NOM` que si `NOM` figure dans `ACCEPTE`.
5. **Fin.** La session est détruite par `deconnecter`, par 30 minutes d'inactivité (`expiration_minutes`), par un accès non autorisé (403), ou depuis l'écran `/SUIVI`. Toutes ses données sont libérées.

&#91;embedded content: cycle de vie d'une session · 3 états\]

Une session anonyme ne peut exécuter que `CONNEXION` ; elle devient active quand `CONNEXION` change `VALIDE`, et toute fermeture ramène la requête suivante à une nouvelle session anonyme.

### 14.2 Une connexion complète, pas à pas

**Étape 1 - la table des comptes**, créée au démarrage :

```
procedure DEMARRAGE
  sql [[create table if not exists utilisateurs (
          nom     varchar primary key,
          mdp     varchar,        -- empreinte, jamais le mot de passe
          droits  varchar,        -- copié dans SESSION.VALIDE
          accepte varchar         -- copié dans SESSION.ACCEPTE
        )]]
  si valeursql("select count(*) from utilisateurs") = 0
    locale mdp = mdpaleatoire(16)
    sql "insert into utilisateurs values (?, ?, ?, ?)" ;
        avec "admin", hachermdp(mdp), "UTILISATEUR,EDITION,SUIVI", ;
             "ACCUEIL,FACTURES,DECONNEXION"
    ? "Mot de passe initial de admin : " + mdp
  finsi
retourner
```

`mdpaleatoire(16)` tire un mot de passe de 16 caractères ; `?` l'affiche dans la console du serveur, une seule fois. Aucun mot de passe par défaut n'est ainsi livré.

**Étape 2 - la procédure CONNEXION :**

```
procedure CONNEXION(nom, mdp)
  locale message = "", r, empreinte = nul
  si REQUETE.METHODE = "POST"
    sql "select mdp, droits, accepte from utilisateurs where nom = ?" avec nom dans r
    si #r = 1
      empreinte = r[1].mdp
    finsi
    si verifiermdp(mdp, empreinte)
      SESSION.UTILISATEUR = nom
      SESSION.ACCEPTE = r[1].accepte      && procédures autorisées
      SESSION.VALIDE = r[1].droits        && la session devient active
      rediriger "/ACCUEIL"
      retourner
    finsi
    message = "Identifiant ou mot de passe incorrect."
  finsi
  envoyer connexion avec message = message
retourner
```

- `verifiermdp(mdp, empreinte)` compare le mot de passe à l'empreinte stockée. Si l'utilisateur n'existe pas, `empreinte` vaut `nul` et la fonction calcule quand même une empreinte complète : le temps de réponse ne révèle pas si l'identifiant existe.
- Le message d'erreur ne dit pas lequel des deux était faux.

**Étape 3 - la page `PAGE/connexion.html` :**

```html
<% inclure entete avec titre = "Connexion" %>
<% si non vide(message) %><p class="alerte"><%= message %></p><% finsi %>
<form method="post" action="/CONNEXION">
  <label>Identifiant <input name="nom" autocomplete="username" required></label>
  <label>Mot de passe <input name="mdp" type="password" autocomplete="current-password" required></label>
  <button>Entrer</button>
</form>
<% inclure pied %>
```

**Étape 4 - la déconnexion :**

```
procedure DECONNEXION
  deconnecter
  rediriger "/"
retourner
```

`DECONNEXION` doit figurer dans `ACCEPTE`. Après `deconnecter`, la requête suivante repart avec une session par défaut.

### 14.3 Les droits

`VALIDE` est une liste CSV libre. Deux mots y ont un sens pour le serveur :

| Droit | Donne accès à |
| --- | --- |
| `EDITION` | l'éditeur intégré `/EDIT` (modifier PROG, PAGE, BLOB) et au détail des erreurs d'exécution |
| `SUIVI` | l'écran de suivi `/SUIVI` (sessions, charge, mesures) |

Les autres mots sont à vous ; testez-les avec l'opérateur `$` ou la liste :

```
si "COMPTABLE" $ SESSION.VALIDE
  …
finsi
```

Pour un menu, testez `ACCEPTE`, qui dit exactement ce que l'utilisateur peut ouvrir :

```html
<% si "FACTURES" $ SESSION.ACCEPTE %><a href="/FACTURES">Factures</a><% finsi %>
```

`$` teste une sous-chaîne : choisissez des noms qui ne sont pas contenus les uns dans les autres (`FACTURES` et `FACTURESARCHIVES` se confondraient), ou testez la liste exacte avec `contient(decouper(SESSION.ACCEPTE, ","), "FACTURES")`.

### 14.4 Ce que le serveur fait respecter

| Situation | Réaction du serveur |
| --- | --- |
| `/NOM` absent de `ACCEPTE` | réponse 403, session **supprimée**, adresse IP inscrite dans la table `incidents` (premier et dernier incident, nombre) |
| `/EDIT` sans `EDITION`, `/SUIVI` sans `SUIVI` | idem |
| plus de 10 tentatives de connexion en 15 min depuis une IP | réponse 429 pendant 15 min, même avec le bon mot de passe |
| plus de 4 requêtes simultanées d'une même session en attente | réponse 429 |
| 30 min sans requête | session fermée |
| fichier hors de `BLOB` (`..`, lien symbolique) | 404 |
| requête trop longue (30 s) ou boucle infinie | requête arrêtée, 500 |

La table `incidents` se lit comme une autre : `requete("select * from incidents order by dernier desc")`.

### 14.5 Mots de passe provisoires

Pour imposer le changement d'un mot de passe initial, donnez à la session des droits restreints :

```
si r[1].changer
  SESSION.ACCEPTE = "MOTDEPASSE,DECONNEXION"
  SESSION.VALIDE = "CHANGEMENT"         && active, mais limitée à ces deux procédures
  rediriger "/MOTDEPASSE"
finsi
```

Toute tentative d'ouvrir une autre page avant le changement est alors refusée (403). L'application d'exemple livrée avec le serveur met ce schéma en œuvre (`PROG/connexion.prg`).

### 14.6 Liste de contrôle de sécurité

- [ ] Mots de passe stockés avec `hachermdp`, vérifiés avec `verifiermdp` ; jamais `hachage` (trop rapide) ni le texte en clair.
- [ ] Toute valeur venant de l'utilisateur passée en paramètre `?` dans le SQL, jamais concaténée (ni dans `ordre`, ni dans `filtre`).
- [ ] Toute valeur affichée avec `<%= %>` ; `<%== %>` et `?` réservés à du contenu sûr.
- [ ] Toute modification de données déclenchée par un formulaire `POST`, avec `REQUETE.METHODE = "POST"` vérifié.
- [ ] `ACCEPTE` limité au strict nécessaire pour chaque profil ; `EDITION` réservé aux développeurs.
- [ ] Les droits métier vérifiés aussi dans la procédure (un utilisateur ne doit lire que ses propres factures : `where client = ?` avec `SESSION.UTILISATEUR`).
- [ ] Variables de travail déclarées `locale`.
- [ ] Hors de `127.0.0.1` : serveur derrière un mandataire HTTPS, `"cookie_securise": true`.

## 15. Tutoriel complet : gestion des contacts

Ce tutoriel construit un carnet de contacts partagé - liste, recherche, création, modification avec contrôle de saisie, suppression, export JSON - en un fichier de procédures, cinq pages et une feuille de style. Le code ci-dessous a été exécuté et testé tel quel.

### 15.1 Ce que l'on va construire

| Adresse | Procédure | Rôle |
| --- | --- | --- |
| `/` (anonyme) | `CONNEXION` | demande un prénom et ouvre la session |
| `/CONTACTS?q=…` | `CONTACTS` | liste, avec recherche |
| `/FICHE?id=…` | `FICHE` | formulaire de création ou de modification |
| `/ENREGISTRER` (POST) | `ENREGISTRER` | contrôle et enregistrement |
| `/SUPPRIMER` (POST) | `SUPPRIMER` | suppression |
| `/EXPORT` | `EXPORT` | tous les contacts en JSON |
| `/DECONNEXION` | `DECONNEXION` | fin de session |

Arborescence finale :

```
contacts/
├── wdgestionv
├── wdgestionv.json
├── linOS/
├── PROG/contacts.prg
├── PAGE/entete.html  pied.html  connexion.html  contacts.html  fiche.html
└── BLOB/style.css
```

### 15.2 Étape 1 - La table

Début de `PROG/contacts.prg` :

```
&& Création de la table au lancement du serveur
procedure DEMARRAGE
  sql [[create sequence if not exists seq_contacts;
        create table if not exists contacts (
          id         integer primary key default nextval('seq_contacts'),
          nom        varchar not null,
          prenom     varchar,
          societe    varchar,
          courriel   varchar,
          telephone  varchar,
          cree_le    timestamp default current_timestamp)]]
retourner
```

La séquence `seq_contacts` numérote automatiquement les contacts. `if not exists` rend la procédure sans effet aux lancements suivants.

### 15.3 Étape 2 - La connexion

Pour garder le tutoriel court, un prénom suffit ; le chapitre 14 montre une vraie connexion par mot de passe.

```
procedure CONNEXION(utilisateur)
  si REQUETE.METHODE = "POST" et non vide(utilisateur)
    SESSION.UTILISATEUR = rogner(utilisateur)
    SESSION.ACCEPTE = "CONTACTS,FICHE,ENREGISTRER,SUPPRIMER,EXPORT,DECONNEXION"
    SESSION.VALIDE = "UTILISATEUR"
    rediriger "/CONTACTS"
    retourner
  finsi
  envoyer connexion
retourner
```

`ACCEPTE` liste exactement les sept procédures appelables : toute autre adresse (`/ADMIN`, `/DEMARRAGE`, `/VERIFIER`…) reçoit un 403 et ferme la session.

`PAGE/connexion.html` :

```html
<% inclure entete avec titre = "Connexion" %>
<form method="post" action="/CONNEXION">
  <label>Votre prénom <input name="utilisateur" required autofocus></label>
  <button>Entrer</button>
</form>
<% inclure pied %>
```

### 15.4 Étape 3 - Le gabarit

`PAGE/entete.html` :

```html
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><%= titre %> · Contacts</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <strong>Contacts</strong>
<% si non estnul(SESSION.UTILISATEUR) %>
  <span><%= SESSION.UTILISATEUR %> · <a href="/DECONNEXION">quitter</a></span>
<% finsi %>
</header>
<main>
```

`PAGE/pied.html` :

```html
</main>
</body>
</html>
```

`BLOB/style.css` :

```css
body { font: 15px system-ui, sans-serif; margin: 0; color: #222; }
header { display: flex; justify-content: space-between; padding: .8rem 1.5rem; background: #1f3fae; color: #fff; }
header a { color: #dfe6ff; }
main { max-width: 900px; margin: 1.5rem auto; padding: 0 1rem; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: .4rem; border-bottom: 1px solid #ddd; }
label { display: block; margin: .5rem 0; }
.erreurs { color: #b42318; }
```

### 15.5 Étape 4 - La liste et la recherche

```
procedure CONTACTS(q)
  locale liste, motif
  si vide(q)
    sql "select * from contacts order by nom, prenom" dans liste
  sinon
    motif = "%" + rogner(q) + "%"
    sql [[select * from contacts
          where nom ilike ? or prenom ilike ? or societe ilike ?
          order by nom, prenom]] avec motif, motif, motif dans liste
  finsi
  envoyer contacts avec liste = liste, q = q
retourner
```

- `liste` et `motif` sont déclarées `locale` : rien ne reste dans la session.
- `ilike` compare sans tenir compte des majuscules ; le motif `%acme%` est passé en paramètre, jamais concaténé au SQL.

`PAGE/contacts.html` :

```html
<% inclure entete avec titre = "Liste" %>
<form method="get" action="/CONTACTS">
  <input name="q" value="<%= q %>" placeholder="Rechercher">
  <button>Chercher</button>
  <a href="/FICHE">Nouveau contact</a>
</form>
<% si #liste = 0 %>
  <p>Aucun contact<% si non vide(q) %> pour "<%= q %>" <% finsi %>.</p>
<% sinon %>
<table>
  <tr><th>Nom</th><th>Société</th><th>Courriel</th><th>Téléphone</th><th></th></tr>
  <% pour chaque c dans liste %>
  <tr>
    <td><a href="/FICHE?id=<%= c.id %>"><%= c.nom %> <%= c.prenom %></a></td>
    <td><%= c.societe %></td>
    <td><%= c.courriel %></td>
    <td><%= c.telephone %></td>
    <td>
      <form method="post" action="/SUPPRIMER" onsubmit="return confirm('Supprimer ce contact ?')">
        <input type="hidden" name="id" value="<%= c.id %>"><button>Supprimer</button>
      </form>
    </td>
  </tr>
  <% suivant %>
</table>
<p><%= #liste %> contact(s)</p>
<% finsi %>
<% inclure pied %>
```

La suppression passe par un petit formulaire POST : un lien ne doit jamais modifier de données.

### 15.6 Étape 5 - La fiche (création et modification)

```
procedure FICHE(id)
  locale c = {}, r
  si non vide(id)
    sql "select * from contacts where id = ?" avec valeur(id) dans r
    si #r = 0
      rediriger "/CONTACTS"
      retourner
    finsi
    c = r[1]
  finsi
  envoyer fiche avec c = c, erreurs = {}
retourner
```

Sans `id`, la fiche est vide (création) ; avec un `id` inconnu, retour à la liste.

`PAGE/fiche.html` :

```html
<% inclure entete avec titre = sisinon(vide(c.id), "Nouveau contact", "Modifier") %>
<h1><%= sisinon(vide(c.id), "Nouveau contact", c.nom + " " + (c.prenom ou "")) %></h1>
<% si #erreurs > 0 %>
<ul class="erreurs">
  <% pour chaque e dans erreurs %><li><%= e %></li><% suivant %>
</ul>
<% finsi %>
<form method="post" action="/ENREGISTRER">
  <input type="hidden" name="id" value="<%= c.id %>">
  <label>Nom* <input name="nom" value="<%= c.nom %>"></label>
  <label>Prénom <input name="prenom" value="<%= c.prenom %>"></label>
  <label>Société <input name="societe" value="<%= c.societe %>"></label>
  <label>Courriel <input name="courriel" value="<%= c.courriel %>"></label>
  <label>Téléphone <input name="telephone" value="<%= c.telephone %>"></label>
  <button>Enregistrer</button> <a href="/CONTACTS">Annuler</a>
</form>
<% inclure pied %>
```

La même page sert à la création, à la modification et au réaffichage après une erreur de saisie. `(c.prenom ou "")` remplace un prénom absent par une chaîne vide.

### 15.7 Étape 6 - Contrôler et enregistrer

```
fonction VERIFIER(c)
  locale erreurs = {}
  si vide(c.nom)
    inserer "Le nom est obligatoire." dans erreurs
  finsi
  si non vide(c.courriel) et non ("@" $ c.courriel)
    inserer "Le courriel est invalide." dans erreurs
  finsi
retourner erreurs

procedure ENREGISTRER(id, nom, prenom, societe, courriel, telephone)
  si REQUETE.METHODE <> "POST"
    rediriger "/CONTACTS"
    retourner
  finsi
  locale c = {id = id, nom = rogner(nom), prenom = rogner(prenom), societe = rogner(societe), ;
              courriel = rogner(courriel), telephone = rogner(telephone)}
  locale erreurs = VERIFIER(c)
  si #erreurs > 0
    envoyer fiche avec c = c, erreurs = erreurs
    retourner
  finsi
  si vide(id)
    sql "insert into contacts (nom, prenom, societe, courriel, telephone) values (?, ?, ?, ?, ?)" ;
        avec c.nom, c.prenom, c.societe, c.courriel, c.telephone
  sinon
    sql "update contacts set nom = ?, prenom = ?, societe = ?, courriel = ?, telephone = ? where id = ?" ;
        avec c.nom, c.prenom, c.societe, c.courriel, c.telephone, valeur(id)
  finsi
  rediriger "/CONTACTS"
retourner
```

Le déroulement :

1. Refus de tout ce qui n'est pas un POST (un lien ne peut pas enregistrer).
2. Nettoyage des saisies (`rogner` enlève les espaces en trop) dans une table `c`.
3. Contrôle par `VERIFIER`, une fonction interne : absente de `ACCEPTE`, le navigateur ne peut pas l'appeler.
4. En cas d'erreur, la fiche est réaffichée avec les valeurs saisies et la liste des erreurs.
5. Sinon, `insert` ou `update` selon la présence d'un `id`, puis redirection vers la liste (Post/Redirect/Get).

### 15.8 Étape 7 - Supprimer, exporter, quitter

```
procedure SUPPRIMER(id)
  si REQUETE.METHODE = "POST" et non vide(id)
    sql "delete from contacts where id = ?" avec valeur(id)
  finsi
  rediriger "/CONTACTS"
retourner

procedure EXPORT
  entete "Content-Type", "application/json; charset=utf-8"
  ?? json(requete("select id, nom, prenom, societe, courriel, telephone from contacts order by id"))
retourner

procedure DECONNEXION
  deconnecter
  rediriger "/"
retourner
```

### 15.9 Étape 8 - Essayer

Lancez `./wdgestionv` dans le dossier `contacts`, ouvrez `http://127.0.0.1:8080/` et vérifiez :

| Action | Résultat attendu (constaté) |
| --- | --- |
| Première visite, après connexion | "Aucun contact." |
| Enregistrer un nom vide et le courriel "pasunmail" | "Le nom est obligatoire. " et "Le courriel est invalide." |
| Créer Durand (Acme), Martin (Globex), O'Brien (Acme) | 3 contact(s) |
| Prénom saisi : `<script>` | affiché `<script>` en texte, jamais exécuté |
| Rechercher "acme" | 2 contact(s) |
| Modifier la société de Martin en Initech | la liste affiche Initech |
| Ouvrir `/SUPPRIMER?id=2` dans la barre d'adresse | rien n'est supprimé (GET refusé) |
| Ouvrir `/EXPORT` | `[{"ID":2,"NOM":"Martin","PRENOM":"Léa","SOCIETE":"Initech",…}, …]` |
| Ouvrir `/ADMIN` | 403 et retour à la page de connexion |

### 15.10 Pour aller plus loin

- Remplacer la connexion par celle du chapitre 14 (mots de passe, droits).
- Restreindre la suppression à un profil : ajouter `SUPPRIMER` à `ACCEPTE` seulement si `"GESTIONNAIRE" $ r[1].droits`.
- Paginer la liste : `order by nom limit 50 offset ?` avec un paramètre `page`.
- Exporter en CSV : `entete "Content-Type", "text/csv; charset=utf-8"` puis `?` ligne par ligne avec `joindre`.

## 16. Référence des instructions

Toutes les instructions de Lexis+, par ordre alphabétique ; les crochets `[ ]` marquent une partie facultative, `…` une répétition. La colonne dBase donne l'équivalent d'origine.

| Instruction | Syntaxe | Effet | dBase | Chapitre |
| --- | --- | --- | --- | --- |
| `?` | `? expr [, expr…]` | écrit les valeurs séparées d'une espace, puis un retour à la ligne | `?` | 3 |
| `??` | `?? expr [, expr…]` | écrit sans retour à la ligne | `??` | 3 |
| affectation | `cible = expr` | affecte une variable, `t.champ` ou `t[clef]` | `=` | 4 |
| `+=` `-=` | `cible += expr` | ajoute, retire (ou concatène) |  | 5 |
| `ajouter` | `ajouter [vide]` · `ajouter champ par expr [, …]` | insère un enregistrement dans la zone courante et s'y place | `APPEND BLANK` + `REPLACE` | 11 |
| `aller` | `aller haut` · `aller bas` · `aller n` | déplacement dans la zone | `GO TOP/BOTTOM/n` | 11 |
| association | `t:procedure NOM [comme clef]` | range la procédure dans la table, comme méthode |  | 9 |
| `chercher` | `chercher expr` | cherche sur la 1re colonne de l'ordre ; `trouve()` dit si c'est réussi | `SEEK` | 11 |
| `compter` | `compter [pour cond] dans var` | compte les enregistrements | `COUNT TO` | 11 |
| `continuer` | `continuer` | reprend le dernier `localiser` | `CONTINUE` | 11 |
| `deconnecter` | `deconnecter` | ferme la session à la fin de la requête |  | 14 |
| `effacer` | `effacer` | supprime immédiatement l'enregistrement courant | `DELETE` + `PACK` | 11 |
| `entete` | `entete "Nom", "valeur"` | ajoute un en-tête HTTP à la réponse |  | 13 |
| `envoyer` | `envoyer page [avec nom = expr, …]` | exécute une page et ajoute son HTML à la réponse |  | 12 |
| `erreur` | `erreur expr` | déclenche une erreur avec ce message |  | 6 |
| `essayer` | `essayer` … `[capturer [var]]` … `finessayer` | intercepte les erreurs | `ON ERROR` | 6 |
| `faire` | `faire NOM [avec expr, …]` | appelle une procédure | `DO … WITH` | 7 |
| `faire cas` | `faire cas` / `cas cond` … / `[autrement]` / `fincas` | choix multiple | `DO CASE` | 6 |
| `fermer` | `fermer [alias]` · `fermer tout` | ferme une zone, ou toutes | `USE` · `CLOSE ALL` | 11 |
| `fixermetatable` | `fixermetatable t, mt` | donne une métatable à `t` (`nul` la retire) |  | 9 |
| `globale` | `globale NOM [= expr], …` | variable de session explicite | `PUBLIC` | 4 |
| `inclure` | comme `envoyer` | inclut une page (usage dans les pages) |  | 12 |
| `inserer` | `inserer expr dans t [position n \| clef k]` | ajoute un élément à une table |  | 8 |
| `liberer` | `liberer nom, …` | efface des variables | `RELEASE` | 4 |
| `localiser` | `localiser [pour] cond` | premier enregistrement vérifiant la condition | `LOCATE FOR` | 11 |
| `locale` (ou `local`) | `locale nom [= expr], …` | variables locales | `LOCAL` | 4 |
| `nouvelle table` | `nouvelle table cible [= expr]` | crée une table vide (ou affecte une table) |  | 8 |
| `parametres` | `parametres nom, …` | reçoit les arguments de la procédure | `PARAMETERS` | 7 |
| `parcourir` | `parcourir [pour cond]` … `finparcourir` | boucle sur les enregistrements de la zone | `SCAN` | 11 |
| `pour` | `pour v = début a fin [pas p]` … `suivant [v]` \| `finpour` | boucle comptée (`a`, `à`, `jusqua`) | `FOR … NEXT` | 6 |
| `pour chaque` | `pour chaque [clef,] valeur dans t` … `suivant` | parcourt une table |  | 6 |
| `procedure` / `fonction` | `procedure NOM[(p, …)]` … `[finprocedure]` | définit une procédure | `PROCEDURE` / `FUNCTION` | 7 |
| `rafraichir` | `rafraichir` | relit la zone courante (ordre, filtre) |  | 11 |
| `rediriger` | `rediriger "url"` | redirection HTTP 302 |  | 13 |
| `remplacer` | `remplacer champ par expr [, …]` | modifie l'enregistrement courant | `REPLACE` | 11 |
| `retirer` | `retirer [de] t [position n \| clef k] [dans var]` | enlève un élément (le dernier par défaut) |  | 8 |
| `retourner` (ou `retour`) | `retourner [expr]` | quitte la procédure, avec une valeur | `RETURN` | 7 |
| `sauter` | `sauter [n]` | avance (ou recule) dans la zone | `SKIP` | 11 |
| `selectionner` | `selectionner alias` | change de zone courante | `SELECT` | 11 |
| `si` | `si cond` … `[sinonsi cond]` … `[sinon]` … `finsi` | alternative | `IF … ENDIF` | 6 |
| `sortir` / `boucler` | `sortir` · `boucler` | quitte la boucle / passe au tour suivant | `EXIT` · `LOOP` | 6 |
| `sql` | `sql "…" [avec expr, …] [dans var]` | exécute du SQL ; lignes dans `var` |  | 10 |
| `statut` | `statut code` | code HTTP de la réponse |  | 13 |
| `stocker` | `stocker expr dans cible, …` | affectation multiple | `STORE … TO` | 4 |
| `supprimer table` | `supprimer table cible` | efface la table / la variable |  | 8 |
| `tantque` | `[faire] tantque cond` … `fintantque` | boucle conditionnelle | `DO WHILE` | 6 |
| `utiliser` | `utiliser table [alias a] [ordre "…"] [filtre "…"]` · `utiliser` seul | ouvre une table SQL comme zone / ferme la zone courante | `USE` | 11 |

Tout appel de procédure ou de méthode peut aussi être une instruction : `TRAITER(x)`, `panier:vider()`.

## 17. Référence des fonctions intégrées

Toutes les fonctions intégrées, par famille ; chaque résultat indiqué a été obtenu en exécutant l'exemple. Les positions dans les chaînes comptent les caractères (accents compris) à partir de 1.

### 17.1 Chaînes

| Fonction | Rôle | Exemple | Résultat |
| --- | --- | --- | --- |
| `majuscule(s)` | en majuscules (accents compris) | `majuscule("été")` | `ÉTÉ` |
| `minuscule(s)` | en minuscules | `minuscule("ÉTÉ")` | `été` |
| `rogner(s)` | retire les espaces aux deux bouts (`ALLTRIM`) | `rogner("  a b  ")` | `a b` |
| `rognerg(s)` / `rognerd(s)` | à gauche / à droite (`LTRIM`/`RTRIM`) | `rognerg("  ab ")` | ` ab  ` |
| `longueur(s)` | nombre de caractères (ou d'éléments d'une table) | `longueur("héllo")` | `5` |
| `souschaine(s, début [, n])` | extrait (`SUBSTR`) | `souschaine("Bonjour", 4, 2)` | `jo` |
| `gauche(s, n)` / `droite(s, n)` | n premiers / derniers caractères | `droite("Bonjour", 4)` | `jour` |
| `position(sous, s)` | position de `sous` dans `s`, 0 si absente (`AT`) | `position("jour", "Bonjour")` | `4` |
| `chaine(v [, largeur, décimales])` | en texte ; avec largeur : aligné à droite (`STR`) | `chaine(3.14159, 8, 2)` · `chaine(42, 1, 0)` | `     3.14 ` · `42` |
| `texte(v)` | en texte (`__tostring` respecté) | `texte(vrai)` | `vrai` |
| `valeur(s)` | en nombre, `0` si impossible (`VAL`) | `valeur("12,5")` | `12.5` |
| `nombre(s)` | en nombre, `nul` si impossible | `nombre("abc")` | `nul` |
| `espace(n)` | n espaces (`SPACE`) | `espace(3)` | `   ` |
| `repliquer(s, n)` | répétition (`REPLICATE`) | `repliquer("ab", 3)` | `ababab` |
| `remplacertexte(s, a, b)` | remplace toutes les occurrences (`STRTRAN`) | `remplacertexte("a-b-c", "-", "+")` | `a+b+c` |
| `contient(s, sous)` | `s` contient `sous` | `contient("Bonjour", "jour")` | `vrai` |
| `commencepar(s, d)` / `finitpar(s, f)` | début / fin de chaîne | `commencepar("Bonjour", "Bon")` | `vrai` |
| `decouper(s [, séparateur])` | en liste ; séparateur `,` par défaut | `joindre(decouper("a,b,,c"), "\|")` | `a\|b\|\|c` |
| `joindre(t [, séparateur])` | liste en chaîne | `joindre({1, 2, 3})` | `123` |
| `html(s)` | échappe `< > & " '` | `html("<b>&</b>")` | `&lt;b&gt;&amp;&lt;/b&gt;` |
| `url(s)` | encode pour une URL | `url("é à")` | `%C3%A9%20%C3%A0` |

`valeur` et la conversion automatique acceptent la virgule décimale (`"12,5"`), mais pas de séparateur de milliers : `valeur("1.234,5")` vaut `0`.

### 17.2 Nombres

| Fonction | Rôle | Exemple | Résultat |
| --- | --- | --- | --- |
| `abs(x)` | valeur absolue | `abs(-3.5)` | `3.5` |
| `entier(x)` | partie entière, vers zéro (`INT`) | `entier(-3.7)` | `-3` |
| `arrondi(x [, d])` | arrondi à d décimales (0 par défaut) | `arrondi(1234.5)` · `arrondi(2/3, 2)` | `1235` · `0.67` |
| `racine(x)` | racine carrée | `racine(16)` | `4` |
| `mod(a, b)` | reste, du signe du diviseur | `mod(-7, 3)` | `2` |
| `max(a, b, …)` / `min(a, b, …)` | plus grand / plus petit (nombres ou chaînes) | `max(3, 9, 2)` · `min("b", "a")` | `9` · `a` |
| `aleatoire([n])` | réel entre 0 et 1, ou entier entre 1 et n | `aleatoire(6)` | entre `1` et `6` |

### 17.3 Types et tests

| Fonction | Rôle | Exemple | Résultat |
| --- | --- | --- | --- |
| `type(v)` | `"nul"`, `"logique"`, `"nombre"`, `"chaine"`, `"table"`, `"procedure"` | `type({})` | `table` |
| `estnul(v)` | v vaut `nul` | `estnul(0)` | `faux` |
| `vide(v)` | `nul`, `faux`, `0`, chaîne vide, table sans élément (`EMPTY`) | `vide("  ")` | `vrai` |
| `sisinon(c, a, b)` | `a` si `c` est vrai, sinon `b` ; seule la branche choisie est calculée (`IIF`) | `sisinon(1 > 2, "oui", "non")` | `non` |

### 17.4 Dates et heures

| Fonction | Rôle | Exemple de résultat |
| --- | --- | --- |
| `date()` | date du jour, `AAAA-MM-JJ` | `2026-10-09` |
| `heure()` | heure, `HH:MM:SS` | `14:05:31` |
| `maintenant()` | date et heure | `2026-10-09 14:05:31` |
| `horodatage()` | secondes depuis le 1er janvier 1970 (avec décimales) | `1791551131.42` |

Les dates sont des chaînes ISO ; les calculs de dates se font en SQL : `valeursql("select date '2026-10-09' + interval 30 day")`, `valeursql("select datediff('day', ?, current_date)", debut)`.

### 17.5 Tables

| Fonction | Rôle | Exemple (t = `{10, 20, x = 1}`) | Résultat |
| --- | --- | --- | --- |
| `taille(t)` | nombre d'éléments de la partie liste (`#t`) | `taille(t)` | `2` |
| `nbelements(t)` | nombre total d'éléments | `nbelements(t)` | `3` |
| `clefs(t)` / `valeurs(t)` | liste des clefs / des valeurs | `joindre(valeurs(t), " ")` | `10 20 1` |
| `aclef(t, k)` | la clef existe | `aclef(t, "X")` | `vrai` |
| `contient(t, v)` | la valeur est présente | `contient(t, 20)` | `vrai` |
| `copier(t)` | copie de premier niveau | `copier(t) == t` | `faux` |
| `inserer(t, v [, pos])` | ajoute ; renvoie `t` | `inserer(t, 30)` | `t` (3 éléments en liste) |
| `retirer(t [, pos])` | enlève et renvoie l'élément (le dernier par défaut) | `retirer(t, 1)` | `10` |
| `trier(t [, @comparer])` | trie la partie liste sur place ; renvoie `t` | `trier({3, 1, 2})` | `{1, 2, 3}` |
| `joindre(t, s)` / `decouper(s, sep)` | voir 17.1 |  |  |
| `fixermetatable(t, mt)` | donne une métatable ; renvoie `t` |  |  |
| `obtenirmetatable(t)` | la métatable ou `nul` |  |  |
| `lirebrut(t, k)` / `ecrirebrut(t, k, v)` | lecture / écriture sans métaméthode |  |  |
| `json(v)` | en texte JSON | `json({1, {a = vrai}})` | `[1,{"A":true}]` |
| `dejson(s)` | depuis JSON (clefs d'objets en majuscules) | `dejson('{"n":1}').N` | `1` |

### 17.6 Procédures

| Fonction | Rôle | Exemple | Résultat |
| --- | --- | --- | --- |
| `appeler(f, args…)` | appelle une référence de procédure | `appeler(@TTC, 10, 10)` | `11` |

### 17.7 Base de données

| Fonction | Rôle |
| --- | --- |
| `requete(sql, params…)` | liste de lignes (tables aux clefs en majuscules) |
| `valeursql(sql, params…)` | première valeur de la première ligne, ou `nul` |
| `fdf([alias])` / `ddf([alias])` | fin / début de fichier de la zone (`EOF` / `BOF`) |
| `numenr([alias])` | numéro de l'enregistrement courant dans l'ordre de la zone (`RECNO`) |
| `nbenr([alias])` | nombre d'enregistrements de la zone (`RECCOUNT`) |
| `trouve([alias])` | résultat du dernier `chercher` / `localiser` (`FOUND`) |
| `alias()` | alias de la zone courante (`ALIAS`) |
| `champ(nom [, alias])` | valeur d'un champ par son nom (`FIELD`) |
| `enregistrement([alias])` | l'enregistrement courant sous forme de table |

### 17.8 Sécurité et identifiants

| Fonction | Rôle | Exemple de résultat |
| --- | --- | --- |
| `hachermdp(mdp)` | empreinte de mot de passe PBKDF2-SHA256 salée (120 000 itérations, environ 0,15 s) | `pbkdf2-sha256$120000$…` |
| `verifiermdp(mdp, empreinte)` | vérifie un mot de passe, à temps constant ; `faux` si l'empreinte est `nul` | `vrai` |
| `mdpaleatoire([n])` | mot de passe aléatoire de n caractères (16 par défaut, sans caractères ambigus) | `qjjRfByLZbbTRs3v` |
| `hachage(s)` | empreinte SHA-256 en hexadécimal (64 caractères) ; **pas pour les mots de passe** | `ba7816bf8f01cfea…` |
| `uuid()` | identifiant unique aléatoire (36 caractères) | `3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90` |

## 18. Erreurs courantes et dépannage

### 18.1 Où lire une erreur

Une erreur pendant une requête ne fait jamais tomber le serveur : la requête échoue, le fil d'exécution continue, et :

1. le **journal** (la console du serveur) affiche une ligne `500 <ip> <procédure> - <fichier>:<ligne> : <message>` ;
2. le **navigateur** reçoit une page "Erreur d'exécution". Le détail (fichier, ligne, message) n'y apparaît que pour les sessions qui ont `EDITION` dans `VALIDE`, ou si `"details_erreurs": true` est mis dans le fichier de configuration - jamais pour un visiteur ordinaire ;
3. une transaction laissée ouverte par la procédure est **annulée automatiquement**.

Pas à pas, pour trouver une erreur : connectez-vous avec un compte `EDITION`, reproduisez l'action, lisez le fichier et la ligne affichés, ouvrez-les dans `/EDIT`, corrigez, enregistrez, recommencez. Pas besoin de redémarrer : l'enregistrement d'un programme dans `/EDIT` recharge `PROG` (et signale ses erreurs de syntaxe), et une page modifiée est relue automatiquement.

### 18.2 Erreurs à la lecture du programme

| Message | Cause probable | Correction |
| --- | --- | --- |
| `instruction hors procédure (attendu : procedure NOM)` | du code au niveau du fichier, en dehors de toute procédure | placer le code dans une `procedure` ou une `fonction` |
| `'finsi' inattendu ici (bloc non ouvert ?)` | une fin de bloc de trop, ou un `si` mal écrit plus haut | compter les `si`/`finsi`, `pour`/`suivant`, `tantque`/`fintantque` |
| `'procedure' inattendu : procédure imbriquée ou bloc non fermé` | un bloc de la procédure précédente n'a pas été fermé | le message indique la ligne d'ouverture du bloc fautif |
| `'a' (ou 'jusqua') attendu dans 'pour'` | `pour i = 1 10` | `pour i = 1 a 10` |
| `',' ou '}' attendu dans la table au lieu de …` | virgule oubliée dans `{…}` | `{a = 1, b = 2}` |
| `expression attendue au lieu de …` | opérateur sans opérande, parenthèse en trop | relire l'expression de la ligne |
| `caractère inattendu : '…'` | caractère non reconnu (guillemet typographique `" "` ou `’` copié d'un traitement de texte) | utiliser `"` ou `'` droits |
| `balise <% non terminée` | page : `<%` sans `%>` | fermer la balise |
| `instruction inconnue ou incomplète` | faute de frappe dans un mot-clé | voir la liste des mots réservés en annexe |

### 18.3 Erreurs à l'exécution

| Message | Cause probable | Correction |
| --- | --- | --- |
| `procédure ou fonction inconnue : NOM` | nom mal orthographié, ou fichier `.prg` absent de `PROG` | vérifier le nom (les majuscules n'ont pas d'importance) |
| `appel impossible d'une valeur de type nul` | `t:methode()` alors que la méthode n'a pas été associée | `t:procedure NOM comme methode` avant l'appel |
| `indexation impossible d'une valeur de type nul` | `a.b.c` alors que `a.b` n'existe pas | tester `si a.b <> nul` ou initialiser `a.b = {}` |
| `'-' : nombre attendu, …` | calcul avec `nul` ou une chaîne non numérique (`+` avec une chaîne, lui, concatène) | convertir avec `valeur()` ; initialiser la variable |
| `'#' : table ou chaîne attendue` | `#x` sur un nombre ou `nul` | vérifier le type avec `type(x)` |
| `'pour chaque' : table attendue` | parcours d'une variable `nul` | initialiser la liste |
| `__index : chaîne de métatables trop longue (cycle ?)` | une métatable qui renvoie vers elle-même par `__index` | revoir l'héritage |
| `json : structure trop profonde (cycle ?)` | `json()` sur une table qui se contient | ne sérialiser que les données |
| `table inconnue : …` / `champ inconnu …` | nom de table ou de colonne erroné | `requete("describe produits")` pour voir les colonnes |
| `alias inconnu : …` | zone non ouverte par `utiliser` | ouvrir la zone, ou vérifier l'alias |
| `sql : …` | erreur DuckDB (syntaxe, contrainte, type) | lire la fin du message, qui vient de DuckDB |
| `sql : impossible de lier le paramètre N` | valeur non prise en charge passée en `?` (table, contenu binaire) | passer des nombres, chaînes, logiques ou `nul` |
| `page introuvable : …` | `envoyer` ou `inclure` d'une page absente de `PAGE` | vérifier le nom du fichier |
| `imbrication de pages trop profonde` | une page s'inclut elle-même | supprimer la boucle d'inclusion |

### 18.4 Réponses HTTP particulières

| Code | Signification | Que faire |
| --- | --- | --- |
| 403 | procédure demandée absente de `ACCEPTE` : la session est **supprimée** et l'IP notée dans les incidents | ajouter la procédure à `ACCEPTE` au bon moment (connexion, étape suivante) |
| 403 "en-tête X-WDG manquant" | appel `fetch` sans l'en-tête anti-falsification | ajouter `headers: {'X-WDG': '1'}` |
| 404 | fichier statique absent de `BLOB` | vérifier le chemin |
| 429 | trop de requêtes en attente pour une même session, ou trop d'essais de connexion | attendre ; éviter les doubles clics qui renvoient le formulaire |
| 500 | erreur d'exécution | voir 18.1 |
| 503 | serveur saturé (trop de sessions, file pleine) ou requête trop longue interrompue | réduire la durée du traitement, augmenter `fils` ou `dureeMax` |

### 18.5 Pièges fréquents

1. **Variable globale involontaire.** Une variable non déclarée devient une globale de la session et survit d'une requête à l'autre. Déclarez toujours avec `locale`.
2. **Clefs en majuscules.** `t.nom` et `t.NOM` désignent la même clef ; mais `t["nom"]` est une clef exacte, différente. Les lignes de `requete` et `dejson` ont des clefs en majuscules.
3. **`0` est vrai.** Seuls `nul` et `faux` sont faux dans un `si`. Pour tester "vide", utilisez `vide(x)`.
4. **Oublier `ACCEPTE`.** Après une connexion réussie, la nouvelle liste d'actions autorisées doit être écrite dans `ACCEPTE`, sinon le premier clic renvoie 403 et ferme la session.
5. **Concaténer une table.** `__tostring` ne suffit pas pour `..` : ajoutez `__concat` ou appelez `texte(t)`.
6. **Échapper l'affichage.** `<%= %>` échappe le HTML ; n'insérez du HTML brut que s'il vient de vous, jamais d'une saisie.
7. **Construire du SQL par concaténation.** Toujours des paramètres `?` avec `avec`.
8. **Nombres saisis à la française.** `valeur("12,5")` vaut `12.5`, mais `"1 234,50"` ou `"1.234,5"` donnent `0` : nettoyez la saisie (`remplacertexte(s, " ", "")`).

## 19. Annexes

### 19.1 Mots réservés

Ces mots ont un sens pour Lexis+ et ne peuvent pas servir de nom de variable :

`a`, `ajouter`, `alias`, `aller`, `autrement`, `avec`, `bas`, `boucler`, `capturer`, `cas`, `chaque`, `chercher`, `cle`, `clef`, `comme`, `compter`, `continuer`, `dans`, `de`, `debut`, `deconnecter`, `du`, `effacer`, `entete`, `envoyer`, `erreur`, `essayer`, `et`, `faire`, `faux`, `fermer`, `filtre`, `fin`, `fincas`, `finessayer`, `finfonction`, `finparcourir`, `finpour`, `finprocedure`, `finsi`, `fintantque`, `fonction`, `globale`, `haut`, `inclure`, `inserer`, `jusqua`, `liberer`, `local`, `locale`, `localiser`, `non`, `nouvelle`, `nul`, `ordre`, `ou`, `par`, `parametres`, `parcourir`, `pas`, `position`, `pour`, `procedure`, `rafraichir`, `rediriger`, `remplacer`, `retirer`, `retour`, `retourner`, `sauter`, `selectionner`, `si`, `sinon`, `sinonsi`, `sortir`, `sql`, `statut`, `stocker`, `suivant`, `supprimer`, `tantque`, `tout`, `utiliser`, `vide`, `vrai`.

Équivalences acceptées : `à` = `a` ; `.v.`, `.t.` = `vrai` ; `.f.` = `faux` ; `.et.`, `.ou.`, `.non.` et `and`, `or`, `not` = `et`, `ou`, `non`.

### 19.2 Correspondances dBase

| dBase | Lexis+ |
| --- | --- |
| `USE clients` | `utiliser clients` |
| `SELECT clients` | `selectionner clients` |
| `GO TOP` / `GO BOTTOM` | `aller haut` / `aller bas` |
| `SKIP` | `sauter` |
| `SEEK` / `LOCATE FOR` | `chercher` / `localiser pour` |
| `REPLACE nom WITH x` | `remplacer nom par x` |
| `APPEND BLANK` | `ajouter vide` |
| `DELETE` | `supprimer` |
| `SET FILTER TO` / `SET ORDER TO` | `filtre` / `ordre` |
| `EOF()`, `BOF()`, `RECNO()`, `FOUND()` | `fdf()`, `ddf()`, `numenr()`, `trouve()` |
| `DO WHILE … ENDDO` | `tantque … fintantque` |
| `IF … ELSE … ENDIF` | `si … sinon … finsi` |
| `DO CASE … CASE … OTHERWISE … ENDCASE` | `faire cas … cas … autrement … fincas` |
| `FOR … NEXT` | `pour … suivant` |
| `SCAN … ENDSCAN` | `parcourir … finparcourir` |
| `PROCEDURE` / `FUNCTION` | `procedure` / `fonction` |
| `PUBLIC` / `LOCAL` | `globale` / `locale` |
| `STORE x TO v` | `stocker x dans v` |
| `&&` commentaire | `&&` commentaire |
| `SUBSTR`, `AT`, `ALLTRIM`, `STR`, `VAL`, `IIF`, `EMPTY` | `souschaine`, `position`, `rogner`, `chaine`, `valeur`, `sisinon`, `vide` |
| fichiers `.DBF` | tables SQL DuckDB |

### 19.3 Correspondances Lua

| Lua | Lexis+ |
| --- | --- |
| `nil`, `true`, `false` | `nul`, `vrai`, `faux` |
| `{}` | `{}` |
| `#t` | `#t` |
| `table.insert` / `table.remove` | `inserer … dans` / `retirer de` |
| `table.concat` / `table.sort` | `joindre` / `trier` |
| `setmetatable` / `getmetatable` | `fixermetatable` / `obtenirmetatable` |
| `rawget` / `rawset` | `lirebrut` / `ecrirebrut` |
| `for k, v in pairs(t)` | `pour chaque k, v dans t … suivant` |
| `obj:methode()` | `obj:methode()` |
| `function t:m()` | `t:procedure NOM comme m` (la table est le premier argument) |
| `pcall` | `essayer … capturer … finessayer` |
| métaméthodes `__index`, `__newindex`, `__len`, `__concat`, `__eq`, `__lt`, `__add`… | identiques |

### 19.4 Glossaire

- **ACCEPTE** : variable de session, liste séparée par des virgules des procédures que le navigateur a le droit d'appeler.
- **BLOB** : dossier des fichiers statiques (images, CSS, scripts) servis tels quels.
- **Incident** : appel d'une procédure non autorisée ; l'IP est enregistrée avec la date du premier et du dernier incident et leur nombre.
- **Métatable** : table qui décrit le comportement d'une autre table (opérateurs, valeurs par défaut).
- **Page** : fichier de `PAGE` mélangeant HTML et balises `<% %>`.
- **Session** : mémoire propre à un visiteur, conservée entre ses requêtes ; ses variables globales sont rangées dans `SESSION`.
- **VALIDE** : variable de session, liste des droits (`CONNEXION`, `EDITION`, `SUIVI`…).
- **Zone** : table SQL ouverte par `utiliser`, avec un enregistrement courant, à la manière d'un fichier dBase.

### 19.5 Mentions légales

**Lexis+** - *Développez naturellement vos applications métier*

© 2026 Jean‑Marc QUÉRÉ, sonaliwan.fr
SIRET : 130333198000013

Distribué sous licence CC BY‑NC‑SA 4.0

Les utilisations commerciales ne sont pas couvertes par cette licence.
Pour obtenir une autorisation d'utilisation commerciale,
contactez l'auteur.

Contact : metalab (at) sonaliwan.fr
