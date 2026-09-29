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

5) Confirmado ao vivo em 2026-09-29 (deploys 9/10/11, teoria dele de que o
   tamanho/tempo de boot do app suspenderia o SW por inatividade): mesmo
   eliminando quase por completo o tempo ocioso de rede durante o boot
   (keep-alive por postMessage+fetch a cada 500ms - ver KEEPALIVE_SCRIPT
   abaixo), o 404 continuou acontecendo, identico. Isso descarta a teoria
   de "SW suspenso por inatividade" como causa - o problema parece mesmo
   ser a limitacao categorica do WebKit da referencia acima (fetches de
   NAVEGACAO originados de dentro do iframe as vezes simplesmente nao
   sao interceptados, independente de quao "ativo"/fresco o SW esteja).

   A partir dessa conclusao, a parte 5 (nova) ataca a causa raiz direto:
   como o SW intercepta corretamente fetches originados do FRAME PAI
   (confirmado - o app principal sempre carrega bem, so a navegacao de
   DENTRO do iframe e que falha as vezes), ao detectar o 404 a gente
   busca o HTML real da mesma rota virtual (app_<hash>/) só que a
   partir do frame pai via fetch() normal, e injeta o resultado direto
   no DOCUMENTO do iframe que ja existe (document.open/write/close) -
   sem precisar de nenhum reload de pagina. Como o iframe ja "navegou"
   pra aquela URL (so que recebeu o 404 errado), a location dele ja e a
   certa, entao os recursos relativos (JS/CSS/wasm) do HTML injetado
   resolvem do jeito certo sem precisar de tag <base>. Risco conhecido/
   aceito: se o bug do WebKit tambem afetar fetches de SUB-RECURSO (nao
   so de navegacao) originados de dentro do iframe - o que os relatos
   publicos nao deixam claro -, os arquivos referenciados pelo HTML
   injetado poderiam falhar do mesmo jeito; por isso essa parte tem um
   temporizador de seguranca de 5s escutando erros de script dentro do
   iframe recem-injetado e, se algo der errado, cai pro plano B de
   sempre (parte 3: desregistrar o SW e recarregar a pagina inteira).
   Zero risco pros casos que ja funcionam - so entra em acao depois do
   404 real ja confirmado.

Mitigacao adicional pro item 5 (parte 4 abaixo, mantida mesmo com a
teoria de inatividade descartada - nao faz mal, e pode ainda ajudar em
outros cenarios): mandar um "ping" inofensivo pro SW durante a fase de
carregamento. O proprio shinylive-sw.js ja ignora silenciosamente
qualquer mensagem que nao seja do tipo "configureProxyPath" (visto no
codigo-fonte gerado), entao esse ping e seguro sem precisar alterar o
arquivo do SW.

No maximo REPLACE_MAX_RELOAD_RETRIES tentativas de "desregistrar SW +
recarregar a pagina inteira" por aba (mais 1 tentativa separada e mais
barata da parte 5, que nao recarrega nada), pra nao entrar em loop se o
dispositivo realmente nao conseguir de jeito nenhum.

Seis blocos de patch, cada um com proposito e timeout PROPRIOS (nao
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
   Pages"), tenta primeiro a parte 5 (abaixo); se ela falhar ou nao
   resolver a tempo, desregistra o Service Worker e SO DEPOIS recarrega
   a pagina inteira - no maximo REPLACE_MAX_RELOAD_RETRIES vezes por
   aba (contador proprio, separado do da parte 1).
4. Mantem o SW "vivo" com um ping (postMessage + fetch real) a cada
   REPLACE_INTERVAL_MSms durante o carregamento.
5. (NOVA, 2026-09-29) Ao detectar o 404 real, busca o HTML da mesma
   rota virtual a partir do FRAME PAI (fetch normal, que e interceptado
   corretamente pelo SW) e injeta o resultado direto no iframe existente
   via document.open/write/close - tentativa mais barata e menos
   disruptiva que recarregar a pagina inteira, tentada 1x por aba antes
   do plano B da parte 3.

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). E
idempotente: pode ser rodado varias vezes sem duplicar nada, e se
rodado sobre um docs/index.html com uma versao ANTIGA de qualquer parte,
ele SUBSTITUI pela versao atual (nao precisa de marcador novo so pra
mudar o MECANISMO/conteudo de uma parte).

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import re
import sys
from pathlib import Path

