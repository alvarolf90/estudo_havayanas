library(shiny)
library(bslib)
library(shinyjs)

# ==============================================================================
# 1. LEITURA DE DADOS (AGORA VIA CSV) E CONFIGURAÇÕES GERAIS
# ==============================================================================

caminho_levadas <- "www/levadas.csv"
caminho_convencoes <- "www/convencoes.csv"

# TRATAMENTO SEGURO PARA SHINYLIVE: 
# Se o WebAssembly não achar o CSV, ele carrega a base padrão sem quebrar a tela.
if (file.exists(caminho_levadas) && file.exists(caminho_convencoes)) {
  df_levadas <- read.csv(caminho_levadas, sep = ";", stringsAsFactors = FALSE)
  df_convencoes <- read.csv(caminho_convencoes, sep = ";", stringsAsFactors = FALSE)
} else {
  df_levadas <- data.frame(
    Levada = c("Ijexá", "Samba Reggae", "Funk"),
    Instrumento = c("Caixa", "Repique", "Dobra"),
    String = c("pe te le co | pe te le co | pe te le co | pe te le co",
               "pe -- le -- | pe -- le -- | pe -- le -- | pe -- le --",
               "pe ta la -- | pe ta la -- | pe ta la -- | pe ta la --"),
    stringsAsFactors = FALSE
  )
  df_convencoes <- data.frame(
    Convencao = c("C1", "C2", "Virada 1"),
    Instrumento = c("Caixa", "Repique", "Dobra"),
    String = c("pe te le co | pe te le co | pe te le co | pe te le co",
               "pe -- le -- | pe -- le -- | pe -- le -- | pe -- le --",
               "pe ta la -- | pe ta la -- | pe ta la -- | pe ta la --"),
    stringsAsFactors = FALSE
  )
}

dict_variada <- c(
  "PeTaLa" = "pe ta la",
  "Pe" = "pe -- -- --",
  "PeLe" = "pe -- le --",
  "PeTeLeCo" = "pe te le co",
  "Pe----Co" = "pe -- -- co",
  "TeLeCo" = "-- te le co",
  "PeTeLe--" = "pe te le --",
  "Pe--LeCo" = "pe -- le co",
  "PeTe--Co" = "pe te -- co",
  "Pausa" = "-- -- -- --"
)

levadas_disponiveis <- unique(c(df_levadas$Levada, "Variada"))
convencoes_disponiveis <- unique(df_convencoes$Convencao)
instrumentos_disponiveis <- unique(c(df_levadas$Instrumento, df_convencoes$Instrumento))

# Mapeamento de imagens
todos_padroes <- unique(c(levadas_disponiveis, convencoes_disponiveis))
map_imagens <- sapply(todos_padroes, function(nome) {
  nome_limpo <- tolower(nome)
  nome_limpo <- iconv(nome_limpo, to = "ASCII//TRANSLIT")
  nome_limpo <- gsub("['\"~^`´]", "", nome_limpo)
  nome_limpo <- gsub("\\.", "", nome_limpo)
  nome_limpo <- gsub("\\s+", "_", trimws(nome_limpo))
  nome_limpo <- gsub("[^a-z0-9_]", "", nome_limpo)
  return(paste0(nome_limpo, ".png"))
}, USE.NAMES = TRUE)

