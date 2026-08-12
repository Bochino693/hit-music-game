/*
  ============================================================
  HIT MUSIC CLEAN R25.1 - FIRMWARE UNICO
  ============================================================

  Novidade do R25 (unica mudanca em relacao ao R24):

  0) MENU COM TERCEIRA LANE OPCIONAL
     A tela de selecao de musica usa tres botoes fisicos
     (A sobe, D desce, B seleciona), mas o MENU do R24 so
     acendia dois. Mandar "LED <idx>" por cima do MENU NAO
     resolve: o handler de LED zera efeito_global e apaga
     justamente os LEDs de A e B. Agora o terceiro indice
     entra no proprio comando MENU, de forma retrocompativel
     (um MENU de 8 tokens funciona igual ao R24).

  ------------------------------------------------------------
  Correcoes que ja vinham do R24 em relacao ao R11:

  1) REFRESH PERIODICO (corrige LEDs do menu apagando sozinhos)
     No R11, MENU e LED estatico eram desenhados UMA unica vez e
     show() nunca mais era chamado. Qualquer glitch na linha de
     dados apagava o pixel para sempre. Agora existe um heartbeat
     que reenvia o quadro a cada INTERVALO_REFRESH_MS.

  2) BAUD MANTIDO EM 9600 - NAO AUMENTE
     A Adafruit_NeoPixel desliga as interrupcoes durante show()
     por ~240 us em cada fita. A UART do AVR so segura 2 bytes em
     hardware. A 9600 esses 2 bytes duram 2,08 ms (folga enorme).
     A 115200 duram 174 us e voce PERDE bytes a cada show().
     Teto seguro nessa montagem: 38400. Acima disso corrompe.

     O gargalo se resolve mandando MENOS BYTES, nao mais rapido.
     Ver item 3.

  3) COMANDO MULTI (atualiza as 8 lanes em UMA linha)
     MULTI RRGGBBRRGGBB... -> 54 bytes contra ~145 bytes do
     equivalente em 8 comandos LED separados.

  4) PARSER BLINDADO
     Linha maior que o buffer agora e descartada ate o proximo
     \n. No R11 o resto da linha virava um comando falso.

  5) MENU COM INDICES CONFIGURAVEIS
     No R11 os dois LEDs do menu eram fixos nos tazos 0 e 1.

  6) DIAGNOSTICO
     DEBUG 1 faz o Arduino responder ERR_CMD <cmd> para todo
     comando que ele nao reconhece. Use isso para confirmar se o
     jogo esta mandando algo fora do protocolo.

  ============================================================
  PROTOCOLO COMPLETO (uma linha por comando, terminada em \n)
  ============================================================

  HELLO                          -> responde HITMUSIC_OK
  PING                           -> responde PONG
  VERSION                        -> responde HITMUSIC_R12

  LED  <idx> <r> <g> <b>         guia fixa na lane (0 0 0 apaga)
  MULTI <hex>                    guia das 8 lanes de uma vez
                                 hex = RRGGBB por lane, sem espaco
                                 ex: MULTI 1E64FF00B8FF000000...
                                 quadro completo das 8 lanes

  PULSE <idx>                    flash branco 125 ms
  HIT   <idx> <r> <g> <b> <ms>   flash colorido (90..1200 ms)
  OK    <idx>                    flash verde 330 ms
  ERR   <idx>                    flash vermelho 330 ms

  SCENE  <r> <g> <b>             fundo tematico (cor unica)
  SCENE2 <r1> <g1> <b1> <r2> <g2> <b2>   fundo com duas cores
  ALL    <r> <g> <b>             alias de SCENE

  MENU <rA> <gA> <bA> <rB> <gB> <bB> [idxA] [idxB]
                                 dois LEDs de navegacao acesos
                                 idxA/idxB opcionais (padrao 0 e 1)

  MENU <rA> <gA> <bA> <rB> <gB> <bB> <idxA> <idxB> <idxC> <rC> <gC> <bC>
                                 TRES LEDs de navegacao acesos (R25)
                                 usado na tela de selecao de musica:
                                 A sobe, D desce, B seleciona.
                                 Nao use "LED <idx>" para isso: o
                                 handler de LED zera efeito_global e
                                 apagaria os LEDs de A e B.

  ATTRACT                        modo atracao
  BLINKALL                       inicia contagem em 5
  COUNT <n>                      define o numero da contagem (0..9)
  READY                          flash de largada, volta ao estado
  CLEAR                          apaga tudo

  BRIGHT <0..255>                brilho global
  DEBUG  <0|1>                   liga/desliga resposta ERR_CMD

  ============================================================
*/

