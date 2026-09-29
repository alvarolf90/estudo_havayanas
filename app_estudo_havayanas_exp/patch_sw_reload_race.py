#!/usr/bin/env python3
"""
Corrige uma corrida conhecida do shinylive (posit-dev/shinylive#133,
posit-dev/py-shiny-site#478): a pagina cria o "iframe" interno do app
(com uma rota virtual tipo app_<hash>/) ANTES do Service Worker estar
de fato controlando a pagina. Se isso acontecer, essa requisicao cai
na rede de verdade (em vez de ser interceptada pelo SW) e vira um 404
real do GitHub Pages, ja que essa rota nao existe como arquivo real -
e como o iframe ocupa a tela inteira, parece que o app inteiro deu 404.
Confirmado ao vivo via Web Inspector (Safari, iPhone) em 2026-09-29.

Duas partes, ambas necessarias, com propositos DIFERENTES e por isso
NAO devem compartilhar o mesmo timeout:
1. Sobrescreve navigator.serviceWorker.ready pra so resolver quando o
   SW REALMENTE assumir o controle (evento controllerchange), com uma
   janela de seguranca de 2s + no maximo 1 reload por aba (nunca loop
   infinito) - baseado no patch usado em posit-dev/py-shiny-site#478.
   Esse timeout de 2s existe so pra decidir "desisto e recarrego a
   pagina", nao pra dizer "pode seguir em frente sem controle real".
2. Faz o script que cria o app (runExportedApp) ESPERAR o controle
   REAL do SW antes de criar o iframe - usando uma espera PROPRIA,
   SEM o atalho de timeout da parte 1 (se usasse o mesmo .ready
   patcheado, o timeout de 2s da parte 1 liberaria a criacao do
   iframe cedo demais de novo, foi exatamente esse o bug da primeira
   tentativa desse patch). Se o controle nunca vier, quem resolve e o
   reload de pagina inteira feito pela parte 1 (que cancela essa
   espera pendente de qualquer forma).

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). E
idempotente: pode ser rodado varias vezes sem duplicar nada, e se
rodado sobre um docs/index.html com uma versao ANTIGA da parte 2 (com
o bug do timeout compartilhado), ele substitui pela versao corrigida.

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import re
import sys
from pathlib import Path

MARKER_1 = "shinylive-sw-reloaded"
MARKER_2 = "espera-controle-real-sem-atalho-de-timeout"

PATCH_SCRIPT = """<script>
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
      var reloadedKey = "REPLACE_MARKER_1";
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
    """.replace("REPLACE_MARKER_1", MARKER_1)

# Bloco que vai ANTES de "runExportedApp({" - substitui qualquer versao
# anterior (inclusive a buggy que reusava o .ready com atalho de 2s).
WAIT_BLOCK = """import { runExportedApp } from "./shinylive/shinylive.js";
      // Fix (parte 2/2 - REPLACE_MARKER_2): espera o controle REAL
      // do Service Worker antes de criar o iframe interno do app. NAO usa
      // o .ready patcheado acima (que tem um atalho de 2s pra decidir
      // "desisto e recarrego") - aqui a espera e sem atalho: se o controle
      // nunca vier, quem resolve e o reload de pagina inteira da parte 1,
      // que cancela essa espera pendente de qualquer forma.
      if (navigator.serviceWorker) {
        await new Promise(function (resolve) {
          if (navigator.serviceWorker.controller) return resolve();
          navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true });
        });
      }
      runExportedApp({""".replace("REPLACE_MARKER_2", MARKER_2)

# Qualquer variante anterior da parte 2 que precise ser removida antes de
# inserir a nova (incluindo a versao buggy que usava "await navigator.
# serviceWorker.ready;"), identificada pelo import seguido de comentarios/
# codigo ate chegar em "runExportedApp({".
IMPORT_TO_CALL_RE = re.compile(
    r'import \{ runExportedApp \} from "\./shinylive/shinylive\.js";.*?runExportedApp\(\{',
    re.S,
)

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

    # Parte 2: substitui (idempotente) o bloco entre o import e runExportedApp({
    if MARKER_2 in html:
        print(f"Parte 2/2 ja aplicada e atualizada (marcador '{MARKER_2}' encontrado).")
    else:
        if not IMPORT_TO_CALL_RE.search(html):
            raise SystemExit(
                "Nao encontrei o ponto de insercao da parte 2 (import ... runExportedApp({). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = IMPORT_TO_CALL_RE.sub(lambda m: WAIT_BLOCK, html, count=1)
        print("Parte 2/2 aplicada: runExportedApp agora espera o controle REAL (sem atalho).")
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
