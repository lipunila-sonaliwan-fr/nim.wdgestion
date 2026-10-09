#!/usr/bin/env bash
# Tests HTTP de bout en bout de l'application exemple.
# Lancer le serveur sur une base neuve en gardant sa sortie :
#     rm -f wdgestionv.duckdb* && ./wdgestionv > wdgestionv.log &
#     tests/e2e.sh http://127.0.0.1:8080 wdgestionv.log
# (les mots de passe provisoires sont lus dans le journal). Le dernier test bloque
# l'IP locale pendant "connexion_blocage_minutes" : relancez le serveur ensuite.
U=${1:-http://127.0.0.1:8080}
JOURNAL=${2:-wdgestionv.log}
MDP_ADMIN=$(grep -o 'admin : [^ ]*' "$JOURNAL" | head -1 | cut -d' ' -f3)
MDP_DEMO=$(grep -o 'demo : [^ ]*' "$JOURNAL" | head -1 | cut -d' ' -f3)
[ -z "$MDP_ADMIN" ] && { echo "mots de passe introuvables dans $JOURNAL (base neuve ?)"; exit 2; }
T=$(mktemp -d); D=$T/demo; A=$T/admin; X=$T/x; ok=0; ko=0
verifie() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "ok    $1"; else ko=$((ko+1)); echo "ÉCHEC $1 : attendu '$3', obtenu '$2'"; fi; }
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
login() { curl -s -c $1 -b $1 -o /dev/null -w "%{redirect_url}" --data-urlencode "nom=$2" --data-urlencode "mdp=$3" $U/CONNEXION; }
changer() { curl -s -c $1 -b $1 -o /dev/null -w "%{redirect_url}" --data-urlencode "ancien=$2" \
            --data-urlencode "nouveau=$3" --data-urlencode "confirmation=$3" $U/MOTDEPASSE; }

verifie "session par défaut -> CONNEXION" "$(curl -s -c $D -b $D $U/ACCUEIL | grep -o '<h1>Connexion')" "<h1>Connexion"
verifie "ancien mot de passe admin/admin refusé" "$(login $X admin admin)" ""
verifie "mauvais mot de passe" "$(curl -s -c $D -b $D -d 'nom=demo&mdp=x' $U/CONNEXION | grep -c alerte)" "1"
verifie "mot de passe provisoire -> changement forcé" "$(login $D demo "$MDP_DEMO")" "$U/MOTDEPASSE"
verifie "catalogue interdit avant changement (403)" "$(code -b $D $U/ACCUEIL)" "403"
login $D demo "$MDP_DEMO" > /dev/null
verifie "nouveau mot de passe trop court" "$(curl -s -b $D -c $D -d "ancien=$MDP_DEMO&nouveau=court&confirmation=court" $U/MOTDEPASSE | grep -o '12 caractères minimum' | head -1)" "12 caractères minimum"
verifie "changement accepté" "$(changer $D "$MDP_DEMO" 'Demo-nouveau-2026')" "$U/ACCUEIL"
verifie "catalogue après changement" "$(curl -s -b $D $U/ACCUEIL | grep -c '<h1>Catalogue')" "1"
verifie "ancien mot de passe provisoire refusé" "$(login $X demo "$MDP_DEMO")" ""
curl -s -b $D -o /dev/null -d "plus=2" $U/CADDIE; curl -s -b $D -o /dev/null -d "plus=2" $U/CADDIE
curl -s -b $D -o /dev/null "$U/CADDIE?plus=2"
verifie "caddie en POST (un GET ne modifie rien)" "$(curl -s -b $D $U/ACCUEIL | grep -o 'class="total">[^<]*')" 'class="total">2 article(s) · 179.80 €'
verifie "fichier statique BLOB" "$(code $U/style.css)" "200"
verifie "statique absent : 404 sans pénalité" "$(code -b $D $U/favicon.ico)" "404"
verifie "traversée de répertoire" "$(code --path-as-is $U/../wdgestionv.json)" "404"
verifie "procédure hors ACCEPTE -> 403" "$(code -b $D $U/PRODUITS)" "403"
verifie "session supprimée après 403" "$(curl -s -b $D $U/ACCUEIL | grep -o '<h1>Connexion')" "<h1>Connexion"
login $D demo 'Demo-nouveau-2026' > /dev/null
verifie "EDIT sans EDITION -> 403" "$(code -b $D $U/EDIT)" "403"
login $D demo 'Demo-nouveau-2026' > /dev/null
verifie "SUIVI sans le droit SUIVI -> 403" "$(code -b $D $U/SUIVI)" "403"
login $A admin "$MDP_ADMIN" > /dev/null; changer $A "$MDP_ADMIN" 'Admin-nouveau-2026' > /dev/null
verifie "EDIT avec EDITION" "$(code -b $A $U/EDIT)" "200"
verifie "API EDIT sans en-tête X-WDG" "$(code -b $A $U/EDIT/arbre)" "403"
verifie "API EDIT hors racines" "$(code -b $A -H 'X-WDG: 1' "$U/EDIT/lire?chemin=PROG/../wdgestionv.json")" "404"
verifie "SUIVI avec le droit SUIVI" "$(code -b $A $U/SUIVI)" "200"
verifie "API SUIVI : état" "$(curl -s -b $A -H 'X-WDG: 1' $U/SUIVI/etat | grep -o '"tablesVivantes"' | head -1)" '"tablesVivantes"'
verifie "incidents enregistrés" "$(curl -s -b $A $U/INCIDENTS | grep -o 'class="n">[0-9]*' | tail -1)" 'class="n">4'
verifie "déconnexion" "$(code -b $A -c $A $U/DECONNEXION)" "302"
# --- limitation des tentatives (en dernier : bloque l'IP)
dernier=""
for i in $(seq 1 12); do dernier=$(code -c $X -b $X -d "nom=admin&mdp=essai$i" $U/CONNEXION); done
verifie "force brute bloquée (429)" "$dernier" "429"
verifie "même le bon mot de passe est refusé pendant le blocage" "$(code -c $X -b $X -d "nom=admin&mdp=Admin-nouveau-2026" $U/CONNEXION)" "429"
verifie "les sessions déjà ouvertes ne sont pas affectées" "$(code -b $D $U/ACCUEIL)" "200"
echo "$ok réussi(s), $ko échec(s)"; rm -rf $T; [ $ko -eq 0 ]