#include <Adafruit_NeoPixel.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#define NUM_TAZOS 8
#define LEDS_POR_TAZO 8
#define BRILHO_MAX 170

/*
  NAO AUMENTE ESTE VALOR SEM LER O ITEM 2 DO CABECALHO.
  A 115200 o show() das fitas faz a UART perder bytes.
  Se um dia precisar de mais banda, 38400 e o teto seguro,
  e tem que ser trocado no bridge do PC junto.
*/
#define BAUD_RATE 9600

#define LINHA_MAX_CHARS 120

/*
  ATENCAO (bug corrigido no R25.1):
  O MENU de tres lanes ocupa 13 tokens ("MENU" + 12 argumentos).
  Com MAX_TOKENS em 12 o tokenizador parava no 12o token, "qtd"
  nunca chegava a 13 e a terceira lane JAMAIS acendia — era esse
  o motivo do LED de descer ficar apagado na tela de cenarios.
  Mantenha folga aqui ao criar comandos novos.
*/
#define MAX_TOKENS 16

/* Teto de quadros durante animacao (~62 fps). */
#define INTERVALO_FRAME_LED_MS 16

/*
  Heartbeat: mesmo parado, o quadro e reenviado nesse intervalo.
  E isto que impede os LEDs do menu de "sumirem" sozinhos.
*/
#define INTERVALO_REFRESH_MS 120

