# patch_golden.py : inserts the trained-weights loader into golden_gru.py
src = open("golden_gru.py").read()
marker = "bo = random.randint(-1024, 1024)\n"
block = '''import json, os
if os.path.exists("trained_params.json"):
    _p = json.load(open("trained_params.json"))
    Wz, Uz, Wr, Ur = _p["Wz"], _p["Uz"], _p["Wr"], _p["Ur"]
    Wn, Un, wo     = _p["Wn"], _p["Un"], _p["wo"]
    bz, br, bnx, bnh, bo = _p["bz"], _p["br"], _p["bnx"], _p["bnh"], _p["bo"]
    print("golden_gru: using TRAINED weights")
'''
if "trained_params" in src:
    print("Already patched - nothing to do")
elif marker not in src:
    print("ERROR: marker line not found - check golden_gru.py")
else:
    open("golden_gru.py", "w").write(src.replace(marker, marker + block, 1))
    print("Patched golden_gru.py")
