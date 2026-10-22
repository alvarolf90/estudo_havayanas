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
  var INSTR = { 'Dobra': true };
  var surdo, surdoCorpo, baquetaD, baquetaE, _pCouro = {};
  var L1 = 0.44, L2 = 0.40, BAQ = 0.5, LEVANTA = 1;   // LEVANTA = 1 → 'h' vai de 0 (batida) a 1 (mão no alto)
  // direção da baqueta (da mão até a ponta): para frente, um pouco para baixo e para dentro (as duas se encontram no couro)
  var GIRO_INST = 0.45, _vsL = {}, _vsN = {};
  [-1, 1].forEach(function (l) { _vsN[l] = new THREE.Vector3(-l * 0.15, -0.3, 0.9).normalize(); _vsL[l] = _vsN[l].clone().multiplyScalar(BAQ); });
  function cil24(r, h, c) { return new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 28), mat(c)); }
  function criarBaqueta() {
    var g = new THREE.Group();
    var haste = cil(0.02, 0.58, 0xE8C9A0); haste.position.y = -0.17; g.add(haste);   // sai um pouco por trás do punho
    var bola = esf(0.055, LARANJA); bola.position.y = -0.455; g.add(bola);
    g.visible = false; tronco.add(g); return g;
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
  }
  function aplicaVisibilidade() {
    var on = !!(est.inst && INSTR[est.inst]);
    surdo.visible = on; baquetaD.visible = on; baquetaE.visible = on;
  }
  function maoDe(tk) {
    tk = String(tk || '').toLowerCase().replace(/[^a-z]/g, '').slice(0, 2);
    if (tk === 'pe' || tk === 'le' || tk === 'la') return 'D';
    if (tk === 'te' || tk === 'ta' || tk === 'co') return 'E';
    return null;
  }
  // altura da baqueta (0 = no couro na batida, ~0.75 = descansada, 1 = pico do "preparo")
  // Antes de cada batida a mão dá uma pequena levantada (preparo) e só então desce.
  function descida(tau) {          // tau = tempo até a próxima batida (ms)
    if (tau >= 340) return 0.75;
    if (tau >= 120) return 0.75 + 0.25 * suave((340 - tau) / 220);   // sobe um pouquinho mais, começando um pouco antes
    return suave(tau / 120);                                          // e desce até o couro
  }
  function alturaMao(hits, t) {
    var tp = -1e9, tn = 1e9, k;
    for (k = 0; k < hits.length; k++) { if (hits[k] <= t) { if (hits[k] > tp) tp = hits[k]; } else if (hits[k] < tn) tn = hits[k]; }
    return Math.min(descida(tn - t), suave(lim01((t - tp) / 150)));
  }
  function pulso(hits, t) {
    var p = 0, k;
    for (k = 0; k < hits.length; k++) { var dt = t - hits[k]; if (dt >= 0 && dt < 120) p = Math.max(p, 1 - dt / 120); }
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
  function tocarMao(b, baq, lado, hits, agora) {
    var P = _pCouro[lado], k = alturaMao(hits, agora);   // k: 0 = baqueta no couro, 1 = no alto
    // posição da mão na batida (ponta no couro)
    _mao.copy(P).sub(_vsL[lado]);
    // ao levantar: a mão sobe um pouco e o punho vira a baqueta para cima
    _mao.y += 0.2 * k;
    _sn.copy(_vsN[lado]).applyAxisAngle(_ex1, -1.05 * k);
    ikBraco(b, _mao.x, _mao.y, _mao.z);
    baq.position.copy(_mao);
    baq.quaternion.setFromUnitVectors(_meno, _sn);
  }
  function aplicaInstrumento(agora) {
    tocarMao(bracoD, baquetaD, -1, est.hitsD, agora);
    tocarMao(bracoE, baquetaE, 1, est.hitsE, agora);
    var p = Math.max(pulso(est.hitsD, agora), pulso(est.hitsE, agora));
    surdoCorpo.scale.set(1 + 0.035 * p, 1 - 0.02 * p, 1 + 0.035 * p);
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
      poses: [
        P({ x: 0, Rx: -0.38, Lx: 0.38, bD: -0.3, bE: 0.3 }),
        P({ x: -0.2, Rx: -0.38, Lx: -0.02, bD: 0.3, bE: -0.3 }),
        P({ x: 0, Rx: -0.38, Lx: 0.38, bD: -0.3, bE: 0.3 }),
        P({ x: 0.2, Rx: 0.02, Lx: 0.38, bD: 0.3, bE: -0.3 })
      ]
    },
    funk1: { // 4 passos alternados pra direita (D,E,D,E) e 4 pra esquerda (E,D,E,D): ciclo de 2 compassos
      lift: 0.14,
      poses: [
        P({ x: -0.175, Rx: -0.53, Lx: 0.18, bD: -0.3, bE: 0.3, inclina: 0.05 }),
        P({ x: -0.35, Rx: -0.53, Lx: -0.17, bD: 0.3, bE: -0.3, inclina: 0.05 }),
        P({ x: -0.525, Rx: -0.88, Lx: -0.17, bD: -0.3, bE: 0.3, inclina: 0.05 }),
        P({ x: -0.70, Rx: -0.88, Lx: -0.52, bD: 0.3, bE: -0.3, inclina: 0.05 }),
        P({ x: -0.52, Rx: -0.88, Lx: -0.16, bD: 0.3, bE: -0.3, inclina: -0.05 }),
        P({ x: -0.34, Rx: -0.52, Lx: -0.16, bD: -0.3, bE: 0.3, inclina: -0.05 }),
        P({ x: -0.16, Rx: -0.52, Lx: 0.18, bD: 0.3, bE: -0.3, inclina: -0.05 }),
        P({ x: 0.02, Rx: -0.16, Lx: 0.18, bD: -0.3, bE: 0.3, inclina: -0.05 })
      ]
    },
    funk2: { // pé direito pisa na frente virando o corpo (tempo 1) e vai pra trás (tempo 3)
      lift: 0.04,
      poses: [
        P({ giro: 0.36, Rz: 0.45, bD: 0.35, bE: -0.35 }),
        P({ giro: 0.4, Rz: 0.45, bD: 0.4, bE: -0.4 }),
        P({ giro: -0.15, Rz: -0.4, bD: -0.35, bE: 0.25 }),
        P({ giro: -0.18, Rz: -0.4, bD: -0.4, bE: 0.3 })
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
    if (est.mistura && est.ultimoV) {
      var k = suave((agora - est.mistura) / 160);
      if (k >= 1) est.mistura = null;
      else { CORPO.concat(PES, ['subD', 'subE']).forEach(function (c) { v[c] = est.ultimoV[c] + (v[c] - est.ultimoV[c]) * k; }); }
    }
    est.ultimoV = v;
    var balanco = Math.abs(Math.sin(Math.PI * v.f));

    raiz.position.set(v.x, 0, v.z);
    raiz.rotation.y = v.giro;
    quadril.position.y = 1.05 - 0.07 * balanco;
    var tocando = !!(est.inst && INSTR[est.inst]);
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
    if (est.inst && INSTR[est.inst]) aplicaInstrumento(agora);
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
        if (chave !== est.chave) { est.mistura = agora; }
        est.chave = chave;
      } else { est.n += 1; }
      est.t = agora; est.beatMs = beatMs > 50 ? beatMs : 600;
      est.alertaAlvo = alerta ? 1 : 0;
      est.tocando = true;
      // batidas deste tempo (e do próximo, para a mão já descer antes): [[sílaba, fração do tempo], ...]
      est.hitsD = est.hitsD.filter(function (t) { return t < agora - 5 && t > agora - 600; });
      est.hitsE = est.hitsE.filter(function (t) { return t < agora - 5 && t > agora - 600; });
      (tokens || []).forEach(function (x) {
        var m = maoDe(x[0]); if (!m) return;
        (m === 'D' ? est.hitsD : est.hitsE).push(agora + x[1] * est.beatMs);
      });
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
      est.alerta = 0; est.hitsD = []; est.hitsE = [];
      var agora = performance.now();
      try { aplicar(0, agora); renderer.render(scene, camera); } catch (e) {}
    },
    // só para testes
    _torce: function (v) { TORCE = v; Robo3D.setInst('Dobra'); },
    _estado: function () { return { chave: est.chave, nome: est.nome, n: est.n }; },
    _teste: function (chave, b) { est.chave = chave; est.mistura = null; var t = performance.now(); aplicar(b, t); renderer.render(scene, camera); return { pesY: [pernaD, pernaE].map(function (p) { return new THREE.Box3().setFromObject(p.pe).min.y; }) }; }
  };
  window.Robo3D = API;
})();