Adafruit_NeoPixel fitaA(LEDS_POR_TAZO, 2, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaB(LEDS_POR_TAZO, 3, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaC(LEDS_POR_TAZO, 4, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaD(LEDS_POR_TAZO, 5, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaE(LEDS_POR_TAZO, 6, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaF(LEDS_POR_TAZO, 7, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaG(LEDS_POR_TAZO, 8, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaH(LEDS_POR_TAZO, 9, NEO_GRB + NEO_KHZ800);

Adafruit_NeoPixel *fitas[NUM_TAZOS] = {
  &fitaA, &fitaB, &fitaC, &fitaD,
  &fitaE, &fitaF, &fitaG, &fitaH
};

struct FlashTazo {
  bool ativo;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  unsigned long inicio_ms;
  unsigned long fim_ms;
};

enum EfeitoGlobal : uint8_t {
  EFEITO_NENHUM,
  EFEITO_ATRACAO,
  EFEITO_SCENE,
  EFEITO_MENU,
  EFEITO_CONTAGEM,
  EFEITO_READY
};

bool guia_ativo[NUM_TAZOS];
uint8_t guia_r[NUM_TAZOS];
uint8_t guia_g[NUM_TAZOS];
uint8_t guia_b[NUM_TAZOS];

uint8_t scene_r = 30;
uint8_t scene_g = 255;
uint8_t scene_b = 100;
uint8_t scene2_r = 25;
uint8_t scene2_g = 150;
uint8_t scene2_b = 255;

uint8_t menu_a_r = 0;
uint8_t menu_a_g = 184;
uint8_t menu_a_b = 255;
uint8_t menu_b_r = 255;
uint8_t menu_b_g = 209;
uint8_t menu_b_b = 20;
uint8_t menu_idx_a = 0;
uint8_t menu_idx_b = 1;

/*
  Terceira lane opcional do MENU (R25).

  Motivo: a tela de selecao de musica usa TRES botoes fisicos
  (A sobe, D desce, B seleciona), mas o MENU do R24 so acendia dois.
  Mandar "LED <idx>" por cima do MENU NAO funciona: o handler de LED
  zera efeito_global, o que apagava justamente os LEDs de A e B.
  Por isso o terceiro indice entra no proprio comando MENU, mantendo
  o estado do menu atomico em uma unica linha (menos bytes na UART,
  como manda o item 3 do cabecalho).
*/
bool menu_c_ativo = false;
uint8_t menu_c_r = 0;
uint8_t menu_c_g = 184;
uint8_t menu_c_b = 255;
uint8_t menu_idx_c = 3;

FlashTazo flashes[NUM_TAZOS];
EfeitoGlobal efeito_global = EFEITO_NENHUM;
EfeitoGlobal efeito_apos_ready = EFEITO_NENHUM;

int8_t numero_contagem = 5;
unsigned long efeito_inicio_ms = 0;
unsigned long passo_contagem_inicio_ms = 0;
unsigned long ultimo_frame_led_ms = 0;

char linha_serial[LINHA_MAX_CHARS + 1];
uint8_t linha_tamanho = 0;
bool descartando_linha = false;
bool desenho_sujo = true;
bool debug_ativo = false;

/* ---------------- utilitarios ---------------- */

bool tempo_passou(unsigned long agora, unsigned long alvo) {
  return (long)(agora - alvo) >= 0;
}

bool indice_valido(int idx) {
  return idx >= 0 && idx < NUM_TAZOS;
}

uint8_t limitar_byte(int valor) {
  if (valor < 0) return 0;
  if (valor > 255) return 255;
  return (uint8_t)valor;
}

uint8_t escalar_byte(uint8_t valor, uint8_t escala) {
  return (uint8_t)(((uint16_t)valor * (uint16_t)escala) / 255U);
}

uint8_t onda_triangular(unsigned long fase) {
  uint16_t p = (uint16_t)(fase & 511UL);
  if (p > 255U) p = 511U - p;
  return (uint8_t)p;
}

void deixar_maiusculo(char *texto) {
  while (*texto) {
    *texto = (char)toupper((unsigned char)*texto);
    texto++;
  }
}

int8_t hex_valor(char c) {
  if (c >= '0' && c <= '9') return (int8_t)(c - '0');
  if (c >= 'A' && c <= 'F') return (int8_t)(c - 'A' + 10);
  if (c >= 'a' && c <= 'f') return (int8_t)(c - 'a' + 10);
  return -1;
}

bool ler_hex_byte(const char *s, uint8_t &saida) {
  int8_t alto = hex_valor(s[0]);
  int8_t baixo = hex_valor(s[1]);
  if (alto < 0 || baixo < 0) return false;
  saida = (uint8_t)(((uint8_t)alto << 4) | (uint8_t)baixo);
  return true;
}

void marcar_sujo() {
  desenho_sujo = true;
}

void limpar_guias() {
  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    guia_ativo[i] = false;
    guia_r[i] = 0;
    guia_g[i] = 0;
    guia_b[i] = 0;
  }
  marcar_sujo();
}

void limpar_flashes() {
  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    flashes[i].ativo = false;
  }
  marcar_sujo();
}

void disparar_flash(
  int idx,
  uint8_t r,
  uint8_t g,
  uint8_t b,
  unsigned long duracao_ms
) {
  if (!indice_valido(idx)) return;

  unsigned long agora = millis();
  flashes[idx].ativo = true;
  flashes[idx].r = r;
  flashes[idx].g = g;
  flashes[idx].b = b;
  flashes[idx].inicio_ms = agora;
  flashes[idx].fim_ms = agora + duracao_ms;
  marcar_sujo();
}

void aplicar_multi(const char *hex) {
  /*
    MULTI = quadro completo da PARTIDA.

    Ao receber MULTI, nenhum efeito global pode continuar "por baixo".
    Isso garante:
      - lane escolhida -> acende;
      - lane 000000    -> apaga de verdade;
      - SCENE/MENU/READY anteriores não vazam para a partida.
  */
  efeito_global = EFEITO_NENHUM;
  efeito_apos_ready = EFEITO_NENHUM;

  /* Estado de partida e soberano: nenhum flash antigo pode ficar por cima. */
  limpar_flashes();

  uint8_t comprimento = (uint8_t)strlen(hex);
  uint8_t lanes = comprimento / 6U;
  if (lanes > NUM_TAZOS) lanes = NUM_TAZOS;

  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;

    if (i < lanes) {
      const char *p = hex + ((uint16_t)i * 6U);

      bool valido =
        ler_hex_byte(p, r) &&
        ler_hex_byte(p + 2, g) &&
        ler_hex_byte(p + 4, b);

      if (!valido) {
        r = 0;
        g = 0;
        b = 0;
      }
    }

    guia_r[i] = r;
    guia_g[i] = g;
    guia_b[i] = b;
    guia_ativo[i] = (r != 0 || g != 0 || b != 0);
  }

  marcar_sujo();
}

/* ---------------- setup / loop ---------------- */

void setup() {
  Serial.begin(BAUD_RATE);

  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    fitas[i]->begin();
    fitas[i]->setBrightness(BRILHO_MAX);
    fitas[i]->clear();
    fitas[i]->show();

    flashes[i].ativo = false;
    guia_ativo[i] = false;
    guia_r[i] = 0;
    guia_g[i] = 0;
    guia_b[i] = 0;
  }

  efeito_global = EFEITO_NENHUM;
  efeito_apos_ready = EFEITO_NENHUM;
  ultimo_frame_led_ms = millis();
  desenho_sujo = true;
}

void loop() {
  ler_serial();
  atualizar_estados();
  desenhar_leds();
}

/* ---------------- serial ---------------- */

void ler_serial() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();

    if (c == '\n' || c == '\r') {
      if (descartando_linha) {
        descartando_linha = false;
        linha_tamanho = 0;
        continue;
      }

      if (linha_tamanho > 0) {
        linha_serial[linha_tamanho] = '\0';
        processar_comando(linha_serial);
        linha_tamanho = 0;
      }
      continue;
    }

    if (descartando_linha) {
      continue;
    }

    if (linha_tamanho < LINHA_MAX_CHARS) {
      linha_serial[linha_tamanho++] = c;
    } else {
      /*
        Linha maior que o buffer: descarta ate o proximo \n.
        No R11 o resto virava um comando falso.
      */
      descartando_linha = true;
      linha_tamanho = 0;
    }
  }
}

uint8_t tokenizar(char *linha, char *tokens[], uint8_t max_tokens) {
  uint8_t quantidade = 0;
  char *contexto = NULL;
  char *token = strtok_r(linha, " \t", &contexto);

  while (token != NULL && quantidade < max_tokens) {
    tokens[quantidade++] = token;
    token = strtok_r(NULL, " \t", &contexto);
  }

  return quantidade;
}

void processar_comando(char *linha) {
  char *tokens[MAX_TOKENS];
  uint8_t qtd = tokenizar(linha, tokens, MAX_TOKENS);
  if (qtd == 0) return;

  deixar_maiusculo(tokens[0]);
  const char *cmd = tokens[0];

  if (strcmp(cmd, "HELLO") == 0) {
    Serial.println(F("HITMUSIC_OK"));
  }
  else if (strcmp(cmd, "PING") == 0) {
    Serial.println(F("PONG"));
  }
  else if (strcmp(cmd, "VERSION") == 0) {
    Serial.println(F("HITMUSIC_CLEAN_R25_1"));
  }
  else if (strcmp(cmd, "LED") == 0 && qtd >= 5) {
    #if 1
    // LED individual também pertence ao estado físico de partida.
    efeito_global = EFEITO_NENHUM;
    efeito_apos_ready = EFEITO_NENHUM;
    #endif

    int idx = atoi(tokens[1]);
    if (indice_valido(idx)) {
      guia_r[idx] = limitar_byte(atoi(tokens[2]));
      guia_g[idx] = limitar_byte(atoi(tokens[3]));
      guia_b[idx] = limitar_byte(atoi(tokens[4]));
      guia_ativo[idx] = (
        guia_r[idx] != 0 ||
        guia_g[idx] != 0 ||
        guia_b[idx] != 0
      );
      marcar_sujo();
    }
  }
  else if (strcmp(cmd, "MULTI") == 0 && qtd >= 2) {
    aplicar_multi(tokens[1]);
  }
  else if (strcmp(cmd, "PULSE") == 0 && qtd >= 2) {
    disparar_flash(atoi(tokens[1]), 255, 255, 255, 125);
  }
  else if (strcmp(cmd, "HIT") == 0 && qtd >= 6) {
    int idx = atoi(tokens[1]);
    uint8_t r = limitar_byte(atoi(tokens[2]));
    uint8_t g = limitar_byte(atoi(tokens[3]));
    uint8_t b = limitar_byte(atoi(tokens[4]));
    unsigned long duracao = (unsigned long)atoi(tokens[5]);
    if (duracao < 90UL) duracao = 90UL;
    if (duracao > 1200UL) duracao = 1200UL;
    disparar_flash(idx, r, g, b, duracao);
  }
  else if (strcmp(cmd, "OK") == 0 && qtd >= 2) {
    disparar_flash(atoi(tokens[1]), 20, 255, 80, 330);
  }
  else if (strcmp(cmd, "ERR") == 0 && qtd >= 2) {
    disparar_flash(atoi(tokens[1]), 255, 20, 30, 330);
  }
  else if (strcmp(cmd, "CLEAR") == 0) {
    limpar_guias();
    limpar_flashes();
    efeito_global = EFEITO_NENHUM;
    efeito_apos_ready = EFEITO_NENHUM;
    marcar_sujo();
  }
  else if (strcmp(cmd, "ATTRACT") == 0) {
    limpar_guias();
    limpar_flashes();
    efeito_global = EFEITO_ATRACAO;
    efeito_apos_ready = EFEITO_NENHUM;
    efeito_inicio_ms = millis();
    marcar_sujo();
  }
  else if (strcmp(cmd, "MENU") == 0 && qtd >= 7) {
    /* MENU e um estado completo: remove qualquer guia/flash anterior. */
    limpar_guias();
    limpar_flashes();

    menu_a_r = limitar_byte(atoi(tokens[1]));
    menu_a_g = limitar_byte(atoi(tokens[2]));
    menu_a_b = limitar_byte(atoi(tokens[3]));
    menu_b_r = limitar_byte(atoi(tokens[4]));
    menu_b_g = limitar_byte(atoi(tokens[5]));
    menu_b_b = limitar_byte(atoi(tokens[6]));

    if (qtd >= 9) {
      int ia = atoi(tokens[7]);
      int ib = atoi(tokens[8]);
      if (indice_valido(ia)) menu_idx_a = (uint8_t)ia;
      if (indice_valido(ib)) menu_idx_b = (uint8_t)ib;
    }

    /*
      Terceira lane (R25) e opcional e retrocompativel: um MENU com
      8 tokens continua se comportando exatamente como no R24.
      Com 12 tokens acende tambem idxC na cor informada.
    */
    menu_c_ativo = false;
    if (qtd >= 13) {
      int ic = atoi(tokens[9]);
      if (indice_valido(ic)) {
        menu_idx_c = (uint8_t)ic;
        menu_c_r = limitar_byte(atoi(tokens[10]));
        menu_c_g = limitar_byte(atoi(tokens[11]));
        menu_c_b = limitar_byte(atoi(tokens[12]));
        menu_c_ativo = true;
      }
    }

    /*
      Sem limpar guias aqui: no R11 MENU nao mexia nas guias,
      e mudar isso quebraria telas que mandam LED antes de MENU.
    */
    efeito_global = EFEITO_MENU;
    efeito_apos_ready = EFEITO_MENU;
    marcar_sujo();
  }
  else if (strcmp(cmd, "SCENE2") == 0 && qtd >= 7) {
    limpar_guias();
    limpar_flashes();

    scene_r = limitar_byte(atoi(tokens[1]));
    scene_g = limitar_byte(atoi(tokens[2]));
    scene_b = limitar_byte(atoi(tokens[3]));
    scene2_r = limitar_byte(atoi(tokens[4]));
    scene2_g = limitar_byte(atoi(tokens[5]));
    scene2_b = limitar_byte(atoi(tokens[6]));
    efeito_global = EFEITO_SCENE;
    efeito_apos_ready = EFEITO_SCENE;
    marcar_sujo();
  }
  else if ((strcmp(cmd, "SCENE") == 0 || strcmp(cmd, "ALL") == 0) && qtd >= 4) {
    limpar_guias();
    limpar_flashes();

    scene_r = limitar_byte(atoi(tokens[1]));
    scene_g = limitar_byte(atoi(tokens[2]));
    scene_b = limitar_byte(atoi(tokens[3]));
    scene2_r = scene_r;
    scene2_g = scene_g;
    scene2_b = scene_b;
    efeito_global = EFEITO_SCENE;
    efeito_apos_ready = EFEITO_SCENE;
    marcar_sujo();
  }
  else if (strcmp(cmd, "BLINKALL") == 0) {
    limpar_guias();
    limpar_flashes();
    efeito_global = EFEITO_CONTAGEM;
    numero_contagem = 5;
    efeito_inicio_ms = millis();
    passo_contagem_inicio_ms = efeito_inicio_ms;
    marcar_sujo();
  }
  else if (strcmp(cmd, "COUNT") == 0 && qtd >= 2) {
    numero_contagem = (int8_t)atoi(tokens[1]);
    if (numero_contagem < 0) numero_contagem = 0;
    if (numero_contagem > 9) numero_contagem = 9;
    efeito_global = EFEITO_CONTAGEM;
    passo_contagem_inicio_ms = millis();
    marcar_sujo();
  }
  else if (strcmp(cmd, "READY") == 0) {
    limpar_flashes();
    efeito_global = EFEITO_READY;
    efeito_inicio_ms = millis();
    marcar_sujo();
  }
  else if (strcmp(cmd, "BRIGHT") == 0 && qtd >= 2) {
    uint8_t nivel = limitar_byte(atoi(tokens[1]));
    for (uint8_t i = 0; i < NUM_TAZOS; i++) {
      fitas[i]->setBrightness(nivel);
    }
    marcar_sujo();
  }
  else if (strcmp(cmd, "DEBUG") == 0 && qtd >= 2) {
    debug_ativo = (atoi(tokens[1]) != 0);
    Serial.println(debug_ativo ? F("DEBUG_ON") : F("DEBUG_OFF"));
  }
  else {
    /*
      Comando desconhecido ou com argumentos de menos.
      No R11 isso era descartado em silencio, o que escondia
      erros de protocolo do lado do jogo.
    */
    if (debug_ativo) {
      Serial.print(F("ERR_CMD "));
      Serial.println(cmd);
    }
  }
}

/* ---------------- estados ---------------- */

void atualizar_estados() {
  unsigned long agora = millis();

  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    if (flashes[i].ativo && tempo_passou(agora, flashes[i].fim_ms)) {
      flashes[i].ativo = false;
      marcar_sujo();
    }
  }

  if (efeito_global == EFEITO_READY && agora - efeito_inicio_ms >= 620UL) {
    efeito_global = efeito_apos_ready;
    marcar_sujo();
  }
}

