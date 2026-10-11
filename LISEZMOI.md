# Nim

## Présentation (rapide)
Nim est un langage compilé performant, doté d’un système de types moderne, d’une métaprogrammation avancée et d’une compilation vers C/C++/ObjC/JS pour produire des binaires rapides et portables. Il combine la simplicité de Python, la vitesse du C, la sécurité de Rust et la puissance des macros pour créer des applications efficaces et élégantes.

## Plateformes supportées
**Officiellement par l´équipe de développement :**
- Linux (binaire natif \[1\])
- masOS (binaire natif \[1\])
- Windows (binaire natif \[1\])
- JS (source => testé avec NodeJS \[2\])

> 1 - Binaires de (très) petite taille, totalement autonomes avec possibilité d'extension FFI (pour accéder à l'ensemble des librairies compatibles avec C ex. SQLite, SDL2, etc.). De très nombreux packages sont disponibles pour couvrir les besoins usuels (via FFI ou en pure Nim).

> 2 - Testé avec succès pour des micro-services. Finalement ceux-ci ont été déployés en pure Nim car les couches réseau de Nim se sont avérées plus efficaces (rapides et moins consommatrices en mémoire) que NodeJS (dont le heap s'autorise à consommer jusqu'à 4Gio par défaut). Testé également avec succès pour faire la jonction avec du code Gleam (transpilé vers JS et non Erlang) avec NodeJS comme hôte. 

