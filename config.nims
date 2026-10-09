# Configuration de compilation wdGestion V/FR
switch("path", thisDir() & "/src")
switch("passC", "-I" & thisDir() & "/src")
# Multitâche : comptage de références atomique (les objets sont partagés entre fils),
# malloc du système (libération sûre depuis n'importe quel fil).
switch("threads", "on")
switch("mm", "atomicArc")
switch("define", "useMalloc")
