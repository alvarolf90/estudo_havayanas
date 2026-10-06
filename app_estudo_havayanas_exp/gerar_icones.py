#!/usr/bin/env python3
"""Gera miniaturas (www/ico/*.png) a partir das imagens dos sinais em www/.
Rode de dentro de app_estudo_havayanas_exp/ sempre que trocar/atualizar as imagens.
Só gera para levadas/convenções (ignora arquivos que não são sinais, como cabeca.png)."""
import glob, os
from PIL import Image

LADO = 96  # maior lado da miniatura (exibida a ~34px de altura; 96 cobre telas retina)
IGNORAR = {"cabeca.png"}
os.makedirs("www/ico", exist_ok=True)
total = 0
for f in sorted(glob.glob("www/*.png")):
    nome = os.path.basename(f)
    if nome in IGNORAR:
        continue
    try:
        im = Image.open(f).convert("RGBA")
    except Exception as e:
        print("pulando", nome, e); continue
    bbox = im.getchannel("A").getbbox()   # corta margem transparente, se houver
    if bbox:
        im = im.crop(bbox)
    im.thumbnail((LADO, LADO), Image.LANCZOS)
    saida = os.path.join("www/ico", nome)
    im.save(saida, optimize=True)
    total += os.path.getsize(saida)
    print(nome, im.size, os.path.getsize(saida))
print("total KB:", round(total / 1024))
