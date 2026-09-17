library(shiny)
library(bslib)
library(shinyjs)
 
# ==============================================================================
# 1. LEITURA DE DADOS E CONFIGURAÇÕES GERAIS
# ==============================================================================

caminho_levadas <- "www/levadas.csv"
caminho_convencoes <- "www/convencoes.csv"

limpar_nome_imagem <- function(texto) {
  if (is.null(texto) || is.na(texto) || trimws(texto) == "") return("")
  
  # Remove acentos manualmente de forma compatível entre Windows/Mac/Linux
  texto_sem_acento <- chartr(
    "áàãâéêíóôõúüçÁÀÃÂÉÊÍÓÔÕÚÜÇ", 
    "aaaaeeiooouucAAAAEEIOOOUUC", 
    texto
  )
  
  # Converte para minúsculas e troca espaços por underline
  texto_limpo <- tolower(trimws(texto_sem_acento))
  texto_limpo <- gsub("\\s+", "_", texto_limpo)
  
  return(texto_limpo)
}

# TRATAMENTO SEGURO PARA SHINYLIVE
if (file.exists(caminho_levadas) && file.exists(caminho_convencoes)) {
  df_levadas <- read.csv(caminho_levadas, sep = ";", stringsAsFactors = FALSE)
  df_convencoes <- read.csv(caminho_convencoes, sep = ";", stringsAsFactors = FALSE)
} 

dict_variada <- c(
  "PeTaLa" = "pe ta la", "Pe" = "pe -- -- --", "PeLe" = "pe -- le --",
  "PeTeLeCo" = "pe te le co", "Pe----Co" = "pe -- -- co", "TeLeCo" = "-- te le co",
  "PeTeLe--" = "pe te le --", "Pe--LeCo" = "pe -- le co", "PeTe--Co" = "pe te -- co", "Pausa" = "-- -- -- --"
)

levadas_disponiveis <- unique(c(df_levadas$Levada, "Variada"))
convencoes_disponiveis <- unique(df_convencoes$Convencao)
instrumentos_disponiveis <- unique(c(df_levadas$Instrumento, df_convencoes$Instrumento))

todos_padroes <- unique(c(levadas_disponiveis, convencoes_disponiveis))
map_imagens <- sapply(todos_padroes, function(nome) {
  nome_limpo <- limpar_nome_imagem(nome)
  return(paste0(nome_limpo, ".png"))
}, USE.NAMES = TRUE)

arquivos_wav <- sapply(instrumentos_disponiveis, function(nome) {
  nome_limpo <- tolower(nome)
  nome_limpo <- iconv(nome_limpo, to = "ASCII//TRANSLIT")
  nome_limpo <- gsub("['\"~^`´]", "", nome_limpo)
  nome_limpo <- gsub("\\s+", "_", trimws(nome_limpo))
  nome_limpo <- gsub("[^a-z0-9_]", "", nome_limpo)
  return(paste0(nome_limpo, ".wav"))
})
map_wav_js <- paste0("{", paste(sprintf("'%s': '%s'", instrumentos_disponiveis, arquivos_wav), collapse = ", "), "}")

