#!/usr/bin/env python3
"""
Corrige duas corridas conhecidas do shinylive envolvendo o Service Worker
e a rota virtual do iframe interno do app (tipo app_<hash>/):

1) posit-dev/shinylive#133 / posit-dev/py-shiny-site#478: a pagina chama
   runExportedApp() (que cria o iframe) ANTES do SW estar de fato
   controlando a pagina.

2) Confirmado ao vivo via Web Inspector (Safari, iPhone) em 2026-09-29,
   e de novo em 2026-09-29 apos a correcao da parte 1+2 nao resolver:
   MESMO com o SW ja no controle (navigator.serviceWorker.controller
   truthy) antes de criar o iframe, a navegacao do iframe pra rota
   virtual as vezes ainda passa direto pra rede (bug conhecido do
   WebKit/iOS: uma requisicao originada de dentro de um iframe nem
   sempre e interceptada pelo fetch handler do SW, mesmo com o SW
   controlando a pagina) e cai no 404 real do GitHub Pages - o erro
   customizado do proprio shinylive-sw.js ("Couldn't find parent page")
   NAO aparece, confirmando que a requisicao nem chega no fetch handler
   do SW. Como o iframe ocupa a tela inteira, parece que o app inteiro
   deu 404.

Tres partes, todas necessarias, com propositos DIFERENTES e por isso
NAO devem compartilhar o mesmo timeout:

1. Sobrescreve navigator.serviceWorker.ready pra so resolver quando o
   SW REALMENTE assumir o controle (evento controllerchange), com uma
   janela de seguranca de 2s + no maximo 1 reload de pagina inteira por
   aba (nunca loop infinito) - baseado no patch usado em
   posit-dev/py-shiny-site#478. Esse timeout de 2s existe so pra decidir
   "desisto e recarrego a pagina", nao pra dizer "pode seguir em frente
   sem controle real".
2. Faz o script que cria o app (runExportedApp) ESPERAR o controle REAL
   do SW antes de criar o iframe - usando uma espera PROPRIA, SEM o
   atalho de timeout da parte 1 (se usasse o mesmo .ready patcheado, o
   timeout de 2s da parte 1 liberaria a criacao do iframe cedo demais de
   novo - foi exatamente esse o bug da primeira tentativa desse patch).
   Se o controle nunca vier, quem resolve e o reload de pagina inteira
   feito pela parte 1 (que cancela essa espera pendente de qualquer
   forma).
3. Observa o iframe interno (via MutationObserver) e, quando ele navega
   pra uma rota app_<hash>/ e o resultado e o 404 real do GitHub Pages
   (identificado pelo titulo do documento carregado, "... GitHub
   Pages" - nao pelo erro customizado do shinylive-sw.js, que e
   diferente), tenta de novo SO a navegacao do iframe (nao a pagina
   toda - evita perder o webR/R.wasm ja carregado, ~12MB) ate 3 vezes
   com atraso crescente, usando um parametro de cache-bust na URL pra
   garantir uma requisicao nova de verdade.

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). E
idempotente: pode ser rodado varias vezes sem duplicar nada, e se
rodado sobre um docs/index.html com uma versao ANTIGA de alguma parte
(ex: parte 2 com o bug do timeout compartilhado, ou sem a parte 3), ele
substitui pela versao corrigida/atual.

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import re
import sys
from pathlib import Path

MARKER_1 = "shinylive-sw-reloaded"
MARKER_2 = "espera-controle-real-sem-atalho-de-timeout"
MARKER_3 = "observa-iframe-404-github-pages-e-tenta-de-novo"

PATCH_SCRIPT = """<script>
    // Fix (parte 1/3): posit-dev/shinylive#133 - navigator.serviceWorker.ready
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
# anterior (inclusive a buggy que reusava o .ready com atalho de 2s, e
# qualquer versao sem a parte 3).
WAIT_BLOCK = """import { runExportedApp } from "./shinylive/shinylive.js";
      // Fix (parte 2/3 - REPLACE_MARKER_2): espera o controle REAL
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
      // Fix (parte 3/3 - REPLACE_MARKER_3): mesmo com o SW ja controlando a
      // pagina (espera acima ja resolvida), a navegacao do iframe pra rota
      // virtual app_<hash>/ as vezes ainda passa direto pra rede (bug do
      // WebKit/iOS - a requisicao de um iframe nem sempre e interceptada
      // pelo fetch handler do SW). Isso cai no 404 real do GitHub Pages
      // (diferente do 404 customizado que o proprio shinylive-sw.js
      // devolveria se so a rota nao estivesse registrada ainda). Aqui a
      // gente observa o iframe e, se detectar esse 404 (pelo titulo do
      // documento carregado), tenta de novo SO a navegacao do iframe
      // (sem recarregar a pagina toda, que perderia o webR/R.wasm ja
      // carregado) ate 3 vezes com atraso crescente.
      (function () {
        var root = document.getElementById("root");
        if (!root) return;
        var maxRetries = 3;
        var seen = new WeakSet();
        function watch(iframe) {
          if (seen.has(iframe)) return;
          seen.add(iframe);
          var attempts = 0;
          iframe.addEventListener("load", function () {
            var doc;
            try {
              doc = iframe.contentDocument;
            } catch (e) {
              return;
            }
            if (!doc || !/\\/app_[^/]+\\//.test(iframe.src || "")) return;
            if ((doc.title || "").indexOf("GitHub Pages") === -1) return;
            if (attempts >= maxRetries) {
              console.log("[fix iframe 404] excedeu " + maxRetries + " tentativas, desistindo.");
              return;
            }
            attempts++;
            console.log(
              "[fix iframe 404] iframe caiu no 404 do GitHub Pages, tentativa " +
                attempts +
                " de " +
                maxRetries +
                "."
            );
            setTimeout(function () {
              var base = iframe.src.split("?")[0];
              iframe.src = base + "?_retry=" + Date.now();
            }, 400 * attempts);
          });
        }
        new MutationObserver(function () {
          var f = root.querySelector("iframe");
          if (f) watch(f);
        }).observe(root, { childList: true, subtree: true });
        var already = root.querySelector("iframe");
        if (already) watch(already);
      })();
      runExportedApp({""".replace("REPLACE_MARKER_2", MARKER_2).replace(
    "REPLACE_MARKER_3", MARKER_3
)