/* ---------------- cores ---------------- */

void cor_menu(uint8_t idx, uint8_t &r, uint8_t &g, uint8_t &b) {
  if (idx == menu_idx_a) {
    r = menu_a_r; g = menu_a_g; b = menu_a_b;
  }
  else if (idx == menu_idx_b) {
    r = menu_b_r; g = menu_b_g; b = menu_b_b;
  }
  else if (menu_c_ativo && idx == menu_idx_c) {
    r = menu_c_r; g = menu_c_g; b = menu_c_b;
  }
  else {
    r = 0; g = 0; b = 0;
  }
}

void cor_guia(uint8_t idx, uint8_t &r, uint8_t &g, uint8_t &b) {
  r = guia_r[idx];
  g = guia_g[idx];
  b = guia_b[idx];
}

void cor_flash(
  uint8_t idx,
  uint8_t pixel,
  unsigned long agora,
  uint8_t &r,
  uint8_t &g,
  uint8_t &b
) {
  FlashTazo &flash = flashes[idx];
  unsigned long duracao = flash.fim_ms - flash.inicio_ms;
  unsigned long restante = tempo_passou(agora, flash.fim_ms)
    ? 0UL : flash.fim_ms - agora;
  uint8_t fade = duracao == 0UL
    ? 0 : (uint8_t)min(255UL, (restante * 255UL) / duracao);
  unsigned long idade = agora - flash.inicio_ms;

  uint8_t onda = onda_triangular(idade * 3UL + (unsigned long)pixel * 46UL);
  uint8_t cabeca = (uint8_t)((idade / 42UL) % LEDS_POR_TAZO);
  uint8_t distancia = (uint8_t)((pixel + LEDS_POR_TAZO - cabeca) % LEDS_POR_TAZO);
  uint8_t destaque = distancia == 0U ? 92U : (distancia == 1U ? 38U : 0U);
  uint8_t nivel = (uint8_t)min(255, (int)fade + ((int)onda * 34) / 255);

  r = escalar_byte(flash.r, nivel);
  g = escalar_byte(flash.g, nivel);
  b = escalar_byte(flash.b, nivel);

  r = (uint8_t)min(255, (int)r + ((int)destaque * fade) / 255);
  g = (uint8_t)min(255, (int)g + ((int)destaque * fade) / 255);
  b = (uint8_t)min(255, (int)b + ((int)destaque * fade) / 255);
}