**Officieusement par la communauté :**
- AIX (non testé, pas d'accès à un système IBM Power)
- DragonFlyBSD (non testé)
- FreeBSD (totalement fonctionnel)
- Haiku (BeOS redéveloppé à partie de zèro et mis à jour pour les systèmes actuels. Testè avec succès sur un ThinkPad L13. stable : interface, usb, wifi, son, etc. Compatible avec les binaires BeOS d'origines, nim fonctionnel. Doit être compilé à partir des sources et requiert la mise ne place du contexte Haiku dans certains packages : Haiku n'est pas totalement POSIX. OS suprenant et pouvant devenir une réelle alternative à Linux dès que plus d'un coeur sera supportè par le noyau.)
- Hurd (non testé)
- Minix (totalement fonctionnel, testé sur un atari st mega4 prété pour l'occasion avec ajout d'un minitel en port série comme second terminal)
- NetBSD (totalement fonctionnel)
- OpenBSD (totalement fonctionnel)
- SerenityOS (non testé)
- Solaris / Illumos (plutôt pénible à installer, totalement fonctionnel => testé sur x86_64)
- Redox OS (non testé)
- QNX (non testé)

**Cross compilation pour :**
- Android avec toolchain Android NDK (non testé)
- iOS avec toolchain Xcode/iOS SDK (non testé)
- [Nim sur microcontrôleur Vidéo ENG](https://www.youtube.com/watch?v=O8Y4faZPnsc)

## Sites officiels
- [Site officiel](https://nim-lang.org/)
- [Liste des packages Web, mise à jour hebdomadaire à partie de Git](https://nimpackages.com/)
- [Liste des packages Git, liste officielle utilisée par nimble list](https://github.com/nim-lang/packages)

## Ouvrages recommandés
- Begining Nim programming, George Ihecaire - 9798326324870 (Amazon Digital Services LLC)
- Programmation Nim, Guide Ultime - Steven Gellis - 9798342007221 (Amazon Digital Services LLC)
- Numerical algorithms in Nim, Applications in Physics, Biology, Finance - Massima Di Pierro - 97981999850537 (Amazon Digital Services LLC)

## Présentation (Youtube)
- [Nim en 100s ENG](https://www.youtube.com/watch?v=WHyOHQ_GkNo)
- [Cours Nim en 60 sessions de 15 min. ENG](https://www.youtube.com/watch?v=hwzkIlNfGHI&list=PLYBJzqz8zpWaiGbFcSdlh08zlpe8Tl_Gh)

## Mes réalisations
[en nim sur githut...](https://github.com/lipunila-sonaliwan-fr)

- **nim.firebird**, bibliothèque cliente permettant d'accéder au serveur de bases de données [Firebird](https://www.firebirdsql.org/) (anciennement Borland InterBase), disponible sous Linux, macOS et Windows. Toute la puissance de Microsoft SQL Server (avec procédures stockées, etc.) dans 30 Mo, sans le prix qui va avec. Très facile à administrer, conforme au SQL standard (ce qui implique quelques différences avec SQL Server, notamment en raison de certains ajouts propriétaires de ce dernier), l'ensemble se prend rapidement en main. Une véritable alternative à l'imposant PostgreSQL sans tomber dans les limites de MySQL/MariaDB. Ayant beaucoup développé en Delphi dans les années 1990, je n'ai depuis jamais rencontré le moindre souci avec ce serveur (alors que j'administre également, au quotidien, de nombreux serveurs SQL Server Standard et Enterprise). Je recommande vivement de faire l'effort de sortir de ses habitudes pour le tester (avec la version [community de DBeaver](https://dbeaver.io/), par exemple) : ce n'est que du bonheur.

- **nim.duckdb**, bibliothèque cliente (et serveur autonome) permettant d'accéder aux bases de données [duckDB](https://duckdb.org/) et de manipuler des données issues de sources hétérogènes (fichiers CSV, Parquet, etc., serveurs SQL, services Web, etc.) en local ou en mode client-serveur. L'ensemble constitue une solution idéale pour tout ce qui a trait à l'ETL, à la création d'entrepôts de données, aux statistiques, à la BI, etc.

- **nim.sawk**, bibliothèque et utilitaire AWK (en pur Nim). Le langage [AWK](https://fr.wikipedia.org/wiki/Awk) est très pratique pour tout ce qui concerne les manipulations de texte fondées sur des motifs (patterns). J'aimais beaucoup [TAWK](http://www.tasoft.com/). Hélas, la société a cessé ses activités. TAWK n'a plus évolué depuis et cible toujours DOS, OS/2 et Win32. Pour pallier ce manque (un AWK « sous stéroïdes » personnalisable), je me suis donc lancé dans l'implémentation de ma propre version d'AWK. Ce dépôt contient une version de base conforme aux spécifications du langage, qui s'avère déjà plus performante que certaines versions commerciales.

- **nim.sonaliwan**, analyseur (parser) léger produisant des arbres syntaxiques à partir d'une grammaire formelle (facile à décrire). Très utile pour tout ce qui touche aux langages, qu'ils soient naturels, construits ou informatiques : TAL, LLM, etc.

- **nim.nimql**, est un interpréteur de logique déclarative écrit en Nim, très proche de Prolog dans l'esprit. Bien qu'exploitable en l'état, ce projet est toujours en phase de développement. Entre temps, j'ai développé un solver CP-SAT (qui va être plublié prochainement) et pourrait étendre les possibilités offertes par NimQL.

- **draw.it** (renommé en *promptmx* dans la liste officielle des packages Nim) permet de piloter l'application d'IA générative [DrawThings](https://drawthings.ai/) afin de produire des kilotonnes d'images à partir d'explorations combinatoires portant sur le média, la technique, le domaine, le point de vue, la description ou encore le ou les sujets. L'outil est particulièrement intéressant dans le cadre de l'analyse de corpus textuels, notamment pour étudier les variations de représentation selon les populations ciblées par les LLM utilisés (approches psycho- et sociolinguistiques).

- **nim.wpwpage** a pour objectif de substituer une page Web (avec JavaScript) au bureau Windows afin d'offrir une interface adaptée au public visé. Il permet d'avoir immédiatement sous la main les outils nécessaires (via un menu dédié) et de normaliser rapidement (un simple exécutable à lancer) des postes Windows de versions et d'origines diverses. À l'origine, je voulais simplement me débarrasser du fond d'écran imposé par mon employeur sur un portable "sécurisé" qui m'avait été attribué, parce que... je n'aime pas les décisions imposées sans justification. À adapter selon les goûts de chacun.

En parlant de goûts et de couleurs, plutôt que de passer d'un éditeur de texte à un autre, puis à un autre encore, je tente de réaliser (toujours en Nim) l'éditeur de mes rêves : aucune fioriture, pas de menus, rien qui encombre l'écran ; juste le code (avec coloration syntaxique), des commandes au clavier et à la souris, et Ctrl+P pour afficher une palette proposant, sous forme de menu, l'ensemble des commandes avec l'indication de leurs raccourcis. C'est tout : rapide, simple et efficace. Et s'il me manque quelque chose ou que je découvre une bonne idée ailleurs, je l'ajoute. Point barre.

[...et autres trucs bizarres plus ou moins hors sujet](https://github.com/jihem?tab=repositories)
