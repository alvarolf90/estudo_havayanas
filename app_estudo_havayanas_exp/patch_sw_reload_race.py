#!/usr/bin/env python3
"""
Corrige corridas conhecidas do shinylive envolvendo o Service Worker (SW)
e a rota virtual do iframe interno do app (tipo app_<hash>/):

1) posit-dev/shinylive#133 / posit-dev/py-shiny-site#478: a pagina chama
   runExportedApp() (que cria o iframe) ANTES do SW estar de fato
   controlando a pagina.

2) Confirmado ao vivo via Web Inspector (Safari, iPhone) em 2026-09-29:
   MESMO com o SW ja no controle (navigator.serviceWorker.controller
   truthy) antes de criar o iframe, a navegacao do iframe pra rota
   virtual as vezes ainda passa direto pra rede e cai no 404 real do
   GitHub Pages - o erro customizado do proprio shinylive-sw.js
   ("Couldn't find parent page") NAO aparece, confirmando que a
   requisicao nem chega no fetch handler do SW.

3) Tentativa anterior (deploy f279e45) de reagir a esse 404 re-navegando
   O MESMO elemento iframe (com um parametro de cache-bust na URL) NAO
   funcionou: confirmado ao vivo que as 3 tentativas de retry, na MESMA
   sessao, falharam de forma IDENTICA (mesmo 404 real do GitHub Pages
   todas as vezes). Isso bate com relatos publicos (ver referencia
   abaixo) de que o WebKit as vezes nunca registra um iframe especifico
   como "client" controlado pelo SW - ou seja, o problema pode ser por
   IFRAME (nao por requisicao), e re-navegar o MESMO iframe nao da uma
   nova chance de verdade. Um iframe totalmente novo (criado do zero)
   teria uma chance independente - mas o iframe interno e gerenciado
   pelo React de dentro do shinylive.js (via viewerFrameRef), e
   substituir esse no do DOM por fora do React arrisca quebrar a
   reconciliacao do React (ex.: crash ao tentar remover um no que o
   React acha que ainda existe). Trocar so o iframe nao e seguro de
   fazer via patch externo.
   Referencia: "ServiceWorkers is not working in iFrame" (Apple Developer
   Forums, https://developer.apple.com/forums/thread/769673) - descreve
   isso como uma limitacao ampla do WebKit (nao so iOS, nao amarrada a
   uma versao especifica) de nao interceptar fetches originados de
   dentro de um iframe mesmo com o SW no controle da pagina pai.

Como um iframe novo so surge organicamente via um reload da pagina
inteira (o React remonta tudo do zero, incluindo um iframe com uma
"chance" nova), a primeira estrategia foi: se o iframe cair nesse 404
real do GitHub Pages, recarregar a PAGINA INTEIRA (nao so o iframe).

4) Confirmado ao vivo em 2026-09-29 (deploy 57c2665): o reload de pagina
   sozinho TAMBEM nao resolveu - o log mostrou DOIS carregamentos
   seguidos (dois app_<hash> diferentes) falhando de forma identica.
   Isso indica que o Service Worker continua sendo o MESMO durante um
   reload simples (reload nao forca um novo register()+activate()) -
   entao se o SW "travou" nesse estado ruim (nao interceptando fetches
   de iframe), so recarregar a pagina nao troca o SW, e o problema se
   repete. Por isso agora, antes de recarregar, a gente desregistra
   TODAS as registrations de Service Worker (navigator.serviceWorker.
   getRegistrations().unregister()) - isso forca o proximo load a
   registrar e ativar um SW genuinamente novo do zero, nao so uma
   pagina nova com o SW velho.

No maximo 1 tentativa (desregistrar + recarregar) por aba, pra nao
entrar em loop se o dispositivo realmente nao conseguir de jeito nenhum
(nesse caso o usuario fica no erro depois dessa 1 tentativa extra, em
vez de ficar recarregando pra sempre).

Cinco partes, cada uma com proposito e timeout PROPRIOS (nao
compartilhados entre si):

1. Sobrescreve navigator.serviceWorker.ready pra so resolver quando o
   SW REALMENTE assumir o controle (evento controllerchange), com uma
   janela de seguranca de 2s + no maximo 1 reload de pagina inteira por
   aba - baseado no patch usado em posit-dev/py-shiny-site#478. Esse
   timeout de 2s existe so pra decidir "desisto e recarrego a pagina",
   nao pra dizer "pode seguir em frente sem controle real".
2. Faz o script que cria o app (runExportedApp) ESPERAR o controle REAL
   do SW antes de criar o iframe - espera PROPRIA, SEM o atalho de
   timeout da parte 1 (reusar o .ready patcheado repetiria o bug da
   primeira tentativa desse patch, que liberava a criacao do iframe
   cedo demais).
3. Observa o iframe interno (via MutationObserver) e, se ele navegar
   pra uma rota app_<hash>/ e cair no 404 real do GitHub Pages
   (identificado pelo titulo do documento carregado, "... GitHub
   Pages"), desregistra o Service Worker e SO DEPOIS recarrega a
   pagina inteira - no maximo 1 vez por aba (contador proprio,
   separado do da parte 1).

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). E
idempotente: pode ser rodado varias vezes sem duplicar nada, e se
rodado sobre um docs/index.html com uma versao ANTIGA de alguma parte
(incluindo a tentativa anterior de retry no mesmo iframe, que nao
funcionou), ele substitui pela versao atual.

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import re
import sys
from pathlib import Path

MARKER_1 = "shinylive-sw-reloaded"
MARKER_2 = "espera-controle-real-sem-atalho-de-timeout"
MARKER_3 = "desregistra-sw-com-timeout-e-recarrega-se-iframe-cair-no-404"

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
# anterior (inclusive a tentativa de retry no mesmo iframe, que nao
# funcionou).
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
      // WebKit de nao registrar esse iframe especifico como "client"
      // controlado pelo SW - ver comentario no topo do script de patch).
      // Como isso parece ser por-iframe (nao por-requisicao), re-navegar
      // o MESMO iframe nao ajuda - confirmado ao vivo que 3 tentativas
      // assim falharam identicamente. Entao aqui a gente detecta o 404
      // real do GitHub Pages (pelo titulo do documento carregado) e
      // recarrega a PAGINA INTEIRA (que remonta um iframe novo do zero),
      // no maximo 1 vez por aba pra nao entrar em loop.
      (function () {
        var root = document.getElementById("root");
        if (!root) return;
        var reloadKey = "REPLACE_MARKER_3";
        var seen = new WeakSet();
        function watch(iframe) {
          if (seen.has(iframe)) return;
          seen.add(iframe);
          iframe.addEventListener("load", function () {
            var doc;
            try {
              doc = iframe.contentDocument;
            } catch (e) {
              return;
            }
            if (!doc || !/\\/app_[^/]+\\//.test(iframe.src || "")) return;
            if ((doc.title || "").indexOf("GitHub Pages") === -1) return;
            var count = 0;
            try {
              count = parseInt(sessionStorage.getItem(reloadKey) || "0", 10);
            } catch (e) {}
            if (count >= 1) {
              console.log(
                "[fix iframe 404] ja tentou desregistrar o SW e recarregar uma vez e o problema persistiu - desistindo."
              );
              return;
            }
            try {
              sessionStorage.setItem(reloadKey, String(count + 1));
            } catch (e) {}
            console.log(
              "[fix iframe 404] iframe caiu no 404 do GitHub Pages - desregistrando o Service Worker (nao so recarregando a pagina, que manteria o MESMO SW no controle) antes de tentar de novo do zero."
            );
            // Confirmado ao vivo em 2026-09-29: no iPhone do usuario, nenhum reload
            // aconteceu depois dessa deteccao (o HAR exportado so mostrava 1
            // carregamento de pagina) - suspeita forte e que getRegistrations()/
            // unregister() pode travar (nunca resolver) quando o proprio SW ja
            // esta num estado travado, o que impediria o .then() de chamar
            // reload(). Por isso agora o reload tem uma garantia de tempo (2s):
            // se o desregistro nao terminar nesse prazo, recarrega assim mesmo.
            var reloadOnce = (function () {
              var done = false;
              return function () {
                if (done) return;
                done = true;
                window.location.reload();
              };
            })();
            setTimeout(reloadOnce, 2000);
            Promise.resolve(
              navigator.serviceWorker
                ? navigator.serviceWorker.getRegistrations().then(function (regs) {
                    return Promise.all(
                      regs.map(function (r) {
                        return r.unregister();
                      })
                    );
                  })
                : null
            )
              .catch(function () {})
              .then(reloadOnce);
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

# Qualquer variante anterior das partes 2/3 que precise ser removida antes
# de inserir a nova, identificada pelo import seguido de comentarios/
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
            "Partes 2/3 e 3/3 aplicadas: espera o controle real do SW e, se o iframe "
            "cair no 404 do GitHub Pages, desregistra o SW e recarrega (no maximo 1 vez)."
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