void cor_atracao(
  uint8_t idx,
  uint8_t pixel,
  unsigned long agora,
  uint8_t &r,
  uint8_t &g,
  uint8_t &b
) {
  uint8_t cabeca = (uint8_t)((agora / 105UL) % NUM_TAZOS);
  uint8_t distancia = (uint8_t)((idx + NUM_TAZOS - cabeca) % NUM_TAZOS);
  uint8_t nivel = 8;
  if (distancia == 0U) nivel = 255;
  else if (distancia == 1U) nivel = 105;
  else if (distancia == 2U) nivel = 32;

  uint8_t onda = onda_triangular(
    agora / 4UL + (unsigned long)pixel * 42UL + (unsigned long)idx * 21UL
  );
  nivel = (uint8_t)min(255, (int)nivel + ((int)onda * 38) / 255);
  r = escalar_byte(25, nivel);
  g = escalar_byte(255, nivel);
  b = escalar_byte(110, nivel);
}

void cor_scene(
  uint8_t idx,
  uint8_t pixel,
  unsigned long agora,
  uint8_t &r,
  uint8_t &g,
  uint8_t &b
) {
  uint8_t onda = onda_triangular(
    agora / 5UL + (unsigned long)idx * 43UL + (unsigned long)pixel * 31UL
  );
  bool segunda = ((idx + pixel / 2U + (uint8_t)(agora / 1300UL)) & 1U);
  uint8_t base_r = segunda ? scene2_r : scene_r;
  uint8_t base_g = segunda ? scene2_g : scene_g;
  uint8_t base_b = segunda ? scene2_b : scene_b;
  uint8_t nivel = (uint8_t)(148U + ((uint16_t)onda * 94U) / 255U);
  r = escalar_byte(base_r, nivel);
  g = escalar_byte(base_g, nivel);
  b = escalar_byte(base_b, nivel);
}

