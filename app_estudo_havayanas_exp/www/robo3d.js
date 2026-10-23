/* Robô 3D do painel condutor (Havayanas Ousadas).
 * Depende de three.min.js (r128), carregado antes. API global: window.Robo3D
 *   Robo3D.init('id_do_div')      -> true se o WebGL funcionou (senão o app segue com o robô 2D)
 *   Robo3D.beat(nome, i, beatMs, alerta)  -> chamado em CADA tempo tocado (nome da levada/convenção, i = 0..3)
 *   Robo3D.parar()                -> volta para a pose parada
 * Danças: Funk 1, Funk 2, Funk 3 (levadas com esse nome); "Pausa" = parado balançando; resto = pisada lateral de sempre.
 */
(function () {
  'use strict';
  if (typeof THREE === 'undefined') return;

  var ROXO = 0x5E2157, LARANJA = 0xEF6C00, METAL = 0xd8d4de, ESCURO = 0x2a1a2e, OLHO = 0xf1c40f, OLHO_ALERTA = 0xEF6C00;

  var renderer, scene, camera, palco;
  var raiz, quadril, tronco, cabeca, bracoD, bracoE, pernaD, pernaE, matOlhos;
  var pronto = false;

  function mat(c) { return new THREE.MeshLambertMaterial({ color: c }); }
  function caixa(w, h, d, c) { return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(c)); }
  function cil(r, h, c) { return new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 16), mat(c)); }
  function esf(r, c) { return new THREE.Mesh(new THREE.SphereGeometry(r, 16, 12), mat(c)); }

  // ---------- Corpo de chinelo de dedo (tema do bloco "Havaianas Usadas") ----------
  // O próprio corpo é um chinelo em pé: sola branca atrás, palmilha roxa na frente e a tira em Y amarela.
  var CH_ALT = 1.42;                         // altura do chinelo (do calcanhar até a ponta)
  function meiaLargura(y) { return 0.34 + 0.17 * (y / CH_ALT); }   // calcanhar (embaixo) mais estreito, ponta (em cima) mais larga
  function contornoChinelo(escala) {
    var sh = new THREE.Shape(), n = 48, k, c = CH_ALT / 2;
    for (k = 0; k < n; k++) {
      var t = (k / n) * Math.PI * 2, y = c + c * Math.cos(t) * escala;
      var x = meiaLargura(y) * escala * Math.sin(t);
      if (k === 0) sh.moveTo(x, y); else sh.lineTo(x, y);
    }
    sh.closePath(); return sh;
  }
  function camadaChinelo(escala, z0, esp, cor) {
    var g = new THREE.ExtrudeGeometry(contornoChinelo(escala), { depth: esp, bevelEnabled: true, bevelThickness: 0.015, bevelSize: 0.015, bevelSegments: 2 });
    g.translate(0, 0, z0);
    return new THREE.Mesh(g, mat(cor));
  }
  function tiraChinelo(x0, y0, topo, cor) {
    var curva = new THREE.QuadraticBezierCurve3(new THREE.Vector3(x0, y0, 0.085), new THREE.Vector3(x0 * 0.45, (y0 + topo.y) / 2 + 0.1, 0.13), topo);
    var m = new THREE.Mesh(new THREE.TubeGeometry(curva, 16, 0.05, 10, false), mat(cor));
    m.scale.set(1, 1, 0.55); m.position.z = topo.z * (1 - 0.55); return m;
  }
  function corpoChinelo() {
    var g = new THREE.Group(), AMARELO = 0xf1c40f;
    g.add(camadaChinelo(1.0, -0.17, 0.12, 0xF5F1E8));      // sola branca (atrás)
    g.add(camadaChinelo(0.9, -0.05, 0.12, ROXO));        // palmilha roxa (frente)
    var topo = new THREE.Vector3(0, 1.08, 0.095);
    var sy = 0.56, sx = meiaLargura(sy) * 0.9;
    g.add(tiraChinelo(sx, sy, topo, AMARELO)); g.add(tiraChinelo(-sx, sy, topo, AMARELO));
    var pino = esf(0.075, AMARELO); pino.position.copy(topo); pino.position.z += 0.03; pino.scale.set(1, 1, 0.7); g.add(pino);
    [-1, 1].forEach(function (l) { var t = esf(0.06, AMARELO); t.position.set(sx * l, sy, 0.085); t.scale.set(1, 1, 0.6); g.add(t); });
    return g;
  }

  // ---------- Construção do robô (de frente pra câmera, +z; lado DIREITO do robô = -x) ----------
  function construir() {
    raiz = new THREE.Group(); scene.add(raiz);
    quadril = new THREE.Group(); quadril.position.y = 1.05; raiz.add(quadril);
    quadril.add(caixa(0.4, 0.22, 0.18, ESCURO));

    function perna(lado) {
      var g = new THREE.Group(); g.position.set(0.18 * lado, -0.08, 0); quadril.add(g);
      var coxa = cil(0.1, 0.5, METAL); coxa.position.y = -0.27; g.add(coxa);
      var joelho = new THREE.Group(); joelho.position.y = -0.52; g.add(joelho);
      joelho.add(esf(0.11, LARANJA));
      var canela = cil(0.09, 0.42, METAL); canela.position.y = -0.24; joelho.add(canela);
      var pe = new THREE.Group(); pe.position.set(0, -0.47, 0); joelho.add(pe);   // pivô exatamente no tornozelo
      var solado = caixa(0.22, 0.1, 0.36, LARANJA); solado.position.set(0, 0, 0.06); pe.add(solado);
      return { g: g, joelho: joelho, pe: pe, lado: lado };
    }
    pernaD = perna(-1); pernaE = perna(1);

    tronco = new THREE.Group(); tronco.position.y = 0.12; quadril.add(tronco);
    var cc = corpoChinelo(); cc.position.y = -0.14; tronco.add(cc);

    function braco(lado) {
      var g = new THREE.Group(); g.position.set(0.43 * lado, 0.84, -0.04); tronco.add(g);
      g.add(esf(0.13, LARANJA));
      var sup = cil(0.08, 0.36, METAL); sup.position.y = -0.24; g.add(sup);
      var cot = new THREE.Group(); cot.position.y = -0.44; g.add(cot);
      cot.add(esf(0.09, LARANJA));
      var ant = cil(0.07, 0.32, METAL); ant.position.y = -0.2; cot.add(ant);
      var mao = esf(0.1, ROXO); mao.position.y = -0.4; cot.add(mao);
      return { g: g, cot: cot, lado: lado };
    }
    bracoD = braco(-1); bracoE = braco(1);

    // cabeça do robô saindo pela ponta do chinelo (a ponta do chinelo fica na frente do pescoço)
    cabeca = new THREE.Group(); cabeca.position.set(0, 1.12, -0.2); cabeca.scale.set(0.8, 0.8, 0.8); tronco.add(cabeca);
    var pescoco = cil(0.09, 0.2, METAL); pescoco.position.y = 0.02; cabeca.add(pescoco);
    var cranio = caixa(0.66, 0.52, 0.52, METAL); cranio.position.y = 0.32; cabeca.add(cranio);
    var visor = caixa(0.54, 0.22, 0.02, ESCURO); visor.position.set(0, 0.36, 0.265); cabeca.add(visor);
    matOlhos = new THREE.MeshBasicMaterial({ color: OLHO });
    [-0.13, 0.13].forEach(function (x) {
      var o = new THREE.Mesh(new THREE.SphereGeometry(0.065, 16, 12), matOlhos); o.position.set(x, 0.36, 0.28); cabeca.add(o);
    });
    var boca = caixa(0.2, 0.04, 0.02, LARANJA); boca.position.set(0, 0.17, 0.265); cabeca.add(boca);
    var haste = cil(0.02, 0.22, METAL); haste.position.y = 0.69; cabeca.add(haste);
    var bolinha = esf(0.06, LARANJA); bolinha.position.y = 0.82; cabeca.add(bolinha);
    [-1, 1].forEach(function (l) { var e = cil(0.08, 0.06, LARANJA); e.rotation.z = Math.PI / 2; e.position.set(0.35 * l, 0.32, 0); cabeca.add(e); });

    construirInstrumento();

    // sombra suave no chão
    var sombra = new THREE.Mesh(new THREE.CircleGeometry(0.9, 32), new THREE.MeshBasicMaterial({ color: 0x5E2157, transparent: true, opacity: 0.12 }));
    sombra.rotation.x = -Math.PI / 2; sombra.position.y = 0.003; scene.add(sombra);
    scene.userData.sombra = sombra;
  }


  // ---------- Instrumento (por enquanto só a Dobra: surdo pendurado + 2 baquetas) ----------
  // Regra das mãos (todos os instrumentos menos o xequerê): pe, le (e la) = mão DIREITA; te, co (e ta) = mão ESQUERDA.
  // tipos: Dobra e Fundos = surdo; Caixa e Repique = tambor menor; Xequerê = chocalho de cabaça
  // movimento da mão: rest = altura de descanso, prep = pico do preparo numa nota normal, acc = pico numa nota de destaque,
  // lead/leadAcc = quanto antes (ms) a mão começa a subir, desc = duração da descida até o couro
  var MOV = {
    surdo: { rest: 0.75, prep: 1.0,  acc: 1.7, lead: 520, leadAcc: 700, desc: 150 },
    caixa: { rest: 0.16, prep: 0.30, acc: 1.15, lead: 200, leadAcc: 440, desc: 90 }
  };
  var TIPOS = {
    dobra:   { k: 'tambor', rx: 1.0,  ry: 1.0,  mov: 'surdo', baq: 'bola' },
    fundo1:  { k: 'tambor', rx: 1.12, ry: 1.15, mov: 'surdo', baq: 'bola' },
    fundo2:  { k: 'tambor', rx: 1.12, ry: 1.15, mov: 'surdo', baq: 'bola' },
    caixa:   { k: 'tambor', rx: 0.78, ry: 0.55, mov: 'caixa', baq: 'madeira' },
    repique: { k: 'tambor', rx: 0.66, ry: 0.55, mov: 'caixa', baq: 'plastico' },
    xequere: { k: 'xeq' }
  };
  function tipoInst(nome) {
    if (!nome) return null;
    var k = String(nome).toLowerCase().replace(/[\u0300-\u036f]/g, '').normalize ? String(nome).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '') : '';
    return TIPOS[k] || null;
  }
  var surdo, surdoCorpo, baquetaD, baquetaE, xeq, _pCouro = {}, _tipoAtual = null;
  var L1 = 0.44, L2 = 0.40, BAQ = 0.5, LEVANTA = 1;   // LEVANTA = 1 → 'h' vai de 0 (batida) a 1 (mão no alto)
  // direção da baqueta (da mão até a ponta): para frente, um pouco para baixo e para dentro (as duas se encontram no couro)
  var GIRO_INST = 0.45, _vsL = {}, _vsN = {};
  [-1, 1].forEach(function (l) { _vsN[l] = new THREE.Vector3(-l * 0.15, -0.3, 0.9).normalize(); _vsL[l] = _vsN[l].clone().multiplyScalar(BAQ); });
  function cil24(r, h, c) { return new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 28), mat(c)); }
  // três tipos de baqueta: 'bola' (Dobra e Fundos: haste com bolinha laranja), 'madeira' (Caixa: baqueta toda de madeira, mais grossa no cabo)
  // e 'plastico' (Repique: duas varetas finas de plástico duro, sem bolinha). A ponta de todas fica a BAQ da mão.
  function criarBaqueta() {
    var g = new THREE.Group(), tipos = {};
    var b1 = new THREE.Group();
    var haste = cil(0.02, 0.58, 0xE8C9A0); haste.position.y = -0.17; b1.add(haste);   // sai um pouco por trás do punho
    var bola = esf(0.055, LARANJA); bola.position.y = -0.455; b1.add(bola);
    var b2 = new THREE.Group();
    var cone = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.017, 0.62, 14), mat(0xC98B45)); cone.position.y = -0.19; b2.add(cone);
    var ponta = esf(0.026, 0xC98B45); ponta.scale.set(1, 1.35, 1); ponta.position.y = -0.485; b2.add(ponta);
    var b3 = new THREE.Group();
    var vara = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.62, 10), mat(0xF4C542)); vara.position.y = -0.19; b3.add(vara);
    tipos.bola = b1; tipos.madeira = b2; tipos.plastico = b3;
    [b1, b2, b3].forEach(function (x) { g.add(x); });
    g.userData.tipos = tipos;
    g.visible = false; tronco.add(g); return g;
  }
  function escolheBaqueta(g, nome) {
    var t = g.userData.tipos;
    Object.keys(t).forEach(function (k) { t[k].visible = (k === nome); });
  }
  function construirInstrumento() {
    surdo = new THREE.Group(); surdo.position.set(0, -0.24, 0.66); surdo.rotation.x = 0.45; surdo.visible = false; tronco.add(surdo);
    surdoCorpo = new THREE.Group(); surdo.add(surdoCorpo);
    surdoCorpo.add(cil24(0.30, 0.40, LARANJA));
    var fita = cil24(0.306, 0.07, 0xf1c40f); surdoCorpo.add(fita);
    var couro = cil24(0.296, 0.026, 0xF5F1E8); couro.position.y = 0.2; surdoCorpo.add(couro);
    [0.2, -0.2].forEach(function (y) { var aro = cil24(0.316, 0.036, METAL); aro.position.y = y; surdoCorpo.add(aro); });
    surdo.updateMatrix();
    [-1, 1].forEach(function (l) { _pCouro[l] = new THREE.Vector3(0.14 * l, 0.2135, 0.06).applyMatrix4(surdo.matrix); });
    baquetaD = criarBaqueta(); baquetaE = criarBaqueta();
    // xequerê: cabaça laranja com a rede de contas amarelas e um cabo
    xeq = new THREE.Group(); xeq.visible = false; tronco.add(xeq);
    var cab = esf(0.17, LARANJA); cab.scale.set(1, 1.15, 1); xeq.add(cab);
    var cabo = cil(0.05, 0.3, 0xE8C9A0); cabo.position.y = -0.34; xeq.add(cabo);
    for (var a = 0; a < 5; a++) for (var h = -2; h <= 2; h++) {
      var ang = a / 5 * Math.PI * 2 + (h % 2) * 0.3, y = h * 0.095, r = 0.17 * Math.sqrt(Math.max(0, 1 - Math.pow(y / 0.195, 2))) * 1.02;
      var bola = esf(0.026, 0xf1c40f); bola.position.set(Math.sin(ang) * r, y, Math.cos(ang) * r); xeq.add(bola);
    }
    xeq.position.set(0, 0.26, 0.5); xeq.rotation.x = 0.35;
  }
  // ajusta o tambor ao tipo (tamanho) mantendo a pele na mesma altura
  function ajustaTambor(t) {
    surdoCorpo.userData.base = [t.rx, t.ry, t.rx];
    surdoCorpo.scale.set(t.rx, t.ry, t.rx);
    var d = 0.2135 * (1 - t.ry), c = Math.cos(0.45), sn = Math.sin(0.45);
    surdo.position.set(0, -0.24 + d * c, 0.66 + d * sn);
    surdo.updateMatrix();
    [-1, 1].forEach(function (l) { _pCouro[l] = new THREE.Vector3(0.14 * l * t.rx, 0.2135 * t.ry, 0.06).applyMatrix4(surdo.matrix); });
  }
  function aplicaVisibilidade() {
    var t = tipoInst(est.inst);
    if (t !== _tipoAtual) { _tipoAtual = t; if (t && t.k === 'tambor') ajustaTambor(t); }
    var tam = !!(t && t.k === 'tambor');
    surdo.visible = tam; baquetaD.visible = tam; baquetaE.visible = tam;
    if (tam) { escolheBaqueta(baquetaD, t.baq || 'bola'); escolheBaqueta(baquetaE, t.baq || 'bola'); }
    xeq.visible = !!(t && t.k === 'xeq');
  }
  function maoDe(tk) {
    tk = String(tk || '').toLowerCase().replace(/[^a-z]/g, '').slice(0, 2);
    if (tk === 'pe' || tk === 'le' || tk === 'la') return 'D';
    if (tk === 'te' || tk === 'ta' || tk === 'co') return 'E';
    return null;
  }
  // altura da baqueta (0 = no couro na batida; MOV.rest = descansada; acima = preparo)
  // Antes de cada batida a mão dá uma levantada (preparo) e só então desce; nota de destaque sobe mais e começa mais cedo.
  function descida(tau, forte, M) {        // tau = tempo até a próxima batida (ms)
    var lead = forte ? M.leadAcc : M.lead, pico = forte ? M.acc : M.prep;
    if (tau >= lead) return M.rest;
    if (tau >= M.desc) return M.rest + (pico - M.rest) * suave((lead - tau) / (lead - M.desc));
    return suave(tau / M.desc) * pico;
  }
  function alturaMao(hits, t, M) {
    var tp = -1e9, tn = 1e9, fn = false, k;
    for (k = 0; k < hits.length; k++) { var h = hits[k].t; if (h <= t) { if (h > tp) tp = h; } else if (h < tn) { tn = h; fn = hits[k].a; } }
    return Math.min(descida(tn - t, fn, M), suave(lim01((t - tp) / 150)) * 1.8);
  }
  function pulso(hits, t) {
    var p = 0, k;
    for (k = 0; k < hits.length; k++) { var dt = t - hits[k].t; if (dt >= 0 && dt < 120) p = Math.max(p, (1 - dt / 120) * (hits[k].a ? 1.6 : 1)); }
    return p;
  }
  var _qt = new THREE.Quaternion(), TORCE = 0.9;
  var _tipo = new THREE.Vector3(), _mao = new THREE.Vector3(), _qb2 = new THREE.Quaternion(), _meno = new THREE.Vector3(0, -1, 0);
  function ikBraco(b, tx, ty, tz) {
    _d.set(tx - b.g.position.x, ty - b.g.position.y, tz - b.g.position.z);
    var len = _d.length();
    len = Math.min(L1 + L2 - 0.002, Math.max(Math.abs(L1 - L2) + 0.03, len));
    _d.normalize();
    var dobra = Math.PI - Math.acos(limita((L1 * L1 + L2 * L2 - len * len) / (2 * L1 * L2)));
    var alfa = Math.acos(limita((L1 * L1 + len * len - L2 * L2) / (2 * L1 * len)));
    _q1.setFromUnitVectors(_down, _d);
    _q2.setFromAxisAngle(_ex, alfa);
    b.g.quaternion.copy(_q1).multiply(_q2);
    _qt.setFromAxisAngle(_d, TORCE * b.lado);   // gira o braço em volta da linha ombro→mão para o cotovelo abrir para o lado
    b.g.quaternion.premultiply(_qt);
    b.cot.rotation.set(-dobra, 0, 0);
  }
  var _sv = new THREE.Vector3(), _sn = new THREE.Vector3(), _ex1 = new THREE.Vector3(1, 0, 0);
  function tocarMao(b, baq, lado, hits, agora, M) {
    var P = _pCouro[lado], k = alturaMao(hits, agora, M);   // k: 0 = baqueta no couro, 1 = no alto
    // posição da mão na batida (ponta no couro)
    _mao.copy(P).sub(_vsL[lado]);
    // ao levantar: a mão sobe um pouco e o punho vira a baqueta para cima
    _mao.y += 0.2 * k;
    _sn.copy(_vsN[lado]).applyAxisAngle(_ex1, -1.05 * k);
    ikBraco(b, _mao.x, _mao.y, _mao.z);
    baq.position.copy(_mao);
    baq.quaternion.setFromUnitVectors(_meno, _sn);
  }
  var _xb = new THREE.Vector3();
  function aplicaInstrumento(agora) {
    var t = tipoInst(est.inst);
    if (!t) return;
    var p = Math.max(pulso(est.hitsD, agora), pulso(est.hitsE, agora));
    if (t.k === 'xeq') {
      // chocalho: a cada batida os dois punhos dão um tranco curto para cima e para a frente
      xeq.position.set(0, 0.26 + 0.07 * p, 0.5 + 0.06 * p); xeq.rotation.x = 0.35 - 0.3 * p;
      [[bracoD, -1], [bracoE, 1]].forEach(function (x) {
        _xb.set(0.2 * x[1], -0.12, 0).applyEuler(xeq.rotation).add(xeq.position);
        ikBraco(x[0], _xb.x, _xb.y, _xb.z);
      });
      return;
    }
    var M = MOV[t.mov] || MOV.surdo;
    tocarMao(bracoD, baquetaD, -1, est.hitsD, agora, M);
    tocarMao(bracoE, baquetaE, 1, est.hitsE, agora, M);
    var base = surdoCorpo.userData.base || [1, 1, 1];
    surdoCorpo.scale.set(base[0] * (1 + 0.035 * p), base[1] * (1 - 0.02 * p), base[2] * (1 + 0.035 * p));
  }

  // ---------- Pernas com cinemática inversa: o pé fica ONDE a gente manda (no chão, sem afundar) ----------
  var COXA = 0.52, CANELA = 0.47, ALT_TORN = 0.05;
  var _d = new THREE.Vector3(), _down = new THREE.Vector3(0, -1, 0), _ex = new THREE.Vector3(1, 0, 0), _ey = new THREE.Vector3(0, 1, 0);
  var _q1 = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _qa = new THREE.Quaternion(), _qb = new THREE.Quaternion();
  function limita(x) { return Math.max(-1, Math.min(1, x)); }
  function ik(p, tx, ty, tz) {
    var hx = p.lado * 0.18, hy = quadril.position.y - 0.08;
    _d.set(tx - hx, ty - hy, tz);
    var len = _d.length();
    len = Math.min(COXA + CANELA - 0.002, Math.max(Math.abs(COXA - CANELA) + 0.03, len));
    _d.normalize();
    var dobra = Math.PI - Math.acos(limita((COXA * COXA + CANELA * CANELA - len * len) / (2 * COXA * CANELA)));
    var alfa = Math.acos(limita((COXA * COXA + len * len - CANELA * CANELA) / (2 * COXA * len)));
    _q1.setFromUnitVectors(_down, _d);
    _q2.setFromAxisAngle(_ex, -alfa);
    p.g.quaternion.copy(_q1).multiply(_q2);
    p.joelho.rotation.set(dobra, 0, 0);
  }
  function niveiaPe(p, giro) {
    p.joelho.getWorldQuaternion(_qa);
    _qb.setFromAxisAngle(_ey, giro);
    p.pe.quaternion.copy(_qa.invert()).multiply(_qb);
  }

  // ---------- Danças ----------
  // Pose j vale NO INÍCIO do tempo j (o passo cai em cima da batida). O corpo vai suavemente de uma pose pra
  // próxima durante o tempo; os pés trocam de lugar nos últimos 30% do tempo anterior.
  // Pés: Rx/Rz (direito) e Lx/Lz (esquerdo) = posição no chão (z+ = frente do robô, x- = lado direito dele).
  var P = function (o) { return Object.assign({ x: 0, z: 0, giro: 0, tronco: 0, inclina: 0, bD: 0, bE: 0, Rx: -0.18, Rz: 0, Lx: 0.18, Lz: 0 }, o); };
  var DANCAS = {
    parado: { lift: 0, poses: [P({ bD: -0.2, bE: 0.2 }), P({ bD: 0.2, bE: -0.2 }), P({ bD: -0.2, bE: 0.2 }), P({ bD: 0.2, bE: -0.2 })] },
    padrao: { // pisada lateral de sempre: abre, junta pra direita, abre, junta pra esquerda
      lift: 0.1,
      poses: [   // o tempo 1 é pisado com a perna ESQUERDA do robô (a da direita na tela, vendo de frente)
        P({ x: 0, Rx: -0.38, Lx: 0.38, bD: -0.3, bE: 0.3 }),
        P({ x: 0.2, Rx: 0.02, Lx: 0.38, bD: 0.3, bE: -0.3 }),
        P({ x: 0, Rx: -0.38, Lx: 0.38, bD: -0.3, bE: 0.3 }),
        P({ x: -0.2, Rx: -0.38, Lx: -0.02, bD: 0.3, bE: -0.3 })
      ]
    },
    funk1: { // 4 passos alternados (E,D,E,D) e 4 de volta (D,E,D,E), começando pelo pé esquerdo do robô: ciclo de 2 compassos
      lift: 0.14,
      poses: [
        P({ x: -0.52, Rx: -0.88, Lx: -0.16, bD: 0.3, bE: -0.3, inclina: -0.05 }),
        P({ x: -0.34, Rx: -0.52, Lx: -0.16, bD: -0.3, bE: 0.3, inclina: -0.05 }),
        P({ x: -0.16, Rx: -0.52, Lx: 0.18, bD: 0.3, bE: -0.3, inclina: -0.05 }),
        P({ x: 0.02, Rx: -0.16, Lx: 0.18, bD: -0.3, bE: 0.3, inclina: -0.05 }),
        P({ x: -0.175, Rx: -0.53, Lx: 0.18, bD: -0.3, bE: 0.3, inclina: 0.05 }),
        P({ x: -0.35, Rx: -0.53, Lx: -0.17, bD: 0.3, bE: -0.3, inclina: 0.05 }),
        P({ x: -0.525, Rx: -0.88, Lx: -0.17, bD: -0.3, bE: 0.3, inclina: 0.05 }),
        P({ x: -0.70, Rx: -0.88, Lx: -0.52, bD: 0.3, bE: -0.3, inclina: 0.05 })
      ]
    },
    funk2: { // pé esquerdo pisa na frente virando o corpo (tempo 1) e vai pra trás (tempo 3)
      lift: 0.04,
      poses: [
        P({ giro: -0.36, Lz: 0.45, bD: -0.35, bE: 0.35 }),
        P({ giro: -0.4, Lz: 0.45, bD: -0.4, bE: 0.4 }),
        P({ giro: 0.15, Lz: -0.4, bD: 0.25, bE: -0.35 }),
        P({ giro: 0.18, Lz: -0.4, bD: 0.3, bE: -0.4 })
      ]
    },
    funk3: { // ombros rolando, um de cada vez, de forma contínua (período de 4 tempos)
      lift: 0,
      poses: [P({}), P({}), P({}), P({})],
      extra: function (b, v) {
        var th = -0.5 * Math.cos(2 * Math.PI * b / 4);
        v.tronco = th; v.bD = -th * 0.9; v.bE = th * 0.9; v.inclina = th * 0.12; v.giro = -th * 0.12;
      }
    }
  };
  var CORPO = ['x', 'z', 'giro', 'tronco', 'inclina', 'bD', 'bE'];
  var PES = ['Rx', 'Rz', 'Lx', 'Lz'];

  function suave(t) { return t < 0 ? 0 : t > 1 ? 1 : t * t * (3 - 2 * t); }
  function lim01(t) { return t < 0 ? 0 : t > 1 ? 1 : t; }

  function chaveDanca(nome) {
    var n = String(nome || '').toLowerCase().replace(/\s+/g, '');
    if (n === 'funk1' || n === 'funk2' || n === 'funk3') return n;
    if (n === 'pausa') return 'parado';
    return 'padrao';
  }

  // estado da animação
  var est = { chave: 'parado', nome: null, n: 0, t: 0, beatMs: 600, alerta: 0, alertaAlvo: 0, tocando: false, mistura: null, ultimoV: null, inst: null, hitsD: [], hitsE: [] };

  function calcularV(d, b) {
    var np = d.poses.length;
    b = Math.max(0, b);
    var j = Math.floor(b) % np, n = (j + 1) % np, f = b - Math.floor(b);
    var A = d.poses[j], B = d.poses[n];
    var kc = suave(f), kp = lim01((f - 0.7) / 0.3), kf = suave(kp);
    var v = { f: f };
    CORPO.forEach(function (c) { v[c] = A[c] + (B[c] - A[c]) * kc; });
    PES.forEach(function (c) { v[c] = A[c] + (B[c] - A[c]) * kf; });
    var mexeD = Math.abs(B.Rx - A.Rx) + Math.abs(B.Rz - A.Rz) > 0.021;
    var mexeE = Math.abs(B.Lx - A.Lx) + Math.abs(B.Lz - A.Lz) > 0.021;
    v.subD = mexeD ? d.lift * Math.sin(Math.PI * kp) : 0;
    v.subE = mexeE ? d.lift * Math.sin(Math.PI * kp) : 0;
    if (d.extra) d.extra(b, v);
    return v;
  }

  function aplicar(b, agora) {
    var d = DANCAS[est.chave];
    var v = calcularV(d, b);
    // mistura rápida ao trocar de dança (evita "teletransporte" dos pés)
    if (est.mistura && est.deV) {
      var dur = Math.max(320, est.beatMs * 0.95);          // a transição dura quase um tempo inteiro
      var k = suave((agora - est.mistura) / dur);
      if (k >= 1) est.mistura = null;
      else {
        CORPO.concat(PES, ['subD', 'subE']).forEach(function (c) { v[c] = est.deV[c] + (v[c] - est.deV[c]) * k; });
        // os pés se arrastam entre as posições: levanta um pouco cada pé que muda de lugar para não deslizar pelo chão
        var lev = 0.07 * Math.sin(Math.PI * k);
        if (Math.abs(v.Rx - est.deV.Rx) + Math.abs(v.Rz - est.deV.Rz) > 0.03) v.subD = Math.max(v.subD, lev);
        if (Math.abs(v.Lx - est.deV.Lx) + Math.abs(v.Lz - est.deV.Lz) > 0.03) v.subE = Math.max(v.subE, lev);
      }
    }
    est.ultimoV = v;
    var balanco = Math.abs(Math.sin(Math.PI * v.f));

    raiz.position.set(v.x, 0, v.z);
    raiz.rotation.y = v.giro;
    quadril.position.y = 1.05 - 0.07 * balanco;
    var tocando = !!tipoInst(est.inst);
    tronco.rotation.y = v.tronco + (tocando ? GIRO_INST : 0);   // tocando, o tronco fica meio de lado para as baquetas aparecerem
    tronco.rotation.z = v.inclina;
    tronco.rotation.x = 0.06 * balanco;
    cabeca.rotation.y = -v.tronco * 0.4 - v.giro * 0.3 - (tocando ? GIRO_INST * 0.85 : 0);   // a cabeça continua olhando para a frente
    cabeca.rotation.x = -0.08 * balanco;

    var c = Math.cos(v.giro), sn = Math.sin(v.giro);
    function loc(fx, fz) { var wx = fx - v.x, wz = fz - v.z; return [wx * c - wz * sn, wx * sn + wz * c]; }
    var lD = loc(v.Rx, v.Rz), lE = loc(v.Lx, v.Lz);
    ik(pernaD, lD[0], ALT_TORN + v.subD, lD[1]);
    ik(pernaE, lE[0], ALT_TORN + v.subE, lE[1]);
    raiz.updateMatrixWorld(true);
    niveiaPe(pernaD, v.giro); niveiaPe(pernaE, v.giro);

    // braços (o alerta do último compasso agora só muda a cor dos olhos; os braços ficam livres para tocar)
    var dobraCot = -0.9 - 0.15 * balanco;
    bracoD.g.rotation.set(v.bD, 0, -0.18); bracoE.g.rotation.set(v.bE, 0, 0.18);
    bracoD.cot.rotation.set(dobraCot, 0, 0); bracoE.cot.rotation.set(dobraCot, 0, 0);
    tronco.updateMatrix();
    if (tipoInst(est.inst)) aplicaInstrumento(agora);
    matOlhos.color.setHex(est.alertaAlvo > 0.5 ? OLHO_ALERTA : OLHO);

    // câmera acompanha um pouco o deslocamento lateral
    camera.position.x = 0.6 + v.x * 0.5; camera.lookAt(v.x * 0.5, 1.3, 0);
    scene.userData.sombra.position.x = v.x;
  }

  // ---------- Laço de animação (só roda enquanto está tocando) ----------
  var rafId = 0;
  function beatAtual(agora) { return est.n + lim01((agora - est.t) / est.beatMs); }
  function quadro() {
    rafId = 0;
    if (!pronto) return;
    var agora = performance.now();
    try { aplicar(beatAtual(agora), agora); renderer.render(scene, camera); } catch (e) { /* nunca derruba o app */ }
    if (est.tocando || est.alerta > 0.01 || est.alertaAlvo > 0) rafId = requestAnimationFrame(quadro);
  }
  function acordar() { if (!rafId) rafId = requestAnimationFrame(quadro); }

  var API = {
    init: function (idDiv, larg, alt) {
      try {
        palco = document.getElementById(idDiv);
        if (!palco) return false;
        var test = document.createElement('canvas');
        if (!(test.getContext('webgl') || test.getContext('experimental-webgl'))) return false;
        larg = larg || 170; alt = alt || 210;
        renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
        renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
        renderer.setSize(larg, alt, false);
        renderer.domElement.style.width = larg + 'px'; renderer.domElement.style.height = alt + 'px';
        renderer.domElement.style.display = 'block';
        palco.appendChild(renderer.domElement);
        scene = new THREE.Scene();
        camera = new THREE.PerspectiveCamera(32, larg / alt, 0.1, 50);
        camera.position.set(0.6, 1.75, 7.4);
        scene.add(new THREE.HemisphereLight(0xffffff, 0x8a7090, 0.85));
        var sol = new THREE.DirectionalLight(0xffffff, 0.7); sol.position.set(3, 6, 5); scene.add(sol);
        construir();
        pronto = true; aplicaVisibilidade();
        est.chave = 'parado'; est.n = 0; est.t = performance.now();
        aplicar(0, est.t); renderer.render(scene, camera);
        return true;
      } catch (e) { pronto = false; return false; }
    },
    // Redimensiona o palco (ex.: troca de layout desktop/celular)
    resize: function (larg, alt, zoom) {
      if (!pronto || !larg || !alt) return;
      try {
        renderer.setSize(larg, alt, false);
        renderer.domElement.style.width = larg + 'px'; renderer.domElement.style.height = alt + 'px';
        camera.aspect = larg / alt; camera.position.z = 7.4 / (zoom || 1); camera.updateProjectionMatrix();
        renderer.render(scene, camera);
      } catch (e) {}
    },
    // Chamado em cada tempo tocado. nome = levada/convenção, i = 0..3, alerta = último compasso da levada
    beat: function (nome, i, beatMs, alerta, inst, tokens) {
      if (!pronto) return;
      var agora = performance.now();
      if (inst !== undefined && inst !== null && inst !== est.inst) { est.inst = inst; aplicaVisibilidade(); }
      var chave = (nome === '__contagem') ? 'padrao' : chaveDanca(nome);
      var convFunk = /^\s*conv(\.|enção|encao)?\s*funk/i.test(String(nome)) && /^funk[123]$/.test(est.chave);
      if (convFunk && nome !== est.nome) {   // convenção do funk logo depois de uma levada funk: segue com as pisadas da levada anterior
        est.nome = nome; est.n += 1;          // (a chave da dança e o ciclo continuam de onde estavam)
      } else if (nome !== est.nome) {         // levada/convenção nova: reinicia o ciclo da dança no tempo 1
        est.nome = nome; est.n = 0;
        if (chave !== est.chave) { est.mistura = agora; est.deV = est.ultimoV ? Object.assign({}, est.ultimoV) : null; }
        est.chave = chave;
      } else { est.n += 1; }
      est.t = agora; est.beatMs = beatMs > 50 ? beatMs : 600;
      est.alertaAlvo = alerta ? 1 : 0;
      est.tocando = true;
      // batidas deste tempo (e do próximo, para a mão já descer antes): [[sílaba, fração do tempo], ...]
      est.hitsD = est.hitsD.filter(function (h) { return h.t < agora - 5 && h.t > agora - 600; });
      est.hitsE = est.hitsE.filter(function (h) { return h.t < agora - 5 && h.t > agora - 600; });
      // mão de cada batida: regra do toque (pe/le/la = direita, te/ta/co = esquerda), mas nunca a mesma mão em batidas seguidas
      // (ex.: "ta.ta" vira esquerda-direita). Escolhe a combinação que menos foge da regra sem repetir a mão em notas próximas.
      var seq = [];
      (tokens || []).forEach(function (x) {
        var n = maoDe(x[0]); if (!n) return;
        var lim = String(x[0]).replace(/[*~()]/g, '');
        seq.push({ n: n, f: x[1], a: lim === lim.toUpperCase() && /[A-Z]/.test(lim) });
      });
      seq.sort(function (p, q) { return p.f - q.f; });
      if (seq.length) {
        var PERTO = 0.76, ult = est.ultMao;   // ult = última batida já feita {m, t}
        var N = seq.length, custo = [null], vem = [], i2;
        for (i2 = 0; i2 < N; i2++) {
          var cur = { D: 1e9, E: 1e9 }, de = {};
          ['D', 'E'].forEach(function (h) {
            var dev = (h === seq[i2].n ? 0 : 1 + 0.01 * (N - i2)), best = 1e9, bp = null;
            (i2 === 0 ? [ult ? ult.m : null] : ['D', 'E']).forEach(function (hp) {
              var gap = i2 === 0 ? (ult ? (agora + seq[0].f * est.beatMs - ult.t) / est.beatMs : 9) : seq[i2].f - seq[i2 - 1].f;
              var conf = (hp && hp === h && gap <= PERTO) ? 10 : 0;
              var base = i2 === 0 ? 0 : custo[i2][hp];
              if (base + conf < best) { best = base + conf; bp = hp; }
            });
            cur[h] = best + dev; de[h] = bp;
          });
          custo.push(cur); vem.push(de);
        }
        var hf = custo[N].D <= custo[N].E ? 'D' : 'E', esc = new Array(N);
        for (i2 = N - 1; i2 >= 0; i2--) { esc[i2] = hf; hf = vem[i2][hf]; }
        var passada = null;
        seq.forEach(function (q, k2) {
          (esc[k2] === 'D' ? est.hitsD : est.hitsE).push({ t: agora + q.f * est.beatMs, a: q.a });
          if (q.f < 1) passada = { m: esc[k2], t: agora + q.f * est.beatMs };   // última batida deste tempo = contexto do próximo
        });
        if (passada) est.ultMao = passada;
      }
      acordar();
    },
    setInst: function (nome) {
      est.inst = nome || null;
      if (!pronto) return;
      aplicaVisibilidade();
      if (!est.tocando) { try { aplicar(0, performance.now()); renderer.render(scene, camera); } catch (e) {} }
    },
    parar: function () {
      if (!pronto) return;
      est.tocando = false; est.alertaAlvo = 0; est.nome = null; est.chave = 'parado'; est.n = 0; est.t = performance.now(); est.mistura = null;
      est.alerta = 0; est.hitsD = []; est.hitsE = []; est.ultMao = null;
      var agora = performance.now();
      try { aplicar(0, agora); renderer.render(scene, camera); } catch (e) {}
    },
    // só para testes
    _torce: function (v) { TORCE = v; Robo3D.setInst('Dobra'); },
    _pes: function () { raiz.updateMatrixWorld(true); var f=function(q){var b=new THREE.Box3().setFromObject(q.pe),c=new THREE.Vector3();b.getCenter(c);return [c.x,b.min.y]}; return { D: f(pernaD), E: f(pernaE) }; },
    _maos: function () { var o = []; est.hitsD.forEach(function (h) { o.push([Math.round(h.t), 'D', h.a ? 1 : 0]); }); est.hitsE.forEach(function (h) { o.push([Math.round(h.t), 'E', h.a ? 1 : 0]); }); return o.sort(function (a, b) { return a[0] - b[0]; }); },
    _estado: function () { return { chave: est.chave, nome: est.nome, n: est.n }; },
    _teste: function (chave, b) { est.chave = chave; est.mistura = null; var t = performance.now(); aplicar(b, t); renderer.render(scene, camera); return { pesY: [pernaD, pernaE].map(function (p) { return new THREE.Box3().setFromObject(p.pe).min.y; }) }; }
  };
  window.Robo3D = API;
})();
