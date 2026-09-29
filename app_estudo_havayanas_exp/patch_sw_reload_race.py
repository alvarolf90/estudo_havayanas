#!/usr/bin/env python3
"""
Corrige uma corrida conhecida do shinylive (posit-dev/shinylive#133,
posit-dev/py-shiny-site#478): o loader padrao (shinylive/load-shinylive-sw.js)
recarrega a pagina baseado em navigator.serviceWorker.ready, que resolve
ANTES do Service Worker realmente assumir o controle da pagina (evento
"controllerchange"). Em navegadores WebKit (Safari desktop, Safari iOS,
Chrome/qualquer navegador no iOS, que usam WebKit por baixo) isso pode
deixar a pagina tentando buscar recursos internos do shinylive sem o SW
interceptando, gerando 404 real no GitHub Pages.

Este script precisa ser rodado toda vez depois de `shinylive::export()`,
pois o export regenera docs/index.html do zero (sem o patch). Ele e
idempotente: pode ser rodado varias vezes sem duplicar o patch.

Uso: python3 patch_sw_reload_race.py [caminho_para_docs/index.html]
"""
import sys
from pathlib import Path

MARKER = "shinylive-sw-reloaded"

PATCH_SCRIPT = '''<script>
    // Fix: posit-dev/shinylive#133 - navigator.serviceWorker.ready resolve
    // antes do controllerchange real (afeta Safari/WebKit). Baseado no
    // patch usado em posit-dev/py-shiny-site#478.
    (function () {
      var container = navigator.serviceWorker;
      if (!container) return;
      var nativeReady = Object.getOwnPropertyDescriptor(
        ServiceWorkerContainer.prototype,
        "ready"
      ).get;
      var reloadedKey = "''' + MARKER + '''";
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
    if MARKER in html:
        print(f"Ja patcheado (marcador '{MARKER}' encontrado), nada a fazer: {index_path}")
        return False
    needle = '    <script\n      src="./shinylive/load-shinylive-sw.js"'
    if needle not in html:
        raise SystemExit(
            "Nao encontrei o ponto de insercao esperado (script load-shinylive-sw.js). "
            "O formato do index.html exportado pode ter mudado - ajuste o script."
        )
    new_html = html.replace(needle, PATCH_SCRIPT + needle, 1)
    index_path.write_text(new_html, encoding="utf-8")
    print(f"Patch aplicado com sucesso: {index_path}")
    return True

if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/index.html")
    patch(target)
