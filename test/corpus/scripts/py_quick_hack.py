import os
import subprocess

print("Nettoyage des conteneurs arrêtés")
out = subprocess.check_output("docker ps -aq -f status=exited", shell=True)
ids = out.decode().split()
print(len(ids), "conteneurs")
if input("Continuer ? ") == "o":
    for i in ids:
        os.system("docker rm " + i)
print("fini")
