#!/usr/bin/env python3
"""
Corrige uma corrida conhecida do shinylive (posit-dev/shinylive#133,
posit-dev/py-shiny-site#478): a pagina cria o "iframe" interno do app
(com uma rota virtual tipo app_<hash>/) ANTES do Service Worker estar
de fato controlando a pagina. Se isso acontecer, essa requisicao cai
na rede de verdade (em vez de ser interceptada pelo SW) e vira um 404
real do GitHub Pages, ja que essa rota nao existe como arquivo real.
Confirmado ao vivo via Web Inspector (Safari) em 2026-09-29: a rota
"app_<hash>" aparecia com status 404 genuino nas requisicoes de rede.

Duas partes, ambas necessarias:
1. Sobrescreve navigator.serviceWorker.ready pra so resolver quando o
   SW REALMENTE assumir o controle (evento controllerchange), com uma
   janela de seguranca de 2s + no maximo 1 reload por aba (nunca loop
   infinito) - baseado no patch usado em posit-dev/py-shiny-site#478.
2. Faz o script que cria o app (runExportedApp) ESPERAR essa mesma
   promise antes de criar o iframe - sem isso, a parte 1 sozinha nao
   adianta, pois o iframe e criado cedo demais de qualquer forma.

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). E
idempotente: pode ser rodado varias vezes sem duplicar nada.

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import sys
from pathlib import Path

MARKER_1 = "shinylive-sw-reloaded"
MARKER_2 = "await navigator.serviceWorker.ready"

PATCH_SCRIPT = '''<script>
    // Fix (parte 1/2): posit-dev/shinylive#133 - navigator.serviceWorker.ready
    // resolve antes do controllerchange real (afeta Safari/WebKit). Baseado no
    // patch usado em posit-dev/py-shiny-site#478.
    (function () {
      var container = navigator.serviceWorker;
      if (!container) return;
      var nativeReady = Object.getOwnPropertyDescriptor(
        ServiceWorkerContainer.prototype,
        "ready"
      ).get;
      var reloadedKey = "''' + MARKER_1 + '''";
      var ready;
      Object.defineProperty(container, "ready", {
        configurable: true,
        get: function () {
          ready = ready || nativeReady.call(container).then(function (registration) {
            return new Promise(function (resolve) {
              function controlled() { resolve(registration); }
              if (container.controller) return controlled();
              container.addEventListener("controllerchange", controlled, { once: true });
              setTimeout(function () {
                if (container.controller) return controlled();
                try {
                  if (sessionStorage.getItem(reloadedKey)) return;
                  sessionStorage.setItem(reloadedKey, "1");
                } catch (e) {
                  return;
                }
                controlled();
              }, 2000);
            });
          });
          return ready;
        },
      });
    })();
    </script>
    '''

def patch(index_path: Path) -> bool:
    html = index_path.read_text(encoding="utf-8")
    changed = False

    # Parte 1: sobrescreve o getter .ready
    if MARKER_1 in html:
        print(f"Parte 1/2 ja aplicada (marcador '{MARKER_1}' encontrado).")
    else:
        needle1 = '    <script\n      src="./shinylive/load-shinylive-sw.js"'
        if needle1 not in html:
            raise SystemExit(
                "Nao encontrei o ponto de insercao da parte 1 (script load-shinylive-sw.js). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = html.replace(needle1, PATCH_SCRIPT + needle1, 1)
        print("Parte 1/2 aplicada: getter navigator.serviceWorker.ready sobrescrito.")
        changed = True

    # Parte 2: faz runExportedApp esperar o ready patcheado antes de criar o iframe
    if MARKER_2 in html:
        print(f"Parte 2/2 ja aplicada (marcador '{MARKER_2}' encontrado).")
    else:
        needle2 = 'import { runExportedApp } from "./shinylive/shinylive.js";\n      runExportedApp({'
        if needle2 not in html:
            raise SystemExit(
                "Nao encontrei o ponto de insercao da parte 2 (chamada runExportedApp). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        replacement2 = (
            'import { runExportedApp } from "./shinylive/shinylive.js";\n'
            '      // Fix (parte 2/2): espera o Service Worker realmente assumir o\n'
            '      // controle (usando o getter .ready ja corrigido acima) antes de criar\n'
            '      // o iframe interno do app - sem isso a parte 1 sozinha nao adianta,\n'
            '      // pois o iframe e criado cedo demais de qualquer forma.\n'
            '      if (navigator.serviceWorker) {\n'
            '        await navigator.serviceWorker.ready;\n'
            '      }\n'
            '      runExportedApp({'
        )
        html = html.replace(needle2, replacement2, 1)
        print("Parte 2/2 aplicada: runExportedApp agora espera o SW estar no controle.")
        changed = True

    if changed:
        index_path.write_text(html, encoding="utf-8")
        print(f"Arquivo salvo: {index_path}")
    else:
        print(f"Nada a fazer, ja estava tudo patcheado: {index_path}")
    return changed

if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/index.html")
    patch(target)
