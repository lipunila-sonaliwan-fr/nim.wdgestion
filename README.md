Lexis+ &
wdGestion V/FR - serveur web intégrant l'interpréteur Lexis+ sur DuckDB<br/>
© 2026 Jean‑Marc "jihem"Quéré, sonaliwan.fr<br/>
SIRET 130333198000013<br/>
Distribué sous licence CC BY‑NC‑SA 4.0.<br/>

Les utilisations commerciales ne sont pas couvertes par cette licence.<br/>
Pour obtenir une autorisation d'utilisation commerciale,<br/>
contactez l'auteur : metalab (at) sonaliwan.fr.<br/>

# wdGestion V/FR — serveur web à interpréteur Lexis+ sur DuckDB

Le serveur web **wdGestion V** écrit en Nim exécute **Lexis+**, un langage orienté données et applications **aux instructions françaises**.
Les données sont stockées dans des **tables SQL DuckDB** (via la bibliothèque `sonaliwan/duckdb` de [duQuack](https://github.com/lipunila-sonaliwan-fr/nim.duckdb)),
le langage est enrichi d'un type **table** (avec métatables) similaire à celui de Lua, et les pages HTML sont générées à la volée
à partir de balises `<% %>` à la manière des pages JSP de Java.

```
wdgestionv/
├── wdgestionv            exécutable (après compilation)
├── wdgestionv.json       configuration (même nom que l'exécutable, dossier courant)
├── wdgestionv.duckdb     base de données (créée au besoin)
├── linOS/ macOS/ winOS/   bibliothèques DuckDB (comme pour duQuack)
├── PROG/             sources des procédures (*.prg, plusieurs procédures par fichier)
├── PAGE/             pages à balises <% %>
├── BLOB/             fichiers statiques (seul dossier servi tel quel)
├── src/              sources Nim
└── tests/            tests du langage (t_langage.nim) et tests HTTP (e2e.sh)
```

## Compilation et lancement

```sh
nimble build          # ou : nim c -d:release -o:wdgestionv src/wdgestionv.nim
./wdgestionv          # à lancer depuis le dossier contenant PROG, PAGE et BLOB
nimble test           # langage, hachage des mots de passe, fuites du parseur
nimble banc           # multitâche : concurrence, fuites, charge, arrêt propre
./wdgestionv > wdgestionv.log & tests/e2e.sh http://127.0.0.1:8080 wdgestionv.log   # tests HTTP (base neuve)
```

Testé avec Nim 2.2.4 et 2.2.10 et DuckDB 1.5.5. `config.nims` fixe les options indispensables :
`--threads:on --mm:atomicArc -d:useMalloc` (voir « Architecture multitâche »).

**Arrêt** : `Ctrl+C` dans le terminal, ou le signal `SIGTERM` (`kill`, `pkill -x wdgestionv`, `systemctl stop`).
Dans les deux cas l'arrêt est propre : plus de nouvelles connexions, fin des requêtes en cours (au plus
`duree_max_secondes`), fils rejoints, sessions démolies, connexions DuckDB puis base fermées. Le journal se termine
par `Tables restantes : 0 · base fermée.`

Comme pour duQuack, la bibliothèque DuckDB est cherchée dans `./linOS/libduckdb.so`, `./macOS/libduckdb.dylib`
ou `./winOS/libduckdb.dll` (relativement au dossier courant). L'en-tête `src/duckdb.h` est utilisé à la compilation
(`config.nims` ajoute `src` au chemin d'inclusion C).

Au démarrage le serveur :

1. lit `<nom de l'exécutable>.json` dans le dossier courant (valeurs par défaut s'il est absent) ;
2. **s'arrête** si `PROG`, `PAGE` ou le dossier statique (`BLOB`) n'existe pas ;
3. ouvre la base DuckDB et crée la table `incidents` si besoin ;
4. compile toutes les procédures de `PROG` (récursivement) — **s'arrête** en cas d'erreur de syntaxe
   ou si la procédure `CONNEXION` n'existe pas ;
5. exécute la procédure `DEMARRAGE` si elle existe (création de tables, données initiales…) ;
6. **verrouille DuckDB** : le SQL ne peut plus accéder au système de fichiers (voir Sécurité) ;
7. écoute sur chaque adresse configurée.

### Configuration (`wdgestionv.json`)

| Clef | Défaut | Rôle |
|---|---|---|
| `adresses` | `["127.0.0.1"]` | adresses d'écoute ; `"ip:port"` ou `"[::1]:port"` pour un port propre |
| `port` | `8080` | port par défaut |
| `statique` | `BLOB` | dossier des fichiers statiques (relatif au dossier courant) |
| `base` | `<nom>.duckdb` | fichier DuckDB (ou `:memory:`) |
| `expiration_minutes` | `30` | inactivité avant suppression d'une session |
| `taille_max_corps` | `16777216` | taille maximale d'une requête (octets) |
| `instructions_max` | `5000000` | instructions maximum par requête (protège des boucles infinies) |
| `cookie_securise` | `false` | ajoute `Secure` au cookie (HTTPS en frontal) |
| `details_erreurs` | `false` | montre le détail des erreurs à tous (sinon : sessions EDITION seulement) |
| `cdn_codemirror` | cdnjs 5.65.16 | base des fichiers CodeMirror de l'éditeur (pour un serveur hors ligne) |
| `connexion_essais_max` | `10` | requêtes POST non connectées (tentatives) par IP avant blocage |
| `connexion_blocage_minutes` | `15` | fenêtre de comptage et durée du blocage (réponse 429) |
| `sessions_anonymes_par_ip` | `20` | sessions non connectées conservées par IP (les plus anciennes sont oubliées) |
| `sessions_max` | `10000` | sessions au total (503 si le serveur est plein de sessions connectées) |
| `acces_fichiers_sql` | `false` | `true` laisse le SQL lire/écrire des fichiers après `DEMARRAGE` (déconseillé) |
| `proxies_de_confiance` | `[]` | adresses des mandataires dont on accepte `X-Forwarded-For` |
| `fils` | `16` | fils d'exécution : nombre de requêtes traitées en parallèle |
| `duree_max_secondes` | `30` | durée maximale d'une requête : le code est arrêté, le SQL interrompu (`0` = illimitée) |
| `connexions_par_ip` | `64` | connexions TCP simultanées par adresse (au-delà : 503) |

`expiration_minutes` se règle aussi depuis l'écran `/SUIVI` (la valeur est alors réécrite dans le fichier).

## Sessions, droits et routage

* Chaque navigateur reçoit un cookie `WDG_SESSION` (128 bits aléatoires, `HttpOnly`, `SameSite=Lax`).
  Chaque session possède son **propre espace mémoire** : la table `SESSION` (ses variables globales)
  et ses propres zones de travail.
* **Session par défaut** : en l'absence de session active, une session `{VALIDE = "CONNEXION"}` est créée.
  Tant que `VALIDE` vaut `"CONNEXION"`, **toute requête appelle la procédure `CONNEXION`**.
  Dès que `CONNEXION` modifie `VALIDE`, la session devient active et reçoit un **nouvel identifiant**
  (protection contre la fixation de session).
* **Session active** : l'URL `/NOM` appelle la procédure `NOM` si et seulement si `NOM` figure dans la liste CSV
  `SESSION.ACCEPTE` (insensible à la casse). `/` appelle la première procédure de `ACCEPTE`.
* **Procédure non listée** → réponse **403**, la session est **supprimée** et l'IP est enregistrée dans la table
  `incidents (ip, premier, dernier, nombre)` (date/heure du premier et du dernier incident, nombre d'incidents).
* Les chemins qui ne sont pas des noms de procédure valides (`/favicon.ico`, `/a/b`…) et qui ne correspondent
  à aucun fichier de `BLOB` renvoient 404 sans pénalité.
* **Fichiers statiques** : seuls les fichiers du dossier `BLOB` sont servis (`/style.css` → `BLOB/style.css`).
  Toute tentative de sortie (`..`, liens symboliques) est refusée.
* **`/EDIT`** : éditeur intégré, accessible uniquement si `SESSION.VALIDE` (CSV) contient `EDITION` —
  sinon même traitement qu'une procédure non autorisée (403, session supprimée, incident).
* **`/SUIVI`** : écran de suivi (sessions, charge, mesures), accessible uniquement si `SESSION.VALIDE` contient
  `SUIVI` — même traitement sinon.

### Appel d'une procédure depuis le navigateur

Les **paramètres** de la procédure reçoivent les champs GET/POST de même nom (insensible à la casse) ;
les champs absents valent `nul`. La variable locale `REQUETE` décrit la requête :

| Clef | Contenu |
|---|---|
| `REQUETE.METHODE` | `"GET"` ou `"POST"` |
| `REQUETE.CHEMIN`, `REQUETE.REQUETE` | chemin et chaîne de requête |
| `REQUETE.IP` | adresse du client |
| `REQUETE.PARAMS` | table de tous les champs (clefs en MAJUSCULES ; champ répété → table de valeurs) |
| `REQUETE.ENTETES`, `REQUETE.COOKIES` | en-têtes et cookies |

Formulaires `x-www-form-urlencoded`, `multipart/form-data` (un fichier envoyé devient une table
`{NOM, TYPE, TAILLE, CONTENU}`) et corps JSON sont décodés.

```
procedure CONNEXION(nom, mdp)
  locale message = ""
  si REQUETE.METHODE = "POST"
    sql "select mdp, droits, accepte from utilisateurs where nom = ?" avec nom dans r
    si verifiermdp(mdp, sisinon(#r = 1, r[1].MDP, nul))
      SESSION.UTILISATEUR = nom
      SESSION.ACCEPTE = r[1].ACCEPTE       && ex. "ACCUEIL,CADDIE,DECONNEXION"
      SESSION.VALIDE = r[1].DROITS         && ex. "UTILISATEUR,EDITION"
      rediriger "/ACCUEIL"
      retourner
    finsi
    message = "Identifiant ou mot de passe incorrect."
  finsi
  envoyer connexion avec message = message
retourner
```

## Le langage

### Généralités

* Les **instructions** s'écrivent en **minuscules**. Les **identifiants** (variables, procédures, champs, clefs
  `t.nom`) sont insensibles à la casse : ils sont normalisés en MAJUSCULES (`t.nom` ≡ `t["NOM"]`).
* Une instruction par ligne ; `;` en fin de ligne = continuation (dBase) ; `;` au milieu = séparateur.
* Commentaires : `*` en début d'instruction, `&&` ou `//` jusqu'à la fin de ligne ; `<%-- … --%>` dans les pages.
* Chaînes : `"…"` ou `'…'` (échappements `\n \t \" \' \\`), ou `[[ … ]]` sur plusieurs lignes (pratique pour SQL).
* Valeurs : `nul`, logiques (`vrai`/`faux`, `.v.`/`.f.`/`.t.`), nombres, chaînes, **tables**, procédures.
  Comme en Lua, seuls `nul` et `faux` sont faux dans un test.
* Les dates sont manipulées comme chaînes ISO (`"2026-10-09"`) ; DuckDB les convertit.

### Portée des variables

| Lecture d'un identifiant | Ordre de recherche |
|---|---|
| `x` | variable locale → champ de la zone courante → `SESSION.X` → procédure `X` → `nul` |
| `m->x` | variable mémoire uniquement (ignore les champs, comme en dBase) |
| `alias->champ` | champ d'une zone de travail donnée |

Une affectation `x = …` modifie la locale `x` si elle existe, sinon **la variable globale de session**
`SESSION.X`. Les paramètres, `locale`, les variables de boucle et les arguments de page sont locaux.

> **Attention** : comme en Lua, une variable non déclarée est globale, donc conservée dans la session.
> `sql "…" dans r` sans `locale r` range le résultat dans `SESSION.R` jusqu'à la fin de la session.
> L'écran `/SUIVI` (contenu d'une session) permet de repérer ces oublis.

### Opérateurs (priorité croissante)

| Opérateurs | |
|---|---|
| `ou` `.ou.` | ou logique (court-circuit, renvoie l'opérande comme en Lua) |
| `et` `.et.` | et logique |
| `non` `.non.` | négation |
| `=` `==` `<>` `!=` `#` `<` `>` `<=` `>=` `$` | comparaisons ; `a $ b` : `a` est contenu dans `b` |
| `..` | concaténation |
| `+` `-` | addition ; `+` concatène si un opérande est une chaîne |
| `*` `/` `%` | `%` modulo (au sens de Lua) |
| `-x` `#x` | opposé ; `#` longueur (chaîne ou table, métaméthode `__len`) |
| `^` `**` | puissance (associative à droite) |
| `.` `[]` `()` `:` `->` | champ de table, indice, appel, appel de méthode, champ d'alias |

`x += e` et `x -= e` sont acceptés. `sisinon(cond, a, b)` n'évalue que la branche choisie.

### Instructions de contrôle

```
si cond                     faire tantque cond (ou : tantque cond)
  …                           …   sortir / boucler
sinonsi cond                fintantque
  …
sinon                       pour i = 1 a 10 pas 2     (a, à ou jusqua)
  …                           …
finsi                       suivant                   (ou finpour)

faire cas                   pour chaque v dans t      && valeurs
  cas x = 1                 pour chaque k, v dans t   && clefs et valeurs
    …                         …
  autrement                 suivant
    …
fincas                      essayer
                              …
                            capturer msg
                              …
                            finessayer
```

`erreur "message"` déclenche une erreur (capturable par `essayer`). La limite d'instructions ne l'est pas.

### Procédures et fonctions

```
procedure NOM(a, b)            && ou :  procedure NOM  puis  parametres a, b
  locale x = 1, y              && variables locales
  globale Z = 3                && écrit explicitement SESSION.Z
  stocker 0 dans u, v          && STORE
  liberer u                    && RELEASE
retourner a + b                && retourner (ou retour) [valeur]

fonction CARRE(n)              && synonyme de procedure
retourner n * n
```

`finprocedure` / `finfonction` sont facultatifs. Appels : `faire NOM avec 1, 2`, `NOM(1, 2)`,
`appeler(@NOM, 1, 2)`. `@NOM` est une référence explicite à une procédure (valeur de type `procedure`).

### Tables (type table de Lua)

| Instruction | Effet |
|---|---|
| `nouvelle table t` | crée une table vide dans `t` (`nouvelle table t = {…}` pour l'initialiser) |
| `supprimer table t` | supprime la table / la variable `t` |
| `inserer v dans t` | ajoute `v` à la fin (`table.insert`) |
| `inserer v dans t position 2` | insère en position 2 (décale la suite) |
| `inserer v dans t clef "nom"` | `t["nom"] = v` |
| `retirer de t` | retire le dernier élément (`table.remove`) |
| `retirer de t position 1 dans x` | retire l'élément 1 et le range dans `x` |
| `retirer de t clef "nom"` | supprime la clef |
| `t:procedure NOM [comme clef]` | associe la procédure `NOM` à la table (clef `NOM` ou `clef`) |
| `fixermetatable t, mt` | `setmetatable` (aussi en fonction : `fixermetatable(t, mt)` renvoie `t`) |

Constructeur : `{1, 2, nom = "x", [clef] = v}` ; accès `t.nom`, `t[1]`, `t["clef libre"]` ; indices à partir de 1.

**Méthodes** : une procédure associée par `t:procedure NOM comme m` s'appelle `t:m(x)` et reçoit **la table
elle-même en premier argument** (`procedure NOM(soi, x)`). `t.m(x)` l'appelle sans la table.

**Métaméthodes** reconnues (clefs de la métatable) : `__index` (table ou procédure), `__newindex`, `__call`,
`__tostring`, `__len`, `__eq`, `__lt`, `__le`, `__add`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`,
`__unm`, `__concat`.

```
nouvelle table Vecteur
Vecteur.__index = Vecteur
Vecteur.__add = @VADD
Vecteur:procedure VNORME comme norme

fonction VNOUVEAU(x, y)
  locale v = {x = x, y = y}
  fixermetatable v, Vecteur
retourner v

procedure VNORME(soi)
retourner racine(soi.x ^ 2 + soi.y ^ 2)
```

Fonctions sur les tables : `taille(t)` (`#t`), `nbelements(t)`, `clefs(t)`, `valeurs(t)`, `aclef(t, k)`,
`copier(t)`, `contient(t, v)`, `joindre(t, sep)`, `trier(t [, @PLUSPETIT])`, `inserer(t, v [, pos])`,
`retirer(t [, pos])`, `lirebrut(t, k)`, `ecrirebrut(t, k, v)`, `obtenirmetatable(t)`, `json(v)`, `dejson(s)`.

### Base de données : SQL direct

```
sql "create table clients (id integer primary key, nom varchar, age integer)"
sql "insert into clients values (?, ?, ?)" avec 1, "Dupont", 33     && requête préparée
sql "select * from clients where age > ?" avec 18 dans liste       && table de lignes
? liste[1].NOM                                                       && colonnes en MAJUSCULES
x = valeursql("select count(*) from clients")                        && première valeur
l = requete("select * from clients where nom = ?", n)               && forme fonction
```

Les paramètres `?` passent par des requêtes préparées (pas d'injection SQL).

### Base de données : zones de travail (DBF → table SQL)

| dBase | wdGestion V/FR |
|---|---|
| `USE t ALIAS a ORDER x` | `utiliser t [alias a] [ordre "col"] [filtre "condition SQL"]` |
| `SELECT a` / `USE` / `CLOSE ALL` | `selectionner a` / `fermer [a]` / `fermer tout` |
| `GO TOP / BOTTOM / n`, `SKIP n` | `aller haut` / `aller bas` / `aller n`, `sauter [n]` |
| `APPEND BLANK` + `REPLACE` | `ajouter [vide]` ou `ajouter champ par v, …` ; `remplacer champ par v, …` |
| `DELETE` | `effacer` (suppression immédiate de la ligne SQL) |
| `LOCATE FOR` / `CONTINUE` | `localiser pour cond` / `continuer` |
| `SEEK` | `chercher valeur` (sur la première colonne de `ordre`) |
| `SCAN FOR … ENDSCAN` | `parcourir [pour cond] … finparcourir` |
| `COUNT FOR … TO v` | `compter [pour cond] dans v` |
| — | `rafraichir` (relit la liste des enregistrements) |
| `EOF() BOF() RECNO() RECCOUNT() FOUND()` | `fdf() ddf() numenr() nbenr() trouve()` (alias facultatif) |
| `FIELD()` | `champ("nom" [, alias])`, `enregistrement([alias])` → table |

Les champs de l'enregistrement courant se lisent directement (`nom`, `clients->nom`).
L'enregistrement est repéré par la clé primaire de la table (si elle est unique), sinon par `rowid` :
une clé primaire est recommandée. `ajouter` place l'enregistrement en fin de liste ; `rafraichir` réapplique l'ordre.

### Pages

Les pages de `PAGE/` (`.html`, `.htm`, `.page` ou sans extension) mêlent HTML et code :

| Balise | Effet |
|---|---|
| `<% instructions %>` | code wdGestion (les blocs `si`, `pour`, `parcourir`… peuvent enjamber du HTML) |
| `<%= expression %>` | valeur **échappée HTML** |
| `<%== expression %>` | valeur brute |
| `<%-- commentaire --%>` | ignoré |

```
envoyer accueil avec titre = "Catalogue", liste = t     && envoie PAGE/accueil.html
inclure entete avec titre = titre                        && synonyme, dans une page
```

Une page voit les **variables de session** et les **arguments transmis** par `envoyer` (variables locales de la
page), ainsi que les champs de la zone courante. Les pages sont recompilées automatiquement quand elles changent.

Autres sorties : `? a, b` (écrit avec retour à la ligne), `?? a` (sans), `rediriger "/URL"`, `statut 404`,
`entete "Content-Type", "application/json"`, `deconnecter` (supprime la session).

### Fonctions intégrées

* **Chaînes** : `majuscule minuscule rogner rognerg rognerd longueur souschaine(s, début [, n]) gauche droite
  position(sous, s) chaine(n [, largeur, décimales]) texte valeur nombre espace repliquer remplacertexte
  contient commencepar finitpar decouper(s, sep) joindre html url`
* **Nombres** : `abs entier arrondi(n [, déc]) racine mod max min aleatoire([n])`
* **Divers** : `type(v)` (`"nul" "logique" "nombre" "chaine" "table" "procedure"`), `vide estnul sisinon
  date heure maintenant horodatage hachage(s)` (SHA-256 simple, **pas pour les mots de passe**) `uuid appeler`
* **Mots de passe** : `hachermdp(mdp)` (PBKDF2-HMAC-SHA256 salé, 120 000 itérations),
  `verifiermdp(mdp, empreinte)` (comparaison à temps constant ; calcule quand même si l'empreinte est `nul`),
  `mdpaleatoire([longueur])`
* **SQL / zones** : `requete valeursql fdf ddf numenr nbenr trouve alias champ enregistrement`

## L'éditeur `/EDIT`

Éditeur CodeMirror (coloration wdGestion V/FR, HTML + balises `<% %>`, CSS, JS) avec arborescence de `BLOB`, `PAGE`
et `PROG` : ouvrir, créer, renommer, supprimer, créer des dossiers, téléverser (images prévisualisées).
`Ctrl+S` enregistre ; la syntaxe est vérifiée pendant la frappe et les erreurs sont listées (cliquables) dans la console.
Enregistrer un fichier de `PROG` recompile toutes les procédures **à chaud** ; en cas d'erreur, ou si `CONNEXION`
disparaît, l'ancienne version reste active. L'API n'accepte que les requêtes portant l'en-tête `X-WDG: 1`
(protection CSRF) et ne peut accéder qu'à `BLOB`, `PAGE` et `PROG`.

Sans accès au CDN, l'éditeur bascule sur une zone de texte simple ; pour un serveur hors ligne, copiez CodeMirror
5.65.16 (même arborescence que cdnjs, fichiers `.min.js`) dans `BLOB/codemirror` et indiquez
`"cdn_codemirror": "/codemirror"`.

## Sécurité

Protections assurées par le serveur, quel que soit le code des procédures :

| Menace | Protection |
|---|---|
| Vol ou devinette de session | cookie de 128 bits aléatoires, `HttpOnly`, `SameSite=Lax` ; nouvel identifiant à la connexion |
| Force brute sur le mot de passe | au-delà de `connexion_essais_max` POST non connectés par IP : 429 pendant `connexion_blocage_minutes`, IP inscrite dans `incidents` |
| Procédure non autorisée, `/EDIT` sans EDITION | 403, session supprimée, IP inscrite dans `incidents` |
| Sortie du dossier statique | chemins `..` et liens symboliques sortant de `BLOB` refusés |
| SQL qui lit ou écrit des fichiers du serveur (`read_csv`, `COPY`, `ATTACH`, `INSTALL`…) | DuckDB verrouillé après `DEMARRAGE` (`enable_external_access = false`, `lock_configuration = true`) : même un compte EDITION compromis ne peut pas atteindre le disque |
| Saturation mémoire par création de sessions | `sessions_anonymes_par_ip`, `sessions_max` |
| Boucle infinie / récursion | `instructions_max`, profondeur d'appel limitée |
| Attaque de l'éditeur depuis un autre site | en-tête `X-WDG` obligatoire pour l'API |

Ce qui reste à la charge du code wdGestion :

* **Mots de passe** : `hachermdp` / `verifiermdp`, jamais `hachage` (trop rapide) ni le texte en clair.
* **SQL** : toujours des paramètres `?` (`sql "… where nom = ?" avec nom`) ; ne jamais concaténer une saisie
  dans `sql`, `requete`, `ordre` ou `filtre`.
* **HTML** : afficher les saisies avec `<%= %>` (échappé) ; `?`, `??` et `<%== %>` écrivent brut.
* **Actions** : modifier les données en réponse à un POST, pas à un lien GET (le cookie `SameSite=Lax` empêche
  alors un autre site de déclencher l'action).
* **Droits** : `ACCEPTE` ne doit lister que le strict nécessaire ; `EDITION` revient à pouvoir modifier tout le site.

**HTTPS** : le serveur parle HTTP. Hors de `127.0.0.1`, placez-le derrière un mandataire HTTPS et activez
`cookie_securise` (cookie `Secure` + en-tête HSTS). Exemple avec Caddy (certificat automatique) :

```
mon-site.fr {
    reverse_proxy 127.0.0.1:8080
}
```

et dans `wdgestionv.json` : `"cookie_securise": true, "proxies_de_confiance": ["127.0.0.1"]`
(sinon toutes les requêtes semblent venir du mandataire et partagent la même limite d'essais).
Le serveur affiche un avertissement s'il écoute hors boucle locale sans `cookie_securise`.

## Architecture multitâche et ressources

**Fils d'exécution.** Le serveur HTTP/1.1 (keep-alive) répartit les requêtes sur `fils` fils de travail :
un traitement long dans une session n'empêche pas les autres utilisateurs de travailler. Un fil de veille
(epoll/kqueue) surveille les connexions inactives : elles n'occupent aucun fil de travail. Les fichiers
statiques sont servis sans session.

**Sessions.** Une session n'est utilisée que par une requête à la fois : deux requêtes simultanées d'un même
navigateur s'exécutent l'une après l'autre (au plus 4 en attente, au-delà : 429), sans perte de mise à jour de
`SESSION`. Deux sessions différentes s'exécutent en parallèle.

**Base.** Une connexion DuckDB par fil (ouverte à la première requête du fil, fermée à sa fin) sur une même base.
Un chien de garde interrompt le SQL d'une requête qui dépasse `duree_max_secondes` ; l'interpréteur s'arrête
de lui-même à la même échéance.

**Mémoire.** Le programme est compilé en comptage de références atomique (`--mm:atomicArc`), indispensable pour
partager des objets entre fils. Ce mode ne libère pas seul les cycles, or les tables façon Lua en forment
volontiers (`t.__index = t`). Chaque session tient donc un registre de ses tables : à la fin de chaque requête,
celles qui ne sont plus accessibles depuis `SESSION` sont démolies (cycles compris) ; à la fermeture d'une
session, toutes ses tables le sont. Un compteur exact des tables vivantes est affiché dans `/SUIVI` et à l'arrêt.

Le banc `tests/concurrence.py` vérifie tout cela : traitement long et caddie d'un autre utilisateur en parallèle,
sérialisation dans une session, interruption du SQL, récursion dans un fil, 74 000 tables cycliques libérées,
mémoire stable, charge (≈ 5 000 requêtes/s en local), arrêt propre sans table restante.

*Pour qui modifie les sources Nim* : en `--mm:atomicArc` (Nim 2.2.4 à 2.2.10 au moins), une valeur déjà placée
dans `result`, ou un objet `ref` dont un champ est en cours de calcul, n'est pas libéré si une exception sort de
la procédure. Le code construit donc ses résultats dans des variables locales et calcule les valeurs avant de
construire les objets (`tests/t_fuites_parseur.nim` le vérifie pour le parseur).

## Écran de suivi `/SUIVI`

Réservé aux sessions dont `VALIDE` contient `SUIVI` (le compte `admin` de l'exemple). Rafraîchi toutes les 5 s.

| Onglet | Contenu |
|---|---|
| **Charge** | processeur (% et cumul utilisateur/système), temps passé en base (total, part du temps, erreurs), mémoire résidente et tables vivantes, trafic réseau reçu/envoyé et débit, requêtes et req/s, fils occupés, connexions, sessions, durée de fonctionnement, taille de la base ; remise à zéro des mesures |
| **Sessions** | utilisateur, IP, état (anonyme, connectée, procédure en cours et depuis quand), durée depuis l'ouverture, durée d'inactivité, nombre de requêtes, tables ; **consulter** le contenu d'une session (arbre de la table `SESSION`, métatables, cycles signalés, zones de travail) ; **fermer** une session ; **fermer toutes les sessions inactives depuis plus de N minutes** ; **durée maximale d'inactivité** (appliquée et enregistrée) |
| **Procédures** | par procédure (appels du navigateur, `/EDIT`, `/SUIVI`) : nombre d'appels, durée min, max, moyenne, total ; les **100 exécutions les plus lentes** (date, utilisateur, IP, statut) |
| **Requêtes SQL** | temps total, nombre, moyenne, erreurs ; les **100 requêtes les plus longues** (texte, date, procédure et utilisateur appelants) |
| **Fichiers statiques** | par fichier : nombre d'envois, durée min, max, moyenne, volume envoyé |

Les tableaux se trient en cliquant sur les en-têtes. Les identifiants affichés sont publics : ils ne permettent pas
de reprendre la session d'un utilisateur. Les mesures sont gardées en mémoire (remises à zéro au redémarrage).

## Application exemple

`PROG/` et `PAGE/` contiennent une petite boutique : connexion, catalogue parcouru par une zone de travail,
caddie en table Lua munie de méthodes et d'une métatable, gestion des produits (`ajouter`, `chercher`,
`remplacer`, `effacer`) et consultation des incidents.

Au premier lancement, `DEMARRAGE` crée les comptes `admin` (EDITION et SUIVI) et `demo` avec des **mots de passe
aléatoires affichés une seule fois dans la console**. Ils sont provisoires : à la première connexion, la session
n'autorise que `MOTDEPASSE` (`VALIDE = "CHANGEMENT"`) jusqu'au choix d'un nouveau mot de passe de 12 caractères
au moins. Pour repartir de zéro, supprimez `wdgestionv.duckdb`.

## Licence

Ce projet utilise la bibliothèque `sonaliwan/duckdb` de duQuack (CC BY-NC-SA 4.0, Jean-Marc « jihem » Quéré)
et DuckDB (licence MIT, Stichting DuckDB Foundation). Voir `LICENCE.md`.
