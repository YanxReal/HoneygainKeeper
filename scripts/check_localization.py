#!/usr/bin/env python3
"""Verifica paridad es/en de Localizable.strings y cobertura de claves en el código."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "HoneygainKeeper"
es_path = root / "es.lproj/Localizable.strings"
en_path = root / "en.lproj/Localizable.strings"

def parse_keys(path):
    txt = path.read_text(encoding="utf-8")
    # Quita comentarios /* ... */
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    keys = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', txt):
        keys[m.group(1)] = m.group(2)
    return keys

es = parse_keys(es_path)
en = parse_keys(en_path)

ok = True
print(f"es: {len(es)} claves | en: {len(en)} claves")
only_es = set(es) - set(en)
only_en = set(en) - set(es)
if only_es:
    ok = False
    print("FALTAN EN EN:", *sorted(only_es), sep="\n  ")
if only_en:
    ok = False
    print("FALTAN EN ES:", *sorted(only_en), sep="\n  ")

# --- Extracción de claves usadas en el código ---
INTERP = {
    r"\\\(Int\(code\)\)": "%lld",
    r"\\\(code\)": "%lld",
    r"\\\(generation\)": "%lld",
    r"\\\(count\)": "%lld",
    r"\\\(shown\)": "%lld",
    r"\\\(logLines\.count\)": "%lld",
    r"\\\(error\.localizedDescription\)": "%@",
    r"\\\(Self\.cleanOutput\(ao\)\)": "%@",
    r"\\\(Self\.cleanOutput\(out\)\)": "%@",
    r"\\\(downloadedVersion\)": "%@",
    r"\\\(Self\.appVersion\)": "%@",
}

def normalize(s):
    for pat, rep in INTERP.items():
        s = re.sub(pat, rep, s)
    return s

missing = set()
swift_files = list(root.glob("*.swift"))
patterns = [
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'\bText\("((?:[^"\\]|\\.)*)"',
    r'\.help\("((?:[^"\\]|\\.)*)"',
    r'\bLabel\("((?:[^"\\]|\\.)*)"',
    r'\bButton\("((?:[^"\\]|\\.)*)"',
    r'\bToggle\("((?:[^"\\]|\\.)*)"',
    r'\bSection\("((?:[^"\\]|\\.)*)"',
    r'navigationTitle\("((?:[^"\\]|\\.)*)"',
    r'LabeledContent\("((?:[^"\\]|\\.)*)"',
]
for f in swift_files:
    src = f.read_text(encoding="utf-8")
    for pat in patterns:
        for m in re.finditer(pat, src):
            key = normalize(m.group(1))
            if key not in es:
                missing.add(f"{f.name}: {key}")

# Claves en contextos no capturables por regex (switch/tuplas)
manual = ["Resumen", "Registros", "Honeygain no instalado", "Protegido", "Parcial",
          "Detenido", "Correcta (0)", "Error (código %lld)"]
for key in manual:
    if key not in es:
        missing.add(f"(manual): {key}")

if missing:
    ok = False
    print("CLAVES USADAS EN CÓDIGO PERO AUSENTES EN ES:", *sorted(missing), sep="\n  ")

print("PARIDAD OK" if ok else "PROBLEMAS DETECTADOS")
sys.exit(0 if ok else 1)
