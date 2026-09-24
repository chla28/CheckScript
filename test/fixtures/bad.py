#!/usr/bin/python
import os, subprocess
import pickle
PASSWORD = "S3cr3tP@ssw0rd!"


def run(cmd, items=[]):
    subprocess.call(cmd, shell=True)
    x = eval(input())
    for i in range(len(items)):
        print(items[i])
    try:
        return pickle.loads(open("/tmp/data").read())
    except:
        pass


def add(a: int, b: int) -> int:
    return a + b + "x"


def classify(n):
    if n == 1:
        return "a"
    elif n == 2:
        return "b"
    elif n == 3:
        return "c"
    elif n == 4:
        return "d"
    elif n == 5:
        return "e"
    elif n == 6:
        return "f"
    elif n == 7:
        return "g"
    elif n == 8:
        return "h"
    elif n == 9:
        return "i"
    elif n == 10:
        return "j"
    return "z"


subprocess.run(
    ["ls", "-l"],
    check=True,
)
match os.name:
    case "nt": print("win")