MARKER_1 = "shinylive-sw-reloaded"
MARKER_2 = "espera-controle-real-sem-atalho-de-timeout"
MARKER_3 = "desregistra-sw-com-timeout-e-recarrega-se-iframe-cair-no-404"
MARKER_4 = "mantem-sw-vivo-durante-carregamento-com-ping"
MARKER_5 = "busca-html-real-pelo-frame-pai-e-injeta-no-iframe-sem-reload"

MAX_RELOAD_RETRIES = 2

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

KEEPALIVE_SCRIPT = """<script>
    // Fix (parte 4 - REPLACE_MARKER_4): mantem o Service Worker "vivo" durante
    // a fase de carregamento do app, que pode ficar varios segundos sem
    // NENHUMA requisicao de rede enquanto o webR/R inicializa (so CPU
    // rodando). Mantido mesmo apos a teoria de "SW suspenso por
    // inatividade" ter sido descartada por HAR (ver item 5 no topo deste
    // script) - nao faz mal e o custo e desprezivel.
    //
    // v2 (2026-09-29): alem do postMessage (que so aciona o listener de
    // "message" do SW, sem garantia de resetar qualquer timer de
    // ociosidade que o WebKit use pra decidir suspender o SW), tambem
    // dispara um fetch() real e barato (reusando um arquivo pequeno ja
    // carregado, load-shinylive-sw.js, sem no-store) a cada tick.
    (function () {
      if (!navigator.serviceWorker) return;
      var count = 0;
      var maxPings = REPLACE_MAX_PINGS;
      var keepaliveUrl = (function () {
        var scripts = document.getElementsByTagName("script");
        for (var i = 0; i < scripts.length; i++) {
          var src = scripts[i].getAttribute("src") || "";
          if (src.indexOf("load-shinylive-sw.js") !== -1) return src;
        }
        return "./shinylive/load-shinylive-sw.js";
      })();
      var timer = setInterval(function () {
        count++;
        if (count > maxPings) {
          clearInterval(timer);
          return;
        }
        if (navigator.serviceWorker.controller) {
          try {
            navigator.serviceWorker.controller.postMessage({ type: "keepAlivePing" });
          } catch (e) {}
        }
        try {
          fetch(keepaliveUrl, { cache: "default" }).catch(function () {});
        } catch (e) {}
      }, REPLACE_INTERVAL_MS);
    })();
    </script>
    """.replace("REPLACE_MARKER_4", MARKER_4).replace("REPLACE_MAX_PINGS", "180").replace(
    "REPLACE_INTERVAL_MS", "500"
)