void cor_contagem(
  uint8_t idx,
  uint8_t pixel,
  unsigned long agora,
  uint8_t &r,
  uint8_t &g,
  uint8_t &b
) {
  unsigned long decorrido = agora - passo_contagem_inicio_ms;
  uint8_t cabeca = (uint8_t)((decorrido / 72UL) % NUM_TAZOS);

  /*
    Um segundo para cada cor da mesa: 3 = AZUL, 2 = VERMELHO,
    1 = AMARELO. Sao os mesmos tres tons dos tazos, entao a contagem
    ja apresenta a paleta do jogo antes da primeira nota.

    O ramo padrao (numero_contagem 4..9) continua ciano e vale como
    aquecimento: e o que aparece entre o BLINKALL e o primeiro COUNT.
  */
  uint8_t base_r = 0;
  uint8_t base_g = 219;
  uint8_t base_b = 255;

  switch (numero_contagem) {
    case 3: base_r = 0;   base_g = 219; base_b = 255; break;  /* azul     */
    case 2: base_r = 255; base_g = 6;   base_b = 14;  break;  /* vermelho */
    case 1: base_r = 255; base_g = 184; base_b = 0;   break;  /* amarelo  */
    case 0: base_r = 40;  base_g = 255; base_b = 90;  break;  /* vai!     */
    default: break;
  }

  uint8_t nivel = idx == cabeca ? 255 : 12;
  uint8_t onda = onda_triangular(agora / 5UL + (unsigned long)pixel * 34UL);
  nivel = (uint8_t)min(255, (int)nivel + ((int)onda * 24) / 255);

  r = escalar_byte(base_r, nivel);
  g = escalar_byte(base_g, nivel);
  b = escalar_byte(base_b, nivel);
}

