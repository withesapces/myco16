#!/usr/bin/env python3
"""Poste le contenu d'un fichier texte en commentaire sur le commit courant."""
import json
import os
import sys
import urllib.request

path, repo, sha, token = sys.argv[1], sys.argv[2], sys.argv[3], os.environ["GITHUB_TOKEN"]
body = open(path, "r", errors="replace").read()[-60000:]
data = json.dumps({"body": "```\n" + body + "\n```"}).encode()
req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/commits/{sha}/comments",
    data=data,
    method="POST",
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    },
)
try:
    with urllib.request.urlopen(req) as r:
        print(r.status)
except Exception as e:
    print("erreur:", e)