# Bloco que vai ANTES de "runExportedApp({" - substitui qualquer versao
# anterior (inclusive tentativas anteriores que nao funcionaram).
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
      // Fix (partes 3 e 5 - REPLACE_MARKER_3 / REPLACE_MARKER_5): mesmo com o
      // SW ja controlando a pagina (espera acima ja resolvida), a navegacao
      // do iframe pra rota virtual app_<hash>/ as vezes ainda passa direto
      // pra rede e cai no 404 real do GitHub Pages (bug conhecido do WebKit
      // de nao interceptar fetches de NAVEGACAO originados de dentro de um
      // iframe - ver referencia no topo do script de patch). Ao detectar
      // isso: primeiro tenta a parte 5 (busca o HTML real pelo FRAME PAI,
      // que e interceptado certinho pelo SW, e injeta direto no documento
      // do iframe existente - sem reload de pagina); se isso falhar ou nao
      // resolver dentro de 5s, cai pro plano B da parte 3 (desregistra o
      // SW e recarrega a PAGINA INTEIRA, no maximo REPLACE_MAX_RELOAD_RETRIES
      // vezes por aba pra nao entrar em loop).
      (function () {
        var root = document.getElementById("root");
        if (!root) return;
        var reloadKey = "REPLACE_MARKER_3";
        var softFixKey = "REPLACE_MARKER_5";
        var maxReloadRetries = REPLACE_MAX_RELOAD_RETRIES;
        var seen = new WeakSet();

        function hardReload() {
          var count = 0;
          try {
            count = parseInt(sessionStorage.getItem(reloadKey) || "0", 10);
          } catch (e) {}
          if (count >= maxReloadRetries) {
            console.log(
              "[fix iframe 404] ja tentou desregistrar o SW e recarregar " +
                maxReloadRetries +
                " vez(es) e o problema persistiu - desistindo."
            );
            return;
          }
          try {
            sessionStorage.setItem(reloadKey, String(count + 1));
          } catch (e) {}
          console.log(
            "[fix iframe 404] plano B: desregistrando o Service Worker (nao so " +
              "recarregando a pagina, que manteria o MESMO SW no controle) antes " +
              "de tentar de novo do zero (tentativa " + (count + 1) + "/" + maxReloadRetries + ")."
          );
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
        }

        function trySoftFix(iframe, onFail) {
          var appUrl = iframe.src;
          var settled = false;
          function fail(reason) {
            if (settled) return;
            settled = true;
            console.log("[fix iframe 404] parte 5 nao resolveu (" + reason + ") - caindo pro plano B.");
            onFail();
          }
          function ok() {
            if (settled) return;
            settled = true;
            console.log(
              "[fix iframe 404] parte 5: HTML real buscado pelo frame pai e injetado " +
                "direto no iframe, sem precisar recarregar a pagina."
            );
          }
          var errored = false;
          fetch(appUrl, { cache: "no-store" })
            .then(function (resp) {
              if (!resp.ok) throw new Error("fetch pelo frame pai tambem nao-ok (" + resp.status + ")");
              return resp.text();
            })
            .then(function (html) {
              if (/GitHub Pages/.test(html.slice(0, 2000))) {
                throw new Error("fetch pelo frame pai tambem caiu no 404 (raro - provavelmente o problema nao e so do iframe dessa vez)");
              }
              var doc = iframe.contentDocument;
              if (!doc) throw new Error("iframe.contentDocument inacessivel");
              try {
                iframe.contentWindow.addEventListener(
                  "error",
                  function () {
                    errored = true;
                  },
                  true
                );
              } catch (e) {}
              doc.open();
              doc.write(html);
              doc.close();
              setTimeout(function () {
                if (errored) {
                  fail("erro de script dentro do iframe apos injetar");
                } else {
                  ok();
                }
              }, 5000);
            })
            .catch(function (e) {
              fail((e && e.message) || String(e));
            });
        }

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
            var softTried = false;
            try {
              softTried = sessionStorage.getItem(softFixKey) === "1";
            } catch (e) {}
            if (!softTried) {
              try {
                sessionStorage.setItem(softFixKey, "1");
              } catch (e) {}
              console.log(
                "[fix iframe 404] iframe caiu no 404 do GitHub Pages - tentando a parte 5 " +
                  "(buscar HTML real pelo frame pai e injetar direto, sem reload)."
              );
              trySoftFix(iframe, hardReload);
              return;
            }
            hardReload();
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
).replace("REPLACE_MARKER_5", MARKER_5).replace(
    "REPLACE_MAX_RELOAD_RETRIES", str(MAX_RELOAD_RETRIES)
)

# Qualquer variante anterior das partes 2/3/5 que precise ser removida antes
# de inserir a nova, identificada pelo import seguido de comentarios/
# codigo ate chegar em "runExportedApp({".
IMPORT_TO_CALL_RE = re.compile(
    r'import \{ runExportedApp \} from "\./shinylive/shinylive\.js";.*?runExportedApp\(\{',
    re.S,
)

NEEDLE_LOAD_SW_SCRIPT = '    <script\n      src="./shinylive/load-shinylive-sw.js"'

# Qualquer variante anterior da parte 4 que precise ser removida antes de
# inserir a nova (ex.: trocar o intervalo/mecanismo do keep-alive sem
# precisar mudar o marcador) - identificada pelo comentario "Fix (parte 4"
# ate o PROXIMO </script> (nao-guloso: um bloco de keep-alive bem-formado
# e auto-contido, entao o primeiro </script> depois do comentario e o dele
# mesmo). Sem lookahead exigindo adjacencia imediata com o script do SW -
# isso ja foi tentado e é fragil: se QUALQUER outro trecho ficar entre o
# bloco antigo e o needle (ex.: a parte 1 sendo inserida na mesma
# passada), o lookahead falha e o ".*?" nao-guloso e forcado a "comer"
# pra frente ate o proximo </script> que SATISFACA o lookahead - o que
# pode engolir conteudo de outras partes por engano. patch() abaixo faz
# uma checagem de sanidade separada (o que vem logo depois do match tem
# que ser o needle) em vez de embutir isso na regex.
KEEPALIVE_BLOCK_RE = re.compile(
    r"<script>\s*// Fix \(parte 4.*?</script>",
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

    # Parte 4: ping periodico pro SW durante o carregamento (independente das
    # demais partes - insercao/idempotencia proprias). Substitui (idempotente)
    # qualquer versao anterior do bloco pra que mudar o MECANISMO do
    # keep-alive nao precise de um marcador novo.
    m4 = KEEPALIVE_BLOCK_RE.search(html)
    if m4:
        end = m4.end()
        # Tolera diferencas de espaco em branco entre o fim do bloco e o
        # needle (o regex nao captura mais o \s* final - ver comentario
        # acima de KEEPALIVE_BLOCK_RE - pra nao arriscar comer os espacos
        # que sao do proprio needle).
        rest = html[end:].lstrip()
        if not rest.startswith(NEEDLE_LOAD_SW_SCRIPT.lstrip()):
            raise SystemExit(
                "Bloco da parte 4 encontrado, mas nao esta logo antes do script "
                "load-shinylive-sw.js como esperado (checagem de sanidade falhou - "
                "ver comentario acima de KEEPALIVE_BLOCK_RE). O formato do "
                "index.html pode estar num estado inesperado - ajuste o script."
            )
        if m4.group(0).rstrip() == KEEPALIVE_SCRIPT.rstrip():
            print(f"Parte 4 ja aplicada e atualizada (marcador '{MARKER_4}').")
        else:
            html = KEEPALIVE_BLOCK_RE.sub(lambda m: KEEPALIVE_SCRIPT, html, count=1)
            print("Parte 4 atualizada: novo mecanismo de keep-alive pro Service Worker.")
            changed = True
    else:
        if NEEDLE_LOAD_SW_SCRIPT not in html:
            raise SystemExit(
                "Nao encontrei o ponto de insercao da parte 4 (script load-shinylive-sw.js). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = html.replace(NEEDLE_LOAD_SW_SCRIPT, KEEPALIVE_SCRIPT + NEEDLE_LOAD_SW_SCRIPT, 1)
        print("Parte 4 aplicada: ping periodico pro Service Worker durante o carregamento.")
        changed = True

    # Partes 2/3/5: substitui (idempotente, por CONTEUDO, igual a parte 4)
    # o bloco entre o import e runExportedApp({ - assim, mudar a LOGICA de
    # qualquer uma dessas partes (como a parte 5 nova) se aplica automatico
    # sobre um docs/index.html com versao antiga, sem precisar de marcador
    # novo soh pra isso.
    existing_block = IMPORT_TO_CALL_RE.search(html)
    if existing_block and existing_block.group(0) == WAIT_BLOCK:
        print("Partes 2/3/5 ja aplicadas e atualizadas.")
    else:
        if not existing_block:
            raise SystemExit(
                "Nao encontrei o ponto de insercao das partes 2/3/5 (import ... runExportedApp({). "
                "O formato do index.html exportado pode ter mudado - ajuste o script."
            )
        html = IMPORT_TO_CALL_RE.sub(lambda m: WAIT_BLOCK, html, count=1)
        print(
            "Partes 2/3/5 aplicadas/atualizadas: espera o controle real do SW e, se o "
            "iframe cair no 404 do GitHub Pages, tenta buscar+injetar o HTML real pelo "
            "frame pai (parte 5) antes de desregistrar o SW e recarregar a pagina (parte 3)."
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
