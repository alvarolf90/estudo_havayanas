#!/usr/bin/env python3
"""Padroniza as imagens dos sinais: remove o fundo, recorta a margem e coloca todas
com a mesma altura (fundo transparente). Lê de www/ (ou de sinais_originais/ se existir)
e grava em sinais_padronizados/ para conferência.  Rode de dentro de app_estudo_havayanas_exp/."""
import glob, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PULAR = {"cabeca.png", "peleco.png", "peteco.png", "petele.png", "teleco.png", "pe_co.png", "petala.png"}  # partituras e foto
ORIG = "../sinais_originais" if os.path.isdir("../sinais_originais") else "www"
SAIDA = "../sinais_padronizados"
REAIS = "../sinais_reais"      # mãos reais novas (têm prioridade sobre as imagens antigas)
ALIAS = {"galope": "arrastape", "c5_-_pagodao": "c5"}   # mesmo sinal, nomes diferentes
ALTURA, LARG_MAX, MARGEM = 150, 320, 3   # altura padrão (px), largura máxima, margem
os.makedirs(SAIDA, exist_ok=True)


def remove_fundo(im, tol):
    """Flood fill a partir da borda, com tolerância, e devolve RGBA com fundo transparente."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    arr = np.asarray(rgb).astype(int)
    borda = np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]])
    fundo = tuple(int(v) for v in np.median(borda, axis=0))
    marca = (255, 0, 255)
    work = rgb.copy()
    pts = [(x, 0) for x in range(0, w, 6)] + [(x, h - 1) for x in range(0, w, 6)] + \
          [(0, y) for y in range(0, h, 6)] + [(w - 1, y) for y in range(0, h, 6)]
    for p in pts:
        px = work.getpixel(p)
        if px != marca and sum(abs(a - b) for a, b in zip(px, fundo)) <= tol * 3:
            ImageDraw.floodfill(work, p, marca, thresh=tol)
    m = np.all(np.asarray(work) == marca, axis=2)
    alpha = Image.fromarray(np.where(m, 0, 255).astype("uint8"))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))
    out = im.convert("RGBA"); out.putalpha(alpha)
    return out


def tem_transparencia(im):
    a = np.asarray(im.getchannel("A"))
    return (a < 250).mean() > 0.05


for f in sorted(glob.glob(os.path.join(ORIG, "*.png"))):
    nome = os.path.basename(f)
    if nome in PULAR:
        continue
    base = os.path.splitext(nome)[0]
    novo = os.path.join(REAIS, ALIAS.get(base, base) + ".png")
    if os.path.exists(novo):
        f = novo
    try:
        im = Image.open(f).convert("RGBA")   # paletas com transparência viram RGBA
    except Exception as e:
        print("pulando", nome, e); continue
    if not tem_transparencia(im):
        im = remove_fundo(im, 26)
    bb = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    if bb:
        im = im.crop(bb)
    # mesma altura para todos (largura livre, limitada a LARG_MAX); recorte justo, sem moldura
    esc = min(ALTURA / im.height, LARG_MAX / im.width)
    im = im.resize((max(1, round(im.width * esc)), max(1, round(im.height * esc))), Image.LANCZOS)
    tela = Image.new("RGBA", (im.width + 2 * MARGEM, im.height + 2 * MARGEM), (0, 0, 0, 0))
    tela.alpha_composite(im, (MARGEM, MARGEM))
    tela = tela.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)  # paleta com transparência: arquivo bem menor
    tela.save(os.path.join(SAIDA, nome), optimize=True)
    print(nome, im.size)
