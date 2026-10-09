#!/usr/bin/env python3
"""Banc de tests du serveur multitâche wdGestion V.

Lance l'exécutable dans un dossier temporaire avec l'application tests/concurrence,
puis vérifie : parallélisme entre sessions, sérialisation dans une session,
interruption du SQL trop long, récursion dans les fils, absence de fuite mémoire
(compteur exact de tables + mémoire résidente), tenue en charge, arrêt propre.

    python3 tests/concurrence.py [chemin/vers/wdgestionv]
"""
import http.client, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time, urllib.parse

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.dirname(ICI)
EXE = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(RACINE, "wdgestionv"))
PORT = 8099
echecs = 0

def verifie(nom, ok, detail=""):
    global echecs
    print(("ok    " if ok else "ÉCHEC ") + nom + (f"  ({detail})" if detail else ""))
    if not ok: echecs += 1

class Client:
    """Client HTTP minimal avec cookie de session et connexion keep-alive"""
    def __init__(self):
        self.cookie = None
        self.c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=60)
    def req(self, methode, chemin, corps=None, entetes=None):
        h = dict(entetes or {})
        if self.cookie: h["Cookie"] = self.cookie
        if corps is not None:
            corps = urllib.parse.urlencode(corps)
            h["Content-Type"] = "application/x-www-form-urlencoded"
        for essai in range(2):
            try:
                self.c.request(methode, chemin, body=corps, headers=h)
                r = self.c.getresponse()
                donnees = r.read().decode("utf-8", "replace")
                break
            except (ConnectionError, http.client.HTTPException):
                self.c.close()
                self.c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=60)
                if essai: raise
        sc = r.getheader("Set-Cookie")
        if sc:
            m = re.match(r"WDG_SESSION=([^;]*)", sc)
            if m: self.cookie = None if "Max-Age=0" in sc else "WDG_SESSION=" + m.group(1)
        return r.status, donnees
    def connexion(self, nom):
        self.req("GET", "/")
        return self.req("POST", "/CONNEXION", {"nom": nom})
    def api(self, action, params=None, post=False):
        q = "?" + urllib.parse.urlencode(params) if params else ""
        st, d = self.req("POST" if post else "GET", "/SUIVI/" + action + q, "" if post else None, {"X-WDG": "1"})
        return json.loads(d)

def chronometre(f):
    t = time.time(); r = f(); return r, time.time() - t

# préparation
tmp = tempfile.mkdtemp(prefix="wdg_conc_")
for d in ("PROG", "PAGE", "BLOB"):
    shutil.copytree(os.path.join(ICI, "concurrence", d), os.path.join(tmp, d))
shutil.copy(EXE, os.path.join(tmp, "wdgestionv"))
for sysdir in ("linOS", "macOS", "winOS"):        # bibliothèque DuckDB selon le système
    src = os.path.join(os.path.dirname(EXE), sysdir)
    if os.path.isdir(src): os.symlink(src, os.path.join(tmp, sysdir))
json.dump({"port": PORT, "base": "test.duckdb", "fils": 8, "duree_max_secondes": 4,
           "instructions_max": 1000000000, "connexion_essais_max": 100000}, open(os.path.join(tmp, "wdgestionv.json"), "w"))
journal = open(os.path.join(tmp, "journal.txt"), "w")
srv = subprocess.Popen(["./wdgestionv"], cwd=tmp, stdout=journal, stderr=subprocess.STDOUT)
for _ in range(50):
    try: http.client.HTTPConnection("127.0.0.1", PORT, timeout=1).request("GET", "/test.css"); break
    except OSError: time.sleep(0.1)
else:
    srv.kill(); journal.close()
    print("ÉCHEC le serveur n'a pas démarré. Journal :")
    print(open(os.path.join(tmp, "journal.txt")).read())
    sys.exit(1)

