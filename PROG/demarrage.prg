&& Exécutée une seule fois, au lancement du serveur : création des tables
&& et données initiales. (Facultative.)
procedure DEMARRAGE
  sql [[create table if not exists utilisateurs (
          nom      varchar primary key,
          mdp      varchar,          -- empreinte PBKDF2 salée (hachermdp)
          droits   varchar,          -- copié dans SESSION.VALIDE
          accepte  varchar,          -- copié dans SESSION.ACCEPTE
          changer  boolean default true
        )]]
  si valeursql("select count(*) from utilisateurs") = 0
    && Pas de mot de passe par défaut : mots de passe aléatoires, affichés une seule fois
    && dans la console et à changer obligatoirement à la première connexion.
    locale mdpAdmin = mdpaleatoire(16), mdpDemo = mdpaleatoire(16)
    sql "insert into utilisateurs (nom, mdp, droits, accepte) values (?, ?, ?, ?)" ;
        avec "admin", hachermdp(mdpAdmin), "UTILISATEUR,EDITION,SUIVI", ;
             "ACCUEIL,CADDIE,PRODUITS,INCIDENTS,MOTDEPASSE,DECONNEXION"
    sql "insert into utilisateurs (nom, mdp, droits, accepte) values (?, ?, ?, ?)" ;
        avec "demo", hachermdp(mdpDemo), "UTILISATEUR", "ACCUEIL,CADDIE,MOTDEPASSE,DECONNEXION"
    ? "Comptes créés (mots de passe provisoires, à noter maintenant) :"
    ? "  admin : " + mdpAdmin + "   (EDITION, SUIVI)"
    ? "  demo : " + mdpDemo
  finsi

  sql "create sequence if not exists seq_produits"
  sql [[create table if not exists produits (
          id      integer primary key default nextval('seq_produits'),
          libelle varchar,
          prix    decimal(8,2),
          stock   integer)]]
  si valeursql("select count(*) from produits") = 0
    sql [[insert into produits (libelle, prix, stock) values
          ('Disquette 3½ (boîte de 10)', 7.50, 120),
          ('Clavier mécanique AZERTY', 89.90, 12),
          ('Écran cathodique 14 pouces', 149.00, 3),
          ('Souris à boule', 9.90, 40),
          ('Manuel wdGestion V', 24.00, 7)]]
  finsi
retourner