void cor_ready(
  uint8_t idx,
  uint8_t pixel,
  unsigned long agora,
  uint8_t &r,
  uint8_t &g,
  uint8_t &b
) {
  unsigned long idade = agora - efeito_inicio_ms;
  uint8_t onda = onda_triangular(
    idade * 3UL + (unsigned long)idx * 58UL + (unsigned long)pixel * 24UL
  );

  if (idade < 180UL) {
    r = 255; g = 255; b = 255;
    return;
  }

  unsigned long fade = idade >= 620UL ? 0UL : 620UL - idade;
  uint8_t nivel = (uint8_t)min(255UL, (fade * 255UL) / 440UL);
  uint8_t brilho = (uint8_t)min(255, (int)nivel + ((int)onda * 40) / 255);

  r = escalar_byte(35, brilho);
  g = escalar_byte(255, brilho);
  b = escalar_byte(90, brilho);
}

/* ---------------- desenho ---------------- */

bool existe_animacao_ativa() {
  if (
    efeito_global == EFEITO_ATRACAO ||
    efeito_global == EFEITO_SCENE ||
    efeito_global == EFEITO_CONTAGEM ||
    efeito_global == EFEITO_READY
  ) {
    return true;
  }

  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    if (flashes[i].ativo) return true;
  }

  return false;
}