# Qualquer variante anterior da parte 2/3 que precise ser removida antes de
# inserir a nova (incluindo versoes buggy ou sem a parte 3), identificada
# pelo import seguido de comentarios/codigo ate chegar em "runExportedApp({".
IMPORT_TO_CALL_RE = re.compile(
    r'import \{ runExportedApp \} from "\./shinylive/shinylive\.js";.*?runExportedApp\(\{',
    re.S,
)


def patch(index_path: Path) -> bool:
    html = index_path.read_text(encoding="utf-8")
    changed = False

    # Parte 1: sobrescreve o getter .ready
    if MARKER_1 in html:
        print(f"Parte 1/3 ja aplicada (marcador '{MARKER_1}' encontrado).")
    else:
        needle1 = '    <script\n      src="./shinylive/load-shinylive-sw.js"'
        if needle1 not in html:
            raise SystemExit(
                "Nao encontrei o ponto de insercao da parte 1 (script load-shinylive-sw.js). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = html.replace(needle1, PATCH_SCRIPT + needle1, 1)
        print("Parte 1/3 aplicada: getter navigator.serviceWorker.ready sobrescrito.")
        changed = True

    # Partes 2 e 3: substitui (idempotente) o bloco entre o import e runExportedApp({
    if MARKER_2 in html and MARKER_3 in html:
        print(f"Partes 2/3 e 3/3 ja aplicadas e atualizadas.")
    else:
        if not IMPORT_TO_CALL_RE.search(html):
            raise SystemExit(
                "Nao encontrei o ponto de insercao das partes 2/3 (import ... runExportedApp({). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = IMPORT_TO_CALL_RE.sub(lambda m: WAIT_BLOCK, html, count=1)
        print(
            "Partes 2/3 e 3/3 aplicadas: espera o controle real do SW e observa "
            "o iframe pra tentar de novo se cair no 404 do GitHub Pages."
        )
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