# ==============================================================================
# 2. INTERFACE DO USUÁRIO (UI)
# ==============================================================================
ui <- page_sidebar(
  title = div(style = "color: white; font-weight: 900; font-style: italic; letter-spacing: -1px;", "HAVAYANAS USADAS"),
  theme = bs_theme(version = 5, "font-sans-serif" = "system-ui, -apple-system, sans-serif"),
  useShinyjs(),
  
  tags$head(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"),
    tags$style(HTML("
      body, .bslib-page-sidebar, .bslib-sidebar-layout > .main { background-color: #5E2157 !important; }
      .navbar { background-color: #EF6C00 !important; border-bottom: none; box-shadow: 0 4px 10px rgba(0,0,0,0.3); }
      .sidebar { background-color: #FFFFFF !important; border-right: none !important; box-shadow: 2px 0 10px rgba(0,0,0,0.2); }
      .sidebar label, .sidebar h1, .sidebar h2, .sidebar h3, .sidebar h4, .sidebar h5, .sidebar h6 { color: #5E2157 !important; font-weight: bold; }
      .sidebar .accordion-button { color: #5E2157 !important; font-weight: bold; }
      .sidebar .accordion-button:not(.collapsed) { background-color: #FFF3E0 !important; color: #EF6C00 !important; }
      .card { background-color: #FFFFFF !important; border: none; box-shadow: 0 10px 25px rgba(0,0,0,0.3); border-radius: 16px; margin: 15px;}
      .btn-primary { background-color: #EF6C00 !important; border-color: #EF6C00 !important; color: white !important; }
      .btn-primary:hover { background-color: #E65C00 !important; }
      .btn-container { display: flex; width: 100%; margin-bottom: 10px;}
      .btn-container > button { flex: 1; font-weight: bold; min-height: 52px; touch-action: manipulation; }
      .btn-modo-tab { background-color: rgba(255,255,255,0.15); color: white; border: 2px solid white; font-weight: bold; padding: 10px 22px; border-radius: 30px; }
      .btn-modo-tab.btn-modo-ativo { background-color: white; color: #5E2157; }
      
      .painel-condutor { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: stretch; gap: 15px; width: 100%; margin-bottom: 15px; min-height: 260px; }
      .box-atual { border: 2px solid #bdc3c7; border-radius: 12px; padding: 15px; flex: 1 1 20%; min-width: 150px; background: #f8f9fa; display: flex; flex-direction: column; align-items: center; justify-content: center; box-shadow: inset 0 0 10px rgba(0,0,0,0.05); transition: opacity 0.3s ease; }
      .box-proximo { border: 4px solid #EF6C00; border-radius: 12px; padding: 15px; flex: 1 1 35%; min-width: 250px; background: white; box-shadow: 0 8px 20px rgba(239,108,0,0.15); display: flex; flex-direction: column; align-items: center; justify-content: center; position: relative; overflow: hidden; transition: box-shadow 0.3s ease; }
      .box-contagem { border: 4px solid #5E2157; border-radius: 12px; padding: 15px; flex: 1 1 35%; min-width: 250px; background: white; box-shadow: 0 8px 20px rgba(94,33,87,0.15); display: flex; flex-direction: column; align-items: center; justify-content: center; }
      
      .contador-numero { font-size: clamp(5rem, 8vw, 7.5rem); font-weight: 900; color: #5E2157; line-height: 1; text-shadow: 2px 2px 5px rgba(0,0,0,0.1); display: flex; align-items: center; justify-content: center; height: auto; }
      .texto-desfoque { opacity: 0.25; filter: grayscale(100%); }
      @keyframes blinker { 0% { opacity: 1; } 50% { opacity: 0.2; } 100% { opacity: 1; } }
      .piscar { animation: blinker 1s linear infinite; }
      
      #texto_peteleco { font-size: clamp(14px, 1.8vw, 24px); font-family: monospace; font-weight: bold; color: #2c3e50; line-height: 1.6; text-align: center; padding: 0; margin: 0; min-height: 70px; display: flex; flex-direction: column; justify-content: center; align-items: center; }
      .span-tempo { transition: color 0.1s ease-in-out; display: inline-block; border-radius: 4px; }
      .acomp-panel { margin-top: 15px; padding: 12px; border-left: 4px solid #EF6C00; background-color: #fcfcfc; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }

      @media (max-width: 768px) {
        .painel-condutor { flex-direction: column; }
        .box-atual, .box-proximo, .box-contagem { width: 100% !important; min-height: 150px; }
        .contador-numero { height: 120px; }
      }
    ")),
    
    # ==========================================================================
    # MOTOR JAVASCRIPT
    # ==========================================================================
    tags$script(HTML(paste0("
      window.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      window.masterGain = window.audioCtx.createGain();
      window.masterGain.connect(window.audioCtx.destination);

      $(document).on('click', '#btn_play', function() {
          if (window.audioCtx && window.audioCtx.state === 'suspended') window.audioCtx.resume();
      });

      window.measureQueue = [];
      window.isPlaying = false;
      window.audioQueueTime = 0;
      window.schedulerTimer = null;
      window.metadeAtiva = 1;

      window.sampleBuffers = {};
      window.wavMap = ", map_wav_js, ";

      window.playSample = function(buffer, time, vol, isSeca) {
        const source = window.audioCtx.createBufferSource();
        source.buffer = buffer;
        const gainNode = window.audioCtx.createGain();
        gainNode.gain.setValueAtTime(vol, time);

        if (isSeca) {
          gainNode.gain.setValueAtTime(vol, time + 0.02);
          gainNode.gain.exponentialRampToValueAtTime(0.001, time + 0.05);
          source.connect(gainNode);
          gainNode.connect(window.masterGain);
          source.start(time);
          source.stop(time + 0.06);
        } else {
          source.connect(gainNode);
          gainNode.connect(window.masterGain);
          source.start(time);
        }
      };

      window.preloadSamples = function() {
        for (let inst in window.wavMap) {
          fetch(window.wavMap[inst])
            .then(r => { if(r.ok) return r.arrayBuffer(); throw new Error('Falha no fetch'); })
            .then(ab => window.audioCtx.decodeAudioData(ab))
            .then(buf => { window.sampleBuffers[inst] = buf; })
            .catch(e => console.log('WAV ignorado ou falhou: ' + window.wavMap[inst]));
        }
      };
      window.preloadSamples();

      // ==========================================================================
      // SEQUENCIAS PROGRAMADAS (link com a sequencia embutida na URL)
      // ==========================================================================
      window.sequenciaModo = false;

      window.codificarSequencia = function(obj) {
        var json = JSON.stringify(obj);
        var b64 = btoa(unescape(encodeURIComponent(json)));
        return b64.replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
      };

      window.decodificarSequencia = function(str) {
        var b64 = str.replace(/-/g, '+').replace(/_/g, '/');
        while (b64.length % 4) b64 += '=';
        var json = decodeURIComponent(escape(atob(b64)));
        return JSON.parse(json);
      };


      Shiny.addCustomMessageHandler('gerarLinkSequencia', function(seqObj) {
        var codigo = window.codificarSequencia(seqObj);
        var base = window.top.location.origin + window.top.location.pathname;
        var url = base + '#seq=' + codigo;
        var qr = 'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=' + encodeURIComponent(url);
        Shiny.setInputValue('link_sequencia_gerado', {url: url, qr: qr}, {priority: 'event'});
      });

      function verificarSequenciaNaURL() {
        var hash = window.top.location.hash;
        if (hash && hash.indexOf('#seq=') === 0) {
          try {
            var codigo = hash.substring(5);
            var seqObj = window.decodificarSequencia(codigo);
            window.sequenciaModo = true;
            Shiny.setInputValue('sequencia_da_url', seqObj, {priority: 'event'});
          } catch (e) {
            console.log('Link de sequencia invalido: ' + e);
          }
        }
      }
      $(document).on('shiny:connected', function() { verificarSequenciaNaURL(); });

      function getNoiseBuffer() {
        if (window.noiseBuffer) return window.noiseBuffer;
        let bSize = window.audioCtx.sampleRate * 1.0; let b = window.audioCtx.createBuffer(1, bSize, window.audioCtx.sampleRate);
        let out = b.getChannelData(0); for (let i = 0; i < bSize; i++) { out[i] = Math.random() * 2 - 1; }
        window.noiseBuffer = b; return b;
      }

      window.stopPlayback = function() {
        window.isPlaying = false; window.measureQueue = [];
        if(window.schedulerTimer) clearInterval(window.schedulerTimer);
        if(window.masterGain) window.masterGain.disconnect();
        window.masterGain = window.audioCtx.createGain(); window.masterGain.connect(window.audioCtx.destination);

        $('#status_texto').text('Pronto para o ensaio! Escolha as levadas e toque.');
        $('#nome_padrao_atual').text('-');
        $('#imagem_sinal_atual').html('<div style=\"height: 80px;\">-</div>');
        $('#conteudo_contador').html('<div class=\"contador-numero texto-desfoque\">-</div>');
        $('#box_proximo_container').html('<div style=\"display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; opacity: 0.3;\"><h2 style=\"font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 0;\">-</h2></div>');
        $('#texto_peteleco').html('Nenhum sinal ativo no momento.');
      }

      function playOscillator(freq, time, dur, vol, type = 'sine') {
        const osc = window.audioCtx.createOscillator(); const gain = window.audioCtx.createGain();
        osc.type = type; osc.connect(gain); gain.connect(window.masterGain);
        osc.frequency.setValueAtTime(freq, time); gain.gain.setValueAtTime(vol, time);
        gain.gain.exponentialRampToValueAtTime(0.001, time + dur); osc.start(time); osc.stop(time + dur);
      }

      function playAcousticDrum(freq, time, dur, vol, isGrave, isAlta, isSeca) {
        if (isSeca) { dur = 0.03; vol = vol * 0.9; }
        if (isGrave) {
          const osc = window.audioCtx.createOscillator(); const gain = window.audioCtx.createGain();
          osc.type = 'sine'; osc.frequency.setValueAtTime(freq * 1.8, time); osc.frequency.exponentialRampToValueAtTime(freq * (isSeca ? 1.1 : 0.6), time + dur);
          gain.gain.setValueAtTime(vol * 1.8, time); gain.gain.exponentialRampToValueAtTime(0.001, time + dur);
          osc.connect(gain); gain.connect(window.masterGain); osc.start(time); osc.stop(time + dur);
          const noise = window.audioCtx.createBufferSource(); noise.buffer = getNoiseBuffer();
          const filter = window.audioCtx.createBiquadFilter(); filter.type = 'lowpass'; filter.frequency.setValueAtTime(300, time);
          const noiseGain = window.audioCtx.createGain(); noiseGain.gain.setValueAtTime(vol * 0.4, time); noiseGain.gain.exponentialRampToValueAtTime(0.01, time + 0.02);
          noise.connect(filter); filter.connect(noiseGain); noiseGain.connect(window.masterGain); noise.start(time); noise.stop(time + 0.02);
        } else {
          const noise = window.audioCtx.createBufferSource(); noise.buffer = getNoiseBuffer();
          const filter = window.audioCtx.createBiquadFilter(); filter.type = isAlta ? 'highpass' : 'bandpass'; filter.frequency.setValueAtTime(isAlta ? 1800 : freq * 2, time); filter.Q.value = 3.0;
          const noiseGain = window.audioCtx.createGain(); noiseGain.gain.setValueAtTime(vol * (isAlta ? 1.6 : 1.0), time); noiseGain.gain.exponentialRampToValueAtTime(0.001, time + (isAlta ? dur * 1.2 : dur));
          noise.connect(filter); filter.connect(noiseGain); noiseGain.connect(window.masterGain); noise.start(time); noise.stop(time + dur * 1.2);
          playOscillator(freq, time, dur * 0.8, vol * 0.6, 'triangle');
        }
      }

      function playSyntheticSound(tipo, time, pack, instrumento_str, timbre, isPrincipal) {
        let token = tipo.trim(); if (token === '--' || token === '') return;
        let cleanToken = token.replace(/[*~]/g, ''); let base = cleanToken.toLowerCase().replace(/[^a-z]/g, '');
        let isAlta = (cleanToken === cleanToken.toUpperCase() && base !== '');
        let isRulo = token.includes('~'); let isSeca = token.includes('*');
        let inst = instrumento_str ? instrumento_str : 'Caixa';
        let balanceVol = 1.0;
        if (isPrincipal) {
            balanceVol = window.volPrincipal !== undefined ? window.volPrincipal : 1.0;
        } else {
            if (window.volAcompMap && window.volAcompMap[inst] !== undefined) {
                balanceVol = window.volAcompMap[inst];
            } else {
                balanceVol = 0.5;
            }
        }
        let instVol = 1.0; let instLow = inst.toLowerCase();

        let baseFreq = 400;
        if (instLow.includes('surdo') || instLow.includes('fundo') || instLow.includes('marca')) { baseFreq = 140; instVol = 1.3; }
        else if (instLow.includes('repique') || instLow.includes('bacurinha')) { baseFreq = 500; instVol = 0.6; }
        else if (instLow.includes('dobra')) { baseFreq = 250; instVol = 1.1; }
        else if (instLow.includes('timbal')) { baseFreq = 180; instVol = 1.0; }
        else if (instLow.includes('caixa')) { baseFreq = 300; instVol = 0.45; }

        if (timbre === 'Meus Sons (.wav)') {
            let buffer = window.sampleBuffers[inst];
            if (buffer) {
                let volWav = (isAlta ? 1.0 : 0.5) * balanceVol * instVol;
                if (isRulo) {
                  window.playSample(buffer, time, volWav*0.7, false);
                  window.playSample(buffer, time+0.035, volWav*0.7, false);
                  window.playSample(buffer, time+0.07, volWav, isSeca);
                }
                else if (base !== '') { window.playSample(buffer, time, volWav, isSeca); }
                return;
            } else { timbre = 'Orgânico / Acústico'; }
        }

        let freq = baseFreq; let isGrave = (baseFreq < 200);
        let dur = isGrave ? 0.16 : 0.08; let vol = (isGrave ? (0.5 * 1.4) : 0.5) * balanceVol * instVol;
        if (isAlta) { vol = vol * 1.8; dur = dur * 1.3; }

        if (timbre === 'Orgânico / Acústico') {
            if (isRulo) { playAcousticDrum(freq, time, 0.03, vol*0.6, isGrave, false, false); playAcousticDrum(freq, time+0.035, 0.03, vol*0.7, isGrave, false, false); playAcousticDrum(freq, time+0.07, 0.04, vol, isGrave, isAlta, isSeca); }
            else { if(base !== '') playAcousticDrum(freq, time, dur, vol, isGrave, isAlta, isSeca); }
        } else if (timbre === 'Eletrônico / Punch') {
            let wave = isAlta ? 'sawtooth' : (isGrave ? 'square' : 'triangle'); if (isSeca) dur = 0.02;
            if (isRulo) { playOscillator(freq, time, 0.02, vol*0.7, wave); playOscillator(freq, time+0.035, 0.02, vol*0.7, wave); playOscillator(freq, time+0.07, 0.03, vol, wave); }
            else { if(base !== '') playOscillator(freq, time, dur, vol * 1.2, wave); }
        } else {
            let type = isGrave ? 'triangle' : 'sine'; if (isAlta) type = 'square'; if (isSeca) dur = 0.02;
            if (isRulo) { playOscillator(freq, time, 0.02, vol*0.7, 'square'); playOscillator(freq, time+0.035, 0.02, vol*0.7, 'square'); playOscillator(freq, time+0.07, 0.03, vol, 'square'); }
            else { if(base !== '') playOscillator(freq, time, dur, vol, type); }
        }
      }

      function formatPetelecoLine(linha_str, offset) {
        if (!linha_str) return '';
        let html = []; 
        let tempos = linha_str.split('|');
        
        for (let i = 0; i < tempos.length; i++) {
            let parts = tempos[i].trim().split(/\\s+/); 
            for (let j = 0; j < parts.length; j++) {
                
                if (parts[j] === '--') {
                    if (j === 0) {
                        parts[j] = '<span style=\"display: inline-flex; align-items: center; justify-content: center; padding: 0 4px; color: #bdc3c7;\">(pe)</span>';
                    } else {
                        parts[j] = '<span style=\"display: inline-flex; align-items: center; justify-content: center; padding: 0 4px; visibility: hidden;\">--</span>';
                    }
                    continue;
                }
                
                let sub_parts = parts[j].split('.'); let fmt_sub = [];
                for(let k=0; k<sub_parts.length; k++) {
                    let sp = sub_parts[k]; let isSeca = sp.includes('*'); let clean = sp.replace('*', '');
                    let txt = clean.toLowerCase();
                    if (clean.includes('~')) txt = '<i>' + clean.replace('~','').toUpperCase() + '</i>';
                    else if (/[A-Z]/.test(clean) && clean === clean.toUpperCase()) txt = '<b>' + clean + '</b>';
                    if(isSeca) txt += '*'; fmt_sub.push(txt);
                }
                // Usando inline-flex com altura fixa e centralização vertical para travar o eixo y
                parts[j] = '<span style=\"display: inline-flex; align-items: center; justify-content: center; padding: 0 6px; height: 1.5em;\">' + fmt_sub.join('.') + '</span>';
            }
            
            html.push(\"<span id='span-tempo-\" + (i + 1 + offset) + \"' class='span-tempo' style='display: inline-flex; align-items: center; justify-content: center; flex: 1; padding: 4px 0;'>\" + parts.join(' ') + \"</span>\");
        }
        
        return \"<div style='display: flex; justify-content: space-around; align-items: center; width: 100%; height: 100%;'><span style='color: #bdc3c7; font-weight: bold; margin-right: 8px;'>|</span> \" + html.join(\" \") + \" <span style='color: #bdc3c7; font-weight: bold; margin-left: 8px;'>|</span></div>\";
      }

      Shiny.addCustomMessageHandler(\"startPlayback\", function(payload) {
          if (window.audioCtx.state === 'suspended') window.audioCtx.resume();
          window.isPlaying = true;
          window.bpm = parseFloat(payload.bpm);
          window.timbre = payload.timbre;
          window.instPrincipal = payload.instPrincipal; window.isLoop = payload.isLoop;
          window.measureQueue = payload.batch;
          window.metadeAtiva = 1;

          let now = window.audioCtx.currentTime; let beatDur = 60.0 / window.bpm;
          window.audioQueueTime = now + 0.1;

          for (let i = 0; i < 4; i++) {
              let beepTime = window.audioQueueTime + (i * beatDur);
              playOscillator(880, beepTime, 0.05, 0.5, 'sine');
              let num = i + 1;

              if (i === 3 && window.measureQueue[0] && window.measureQueue[0].nome.toLowerCase() === 'c2') {
                  Object.keys(window.measureQueue[0].strings).forEach(inst => {
                      if (inst === 'Caixa' || inst === 'Repique') {
                          let t1 = beepTime + (beatDur * 0.75);
                          let t2 = beepTime + (beatDur * 0.875);
                          let isP = (inst === window.instPrincipal);
                          playSyntheticSound('co', t1, '1', inst, window.timbre, isP);
                          playSyntheticSound('co', t2, '1', inst, window.timbre, isP);
                      }
                  });
              }

              setTimeout(() => {
                  $('#status_texto').text('Atenção, bateria...');
                  $('#conteudo_contador').html('<div class=\"contador-numero\">' + num + '</div>');
                  
                  // ====== PISADA DO ROBÔ NA CONTAGEM INICIAL ====== //
                  // Alterna os pés a cada número da contagem (1, 2, 3, 4)
                  if (i === 0) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 1) { 
                      $('#foot-l').css('transform', 'translateX(15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 2) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 3) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(-15px)');
                  }
                  // =============================================== //
                  
                  let n = window.measureQueue[0];
                  let iH = n && n.img ? '<img src=\"' + n.img + '\" style=\"max-height: 90px; max-width: 100%; object-fit: contain;\">' : '<div style=\"height: 90px;\"></div>';
                  
                  $('#box_proximo_container').html('<div style=\"opacity:1; display:flex; flex-direction:column; align-items:center; justify-content:center; width:100%; height:100%;\"><h6 class=\"piscar\" style=\"color:#EF6C00; font-weight:bold; margin:0;\">ATENÇÃO BATERIA: PREPARA</h6><h2 style=\"font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 2px 0;\">' + (n ? n.nome : '-') + '</h2><div style=\"height: 100px; display: flex; align-items: center; justify-content: center; width: 100%;\">' + iH + '</div></div>');
              }, Math.max(0, (beepTime - window.audioCtx.currentTime) * 1000));
          }

          window.audioQueueTime += 4 * beatDur;
          if (window.schedulerTimer) clearInterval(window.schedulerTimer);

          window.schedulerTimer = setInterval(schedulerLoop, 100);
      });
      
      Shiny.addCustomMessageHandler(\"updateVolume\", function(v) {
          window.volPrincipal = v.p;
          window.volAcompMap = v.a;
      });


      Shiny.addCustomMessageHandler(\"appendBatch\", function(batch) { window.measureQueue.push(...batch); });

      function schedulerLoop() {
          if (!window.isPlaying) return;
          let now = window.audioCtx.currentTime;

          if (window.audioQueueTime < now) { window.audioQueueTime = now + 0.1; }

          while (window.measureQueue.length > 0 && window.audioQueueTime < now + 1.0) {
              let m = window.measureQueue.shift();
              let m_next = window.measureQueue.length > 0 ? window.measureQueue[0] : m;

              scheduleMeasure(m, m_next, window.audioQueueTime);

              let beatDurAtual = 60.0 / window.bpm;

              if (m.fim_sequencia) {
                  let delayMsFim = Math.max(0, ((window.audioQueueTime + beatDurAtual * 4) - window.audioCtx.currentTime) * 1000);
                  setTimeout(window.finalizarSequencia, delayMsFim);
                  window.audioQueueTime += beatDurAtual * 4;
                  break;
              }

              window.audioQueueTime += beatDurAtual * 4;
              window.metadeAtiva = (window.metadeAtiva === 1) ? 2 : 1;

              if (window.measureQueue.length < 8) { Shiny.setInputValue('js_request_batch', Math.random()); }
          }
      }

      window.finalizarSequencia = function() {
          window.isPlaying = false; window.measureQueue = [];
          if (window.schedulerTimer) clearInterval(window.schedulerTimer);
          if (window.masterGain) window.masterGain.disconnect();
          window.masterGain = window.audioCtx.createGain(); window.masterGain.connect(window.audioCtx.destination);

          $('#status_texto').text('Sequência concluída! Parabéns!');
          $('#nome_padrao_atual').text('-');
          $('#imagem_sinal_atual').html('<div style=\"height: 80px;\">-</div>');
          $('#conteudo_contador').html('<div class=\"contador-numero texto-desfoque\">-</div>');
          $('#box_proximo_container').html('<div style=\"display:flex; flex-direction:column; align-items:center; justify-content:center; width:100%; height:100%;\"><h2 style=\"font-size:1.8rem; color:#27ae60; font-weight:900; margin:0;\">CONCLUÍDO!</h2></div>');
          $('#texto_peteleco').html('Sequência concluída. Toque em Tocar para repetir do início.');

          Shiny.setInputValue('sequencia_terminou', Math.random(), {priority: 'event'});
      };

      function scheduleMeasure(m, m_next, startTime) {
          let beatDur = 60.0 / window.bpm; let delayMs = Math.max(0, (startTime - window.audioCtx.currentTime) * 1000);
          let currentMet = window.metadeAtiva;

          setTimeout(() => {
              if(!window.isPlaying) return;

              $('#status_texto').text('Tocando...');
              $('#nome_padrao_atual').text(m.nome);
              $('#imagem_sinal_atual').html(m.img ? '<img src=\"' + m.img + '\" style=\"max-height: 80px; max-width: 100%; object-fit: contain; filter: grayscale(40%); opacity: 0.9;\">' : '<div style=\"height: 80px;\">-</div>');

              if (window.isLoop) {
                  $('#conteudo_contador').html('<div class=\"contador-numero texto-desfoque\">∞</div>');
                  $('#box_proximo_container').html('<div style=\"display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; opacity: 0.3;\"><h2 style=\"font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 0;\">MODO LOOP</h2></div>').css('box-shadow', '0 8px 20px rgba(0,0,0,0.05)');
                              } else {
                                if (m.restantes === 1) {
                                  let iH = m.futuro_img ? '<img src=\"'+m.futuro_img+'\" style=\"max-height: 90px; max-width: 100%; object-fit: contain;\">' : '<div style=\"height: 90px;\"></div>';
                                  
                                  $('#conteudo_contador').html('<div class=\"contador-numero texto-desfoque\">-</div>');
                                  $('#box_proximo_container').html('<div style=\"display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%;\"><h6 class=\"piscar\" style=\"color: #EF6C00; font-weight: bold; margin: 0; min-height: 20px;\">ATENÇÃO BATERIA: PREPARA</h6><h2 style=\"font-size: 1.8rem; color: #5E2157; font-weight: 900; text-align: center; margin: 2px 0; min-height: 35px;\">' + (m.futuro || '-') + '</h2><div style=\"height: 100px; display: flex; align-items: center; justify-content: center; width: 100%;\">' + iH + '</div></div>').css('box-shadow', '0 8px 30px rgba(239,108,0,0.5)');
                                } else {
                                  $('#conteudo_contador').html('<div class=\"contador-numero texto-desfoque\">-</div>');
                                  $('#box_proximo_container').html('<div style=\"display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; opacity: 0.3;\"><h2 style=\"font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 0;\">-</h2><div style=\"position: absolute; color: #bdc3c7; font-weight: bold; font-style: italic; font-size: 1.3rem;\">MANTÉM...</div></div>').css('box-shadow', '0 8px 20px rgba(239,108,0,0.05)');
                                }
                              }

              let str1 = (currentMet === 1) ? m.html : m_next.html;
              let str2 = (currentMet === 1) ? m_next.html : m.html;
              $('#texto_peteleco').html('<div style=\"margin-bottom: 8px;\">' + formatPetelecoLine(str1, 0) + '</div><div>' + formatPetelecoLine(str2, 4) + '</div>');

          }, delayMs);

          for(let i=0; i<4; i++) {
              let dM = Math.max(0, (startTime + (i * beatDur) - window.audioCtx.currentTime) * 1000);
              let cId = (currentMet === 1) ? (i + 1) : (i + 5);
              
              setTimeout(() => {
                  if(!window.isPlaying) return;
                  
                  $('.span-tempo').css({'color': '', 'text-shadow': 'none'});
                  $('#span-tempo-' + cId).css({'color': '#EF6C00', 'text-shadow': '0px 0px 4px rgba(239,108,0,0.3)'});
                  
                  // ====== ANIMAÇÃO DO ROBÔ ====== //
                  
                  // 1. A Pisada Lateral (Abre, junta direita, abre, junta esquerda)
                  if (i === 0) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 1) { 
                      $('#foot-l').css('transform', 'translateX(15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 2) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(15px)');
                  } else if (i === 3) { 
                      $('#foot-l').css('transform', 'translateX(-15px)');
                      $('#foot-r').css('transform', 'translateX(-15px)');
                  }

                  // 2. Os Braços e os Olhos
                  if (!window.isLoop && m.restantes === 1) {
                      // Modo Alerta (Último compasso): Levanta os braços e pisca vermelho
                      $('#arm-l').css('transform', 'rotate(130deg)');
                      $('#arm-r').css('transform', 'rotate(-130deg)');
                      $('.robo-eye').attr('fill', '#EF6C00');
                      $('#robo-led').attr('fill', (i % 2 === 0) ? '#f1c40f' : '#EF6C00'); 
                      
                      let countNum = i + 1;
                      $('#conteudo_contador').html('<div class=\"contador-numero\" style=\"color: #EF6C00; text-shadow: 2px 2px 5px rgba(239,108,0,0.2);\">' + countNum + '</div>');
                  } else {
                      // Modo Regência normal: balança os braços 
                      let angleL = (i % 2 === 0) ? -30 : 15;
                      let angleR = (i % 2 === 0) ? 30 : -15;
                      
                      $('#arm-l').css('transform', 'rotate(' + angleL + 'deg)');
                      $('#arm-r').css('transform', 'rotate(' + angleR + 'deg)');
                      $('.robo-eye').attr('fill', '#f1c40f');
                      $('#robo-led').attr('fill', '#bdc3c7');
                  }
                  
              }, dM);
          }

          for (let inst in m.strings) {
              let isPrin = (inst === window.instPrincipal); let bStr = m.strings[inst]; if (!bStr) continue;
              let beats = bStr.split('|');
              for (let b = 0; b < 4; b++) {
                  if (!beats[b]) continue;
                  let tks = beats[b].trim().split(/\\s+/).filter(t => t.length > 0);
                  if (tks.length === 0) continue;
                  let tkDur = beatDur / tks.length;
                  for (let j = 0; j < tks.length; j++) {
                      let tk = tks[j]; let slot = startTime + (b * beatDur) + (j * tkDur);
                      if (tk.includes('.')) { let subT = tk.split('.'); let sDur = tkDur / subT.length; for (let k=0; k<subT.length; k++) playSyntheticSound(subT[k], slot + (k*sDur), '1', inst, window.timbre, isPrin); }
                      else { playSyntheticSound(tk, slot, '1', inst, window.timbre, isPrin); }
                  }
              }
          }
      }
    ")))
  ),
  
  sidebar = sidebar(
    id = "sidebar_principal",
    width = 340,
    
    div(class = "btn-container", actionButton("btn_play", "Tocar", icon = icon("play-circle"), class = "btn-lg btn-primary", disabled = "TRUE")),
    hr(),
    
    sliderInput("bpm", "Velocidade (BPM):", min = 40, max = 150, value = 80, step = 5),
    sliderInput("rep_levadas", "Repetições das Levadas (mín - máx):", min = 4, max = 32, value = c(4, 8), step = 2),
    selectInput("instrumento", "Foco no Instrumento:", choices = instrumentos_disponiveis, selected = "Dobra"),
    
    # O parâmetro 'open' força todas as abas listadas a já começarem abertas!
    accordion(
      open = c("Levadas", "Convenções", "Acompanhamento", "Mixagem"),
      
      accordion_panel("Levadas", 
                      checkboxGroupInput("levadas_ativas", NULL, choices = levadas_disponiveis, selected = character(0)),
                      conditionalPanel(
                        condition = "input.levadas_ativas && input.levadas_ativas.indexOf('Variada') > -1",
                        div(
                          style = "margin-top: 10px; padding: 12px; background-color: #FFF3E0; border-left: 4px solid #EF6C00; border-radius: 4px;",
                          tags$label("Opções para Variada (Batidas):", style = "font-weight: bold; color: #5E2157; font-size: 0.95em;"),
                          checkboxGroupInput("variada_opcoes", label = NULL, choices = names(dict_variada), selected = c("Pe", "PeLe", "PeTaLa", "Pausa"), inline = TRUE)
                        )
                      )
      ),
      accordion_panel("Convenções", checkboxGroupInput("conv_ativas", NULL, choices = convencoes_disponiveis, selected = character(0))),
      accordion_panel("Acompanhamento", 
                      checkboxGroupInput("acompanhamento_ativo", "Adicionar à banda:", choices = character(0), selected = character(0)),
                      uiOutput("config_acompanhamento")
      ),
      accordion_panel("Mixagem", 
                      sliderInput("vol_principal", "Volume do Foco:", min = 0, max = 100, value = 100, step = 5, post = "%"),
                      uiOutput("mixagem_acomp")
      )
    )
  ),
  
  div(id = "seletor_modo", style = "display: flex; gap: 10px; justify-content: center; margin-bottom: 15px;",
      actionButton("ir_modo_livre", "🎵 Ensaio Livre", class = "btn-modo-tab btn-modo-ativo"),
      actionButton("ir_modo_montar", "🛠️ Montar Sequência", class = "btn-modo-tab")
  ),
  div(id = "tela_ensaio_livre", style = "width: 100%;",
  card(
    class = "text-center", style = "display: flex; flex-direction: column; justify-content: center; align-items: center; min-height: 85vh;",
    div(
      id = "cabecalho_livre",
      style = "display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 15px; padding: 0 10px;",
      h4(id = "status_texto", "Pronto para o ensaio! Escolha as levadas e toque.", style = "color: #EF6C00 !important; font-weight: bold; margin: 0;"),
      div(
        actionButton("btn_toggle_leitura", " Modo Avançado", icon = icon("eye-slash"), class = "btn-sm btn-outline-secondary", style = "font-weight: bold; border-color: #bdc3c7; margin-right: 8px;"),
        actionButton("btn_toggle_box_atual", " Ocultar Sinal Atual", icon = icon("eye-slash"), class = "btn-sm btn-outline-secondary", style = "font-weight: bold; border-color: #bdc3c7;")
      )
    ),
    div(
      id = "cabecalho_sequencia", style = "display: none; flex-direction: column; align-items: center; width: 100%; margin-bottom: 15px; padding: 10px;",
      h6("EXERCÍCIO", style = "color: #bdc3c7; font-weight: bold; letter-spacing: 2px; margin: 0 0 4px 0;"),
      h3(id = "titulo_sequencia_ativa", "-", style = "color: #5E2157; font-weight: 900; margin: 0 0 14px 0; text-align: center;"),
      div(
        id = "seq_opcoes_extra",
        style = "display: flex; flex-direction: column; align-items: stretch; gap: 4px; width: 100%; max-width: 360px; margin-bottom: 14px; padding: 12px 16px; background-color: #f8f9fa; border-radius: 10px; border: 1px solid #e0e0e0;",
        sliderInput("seq_bpm_control", "Velocidade (BPM):", min = 40, max = 150, value = 80, step = 5, width = "100%"),
        checkboxGroupInput("seq_acompanhamento_ativo", "Tocar junto com:", choices = character(0), selected = character(0), inline = TRUE)
      ),
      actionButton("btn_play_seq", "TOCAR", icon = icon("play-circle"), class = "btn-lg btn-primary", style = "font-size: 1.5rem; padding: 14px 40px; font-weight: 900;")
    ),
    
    # 2. Painel Condutor Reorganizado
    div(
      class = "painel-condutor",
      style = "display: flex; flex-direction: column; gap: 15px; width: 100%;",
      
      # Linha Superior: Tocando e Próximo
      div(
        style = "display: flex; gap: 15px; width: 100%;",
        div(
          class = "box-atual", id = "box_atual_container", style = "flex: 1;",
          h6("TOCANDO", style = "color: #7f8c8d; font-weight: bold; font-size: 0.8rem; margin: 0;"),
          h3(id = "nome_padrao_atual", "-", style = "font-size: 1.1rem; font-weight: bold; color: #34495e; text-align: center; margin: 8px 0; min-height: 28px;"),
          tags$div(id = "imagem_sinal_atual", tags$div(style = "height: 80px;", "-"))
        ),
        div(
          class = "box-proximo", id = "box_proximo_container", style = "flex: 1;",
          tags$div(style = "display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; opacity: 0.3;", tags$h2("-", style = "font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 0;"))
        )
      ),
      
      # Linha Inferior: Robô Maestro (à esquerda) e Caixa de Contagem Quadrada (à direita)
      div(
        style = "display: flex; gap: 15px; width: 100%; align-items: stretch;",
        
        # Robô Centralizado
        div(
          id = "robo_maestro",
          style = "background-color: #f8f9fa; border: 1px solid #e0e0e0; border-radius: 12px; display: flex; justify-content: center; align-items: center; padding: 10px; min-width: 150px;",
          HTML("
            <svg width=\"130\" height=\"130\" viewBox=\"0 0 140 150\" xmlns=\"http://www.w3.org/2000/svg\">
            <style>
              #arm-l, #arm-r, #foot-l, #foot-r { 
                transition: transform 0.1s ease-in-out; 
                transform-box: fill-box;
              }
              /* Define o pivô exatamente no topo interno de cada braço (ombro) */
              #arm-l { transform-origin: 80% 10%; }
              #arm-r { transform-origin: 20% 10%; }
            </style>
            
            <rect x=\"50\" y=\"110\" width=\"12\" height=\"28\" fill=\"#7f8c8d\" />
            <rect x=\"78\" y=\"110\" width=\"12\" height=\"28\" fill=\"#7f8c8d\" />
            
            <rect id=\"foot-l\" x=\"40\" y=\"135\" width=\"24\" height=\"15\" rx=\"6\" fill=\"#2c3e50\" />
            <rect id=\"foot-r\" x=\"74\" y=\"135\" width=\"24\" height=\"15\" rx=\"6\" fill=\"#2c3e50\" />
            
            <rect id=\"arm-l\" x=\"22\" y=\"58\" width=\"14\" height=\"45\" rx=\"7\" fill=\"#95a5a6\" />
            
            <rect id=\"arm-r\" x=\"104\" y=\"58\" width=\"14\" height=\"45\" rx=\"7\" fill=\"#95a5a6\" />
            
            <rect x=\"40\" y=\"50\" width=\"60\" height=\"65\" rx=\"10\" fill=\"#34495e\" />
            <circle id=\"robo-led\" cx=\"70\" cy=\"85\" r=\"8\" fill=\"#bdc3c7\" />
            
            <rect id=\"antena-stick\" x=\"67\" y=\"6\" width=\"6\" height=\"10\" fill=\"#7f8c8d\" />
            <circle id=\"antena-ball\" cx=\"70\" cy=\"6\" r=\"6\" fill=\"#EF6C00\" />
            
            <rect x=\"38\" y=\"15\" width=\"64\" height=\"35\" rx=\"14\" fill=\"#46637d\" />
            <circle cx=\"55\" cy=\"32\" r=\"8\" fill=\"#ecf0f1\" />
            <circle cx=\"85\" cy=\"32\" r=\"8\" fill=\"#ecf0f1\" />
            <circle cx=\"55\" cy=\"32\" r=\"3.5\" fill=\"#2c3e50\" />
            <circle cx=\"85\" cy=\"32\" r=\"3.5\" fill=\"#2c3e50\" />
            <rect x=\"55\" y=\"43\" width=\"30\" height=\"5\" rx=\"2.5\" fill=\"#2c3e50\" />
          </svg>
          ")
        ),
        
        # Caixa de Contagem (Quadrada e ocupando o resto do espaço ao lado do robô)
        div(
          class = "box-contagem",
          style = "flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: center; margin: 0; background-color: #f8f9fa; border: 1px solid #e0e0e0; border-radius: 12px; padding: 15px;",
          h5("CONTAGEM", style = "color: #5E2157; font-weight: bold; letter-spacing: 2px; margin-bottom: 5px; font-size: 0.9rem;"),
          tags$div(id = "conteudo_contador", style = "display: flex; align-items: center; justify-content: center; flex: 1;", tags$div(class = "contador-numero texto-desfoque", "-"))
        )
      )
    ),
    
    div(
      id = "box_leitura",
      style = "background-color: #f8f9fa; padding: 20px 25px; border-radius: 12px; width: 100%; margin-top: 10px; border: 1px solid #e0e0e0; display: flex; flex-direction: column; justify-content: center; box-sizing: border-box;",
      h5(textOutput("titulo_instrumento"), style = "color: #7f8c8d !important; margin-bottom: 15px; text-align: center; font-size: 1.1rem; font-weight: bold;"),
      tags$div(id = "texto_peteleco", style = "font-size: clamp(14px, 2.2vw, 26px); width: 100%; display: flex; flex-direction: column; gap: 8px;", "Nenhum sinal ativo no momento.")
    )
  )
  ),
  div(id = "tela_montar_sequencia", style = "display: none; width: 100%;",
    card(
      class = "text-center", style = "min-height: 85vh; padding: 10px 5px;",
      h3("Montar Sequência", style = "color: #5E2157; font-weight: 900; margin-bottom: 4px;"),
      p("Monte um exercício com passos fixos (sem sorteio) e gere um link + QR code pra compartilhar.", style = "color: #7f8c8d; font-size: 0.95em; margin-bottom: 20px;"),
      
      div(style = "max-width: 480px; margin: 0 auto; text-align: left;",
        
        div(style = "display: flex; gap: 15px; margin-bottom: 5px;",
          div(style = "flex: 1;", selectInput("seq_instrumento", "Instrumento:", choices = instrumentos_disponiveis, selected = "Dobra", width = "100%")),
          div(style = "flex: 1;", sliderInput("seq_bpm", "BPM:", min = 40, max = 150, value = 80, step = 5, width = "100%"))
        ),
        
        hr(),
        
        h5("Adicionar passo", style = "color: #5E2157; font-weight: bold; margin-bottom: 10px;"),
        selectInput("seq_tipo_passo", "Tipo de passo:", choices = c("Levada" = "levada", "Convenção" = "convencao"), width = "100%"),
        conditionalPanel(
          condition = "input.seq_tipo_passo == 'levada'",
          selectInput("seq_padrao_levada", "Levada:", choices = setdiff(levadas_disponiveis, "Variada"), width = "100%"),
          numericInput("seq_compassos_passo", "Nº de compassos:", value = 8, min = 2, max = 32, step = 2, width = "100%")
        ),
        conditionalPanel(
          condition = "input.seq_tipo_passo == 'convencao'",
          selectInput("seq_padrao_convencao", "Convenção:", choices = convencoes_disponiveis, width = "100%")
        ),
        div(style = "text-align: center; margin: 10px 0 20px 0;",
            actionButton("btn_add_passo", "+ Adicionar à sequência", icon = icon("plus"), class = "btn-outline-primary")
        ),
        
        h5("Passos da sequência", style = "color: #5E2157; font-weight: bold; margin-bottom: 10px;"),
        uiOutput("lista_passos_sequencia"),
        
        hr(),
        
        textInput("seq_nome", "Nome do exercício:", placeholder = "Ex.: Aula 3 - Baião e Xote", width = "100%"),
        div(style = "text-align: center; margin-top: 10px;",
            actionButton("btn_gerar_link_seq", "Gerar link e QR code", icon = icon("link"), class = "btn-lg btn-primary")
        ),
        uiOutput("resultado_link_seq")
      )
    )
  )

)

# ==============================================================================
# 3. LÓGICA DO SERVIDOR (SERVER) - APENAS GERA OS DADOS
# ==============================================================================
server <- function(input, output, session) {
  
  observeEvent(input$instrumento, {
    opcoes_disponiveis <- setdiff(instrumentos_disponiveis, input$instrumento)
    selecionados_atuais <- intersect(input$acompanhamento_ativo, opcoes_disponiveis)
    updateCheckboxGroupInput(session, "acompanhamento_ativo", choices = opcoes_disponiveis, selected = selecionados_atuais)
  })
  
  output$config_acompanhamento <- renderUI({
    req(input$acompanhamento_ativo)
    l_ativas <- input$levadas_ativas; c_ativas <- input$conv_ativas
    if (length(l_ativas) == 0 && length(c_ativas) == 0) return(tags$p(style="color: #e74c3c; font-size: 0.9em; margin-top: 15px; text-align: center;", "Selecione primeiro as Levadas ou Convenções acima."))
    ui_list <- lapply(input$acompanhamento_ativo, function(inst) {
      id_inst <- gsub(" ", "_", inst)
      div(
        class = "acomp-panel",
        tags$strong(paste("O que a", inst, "toca?"), style = "color: #5E2157; display: block; margin-bottom: 8px;"),
        if (length(l_ativas) > 0) checkboxGroupInput(inputId = paste0("acomp_lev_", id_inst), label = "Levadas:", choices = l_ativas, selected = l_ativas, inline = TRUE),
        if (length(c_ativas) > 0) checkboxGroupInput(inputId = paste0("acomp_conv_", id_inst), label = "Convenções:", choices = c_ativas, selected = c_ativas, inline = TRUE)
      )
    })
    do.call(tagList, ui_list)
  })
  
  output$titulo_instrumento <- renderText({ paste("Leitura -", input$instrumento) })
  
  estado <- reactiveValues(
    rodando = FALSE, exibir_box_atual = TRUE, exibir_leitura = TRUE, veio_de_convencao = TRUE, nota_forcada = "",
    fase_atual = "Levada", padrao_atual = "", compassos_restantes = 0, compassos_tocados = 0,
    proxima_fase = "", proximo_padrao = "", proximos_compassos = 0,
    modo_sequencia = FALSE, sequencia_passos = list(), sequencia_indice = 1, sequencia_fim = FALSE, sequencia_nome = "",
    passos_sequencia_editor = list(), sequencia_bpm = NULL, sequencia_instrumento = NULL
  )
  
  bpm_ativo <- function() if (isTRUE(estado$modo_sequencia)) estado$sequencia_bpm else input$bpm
  instrumento_ativo <- function() if (isTRUE(estado$modo_sequencia)) estado$sequencia_instrumento else input$instrumento
  
  observeEvent(input$seq_bpm_control, {
    req(isTRUE(estado$modo_sequencia))
    estado$sequencia_bpm <- input$seq_bpm_control
  })
  
  observe({
    req(input$vol_principal) 
    if (isTRUE(estado$modo_sequencia)) return()
    vol_p <- input$vol_principal / 100.0
    
    vol_map <- list()
    if (length(input$acompanhamento_ativo) > 0) {
      for (inst in input$acompanhamento_ativo) {
        id_inst <- gsub(" ", "_", inst)
        val <- input[[paste0("vol_", id_inst)]]
        vol_map[[inst]] <- if(is.null(val)) 0.5 else (val / 100.0)
      }
    }
    session$sendCustomMessage("updateVolume", list(p = vol_p, a = vol_map))
  })
  
  observe({
    req(isTRUE(estado$modo_sequencia))
    vol_map <- list()
    if (length(input$seq_acompanhamento_ativo) > 0) {
      for (inst in input$seq_acompanhamento_ativo) {
        vol_map[[inst]] <- 0.7
      }
    }
    session$sendCustomMessage("updateVolume", list(p = 1.0, a = vol_map))
  })
  
  output$mixagem_acomp <- renderUI({
    req(input$acompanhamento_ativo)
    ui_list <- lapply(input$acompanhamento_ativo, function(inst) {
      id_inst <- gsub(" ", "_", inst)
      sliderInput(paste0("vol_", id_inst), paste("Volume -", inst, ":"), min = 0, max = 100, value = 50, step = 5, post = "%")
    })
    do.call(tagList, ui_list)
  })
  
  observeEvent(input$btn_toggle_leitura, {
    estado$exibir_leitura <- !estado$exibir_leitura
    if (estado$exibir_leitura) {
      updateActionButton(session, "btn_toggle_leitura", label = " Modo Avançado", icon = icon("eye-slash"))
      shinyjs::show("box_leitura")
    } else {
      updateActionButton(session, "btn_toggle_leitura", label = " Mostrar Leitura", icon = icon("eye"))
      shinyjs::hide("box_leitura")
    }
  })
  
  observeEvent(input$btn_toggle_box_atual, {
    estado$exibir_box_atual <- !estado$exibir_box_atual
    if (estado$exibir_box_atual) {
      updateActionButton(session, "btn_toggle_box_atual", label = " Ocultar Sinal Atual", icon = icon("eye-slash"))
      shinyjs::show("box_atual_container")
    } else {
      updateActionButton(session, "btn_toggle_box_atual", label = " Exibir Sinal Atual", icon = icon("eye"))
      shinyjs::hide("box_atual_container")
    }
  })
  
  observe({
    if (isTRUE(estado$modo_sequencia)) return()
    if (length(input$levadas_ativas) > 0 || length(input$conv_ativas) > 0) { shinyjs::enable("btn_play") } 
    else { shinyjs::disable("btn_play"); if (estado$rodando) reset_tudo() }
  })
  
  reset_tudo <- function() {
    estado$rodando <- FALSE
    
    estado$padrao_atual <- ""
    estado$proximo_padrao <- ""
    estado$proxima_fase <- ""
    estado$compassos_tocados <- 0
    estado$nota_forcada <- ""
    estado$sequencia_indice <- 1
    estado$sequencia_fim <- FALSE
    
    shinyjs::runjs("stopPlayback();")
    id_botao <- if (isTRUE(estado$modo_sequencia)) "btn_play_seq" else "btn_play"
    updateActionButton(session, id_botao, label = if (isTRUE(estado$modo_sequencia)) "TOCAR" else " Tocar", icon = icon("play-circle"))
    shinyjs::removeClass(id_botao, "btn-danger"); shinyjs::addClass(id_botao, "btn-primary")
    shinyjs::enable("bpm"); shinyjs::enable("rep_levadas"); shinyjs::enable("instrumento"); 
    shinyjs::enable("levadas_ativas"); shinyjs::enable("variada_opcoes"); shinyjs::enable("conv_ativas"); shinyjs::enable("acompanhamento_ativo")
    shinyjs::enable("seq_bpm_control"); shinyjs::enable("seq_acompanhamento_ativo")
  }
  
  get_duracao <- function(padrao, df_conv) {
    if ("Duracao" %in% colnames(df_conv)) {
      dur <- df_conv$Duracao[df_conv$Convencao == padrao][1]
      if (!is.na(dur) && !is.null(dur)) return(as.numeric(dur))
    }
    
    c2_str <- NULL
    if ("Compasso_2" %in% colnames(df_conv)) {
      c2_str <- df_conv$Compasso_2[df_conv$Convencao == padrao][1]
    } else if ("Compasso.2" %in% colnames(df_conv)) {
      c2_str <- df_conv$Compasso.2[df_conv$Convencao == padrao][1]
    } else if (ncol(df_conv) >= 4) {
      c2_str <- df_conv[[4]][df_conv$Convencao == padrao][1]
    }
    
    if (is.null(c2_str) || is.na(c2_str) || trimws(c2_str) == "" || grepl("^[\\s|-]*$", c2_str, perl=TRUE)) {
      return(1)
    } else {
      return(2)
    }
  }
  
  processar_compasso <- function(padrao, instrumento, fase, tocados, veio_conv, nota_forcada = "") {
    if (fase == "Levada") { df <- df_levadas[df_levadas$Levada == padrao & df_levadas$Instrumento == instrumento, ] }
    else { df <- df_convencoes[df_convencoes$Convencao == padrao & df_convencoes$Instrumento == instrumento, ] }
    if (nrow(df) == 0) return("-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --")
    
    # 1. Busca dinamicamente TODAS as colunas que comecem com "Compasso"
    cols_compasso <- grep("^Compasso", colnames(df), value = TRUE, ignore.case = TRUE)
    cols_compasso <- sort(cols_compasso) # Garante a ordem correta 1, 2, 3, 4
    
    valores <- as.character(df[1, cols_compasso])
    
    # 2. Mantém apenas os compassos que foram preenchidos no CSV para esta linha
    valores_validos <- valores[!is.na(valores) & trimws(valores) != ""]
    
    if (length(valores_validos) == 0) {
      valores_validos <- c("-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --")
    }
    
    # Verifica loop estático no compasso 2
    col_loop <- grep("^Loop", colnames(df), value = TRUE, ignore.case = TRUE)[1]
    is_loop_c2 <- FALSE
    if (fase == "Levada" && !is.na(col_loop)) {
      val_loop <- df[[col_loop]][1]
      if (!is.na(val_loop) && toupper(trimws(as.character(val_loop))) %in% c("SIM", "S", "TRUE", "1")) is_loop_c2 <- TRUE
    }
    
    # 3. Faz o looping matemático baseado na quantidade exata de compassos da levada
    if (is_loop_c2 && length(valores_validos) >= 2) { 
      idx <- if (tocados == 0) 1 else 2 
    } else { 
      idx <- (tocados %% length(valores_validos)) + 1 
    }
    
    comp_str <- valores_validos[idx]
    
    if (fase == "Levada") { 
      if (tocados == 0 && veio_conv) comp_str <- gsub("\\([^)]+\\)", "--", comp_str) 
      else comp_str <- gsub("\\(|\\)", "", comp_str) 
    } else { 
      comp_str <- gsub("\\(|\\)", "", comp_str) 
    }
    
    if (tocados == 0 && !is.null(nota_forcada) && !is.na(nota_forcada) && nota_forcada != "") {
      comp_str <- sub("^\\S+", nota_forcada, trimws(comp_str))
    }
    
    return(comp_str)
  }
  
  avancar_fase <- function() {
    fase_anterior <- estado$fase_atual; padrao_anterior <- estado$padrao_atual
    
    if (fase_anterior == "Convenção") {
      df_c <- df_convencoes[df_convencoes$Convencao == estado$padrao_atual & df_convencoes$Instrumento == instrumento_ativo(), ]
      col_forca <- if("Forca_Primeira_Nota" %in% colnames(df_c)) "Forca_Primeira_Nota" else if("Forca.Primeira.Nota" %in% colnames(df_c)) "Forca.Primeira.Nota" else NULL
      estado$nota_forcada <- if(!is.null(col_forca) && nrow(df_c) > 0 && !is.na(df_c[[col_forca]][1])) df_c[[col_forca]][1] else ""
    } else { 
      estado$nota_forcada <- "" 
    }
    
    estado$veio_de_convencao <- (fase_anterior == "Convenção")
    estado$fase_atual <- estado$proxima_fase
    estado$padrao_atual <- estado$proximo_padrao
    
    estado$compassos_restantes <- estado$proximos_compassos
    
    estado$compassos_tocados <- 0
    estado$proximo_padrao <- ""
  }
  
  preencher_proximo <- function() {
    if (estado$proximo_padrao == "") {
      
      if (isTRUE(estado$modo_sequencia)) {
        idx <- estado$sequencia_indice
        passos <- estado$sequencia_passos
        if (idx > length(passos)) { estado$sequencia_fim <- TRUE; return() }
        passo <- passos[[idx]]
        estado$sequencia_indice <- idx + 1
        if (identical(passo$tipo, "levada")) {
          estado$proxima_fase <- "Levada"
          estado$proximo_padrao <- passo$padrao
          estado$proximos_compassos <- as.numeric(passo$compassos)
        } else {
          estado$proxima_fase <- "Convenção"
          estado$proximo_padrao <- passo$padrao
          estado$proximos_compassos <- get_duracao(passo$padrao, df_convencoes)
        }
        return()
      }
      
      opcoes_l <- input$levadas_ativas; opcoes_c <- input$conv_ativas
      tem_l <- length(opcoes_l) > 0; tem_c <- length(opcoes_c) > 0
      if (tem_l && tem_c) { estado$proxima_fase <- ifelse(estado$fase_atual == "Levada", "Convenção", "Levada") } 
      else if (tem_l) { estado$proxima_fase <- "Levada" } else if (tem_c) { estado$proxima_fase <- "Convenção" } else { return() }
      
      if (estado$proxima_fase == "Levada") {
        opcoes_validas <- opcoes_l
        if (length(opcoes_l) > 1 && estado$padrao_atual %in% opcoes_l) opcoes_validas <- setdiff(opcoes_l, estado$padrao_atual)
        estado$proximo_padrao <- sample(opcoes_validas, 1)
        opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
        estado$proximos_compassos <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
      } else {
        opcoes_validas <- opcoes_c
        if (length(opcoes_c) > 1 && estado$padrao_atual %in% opcoes_c) opcoes_validas <- setdiff(opcoes_c, estado$padrao_atual)
        estado$proximo_padrao <- sample(opcoes_validas, 1)
        estado$proximos_compassos <- get_duracao(estado$proximo_padrao, df_convencoes)
      }
    }
  }
  
  gerar_compasso_interno <- function() {
    
    if (estado$compassos_restantes <= 0) { avancar_fase(); preencher_proximo() }
    nf <- if (estado$compassos_tocados == 0) estado$nota_forcada else ""
    insts_tocar <- if (isTRUE(estado$modo_sequencia)) unique(c(instrumento_ativo(), input$seq_acompanhamento_ativo)) else unique(c(input$instrumento, input$acompanhamento_ativo))
    strings_comp <- list(); str_variada <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
    
    if (estado$padrao_atual == "Variada") {
      opcoes_sel <- input$variada_opcoes; if (is.null(opcoes_sel) || length(opcoes_sel) == 0) opcoes_sel <- c("Pausa")
      padroes_sel <- dict_variada[opcoes_sel]; batidas_sorteadas <- sample(padroes_sel, 4, replace = TRUE)
      if ("Pausa" %in% opcoes_sel && !(dict_variada[["Pausa"]] %in% batidas_sorteadas)) batidas_sorteadas[sample(1:4, 1)] <- dict_variada[["Pausa"]]
      str_variada <- paste(batidas_sorteadas, collapse = " | ")
    }
    
    for (inst in insts_tocar) {
      if (inst == instrumento_ativo()) {
        if (estado$padrao_atual == "Variada") { comp_str <- str_variada; if (estado$compassos_tocados == 0 && nf != "") comp_str <- sub("^\\S+", nf, trimws(comp_str))
        } else { comp_str <- processar_compasso(estado$padrao_atual, inst, estado$fase_atual, estado$compassos_tocados, estado$veio_de_convencao, nf) }
      } else {
        id_inst <- gsub(" ", "_", inst); ativas_l <- input[[paste0("acomp_lev_", id_inst)]]; ativas_c <- input[[paste0("acomp_conv_", id_inst)]]
        pode_tocar <- FALSE
        if (isTRUE(estado$modo_sequencia)) {
          pode_tocar <- TRUE
        } else {
          if (estado$fase_atual == "Levada" && (estado$padrao_atual %in% ativas_l)) pode_tocar <- TRUE
          if (estado$fase_atual == "Convenção" && (estado$padrao_atual %in% ativas_c)) pode_tocar <- TRUE
        }
        if (pode_tocar) {
          if (estado$padrao_atual == "Variada") { comp_str <- str_variada; if (estado$compassos_tocados == 0 && nf != "") comp_str <- sub("^\\S+", nf, trimws(comp_str))
          } else { comp_str <- processar_compasso(estado$padrao_atual, inst, estado$fase_atual, estado$compassos_tocados, estado$veio_de_convencao, nf) }
        } else { comp_str <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --" }
      }
      
      if (estado$compassos_restantes == 1 && tolower(estado$proximo_padrao) == "c2" && inst %in% c("Caixa", "Repique")) {
        tempos <- strsplit(comp_str, "\\|")[[1]]
        ultimo_tempo <- trimws(tempos[length(tempos)])
        notas <- strsplit(ultimo_tempo, "\\s+")[[1]]
        
        if (length(notas) >= 4) {
          notas[4] <- "co.co"
        } else {
          notas <- c("--", "--", "--", "co.co")
        }
        
        tempos[length(tempos)] <- paste(notas, collapse = " ")
        comp_str <- paste(tempos, collapse = " | ")
      }
      strings_comp[[inst]] <- comp_str
    }
    if (estado$compassos_tocados == 0) estado$nota_forcada <- "" 
    
    img_atual <- if (nzchar(estado$padrao_atual)) map_imagens[[estado$padrao_atual]] else NULL; if(is.null(img_atual)) img_atual <- ""
    img_prox <- if (nzchar(estado$proximo_padrao)) map_imagens[[estado$proximo_padrao]] else NULL; if(is.null(img_prox)) img_prox <- ""
    
    res <- list(html = strings_comp[[instrumento_ativo()]], strings = strings_comp, nome = estado$padrao_atual, 
                img = img_atual, restantes = estado$compassos_restantes, futuro = estado$proximo_padrao, futuro_img = img_prox,
                fim_sequencia = FALSE)
    estado$compassos_restantes <- estado$compassos_restantes - 1; estado$compassos_tocados <- estado$compassos_tocados + 1
    preencher_proximo()
    if (isTRUE(estado$modo_sequencia) && isTRUE(estado$sequencia_fim) && estado$compassos_restantes <= 0) res$fim_sequencia <- TRUE
    return(res)
  }
  
  gerar_lote_compassos <- function(qtd) {
    lote <- list()
    for (i in seq_len(qtd)) {
      if (isTRUE(estado$modo_sequencia) && isTRUE(estado$sequencia_fim) && estado$compassos_restantes <= 0) break
      lote[[length(lote) + 1]] <- gerar_compasso_interno()
    }
    return(lote)
  }
  
  executar_play_toggle <- function() {
    id_botao <- if (isTRUE(estado$modo_sequencia)) "btn_play_seq" else "btn_play"
    
    if (!isTRUE(estado$modo_sequencia)) {
      req(length(input$levadas_ativas) > 0 || length(input$conv_ativas) > 0)
    } else {
      req(length(estado$sequencia_passos) > 0)
    }
    estado$rodando <- !estado$rodando
    
    
    if (estado$rodando) {
      shinyjs::disable("bpm"); shinyjs::disable("rep_levadas"); shinyjs::disable("instrumento");
      shinyjs::disable("levadas_ativas"); shinyjs::disable("variada_opcoes"); shinyjs::disable("conv_ativas"); shinyjs::disable("acompanhamento_ativo")
      shinyjs::disable("seq_bpm_control"); shinyjs::disable("seq_acompanhamento_ativo")
      
      estado$veio_de_convencao <- TRUE; estado$nota_forcada <- ""
      
      if (isTRUE(estado$modo_sequencia)) {
        estado$sequencia_indice <- 1
        estado$sequencia_fim <- FALSE
        primeiro <- estado$sequencia_passos[[1]]
        estado$sequencia_indice <- 2
        if (identical(primeiro$tipo, "levada")) {
          estado$fase_atual <- "Levada"
          estado$padrao_atual <- primeiro$padrao
          estado$compassos_restantes <- as.numeric(primeiro$compassos)
        } else {
          estado$fase_atual <- "Convenção"
          estado$padrao_atual <- primeiro$padrao
          estado$compassos_restantes <- get_duracao(primeiro$padrao, df_convencoes)
        }
      } else {
        fases_possiveis <- c()
        if (length(input$levadas_ativas) > 0) fases_possiveis <- c(fases_possiveis, "Levada")
        if (length(input$conv_ativas) > 0) fases_possiveis <- c(fases_possiveis, "Convenção")
        estado$fase_atual <- sample(fases_possiveis, 1)
        
        if (estado$fase_atual == "Levada") {
          estado$padrao_atual <- sample(input$levadas_ativas, 1)
          opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
          estado$compassos_restantes <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
        } else {
          estado$padrao_atual <- sample(input$conv_ativas, 1)
          estado$compassos_restantes <- get_duracao(estado$padrao_atual, df_convencoes)
        }
      }
      estado$compassos_tocados <- 0
      preencher_proximo()
      
      vol_map <- list()
      if (!isTRUE(estado$modo_sequencia) && length(input$acompanhamento_ativo) > 0) {
        for (inst in input$acompanhamento_ativo) {
          id_inst <- gsub(" ", "_", inst)
          val <- input[[paste0("vol_", id_inst)]]
          vol_map[[inst]] <- if(is.null(val)) 0.5 else (val / 100.0)
        }
      } else if (isTRUE(estado$modo_sequencia) && length(input$seq_acompanhamento_ativo) > 0) {
        for (inst in input$seq_acompanhamento_ativo) {
          vol_map[[inst]] <- 0.7
        }
      }
      
      payload <- list(
        bpm = as.numeric(bpm_ativo()), 
        timbre = "Meus Sons (.wav)",
        volPrincipal = if (isTRUE(estado$modo_sequencia)) 1.0 else input$vol_principal / 100.0,
        volAcompMap = vol_map,
        instPrincipal = instrumento_ativo(), 
        isLoop = if (isTRUE(estado$modo_sequencia)) FALSE else (length(input$levadas_ativas) + length(input$conv_ativas)) == 1,
        batch = gerar_lote_compassos(16)
      )
      session$sendCustomMessage("startPlayback", payload)
      
      updateActionButton(session, id_botao, label = " Pausar", icon = icon("pause-circle"))
      shinyjs::removeClass(id_botao, "btn-primary"); shinyjs::addClass(id_botao, "btn-danger")
    } else { reset_tudo() }
  }
  
  observeEvent(input$btn_play, { executar_play_toggle() })
  observeEvent(input$btn_play_seq, { executar_play_toggle() })
  
  observeEvent(input$js_request_batch, {
    if (estado$rodando) {
      session$sendCustomMessage("appendBatch", gerar_lote_compassos(8))
    }
  })

  observeEvent(input$btn_add_passo, {
    if (identical(input$seq_tipo_passo, "levada")) {
      req(input$seq_padrao_levada)
      novo <- list(tipo = "levada", padrao = input$seq_padrao_levada, compassos = as.numeric(input$seq_compassos_passo))
    } else {
      req(input$seq_padrao_convencao)
      novo <- list(tipo = "convencao", padrao = input$seq_padrao_convencao)
    }
    estado$passos_sequencia_editor[[length(estado$passos_sequencia_editor) + 1]] <- novo
  })
  
  observeEvent(input$remover_passo_seq, {
    i <- input$remover_passo_seq
    passos <- estado$passos_sequencia_editor
    if (i >= 1 && i <= length(passos)) {
      estado$passos_sequencia_editor <- passos[-i]
    }
  })
  
  observeEvent(input$mover_passo_seq, {
    info <- input$mover_passo_seq
    i <- info$i; novo_i <- i + info$dir
    passos <- estado$passos_sequencia_editor
    if (novo_i >= 1 && novo_i <= length(passos)) {
      tmp <- passos[[i]]; passos[[i]] <- passos[[novo_i]]; passos[[novo_i]] <- tmp
      estado$passos_sequencia_editor <- passos
    }
  })
  
  output$lista_passos_sequencia <- renderUI({
    passos <- estado$passos_sequencia_editor
    if (length(passos) == 0) {
      return(tags$p("Nenhum passo adicionado ainda.", style = "color:#bdc3c7; font-size:0.85em; text-align:center; margin: 10px 0;"))
    }
    
    linhas <- lapply(seq_along(passos), function(i) {
      p <- passos[[i]]
      rotulo <- if (identical(p$tipo, "levada")) paste0(i, ". ", p$padrao, " (", p$compassos, " compassos)") else paste0(i, ". [Convenção] ", p$padrao)
      seta_cima <- if (i > 1) tags$a(icon("arrow-up"), href = "#", onclick = sprintf("Shiny.setInputValue('mover_passo_seq', {i: %d, dir: -1}, {priority:'event'}); return false;", i), style = "margin-right: 10px; color: #5E2157;") else NULL
      seta_baixo <- if (i < length(passos)) tags$a(icon("arrow-down"), href = "#", onclick = sprintf("Shiny.setInputValue('mover_passo_seq', {i: %d, dir: 1}, {priority:'event'}); return false;", i), style = "margin-right: 10px; color: #5E2157;") else NULL
      
      div(style = "display: flex; align-items: center; justify-content: space-between; padding: 6px 10px; margin-bottom: 4px; background: #f8f9fa; border-radius: 6px; font-size: 0.85em;",
          tags$span(rotulo, style = "flex: 1;"),
          tags$span(seta_cima, seta_baixo, tags$a(icon("trash"), href = "#", onclick = sprintf("Shiny.setInputValue('remover_passo_seq', %d, {priority:'event'}); return false;", i), style = "color: #e74c3c;"))
      )
    })
    do.call(tagList, linhas)
  })
  
  observeEvent(input$btn_gerar_link_seq, {
    passos <- estado$passos_sequencia_editor
    if (length(passos) == 0) { showNotification("Adicione pelo menos um passo antes de gerar o link.", type = "warning"); return() }
    nome <- trimws(input$seq_nome)
    if (nome == "") { showNotification("Digite um nome para o exercício.", type = "warning"); return() }
    
    seq_obj <- list(
      nome = nome,
      bpm = input$seq_bpm,
      instrumento = input$seq_instrumento,
      passos = passos
    )
    
    session$sendCustomMessage("gerarLinkSequencia", seq_obj)
  })
  
  observeEvent(input$link_sequencia_gerado, {
    info <- input$link_sequencia_gerado
    output$resultado_link_seq <- renderUI({
      div(style = "margin-top: 12px;",
          tags$label("Link do exercício (toque para copiar):", style = "font-weight: bold; font-size: 0.85em; display: block; margin-bottom: 4px;"),
          tags$input(type = "text", value = info$url, readonly = "readonly", onclick = "this.select(); document.execCommand('copy');",
                     style = "width: 100%; font-size: 0.72em; padding: 6px; margin-bottom: 10px; border: 1px solid #ddd; border-radius: 4px; background: #fff;"),
          div(style = "text-align: center;", tags$img(src = info$qr, style = "max-width: 180px; border-radius: 8px; border: 1px solid #eee;"))
      )
    })
  })
  
  observeEvent(input$sequencia_da_url, {
    seq <- input$sequencia_da_url
    req(seq, seq$passos)
    
    estado$modo_sequencia <- TRUE
    estado$sequencia_nome <- if (!is.null(seq$nome)) seq$nome else "Exercício"
    estado$sequencia_passos <- seq$passos
    estado$sequencia_indice <- 1
    estado$sequencia_fim <- FALSE
    
    estado$sequencia_bpm <- if (!is.null(seq$bpm)) as.numeric(seq$bpm) else 80
    estado$sequencia_instrumento <- if (!is.null(seq$instrumento)) seq$instrumento else "Dobra"
    if (!is.null(seq$bpm)) updateSliderInput(session, "bpm", value = as.numeric(seq$bpm))
    if (!is.null(seq$instrumento)) updateSelectInput(session, "instrumento", selected = seq$instrumento)
    
    updateSliderInput(session, "seq_bpm_control", value = estado$sequencia_bpm)
    updateCheckboxGroupInput(session, "seq_acompanhamento_ativo", choices = setdiff(instrumentos_disponiveis, estado$sequencia_instrumento), selected = character(0))
    
    shinyjs::hide("sidebar_principal")
    shinyjs::hide("seletor_modo")
    shinyjs::hide("cabecalho_livre")
    shinyjs::show("cabecalho_sequencia")
    shinyjs::html(id = "titulo_sequencia_ativa", html = estado$sequencia_nome)
  })
  
  observeEvent(input$sequencia_terminou, {
    estado$rodando <- FALSE
    shinyjs::enable("bpm"); shinyjs::enable("rep_levadas"); shinyjs::enable("instrumento")
    shinyjs::enable("levadas_ativas"); shinyjs::enable("variada_opcoes"); shinyjs::enable("conv_ativas"); shinyjs::enable("acompanhamento_ativo")
    shinyjs::enable("seq_bpm_control"); shinyjs::enable("seq_acompanhamento_ativo")
    if (isTRUE(estado$modo_sequencia)) {
      updateActionButton(session, "btn_play_seq", label = "Tocar de novo", icon = icon("redo"))
    } else {
      updateActionButton(session, "btn_play", label = " Tocar", icon = icon("play-circle"))
    }
  })
  
  observeEvent(input$ir_modo_montar, {
    if (isTRUE(estado$rodando)) reset_tudo()
    shinyjs::hide("sidebar_principal")
    shinyjs::hide("tela_ensaio_livre")
    shinyjs::show("tela_montar_sequencia")
    shinyjs::addClass("ir_modo_montar", "btn-modo-ativo")
    shinyjs::removeClass("ir_modo_livre", "btn-modo-ativo")
  })
  
  observeEvent(input$ir_modo_livre, {
    if (isTRUE(estado$rodando)) reset_tudo()
    shinyjs::show("sidebar_principal")
    shinyjs::show("tela_ensaio_livre")
    shinyjs::hide("tela_montar_sequencia")
    shinyjs::addClass("ir_modo_livre", "btn-modo-ativo")
    shinyjs::removeClass("ir_modo_montar", "btn-modo-ativo")
  })
}

shinyApp(ui = ui, server = server)