void desenhar_leds() {
  unsigned long agora = millis();
  bool animando = existe_animacao_ativa();

  /*
    CORRECAO CENTRAL DO R12.
    Mesmo sem animacao e sem comando novo, o quadro e reenviado
    a cada INTERVALO_REFRESH_MS. Sem isso, MENU e LED estatico
    eram escritos uma unica vez e qualquer ruido na linha de
    dados apagava o pixel de forma permanente.
  */
  bool refresh_periodico = tempo_passou(
    agora, ultimo_frame_led_ms + INTERVALO_REFRESH_MS
  );

  if (!desenho_sujo && !animando && !refresh_periodico) {
    return;
  }

  /* Teto de taxa unico, inclusive para rajadas de comandos. */
  if (!tempo_passou(agora, ultimo_frame_led_ms + INTERVALO_FRAME_LED_MS)) {
    return;
  }

  ultimo_frame_led_ms = agora;

  for (uint8_t idx = 0; idx < NUM_TAZOS; idx++) {
    for (uint8_t pixel = 0; pixel < LEDS_POR_TAZO; pixel++) {
      uint8_t r = 0;
      uint8_t g = 0;
      uint8_t b = 0;

      if (efeito_global == EFEITO_ATRACAO) {
        cor_atracao(idx, pixel, agora, r, g, b);
      }
      else if (efeito_global == EFEITO_SCENE) {
        cor_scene(idx, pixel, agora, r, g, b);
      }
      else if (efeito_global == EFEITO_MENU) {
        cor_menu(idx, r, g, b);
      }
      else if (efeito_global == EFEITO_CONTAGEM) {
        cor_contagem(idx, pixel, agora, r, g, b);
      }
      else if (efeito_global == EFEITO_READY) {
        cor_ready(idx, pixel, agora, r, g, b);
      }

      /* Guia por cima da cena: o fundo da musica continua vivo. */
      if (guia_ativo[idx]) {
        cor_guia(idx, r, g, b);
      }

      /* Flash sempre por cima de tudo. */
      if (flashes[idx].ativo) {
        cor_flash(idx, pixel, agora, r, g, b);
      }

      fitas[idx]->setPixelColor(pixel, fitas[idx]->Color(r, g, b));
    }
  }

  for (uint8_t i = 0; i < NUM_TAZOS; i++) {
    fitas[i]->show();
  }

  desenho_sujo = false;
}