# Mapeamento de arquivos WAV
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
      
      .painel-condutor { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: stretch; gap: 15px; width: 100%; margin-bottom: 15px; min-height: 260px; }
      .box-atual { border: 2px solid #bdc3c7; border-radius: 12px; padding: 15px; flex: 1 1 20%; min-width: 150px; background: #f8f9fa; display: flex; flex-direction: column; align-items: center; justify-content: center; box-shadow: inset 0 0 10px rgba(0,0,0,0.05); transition: opacity 0.3s ease; }
      .box-proximo { border: 4px solid #EF6C00; border-radius: 12px; padding: 15px; flex: 1 1 35%; min-width: 250px; background: white; box-shadow: 0 8px 20px rgba(239,108,0,0.15); display: flex; flex-direction: column; align-items: center; justify-content: center; position: relative; overflow: hidden; transition: box-shadow 0.3s ease; }
      .box-contagem { border: 4px solid #5E2157; border-radius: 12px; padding: 15px; flex: 1 1 35%; min-width: 250px; background: white; box-shadow: 0 8px 20px rgba(94,33,87,0.15); display: flex; flex-direction: column; align-items: center; justify-content: center; }
      
      .contador-numero { font-size: clamp(5rem, 8vw, 7.5rem); font-weight: 900; color: #5E2157; line-height: 1; text-shadow: 2px 2px 5px rgba(0,0,0,0.1); display: flex; align-items: center; justify-content: center; height: auto; }
      .texto-desfoque { opacity: 0.25; filter: grayscale(100%); }
      @keyframes blinker { 0% { opacity: 1; } 50% { opacity: 0.2; } 100% { opacity: 1; } }
      .piscar { animation: blinker 1s linear infinite; }
      
      #texto_peteleco { font-size: clamp(14px, 1.8vw, 24px); font-family: monospace; font-weight: bold; color: #2c3e50; line-height: 1.6; text-align: center; padding: 0; margin: 0; min-height: 70px; display: flex; flex-direction: column; justify-content: center; align-items: center; }
      
      .span-tempo { transition: color 0.15s ease-in-out; display: inline-block; border-radius: 4px; }
      .acomp-panel { margin-top: 15px; padding: 12px; border-left: 4px solid #EF6C00; background-color: #fcfcfc; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }

      @media (max-width: 768px) {
        .painel-condutor { flex-direction: column; }
        .box-atual, .box-proximo, .box-contagem { width: 100% !important; min-height: 150px; }
        .contador-numero { height: 120px; }
      }
    ")),
    
    tags$script(HTML(paste0("
      window.lastTempo = 0; window.lastRodando = false;
      window.atualizarCursor = function(tempo_atual, rodando_valendo) {
          window.lastTempo = tempo_atual; window.lastRodando = rodando_valendo;
          $('.span-tempo').css({'color': '', 'text-shadow': 'none'});
          if (rodando_valendo && tempo_atual >= 1 && tempo_atual <= 8) {
              $('#span-tempo-' + tempo_atual).css({'color': '#EF6C00', 'text-shadow': '0px 0px 4px rgba(239,108,0,0.3)'});
          }
      };
      window.reaplicarCursor = function() { if (window.atualizarCursor) window.atualizarCursor(window.lastTempo, window.lastRodando); };
      
      window.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      window.masterGain = window.audioCtx.createGain();
      window.masterGain.connect(window.audioCtx.destination);
      window.audioQueueTime = 0; 
      
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
          let url = window.wavMap[inst];
          fetch(url).then(r => { if(r.ok) return r.arrayBuffer(); return null; })
          .then(ab => { if(ab) return window.audioCtx.decodeAudioData(ab); return null; })
          .then(buf => { if(buf) window.sampleBuffers[inst] = buf; })
          .catch(e => console.log('WAV não encontrado na pasta www para: ' + url));
        }
      };
      window.preloadSamples();

      function getNoiseBuffer() {
        if (window.noiseBuffer) return window.noiseBuffer;
        let bufferSize = window.audioCtx.sampleRate * 1.0;
        let buffer = window.audioCtx.createBuffer(1, bufferSize, window.audioCtx.sampleRate);
        let output = buffer.getChannelData(0);
        for (let i = 0; i < bufferSize; i++) { output[i] = Math.random() * 2 - 1; }
        window.noiseBuffer = buffer; return buffer;
      }
      
      function stopAudio() {
        if(window.masterGain) window.masterGain.disconnect();
        window.masterGain = window.audioCtx.createGain();
        window.masterGain.connect(window.audioCtx.destination);
        window.audioQueueTime = 0; // Zera a fila para não engolir o começo no próximo play
      }
      
      function playOscillator(freq, time, dur, vol, type = 'sine') {
        const osc = window.audioCtx.createOscillator(); const gain = window.audioCtx.createGain();
        osc.type = type; osc.connect(gain); gain.connect(window.masterGain);
        osc.frequency.setValueAtTime(freq, time); gain.gain.setValueAtTime(vol, time);
        gain.gain.exponentialRampToValueAtTime(0.001, time + dur);
        osc.start(time); osc.stop(time + dur);
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
        let cleanToken = token.replace(/[*~]/g, '');
        let base = cleanToken.toLowerCase().replace(/[^a-z]/g, ''); 
        let isAlta = (cleanToken === cleanToken.toUpperCase() && base !== ''); 
        let isRulo = token.includes('~'); 
        let isSeca = token.includes('*');
        let inst = instrumento_str ? instrumento_str : 'Caixa';
        
        let balanceVol = isPrincipal ? 1.0 : 0.5;
        
        let mult = 1.0; let isGrave = false; let instVol = 1.0;
        let instLow = inst.toLowerCase();
        if (instLow.includes('surdo') || instLow.includes('fundo') || instLow.includes('marca')) { mult = 0.35; isGrave = true; instVol = 1.3; } 
        else if (instLow.includes('repique') || instLow.includes('bacurinha')) { mult = 1.6; instVol = 0.6; } 
        else if (instLow.includes('dobra')) { mult = 0.65; instVol = 1.1; } 
        else if (instLow.includes('timbal')) { mult = 0.8; isGrave = true; instVol = 1.0; }
        else if (instLow.includes('caixa')) { instVol = 0.45; }
        
        if (timbre === 'Meus Sons (.wav)') {
            let buffer = window.sampleBuffers[inst];
            let volWav = (isAlta ? 1.0 : 0.5) * balanceVol * instVol; 
            if (buffer) {
                if (isRulo) {
                    window.playSample(buffer, time, volWav * 0.7, false);
                    window.playSample(buffer, time + 0.035, volWav * 0.7, false);
                    window.playSample(buffer, time + 0.07, volWav, isSeca);
                } else if (base !== '') {
                    window.playSample(buffer, time, volWav, isSeca);
                }
                return;
            }
        }

        let freq = isGrave ? (140 * mult) : (400 * mult); let dur = isGrave ? 0.16 : 0.08; 
        let vol = (isGrave ? (0.5 * 1.4) : 0.5) * balanceVol * instVol;
        if (isAlta) { vol = vol * 1.8; dur = dur * 1.3; } 
        
        if (timbre === 'Orgânico / Acústico') {
            if (isRulo) {
                playAcousticDrum(freq, time, 0.03, vol*0.6, isGrave, false, false); 
                playAcousticDrum(freq, time + 0.035, 0.03, vol*0.7, isGrave, false, false); 
                playAcousticDrum(freq, time + 0.07, 0.04, vol, isGrave, isAlta, isSeca);
            } else { if(base !== '') playAcousticDrum(freq, time, dur, vol, isGrave, isAlta, isSeca); }
        } else if (timbre === 'Eletrônico / Punch') {
            let wave = isAlta ? 'sawtooth' : (isGrave ? 'square' : 'triangle');
            if (isSeca) dur = 0.02;
            if (isRulo) {
                playOscillator(freq, time, 0.02, vol*0.7, wave); playOscillator(freq, time + 0.035, 0.02, vol*0.7, wave); playOscillator(freq, time + 0.07, 0.03, vol, wave);
            } else { if(base !== '') playOscillator(freq, time, dur, vol * 1.2, wave); }
        } else {
            let type = isGrave ? 'triangle' : 'sine'; if (isAlta) type = 'square';
            if (isSeca) dur = 0.02;
            if (isRulo) {
                playOscillator(freq, time, 0.02, vol*0.7, 'square'); playOscillator(freq, time + 0.035, 0.02, vol*0.7, 'square'); playOscillator(freq, time + 0.07, 0.03, vol, 'square');
            } else { if(base !== '') playOscillator(freq, time, dur, vol, type); }
        }
      }
      
      // FUNÇÃO DE REPRODUÇÃO E SINCRONIZAÇÃO EM TEMPO REAL NO JS
      function queuePattern(patternStr, bpm, pack, instrumento_str, timbre, isLast, isPrincipal) {
        if (window.audioCtx.state === 'suspended') window.audioCtx.resume();
        let beatDuration = 60.0 / bpm;
        let now = window.audioCtx.currentTime;
        
        // Garante que se houve um engasgo, a fila se ajusta sem engolir o tempo todo
        if (window.audioQueueTime < now) { window.audioQueueTime = now + 0.02; }
        
        let startTime = window.audioQueueTime;
        let beats = patternStr.split('|'); 
        
        for (let b = 0; b < beats.length; b++) {
          let beatStr = beats[b].trim(); if (beatStr === '') continue;
          
          if (isPrincipal) {
            let beatTime = startTime + (b * beatDuration);
            let delayMs = Math.max(0, (beatTime - window.audioCtx.currentTime) * 1000);
            let tempoNum = b + 1; // 1 a 8
            setTimeout(() => {
              window.atualizarCursor(tempoNum, true);
            }, delayMs);
          }

          let tokens = beatStr.split(/\\s+/).filter(t => t.length > 0); if (tokens.length === 0) continue;
          let tokenDuration = beatDuration / tokens.length; 
          for (let i = 0; i < tokens.length; i++) {
            let token = tokens[i]; let slotTime = startTime + (b * beatDuration) + (i * tokenDuration);
            if (token.includes('.')) {
              let subTokens = token.split('.'); let subDuration = tokenDuration / subTokens.length;
              for (let j = 0; j < subTokens.length; j++) { playSyntheticSound(subTokens[j], slotTime + (j * subDuration), pack, instrumento_str, timbre, isPrincipal); }
            } else { playSyntheticSound(token, slotTime, pack, instrumento_str, timbre, isPrincipal); }
          }
        }
        
        if (isLast) { window.audioQueueTime = startTime + (beats.length * beatDuration); }
      }
    ")))
  ),
  
  sidebar = sidebar(
    width = 340,
    sliderInput("bpm", "Velocidade (BPM):", min = 40, max = 150, value = 80, step = 5),
    sliderInput("rep_levadas", "Repetições das Levadas (mín - máx):", min = 2, max = 32, value = c(2, 8), step = 2),
    selectInput("instrumento", "Foco no Instrumento:", choices = instrumentos_disponiveis, selected = "Dobra"),
    
    selectInput("timbre_som", "Estilo / Timbre dos Sons:", 
                choices = c("Meus Sons (.wav)", "Orgânico / Acústico", "Sintético Padrão", "Eletrônico / Punch"), 
                selected = "Meus Sons (.wav)"),
    
    accordion(
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
      )
    ),
    
    hr(),
    div(class = "btn-container",
        actionButton("btn_play", "Tocar", icon = icon("play-circle"), class = "btn-lg btn-primary", disabled = "TRUE")
    )
  ),
  
  card(
    class = "text-center",
    style = "display: flex; flex-direction: column; justify-content: center; align-items: center; min-height: 85vh;",
    
    div(
      style = "display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 15px; padding: 0 10px;",
      h4(textOutput("status_texto"), style = "color: #EF6C00 !important; font-weight: bold; margin: 0;"),
      actionButton("btn_toggle_box_atual", " Ocultar Sinal Atual", icon = icon("eye-slash"), class = "btn-sm btn-outline-secondary", style = "font-weight: bold; border-color: #bdc3c7;")
    ),
    
    div(
      class = "painel-condutor",
      div(
        class = "box-atual", id = "box_atual_container",
        h6("TOCANDO", style = "color: #7f8c8d; font-weight: bold; font-size: 0.8rem; margin: 0;"),
        h3(textOutput("nome_padrao_atual"), style = "font-size: 1.1rem; font-weight: bold; color: #34495e; text-align: center; margin: 8px 0; min-height: 28px;"),
        uiOutput("imagem_sinal_atual")
      ),
      div(
        class = "box-proximo", id = "box_proximo_container",
        uiOutput("conteudo_proximo_dinamico")
      ),
      div(
        class = "box-contagem",
        h5("CONTAGEM", style = "color: #5E2157; font-weight: bold; letter-spacing: 2px; margin-bottom: 5px;"),
        uiOutput("conteudo_contador")
      )
    ),
    
    div(
      style = "background-color: #f8f9fa; padding: 15px 20px; border-radius: 10px; width: 100%; margin-top: 5px; border: 1px solid #e0e0e0; min-height: 140px; display: flex; flex-direction: column; justify-content: center;",
      h5(textOutput("titulo_instrumento"), style = "color: #7f8c8d !important; margin-bottom: 8px; text-align: center;"),
      tags$div(id = "texto_peteleco", "Nenhum sinal ativo no momento.")
    )
  )
)

# ==============================================================================
# 3. LÓGICA DO SERVIDOR (SERVER)
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
    if (length(l_ativas) == 0 && length(c_ativas) == 0) {
      return(tags$p(style="color: #e74c3c; font-size: 0.9em; margin-top: 15px; text-align: center;", "Selecione primeiro as Levadas ou Convenções acima."))
    }
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
  
  estado <- reactiveValues(
    rodando = FALSE, tempo_atual = 0, em_contagem = FALSE, bips_contagem = 0,
    primeira_renderizacao = FALSE, metade_ativa = 1, veio_de_convencao = TRUE, nota_forcada = "",
    exibir_box_atual = TRUE, fase_atual = "Levada", padrao_atual = "", compassos_restantes = 0, compassos_tocados = 0,
    proxima_fase = "", proximo_padrao = "", proximos_compassos = 0,
    m1 = list(), m2 = list(), m3 = list(),
    m1_next = list(), m2_next = list(), m3_next = list()
  )
  
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
  
  reset_tudo <- function() {
    estado$rodando <- FALSE; estado$em_contagem <- FALSE; estado$bips_contagem <- 0
    shinyjs::runjs("stopAudio(); if(window.atualizarCursor) window.atualizarCursor(0, false);")
    updateActionButton(session, "btn_play", label = " Tocar", icon = icon("play-circle"))
    shinyjs::removeClass("btn_play", "btn-danger"); shinyjs::addClass("btn_play", "btn-primary")
    
    shinyjs::enable("bpm"); shinyjs::enable("rep_levadas"); shinyjs::enable("instrumento"); shinyjs::enable("timbre_som")
    shinyjs::enable("levadas_ativas"); shinyjs::enable("variada_opcoes"); shinyjs::enable("conv_ativas")
    shinyjs::enable("acompanhamento_ativo"); shinyjs::enable("config_acompanhamento")
    
    estado$veio_de_convencao <- TRUE; estado$nota_forcada <- ""; estado$tempo_atual <- 0
    estado$fase_atual <- "Levada"; estado$padrao_atual <- ""; estado$compassos_restantes <- 0; estado$compassos_tocados <- 0
    estado$metade_ativa <- 1; estado$proxima_fase <- ""; estado$proximo_padrao <- ""; estado$proximos_compassos <- 0
    estado$m1 <- list(); estado$m2 <- list(); estado$m3 <- list()
    shinyjs::html("texto_peteleco", "Nenhum sinal ativo no momento.")
  }
  
  processar_compasso <- function(padrao, instrumento, fase, tocados, veio_conv, nota_forcada = "") {
    if (fase == "Levada") { df <- df_levadas[df_levadas$Levada == padrao & df_levadas$Instrumento == instrumento, ] }
    else { df <- df_convencoes[df_convencoes$Convencao == padrao & df_convencoes$Instrumento == instrumento, ] }
    
    if (nrow(df) == 0) return("-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --")
    
    # Tolerância caso a coluna do CSV venha com "." no lugar de espaço (ex: Compasso.1)
    col_c1 <- if("Compasso_1" %in% colnames(df)) "Compasso_1" else if("Compasso.1" %in% colnames(df)) "Compasso.1" else names(df)[3]
    col_c2 <- if("Compasso_2" %in% colnames(df)) "Compasso_2" else if("Compasso.2" %in% colnames(df)) "Compasso.2" else names(df)[4]
    
    c1 <- df[[col_c1]][1]; c2 <- df[[col_c2]][1]
    if (is.na(c1)) c1 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
    if (is.na(c2)) c2 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
    
    col_loop <- if("Loop_C2" %in% colnames(df)) "Loop_C2" else if("Loop.C2" %in% colnames(df)) "Loop.C2" else NULL
    is_loop_c2 <- FALSE
    
    if (fase == "Levada" && !is.null(col_loop)) {
      val_loop <- df[[col_loop]][1]
      if (!is.na(val_loop) && toupper(trimws(as.character(val_loop))) %in% c("SIM", "S", "TRUE", "1")) {
        is_loop_c2 <- TRUE
      }
    }
    
    if (is_loop_c2) { idx <- if (tocados == 0) 1 else 2 } else { idx <- (tocados %% 2) + 1 }
    comp_str <- if (idx == 1) c1 else c2
    
    if (fase == "Levada") {
      if (tocados == 0 && veio_conv) comp_str <- gsub("\\([^)]+\\)", "--", comp_str) else comp_str <- gsub("\\(|\\)", "", comp_str)      
    } else { comp_str <- gsub("\\(|\\)", "", comp_str) }
    
    if (tocados == 0 && !is.null(nota_forcada) && !is.na(nota_forcada) && nota_forcada != "") comp_str <- sub("^\\S+", nota_forcada, trimws(comp_str))
    return(comp_str)
  }
  
  avancar_fase <- function() {
    fase_anterior <- estado$fase_atual
    padrao_anterior <- estado$padrao_atual
    
    if (fase_anterior == "Convenção") {
      df_c <- df_convencoes[df_convencoes$Convencao == estado$padrao_atual & df_convencoes$Instrumento == input$instrumento, ]
      col_forca <- if("Forca_Primeira_Nota" %in% colnames(df_c)) "Forca_Primeira_Nota" else if("Forca.Primeira.Nota" %in% colnames(df_c)) "Forca.Primeira.Nota" else NULL
      estado$nota_forcada <- if(!is.null(col_forca) && nrow(df_c) > 0 && !is.na(df_c[[col_forca]][1])) df_c[[col_forca]][1] else ""
    } else { estado$nota_forcada <- "" }
    
    estado$veio_de_convencao <- (fase_anterior == "Convenção")
    estado$fase_atual <- estado$proxima_fase; 
    estado$padrao_atual <- estado$proximo_padrao
    estado$compassos_restantes <- estado$proximos_compassos; 
    
    if (padrao_anterior != estado$padrao_atual) { estado$compassos_tocados <- 0 }
    estado$proximo_padrao <- ""
  }
  
  preencher_proximo <- function() {
    if (estado$proximo_padrao == "") {
      opcoes_l <- input$levadas_ativas; opcoes_c <- input$conv_ativas
      tem_l <- length(opcoes_l) > 0; tem_c <- length(opcoes_c) > 0
      
      if (tem_l && tem_c) { estado$proxima_fase <- ifelse(estado$fase_atual == "Levada", "Convenção", "Levada") } 
      else if (tem_l) { estado$proxima_fase <- "Levada" } else if (tem_c) { estado$proxima_fase <- "Convenção" } else { return() }
      
      if (estado$proxima_fase == "Levada") {
        opcoes_validas <- opcoes_l
        if (length(opcoes_l) > 1 && estado$padrao_atual %in% opcoes_l) { opcoes_validas <- setdiff(opcoes_l, estado$padrao_atual) }
        estado$proximo_padrao <- sample(opcoes_validas, 1)
        
        opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
        estado$proximos_compassos <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
      } else {
        opcoes_validas <- opcoes_c
        if (length(opcoes_c) > 1 && estado$padrao_atual %in% opcoes_c) { opcoes_validas <- setdiff(opcoes_c, estado$padrao_atual) }
        estado$proximo_padrao <- sample(opcoes_validas, 1)
        
        dur <- df_convencoes$Duracao[df_convencoes$Convencao == estado$proximo_padrao][1]
        estado$proximos_compassos <- if(!is.na(dur)) dur else 2
      }
    }
  }
  
  gerar_compasso <- function() {
    if (estado$compassos_restantes <= 0) { avancar_fase(); preencher_proximo() }
    nf <- if (estado$compassos_tocados == 0) estado$nota_forcada else ""
    insts_tocar <- unique(c(input$instrumento, input$acompanhamento_ativo))
    strings_comp <- list(); str_variada <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
    
    if (estado$padrao_atual == "Variada") {
      opcoes_sel <- input$variada_opcoes; if (is.null(opcoes_sel) || length(opcoes_sel) == 0) opcoes_sel <- c("Pausa")
      padroes_sel <- dict_variada[opcoes_sel]; batidas_sorteadas <- sample(padroes_sel, 4, replace = TRUE)
      if ("Pausa" %in% opcoes_sel && !(dict_variada[["Pausa"]] %in% batidas_sorteadas)) batidas_sorteadas[sample(1:4, 1)] <- dict_variada[["Pausa"]]
      str_variada <- paste(batidas_sorteadas, collapse = " | ")
    }
    
    for (inst in insts_tocar) {
      if (inst == input$instrumento) {
        if (estado$padrao_atual == "Variada") {
          comp_str <- str_variada
          if (estado$compassos_tocados == 0 && nf != "") comp_str <- sub("^\\S+", nf, trimws(comp_str))
        } else { comp_str <- processar_compasso(estado$padrao_atual, inst, estado$fase_atual, estado$compassos_tocados, estado$veio_de_convencao, nf) }
      } else {
        id_inst <- gsub(" ", "_", inst); ativas_l <- input[[paste0("acomp_lev_", id_inst)]]; ativas_c <- input[[paste0("acomp_conv_", id_inst)]]
        pode_tocar <- FALSE
        if (estado$fase_atual == "Levada" && (estado$padrao_atual %in% ativas_l)) pode_tocar <- TRUE
        if (estado$fase_atual == "Convenção" && (estado$padrao_atual %in% ativas_c)) pode_tocar <- TRUE
        
        if (pode_tocar) {
          if (estado$padrao_atual == "Variada") {
            comp_str <- str_variada; if (estado$compassos_tocados == 0 && nf != "") comp_str <- sub("^\\S+", nf, trimws(comp_str))
          } else { comp_str <- processar_compasso(estado$padrao_atual, inst, estado$fase_atual, estado$compassos_tocados, estado$veio_de_convencao, nf) }
        } else { comp_str <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --" }
      }
      
      if (estado$compassos_restantes == 1 && tolower(estado$proximo_padrao) == "c2" && inst %in% c("Caixa", "Repique")) {
        tempos <- strsplit(comp_str, "\\|")[[1]]; ultimo_tempo <- trimws(tempos[length(tempos)])
        batidas <- strsplit(ultimo_tempo, "\\s+")[[1]]; batidas[length(batidas)] <- "co.co"
        tempos[length(tempos)] <- paste(batidas, collapse = " ")
        comp_str <- paste(tempos, collapse = " | ")
      }
      strings_comp[[inst]] <- comp_str
    }
    
    if (estado$compassos_tocados == 0) estado$nota_forcada <- "" 
    res <- list(html = strings_comp[[input$instrumento]], strings = strings_comp, nome = estado$padrao_atual, 
                img = map_imagens[[estado$padrao_atual]], restantes = estado$compassos_restantes, futuro = estado$proximo_padrao)
    estado$compassos_restantes <- estado$compassos_restantes - 1; estado$compassos_tocados <- estado$compassos_tocados + 1
    preencher_proximo(); return(res)
  }
  
  observe({
    if (length(input$levadas_ativas) > 0 || length(input$conv_ativas) > 0) { shinyjs::enable("btn_play") } 
    else { shinyjs::disable("btn_play"); if (estado$rodando) reset_tudo() }
  })
  
  observeEvent(input$btn_play, {
    req(length(input$levadas_ativas) > 0 || length(input$conv_ativas) > 0)
    estado$rodando <- !estado$rodando
    
    if (estado$rodando) {
      shinyjs::runjs("
        if (window.audioCtx.state === 'suspended') window.audioCtx.resume();
        window.audioQueueTime = window.audioCtx.currentTime + 0.1;
      ")
      
      shinyjs::disable("bpm"); shinyjs::disable("rep_levadas"); shinyjs::disable("instrumento"); shinyjs::disable("timbre_som")
      shinyjs::disable("levadas_ativas"); shinyjs::disable("variada_opcoes"); shinyjs::disable("conv_ativas"); shinyjs::disable("acompanhamento_ativo"); shinyjs::disable("config_acompanhamento")
      
      estado$em_contagem <- TRUE; estado$bips_contagem <- 0
      
      if (estado$padrao_atual == "") {
        estado$veio_de_convencao <- TRUE; estado$nota_forcada <- ""; fases_possiveis <- c()
        if (length(input$levadas_ativas) > 0) fases_possiveis <- c(fases_possiveis, "Levada")
        if (length(input$conv_ativas) > 0) fases_possiveis <- c(fases_possiveis, "Convenção")
        estado$fase_atual <- sample(fases_possiveis, 1)
        
        if (estado$fase_atual == "Levada") {
          estado$padrao_atual <- sample(input$levadas_ativas, 1)
          opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
          estado$compassos_restantes <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
        } else {
          estado$padrao_atual <- sample(input$conv_ativas, 1)
          dur <- df_convencoes$Duracao[df_convencoes$Convencao == estado$padrao_atual][1]
          estado$compassos_restantes <- if(!is.na(dur)) dur else 2
        }
        estado$tempo_atual <- 0; estado$compassos_tocados <- 0; estado$primeira_renderizacao <- TRUE; estado$metade_ativa <- 1
        preencher_proximo()
        
        estado$m1 <- gerar_compasso(); estado$m2 <- gerar_compasso(); estado$m3 <- gerar_compasso()
      }
      updateActionButton(session, "btn_play", label = " Pausar", icon = icon("pause-circle")); shinyjs::removeClass("btn_play", "btn-primary"); shinyjs::addClass("btn_play", "btn-danger")
    } else { reset_tudo() }
  })
  
  observe({
    req(estado$rodando)
    intervalo_ms <- 60000 / input$bpm
    invalidateLater(intervalo_ms)
    
    isolate({
      if (estado$em_contagem) {
        estado$bips_contagem <- estado$bips_contagem + 1
        
        if (estado$bips_contagem == 4 && length(estado$m1) > 0 && !is.null(estado$m1$nome) && tolower(estado$m1$nome) == "c2") {
          insts_tocar <- unique(c(input$instrumento, input$acompanhamento_ativo))
          for (inst in insts_tocar) {
            if (inst %in% c("Caixa", "Repique")) {
              is_principal <- tolower(as.character(inst == input$instrumento))
              js_code <- sprintf("
                if (window.audioCtx.state === 'suspended') window.audioCtx.resume();
                let now = window.audioCtx.currentTime;
                let beatDur = 60.0 / %s;
                playSyntheticSound('co', now + (beatDur * 0.75), '1', '%s', '%s', %s);
                playSyntheticSound('co', now + (beatDur * 0.875), '1', '%s', '%s', %s);
              ", input$bpm, inst, input$timbre_som, is_principal, inst, input$timbre_som, is_principal)
              shinyjs::runjs(js_code)
            }
          }
        }
        
        if (estado$bips_contagem <= 4) { 
          shinyjs::runjs("if (window.audioCtx.state === 'suspended') window.audioCtx.resume(); playOscillator(880, window.audioCtx.currentTime, 0.05, 0.5, 'sine');")
          return() 
        } else { 
          estado$em_contagem <- FALSE 
        }
      }
      
      estado$tempo_atual <- estado$tempo_atual + 1
      if (estado$tempo_atual > 8) estado$tempo_atual <- 1
      if (estado$tempo_atual >= 1 && estado$tempo_atual <= 4) estado$metade_ativa <- 1 else estado$metade_ativa <- 2
      
      if (estado$tempo_atual == 4 && !estado$primeira_renderizacao) {
        estado$m_buffer_2 <- gerar_compasso(); estado$m_buffer_3 <- gerar_compasso()
        estado$m1_next <- estado$m3; estado$m2_next <- estado$m_buffer_2; estado$m3_next <- estado$m_buffer_3
        
        insts_tocar <- unique(c(input$instrumento, input$acompanhamento_ativo))
        for (i in seq_along(insts_tocar)) {
          inst <- insts_tocar[i]; is_last <- tolower(as.character(i == length(insts_tocar))); is_principal <- tolower(as.character(inst == input$instrumento))
          s1 <- estado$m1_next$strings[[inst]]; s2 <- estado$m2_next$strings[[inst]]
          if (is.null(s1)) s1 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
          if (is.null(s2)) s2 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
          texto_limpo <- gsub("\n", " ", paste(s1, s2, sep=" | "))
          shinyjs::runjs(sprintf("queuePattern('%s', %s, '1', '%s', '%s', %s, %s);", texto_limpo, input$bpm, inst, input$timbre_som, is_last, is_principal))
        }
      }
      
      if (estado$tempo_atual == 1) {
        if (estado$primeira_renderizacao) { 
          estado$primeira_renderizacao <- FALSE 
          insts_tocar <- unique(c(input$instrumento, input$acompanhamento_ativo))
          
          for (i in seq_along(insts_tocar)) {
            inst <- insts_tocar[i]; is_last <- tolower(as.character(i == length(insts_tocar))); is_principal <- tolower(as.character(inst == input$instrumento))
            s1 <- estado$m1$strings[[inst]]; s2 <- estado$m2$strings[[inst]]
            if (is.null(s1)) s1 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
            if (is.null(s2)) s2 <- "-- -- -- -- | -- -- -- -- | -- -- -- -- | -- -- -- --"
            texto_limpo <- gsub("\n", " ", paste(s1, s2, sep=" | "))
            shinyjs::runjs(sprintf("queuePattern('%s', %s, '1', '%s', '%s', %s, %s);", texto_limpo, input$bpm, inst, input$timbre_som, is_last, is_principal))
          }
        } else { 
          estado$m1 <- estado$m1_next; estado$m2 <- estado$m2_next; estado$m3 <- estado$m3_next
        }
      }
    })
  })
  
  observe({
    req(estado$rodando)
    if (estado$padrao_atual == "" || length(estado$m1$html) == 0 || estado$m1$html == "") return()
    
    str_l1 <- if (estado$metade_ativa == 1) estado$m1$html else estado$m3$html
    str_l2 <- estado$m2$html
    
    formatar_linha <- function(linha_str, offset) {
      if (is.null(linha_str) || linha_str == "") return("")
      tempos <- strsplit(linha_str, "\\|")[[1]]
      tempos_fmt <- sapply(seq_along(tempos), function(i) {
        parts <- strsplit(trimws(tempos[i]), "\\s+")[[1]]
        for (j in seq_along(parts)) {
          s <- parts[j]; if (s == "--") next
          if (grepl("\\.", s)) {
            sub_parts <- strsplit(s, "\\.")[[1]]
            fmt_sub <- sapply(sub_parts, function(sp) {
              is_seca <- grepl("\\*", sp); sp_clean <- gsub("\\*", "", sp)
              if (grepl("~", sp_clean)) { txt <- paste0("<i>", toupper(gsub("~", "", sp_clean)), "</i>") } 
              else if (grepl("[A-Z]", sp_clean) && sp_clean == toupper(sp_clean)) { txt <- paste0("<b>", sp_clean, "</b>") } 
              else { txt <- tolower(sp_clean) }
              if (is_seca) txt <- paste0(txt, "*")
              return(txt)
            })
            parts[j] <- paste(fmt_sub, collapse = ".")
          } else {
            is_seca <- grepl("\\*", s); s_clean <- gsub("\\*", "", s)
            if (grepl("~", s_clean)) { txt <- paste0("<i>", toupper(gsub("~", "", s_clean)), "</i>") } 
            else if (grepl("[A-Z]", s_clean) && s_clean == toupper(s_clean)) { txt <- paste0("<b>", s_clean, "</b>") } 
            else { txt <- tolower(s_clean) }
            if (is_seca) txt <- paste0(txt, "*")
            parts[j] <- txt
          }
        }
        paste0("<span id='span-tempo-", (i + offset), "' class='span-tempo'>", paste(parts, collapse = " "), "</span>")
      }, USE.NAMES = FALSE)
      return(paste(tempos_fmt, collapse = " <span style='color: #bdc3c7'>|</span> "))
    }
    
    l1 <- formatar_linha(str_l1, offset = 0); l2 <- formatar_linha(str_l2, offset = 4)
    shinyjs::html("texto_peteleco", paste0("<div style='margin-bottom: 8px;'>", l1, "</div><div>", l2, "</div>"))
    shinyjs::runjs("if(window.reaplicarCursor) window.reaplicarCursor();")
  })
  
  output$status_texto <- renderText({
    if (estado$padrao_atual == "") return("Pronto para o ensaio! Escolha as levadas e toque.")
    if (estado$em_contagem) return("Atenção, bateria...")
    return("Tocando...")
  })
  output$nome_padrao_atual <- renderText({ 
    if (estado$padrao_atual == "") return("-")
    m_active <- if(estado$metade_ativa == 1) estado$m1 else estado$m2
    return(if(length(m_active) > 0 && !is.null(m_active$nome)) m_active$nome else "")
  })
  output$imagem_sinal_atual <- renderUI({
    if (!estado$rodando && estado$padrao_atual == "") return(tags$div(style = "height: 80px;"))
    m_active <- if(estado$metade_ativa == 1) estado$m1 else estado$m2
    img_ativa <- if(length(m_active) > 0 && !is.null(m_active$img)) m_active$img else ""
    if (img_ativa != "") tags$img(src = img_ativa, style = "max-height: 80px; max-width: 100%; object-fit: contain; filter: grayscale(40%); opacity: 0.9;")
    else tags$div("-", style = "height: 80px;")
  })
  
  output$conteudo_proximo_dinamico <- renderUI({
    is_loop <- (length(input$levadas_ativas) + length(input$conv_ativas)) == 1
    if (is_loop) {
      shinyjs::runjs("$('#box_proximo_container').css('box-shadow', '0 8px 20px rgba(0,0,0,0.05)');")
      return(div(style = "display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; opacity: 0.3;",
                 h2("MODO LOOP", style = "font-size: 1.8rem; color: #5E2157; font-weight: 900; margin: 0;")))
    }
    
    m_active <- if(estado$metade_ativa == 1) estado$m1 else estado$m2
    restantes <- if(length(m_active) > 0 && !is.null(m_active$restantes)) m_active$restantes else -1
    is_transicao <- estado$em_contagem || (estado$rodando && restantes == 1)
    
    nome_mostrar <- ""
    if (estado$em_contagem) { 
      nome_mostrar <- if(length(estado$m1) > 0 && !is.null(estado$m1$nome)) estado$m1$nome else estado$padrao_atual 
    } 
    else if (is_transicao) {
      m_next <- if(estado$metade_ativa == 1) estado$m2 else estado$m3
      nome_mostrar <- if (!is.null(m_next$nome) && m_next$nome != "") m_next$nome else (if(!is.null(m_active$futuro) && m_active$futuro != "") m_active$futuro else estado$proximo_padrao)
    }
    
    arquivo_img <- if(nome_mostrar != "") map_imagens[[nome_mostrar]] else NULL
    shinyjs::runjs(sprintf("$('#box_proximo_container').css('box-shadow', '0 8px %spx rgba(239,108,0,0.%s)');", if(is_transicao) "30" else "20", if(is_transicao) "5" else "05"))
    
    div(
      style = "display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 100%; position: relative;",
      div(
        style = sprintf("opacity: %s; transition: opacity 0.25s ease-in-out; display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%%;", if(is_transicao) "1" else "0"),
        h6("ATENÇÃO BATERIA: PREPARA", class = if(is_transicao) "piscar" else "", style = "color: #EF6C00; font-weight: bold; margin: 0; min-height: 20px;"),
        h2(if(nome_mostrar != "") nome_mostrar else "-", style = "font-size: 2.2rem; color: #5E2157; font-weight: 900; text-align: center; margin: 5px 0; min-height: 45px;"),
        div(style = "height: 120px; display: flex; align-items: center; justify-content: center; width: 100%;", if (!is.null(arquivo_img)) tags$img(src = arquivo_img, style = "max-height: 110px; max-width: 100%; object-fit: contain;") else tags$div(style = "height: 110px;"))
      ),
      if (!is_transicao) div(style = "position: absolute; color: #bdc3c7; font-weight: bold; font-style: italic; font-size: 1.3rem;", "MANTÉM...")
    )
  })
  
  output$conteudo_contador <- renderUI({
    is_loop <- (length(input$levadas_ativas) + length(input$conv_ativas)) == 1
    if (is_loop && !estado$em_contagem) { return(div(class = "contador-numero texto-desfoque", "∞")) }
    
    m_active <- if(estado$metade_ativa == 1) estado$m1 else estado$m2
    restantes <- if(length(m_active) > 0 && !is.null(m_active$restantes)) m_active$restantes else -1
    is_transicao <- estado$em_contagem || (estado$rodando && restantes == 1); numero_exibir <- "-"
    
    if (estado$em_contagem) { val <- 5 - estado$bips_contagem; numero_exibir <- ifelse(val >= 1 && val <= 4, val, "!") } 
    else if (is_transicao) { t_relativo <- ifelse(estado$tempo_atual <= 4, estado$tempo_atual, estado$tempo_atual - 4); numero_exibir <- 5 - t_relativo }
    
    div(class = ifelse(is_transicao, "contador-numero", "contador-numero texto-desfoque"), numero_exibir)
  })
  output$titulo_instrumento <- renderText({ paste("Leitura -", input$instrumento) })
}
shinyApp(ui = ui, server = server)