try:
    admin = Client(); admin.connexion("admin")

    # 1. parallélisme entre sessions
    a = Client(); a.connexion("alice")
    res = {}
    def long(): res["long"] = chronometre(lambda: a.req("GET", "/LONG?secondes=3"))
    th = threading.Thread(target=long); th.start()
    time.sleep(0.3)
    b = Client()
    durees = []
    (_, d) = chronometre(lambda: b.connexion("bob")); durees.append(d)
    for i in range(5):
        (st, _), d = chronometre(lambda: b.req("POST", "/AJOUT", {"id": i})); durees.append(d)
    st_b, corps_b = b.req("POST", "/AJOUT", {"id": 99})
    pendant = th.is_alive()
    th.join()
    (st_a, corps_a), d_a = res["long"]
    verifie("traitement long de 3 s dans une session", st_a == 200 and d_a >= 2.9, f"{d_a:.2f} s")
    verifie("pendant ce temps, un autre utilisateur se connecte et remplit son caddie",
            pendant and max(durees) < 0.5 and corps_b.strip() == "6", f"max {max(durees)*1000:.0f} ms")

    # 2. sérialisation dans une session
    c = Client(); c.connexion("carole")
    def compteur(cl, out): out.append(cl.req("GET", "/COMPTEUR"))
    clones = []
    for _ in range(5):
        x = Client(); x.cookie = c.cookie; clones.append(x)
    sorties = []
    ths = [threading.Thread(target=compteur, args=(x, sorties)) for x in clones]
    [t.start() for t in ths]; [t.join() for t in ths]
    valeurs = sorted(int(d.strip()) for st, d in sorties if st == 200)
    verifie("5 requêtes simultanées d'une même session : exécutées l'une après l'autre", valeurs == [1, 2, 3, 4, 5], str(valeurs))
    clones = []
    for _ in range(12):
        x = Client(); x.cookie = c.cookie; clones.append(x)
    sorties = []
    ths = [threading.Thread(target=compteur, args=(x, sorties)) for x in clones]
    [t.start() for t in ths]; [t.join() for t in ths]
    codes = [st for st, _ in sorties]
    _, fin = c.req("GET", "/COMPTEUR")
    verifie("au-delà de 4 en attente : 429, aucun incrément perdu",
            codes.count(429) > 0 and int(fin.strip()) == 5 + codes.count(200) + 1, f"{codes.count(200)} × 200, {codes.count(429)} × 429")

    # 3. SQL trop long interrompu
    d = Client(); d.connexion("david")
    res = {}
    th = threading.Thread(target=lambda: res.update(r=chronometre(lambda: d.req("GET", "/SQLLONG"))))
    th.start(); time.sleep(0.5)
    (st_e, _), d_e = chronometre(lambda: Client().req("GET", "/test.css"))
    th.join()
    (st_s, _), d_s = res["r"]
    verifie("requête SQL de plus de 4 s interrompue (500)", st_s == 500 and d_s < 8, f"{d_s:.1f} s")
    verifie("le serveur répond pendant la requête SQL longue", st_e == 200 and d_e < 0.5, f"{d_e*1000:.0f} ms")

    # 4. récursion dans un fil
    st1, r1 = a.req("GET", "/RECURSION?n=190")
    st2, _ = a.req("GET", "/RECURSION?n=500")
    verifie("récursion de 190 niveaux dans un fil de travail", st1 == 200 and r1.strip() == "190")
    verifie("récursion infinie arrêtée proprement (500)", st2 == 500)

    # 5. fuites mémoire
    admin.api("fermerinactives", {"minutes": 0}, True)
    base = admin.api("etat")["tablesVivantes"]
    rss = []
    for tour in range(4):
        clients = [Client() for _ in range(30)]
        def travail(cl, n):
            cl.connexion("u%d" % n)
            for _ in range(15): cl.req("GET", "/CYCLES?n=40")
        ths = [threading.Thread(target=travail, args=(cl, i)) for i, cl in enumerate(clients)]
        [t.start() for t in ths]; [t.join() for t in ths]
        pendant = admin.api("etat")["tablesVivantes"]
        fermees = admin.api("fermerinactives", {"minutes": 0}, True)["fermees"]
        e = admin.api("etat")
        rss.append(e["memoire"])
        print(f"      tour {tour+1} : {30*15*41} tables cycliques créées, {pendant} vivantes en fin de requêtes "
              f"(SESSION, PANIER, GARDE par session), {fermees} sessions fermées, {e['tablesVivantes']} vivantes, RSS {e['memoire']/2**20:.1f} Mo")
        for cl in clients: cl.c.close()
    verifie("tables cycliques libérées en fin de requête et à la fermeture des sessions",
            e["tablesVivantes"] == base, f"{e['tablesVivantes']} vivantes (avant : {base})")
    verifie("mémoire stable d'un tour à l'autre", rss[-1] - rss[1] < 8 * 2**20,
            " → ".join(f"{x/2**20:.1f}" for x in rss) + " Mo")

    # 6. charge
    erreurs = []; total = [0]
    def charge(n):
        cl = Client(); cl.connexion("charge%d" % n)
        for i in range(150):
            st, _ = cl.req("GET", "/ACCUEIL" if i % 3 else "/test.css")
            if st != 200: erreurs.append(st)
            total[0] += 1
    t0 = time.time()
    ths = [threading.Thread(target=charge, args=(i,)) for i in range(24)]
    [t.start() for t in ths]; [t.join() for t in ths]
    dt = time.time() - t0
    verifie("charge : 24 clients × 150 requêtes sans erreur", not erreurs, f"{total[0]/dt:.0f} req/s, {len(erreurs)} erreur(s)")

    # 7. mesures de l'écran de suivi
    m = admin.api("mesures")
    noms = {p["nom"]: p for p in m["procedures"]}
    verifie("mesures par procédure (min/max/moyenne/nombre)", "LONG" in noms and noms["LONG"]["max"] >= 2.9 and noms["ACCUEIL"]["nombre"] > 0,
            f"ACCUEIL : {noms.get('ACCUEIL', {}).get('nombre')} appels, moyenne {noms.get('ACCUEIL', {}).get('moyenne', 0)*1000:.2f} ms")
    verifie("top des requêtes SQL (la requête interrompue en tête)", m["topSql"] and "range(300000)" in m["topSql"][0]["nom"])
    verifie("mesures des fichiers statiques", any(s["nom"] == "test.css" and s["nombre"] > 0 for s in m["statiques"]))
    e = admin.api("etat")
    verifie("charge : CPU, temps base, mémoire, trafic", e["cpuUtilisateur"] > 0 and e["tempsSql"] > 3 and e["memoire"] > 0 and e["octetsEnvoyes"] > 0)
finally:
    # 8. arrêt propre
    srv.send_signal(signal.SIGTERM)
    try: code = srv.wait(30)
    except subprocess.TimeoutExpired: srv.kill(); code = -1
    journal.close()
    texte = open(os.path.join(tmp, "journal.txt")).read()
    verifie("arrêt propre sur SIGTERM (fils rejoints, base fermée)", code == 0 and "base fermée" in texte, f"code {code}")
    m = re.search(r"Tables restantes : (\d+)", texte)
    verifie("aucune table restante après l'arrêt", m is not None and m.group(1) == "0", m.group(0) if m else "?")
    shutil.rmtree(tmp, ignore_errors=True)

print("ÉCHECS : %d" % echecs if echecs else "Tous les tests sont passés.")
sys.exit(1 if echecs else 0)
