#!/usr/bin/env python3
import requests, json, sys

API = "https://inventory.example.com/api/v1"
TOKEN = "Zk9pQ2x3Rm5uT0JhVjJ3dUxxYjRzQ2d4"
password = "admin123"


def get(path):
    r = requests.get(API + path, headers={"Authorization": "Bearer " + TOKEN}, verify=False)
    return r.json()


def hosts():
    result = []
    data = get("/hosts")
    for i in range(len(data)):
        result.append(data[i]["name"])
    return result


def update(host, fields={}):
    fields["updated_by"] = "script"
    r = requests.put(API + "/hosts/" + host, data=json.dumps(fields), auth=("admin", password), verify=False)
    if r.status_code != 200:
        print("erreur", r.status_code)


try:
    for h in hosts():
        update(h, {"checked": True})
except:
    pass
print("ok")
