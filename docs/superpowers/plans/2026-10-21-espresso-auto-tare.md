# Espresso com tara automática — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o app reconhece dosímetro, copinho do moedor e xícara pelo peso e conduz o espresso sozinho: grãos, dose de pó, bebida, ratio, cronômetro e resultado final.

**Architecture:** lógica nova em `lib/espresso/` em Dart puro (recipientes, estabilidade, máquina de estados alimentada por `(DateTime, gramas)`). Um `EspressoController` (ChangeNotifier) liga os eventos da conexão à máquina e persiste os recipientes. A UI ganha um painel de espresso na tela principal e uma tela de Recipientes. Protocolo e BLE não mudam.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `shared_preferences` (já é dependência), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-21-espresso-auto-tare-design.md`

## Global Constraints

- Ambiente: `export PATH="$HOME/development/flutter/bin:$PATH"`; testes com `flutter test`, análise com `flutter analyze` (zero issues).
- `lib/espresso/` não importa `package:flutter` nem nada de `lib/ble` ou `lib/ui`.
- Nenhum comando para a Dot durante o fluxo; toda tara do fluxo é offset no app. O botão "Tarar" (v1) só é habilitado em `EspressoStep.idle`.
- Limiares (todos num `EspressoTuning` const): estável = amplitude ≤ 0,3 g em 1,0 s com ≥ 5 leituras; vazia = estável e |g| < 1,0; recipiente bate = ±1,5 g; copinho+pó entre `copinho + grãos − 3,0` e `copinho + grãos + 1,0`; grãos mínimos 3,0 g; gotas = janela 1,0 s sem queda > 0,2 g abaixo do máximo da janela, subida ≥ 0,3 g na janela, líquido > 1,0 g no fim, início = primeira leitura da janela; fim = sem subir > 0,2 g em 4,0 s, fim = instante da última subida, bebida = maior líquido; aviso de conflito no cadastro a < 3,0 g.
- Textos da UI em português, exatamente como o spec quando ele fixa: "Coloque o dosímetro", "Coloque o copinho com o pó", "Coloque a xícara na Gaggia", "Usar peso dos grãos", "Iniciar", "Cancelar", "Cadastrar recipiente", aviso "A balança desconectou. Se ela reiniciou, os pesos podem estar errados — cancele e recomece."
- Ratio exibido como `1:<bebida/dose com 1 casa>`, ex. `1:2.0`. Tempos com 1 casa: `27.4 s`.
- Commits com `user.email=humberto.soares@gmail.com` (já configurado no repo) e linha `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Peso oscilando perto de 1,0 g** (balança "quase vazia") não pode reconhecer recipiente nem registrar grãos duas vezes: o rearme exige vazio estável → teste em Task 3.
2. **Leituras negativas** (Dot zerou com carga) não podem casar com nada nem iniciar fluxo → teste em Task 3.
3. **Xícara com peso perto do dosímetro (±1,5 g)** reinicia o espresso no passo 5; o cadastro precisa avisar → teste de `containersNear` em Task 1 e de aviso em Task 5.
4. **Lacuna de leituras durante a extração** (desconexão) não pode travar a máquina nem gerar resultado com bebida 0 → teste em Task 4.
5. **Dosímetro colocado com resultado na tela** deve apagar o resultado e começar novo espresso; durante `extracting` deve ser ignorado → testes em Task 3/4.

---

### Task 1: Recipientes (modelo + persistência)

**Files:**
- Create: `lib/espresso/scale_container.dart`, `lib/espresso/container_store.dart`
- Create: `test/espresso/scale_container_test.dart`, `test/espresso/container_store_test.dart`, `test/fakes/in_memory_container_store.dart`

**Interfaces:**
- Produces:
  - `enum ContainerKind { doser, grinderCup, cup }` com `String get label` → `'Dosímetro'`, `'Copinho do moedor'`, `'Xícara'`.
  - `class ScaleContainer { final String id; final String name; final ContainerKind kind; final double grams; const ScaleContainer({required ...}); ScaleContainer copyWith({String? name}); Map<String, Object> toJson(); factory ScaleContainer.fromJson(Map<String, Object?>) }`
  - `List<ScaleContainer> containersNear(List<ScaleContainer> all, double grams, {double within = 3.0})` — os que têm `|c.grams − grams| < within`.
  - `abstract interface class ContainerStore { Future<List<ScaleContainer>> load(); Future<void> save(List<ScaleContainer> containers); }`
  - `class PrefsContainerStore implements ContainerStore` — chave `'containers'`, valor JSON (lista); chave ausente ou JSON inválido → lista vazia.
  - test fake `InMemoryContainerStore implements ContainerStore` (guarda a lista; `saves` conta chamadas).

- [ ] **Step 1: testes que falham**
  - `scale_container_test.dart`: `'toJson/fromJson ida e volta'` (todos os campos, os 3 kinds); `'containersNear acha só os que estão a menos de 3 g'` com dosímetro 80.0, xícara 82.5, copinho 40.0 e `grams: 81.0` → [dosímetro, xícara]; `'label em português'`.
  - `container_store_test.dart` (com `SharedPreferences.setMockInitialValues({})`): `'load sem nada salvo devolve vazio'`; `'save e load devolvem a mesma lista'`; `'JSON corrompido devolve vazio'` (`setMockInitialValues({'containers': 'xx'})`).
- [ ] **Step 2:** `flutter test test/espresso` → FAIL (arquivos não existem).
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `flutter test test/espresso` → PASS; `flutter analyze` → No issues.
- [ ] **Step 5:** commit `feat: modelo e persistência de recipientes`.

### Task 2: Limiares e detector de estabilidade

**Files:**
- Create: `lib/espresso/tuning.dart`, `lib/espresso/stability.dart`, `test/espresso/stability_test.dart`

**Interfaces:**
- Produces:
  - `class EspressoTuning` — construtor `const` com todos os valores dos Global Constraints como parâmetros nomeados com default: `stableWindow`, `stableRange`, `stableMinSamples`, `emptyBelow`, `matchTolerance`, `groundsBelow`, `groundsAbove`, `minBeans`, `dripWindow`, `dripMaxDip`, `dripMinRise`, `dripMinNet`, `endWindow`, `endMinRise`, `conflictWithin`.
  - `class StabilityTracker { StabilityTracker(EspressoTuning tuning); void add(DateTime at, double grams); void reset(); double? get stableGrams; }` — guarda as leituras dos últimos `stableWindow`; `stableGrams` = média da janela (arredondada a 0,1) quando há ≥ `stableMinSamples` leituras, a janela cobre ≥ 90% de `stableWindow` e máx − mín ≤ `stableRange`; senão `null`.

- [ ] **Step 1: testes que falham** (helper `feed(tracker, start, [valores], every: 100ms)`):
  - `'10 leituras iguais em 1 s são estáveis'` → `stableGrams == 50.0`;
  - `'menos de 5 leituras não é estável'`;
  - `'variação de 0,4 g não é estável'`;
  - `'pico sai da janela depois de 1 s e volta a ser estável'`;
  - `'reset esquece tudo'`.
- [ ] **Step 2:** `flutter test test/espresso/stability_test.dart` → FAIL.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** PASS; analyze limpo.
- [ ] **Step 5:** commit `feat: detector de estabilidade do peso`.

### Task 3: Máquina do espresso — preparo (dosímetro → xícara tarada)

**Files:**
- Create: `lib/espresso/espresso_session.dart`, `test/espresso/espresso_session_prep_test.dart`, `test/espresso/session_driver.dart` (helper de teste)

**Interfaces:**
- Consumes: `ScaleContainer`, `ContainerKind` (Task 1); `EspressoTuning`, `StabilityTracker` (Task 2).
- Produces (completado na Task 4):
  - `enum EspressoStep { idle, weighingBeans, awaitingGrounds, awaitingCup, cupReady, preInfusion, extracting }`
  - `class WeightSample { final Duration t; final double grams; }`
  - `class EspressoResult { final double dose; final double? beans; final double beverage; final Duration extraction; final Duration? preInfusion; final String? cupName; final List<WeightSample> samples; double get ratio => beverage / dose; }`
  - `class EspressoSession`:
    - `EspressoSession({List<ScaleContainer> containers = const [], EspressoTuning tuning = const EspressoTuning()})`; `List<ScaleContainer> containers` (getter/setter).
    - estado: `EspressoStep get step`, `double? get rawGrams`, `double? get netGrams` (raw − offset do passo), `double? get stableGrams` (do tracker, bruto), `double? get beans`, `double? get dose`, `double? get retention` (beans − dose, só quando a dose veio do copinho), `String? get cupName`, `EspressoResult? get result`, `bool get reconnectWarning`.
    - tempos: `DateTime? get timerStartedAt` (início da pré-infusão, senão das gotas), `DateTime? get extractionStartedAt`.
    - ações: `void addReading(DateTime at, double grams)`, `void startTimer(DateTime at)`, `void useBeansAsDose()`, `void cancel()`, `void connectionLost()`.
  - Helper de teste `SessionDriver(session, {start})`: `hold(double grams, Duration d)` envia leituras a cada 100 ms; `ramp(from, to, Duration d)`; `DateTime now`.

Regra central (o "rearme"): a sessão só reconhece um objeto no **primeiro estável não-vazio depois de um estável vazio**. Reconhecer consome o rearme; um novo vazio estável rearma. Antes de qualquer vazio desde a criação, a sessão está rearmada.

- [ ] **Step 1: testes que falham** (containers: dosímetro 80.0, copinho 40.0, xícara "Azul" 150.0):
  - `'dosímetro vazio inicia o espresso com líquido 0'` → step `weighingBeans`, `netGrams == 0.0`;
  - `'grãos são registrados ao tirar o dosímetro'` (80 → 98 → 0) → `beans == 18.0`, step `awaitingGrounds`;
  - `'menos de 3 g de grãos volta para ocioso'`;
  - `'copinho com pó registra dose e retenção'` (40 + 17.8 = 57.8) → `dose == 17.8`, `retention` ≈ 0.2, step `awaitingCup`;
  - `'copinho vazio é ignorado'` (40.0 sozinho) → continua `awaitingGrounds`;
  - `'outro objeto pula o copinho: dose = grãos e objeto vira xícara'` (120.0) → `dose == 18.0`, step `cupReady`, `netGrams == 0.0`;
  - `'usar peso dos grãos'` → `dose == 18.0`, step `awaitingCup`;
  - `'xícara cadastrada é tarada e nomeada'` → step `cupReady`, `cupName == 'Azul'`, `netGrams == 0.0`;
  - `'xícara não cadastrada também é tarada'` (133.0) → `cupReady`, `cupName == null`;
  - `'tirar a xícara antes das gotas tara de novo o próximo objeto'`;
  - `'dosímetro no meio do preparo reinicia'` (em `awaitingCup`) → `weighingBeans`, `beans == null`, `dose == null`;
  - `'peso oscilando perto de 1 g não rearma'` (alterna 0.9/1.1 por 2 s depois de registrar a dose; nenhum novo reconhecimento);
  - `'leituras negativas não casam com nada'` (estável em −80.0) → continua `idle`;
  - `'cancelar volta para ocioso sem resultado'`.
- [ ] **Step 2:** `flutter test test/espresso/espresso_session_prep_test.dart` → FAIL.
- [ ] **Step 3:** implementar passos 1–5 do spec. `startTimer`, `connectionLost` e a extração podem ficar como no-op até a Task 4.
- [ ] **Step 4:** PASS; analyze limpo.
- [ ] **Step 5:** commit `feat: máquina do espresso — preparo`.

### Task 4: Máquina do espresso — extração, resultado, desconexão

**Files:**
- Modify: `lib/espresso/espresso_session.dart`
- Create: `test/espresso/espresso_session_extraction_test.dart`

**Interfaces:**
- Consumes/Produces: a API da Task 3, agora completa.

Regras:
- Em `cupReady`/`preInfusion`, gotas detectadas → `extracting`, `extractionStartedAt` = primeira leitura da janela.
- `startTimer` só age em `cupReady` → `preInfusion`; nos outros passos, nada.
- Em `extracting`, o fim → `result` preenchido, step `idle`. Leituras depois disso não mudam `result`.
- `samples`: leituras `(t desde a tara da xícara, líquido)` da tara até o fim.
- Dosímetro reconhecido durante `extracting` é ignorado. Em `idle` com resultado, dosímetro inicia novo espresso e zera `result`.
- `connectionLost()`: `reconnectWarning = true` se o step for `weighingBeans`, `cupReady`, `preInfusion` ou `extracting`; zera o tracker de estabilidade. O aviso some em `cancel()`, num novo espresso e no fim da extração.

- [ ] **Step 1: testes que falham** (preparo até `cupReady` com dose 18.0 via driver):
  - `'extração completa: tempo, bebida e ratio'`: 0 g por 3 s, rampa 0 → 36.0 em 27 s, 36.0 parado por 5 s → `result.beverage == 36.0`, `result.ratio` ≈ 2.0, `result.extraction` ≈ 27 s (±0,2 s), `result.preInfusion == null`, `step == idle`;
  - `'Iniciar marca a pré-infusão'`: `startTimer` 8 s antes das gotas → `result.preInfusion` ≈ 8 s, `result.extraction` ≈ 27 s;
  - `'vibração não inicia o cronômetro'`: picos de +2 g por 300 ms, que voltam a 0, repetidos 5×, → step continua `cupReady`, `extractionStartedAt == null`;
  - `'tirar a balança depois do fim não muda o resultado'`: após o fim, rampa para −150 e oscilações → `result` igual;
  - `'dosímetro durante a extração é ignorado'`;
  - `'dosímetro com resultado na tela começa outro espresso'` → `result == null`, `weighingBeans`;
  - `'lacuna de leituras na extração'`: rampa até 20 g, `connectionLost()`, sem leituras por 6 s, volta subindo até 36 → `reconnectWarning` verdadeiro durante, resultado com `beverage == 36.0` e aviso apagado após o fim;
  - `'samples cobrem da tara ao fim'` (primeiro `t == Duration.zero`, último ≤ fim).
- [ ] **Step 2:** `flutter test test/espresso` → FAIL só nos novos.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `flutter test test/espresso` → PASS; analyze limpo.
- [ ] **Step 5:** commit `feat: máquina do espresso — extração e resultado`.

### Task 5: EspressoController e tela de Recipientes

**Files:**
- Create: `lib/ui/espresso_controller.dart`, `lib/ui/containers_page.dart`
- Modify: `lib/ui/format.dart` (+ `formatRatio`, `formatSeconds`)
- Create: `test/ui/espresso_controller_test.dart`, `test/ui/containers_page_test.dart`; Modify: `test/ui/format_test.dart`

**Interfaces:**
- Consumes: `ScaleConnection` (status/events), `FakeScaleConnection`, `InMemoryContainerStore`, `EspressoSession`.
- Produces:
  - `String formatRatio(double beverage, double dose)` → `'1:2.0'`; `String formatSeconds(Duration d)` → `'27.4 s'`.
  - `class EspressoController extends ChangeNotifier`:
    - `EspressoController(ScaleConnection connection, ContainerStore store, {DateTime Function() now = DateTime.now, EspressoTuning tuning = const EspressoTuning()})` — assina `connection.events` (cada `WeightReading` → `session.addReading(now(), grams)` + notify) e `connection.status` (sair de `connected` depois de ter estado conectado → `session.connectionLost()`).
    - `Future<void> load()`; `EspressoSession get session`; `List<ScaleContainer> get containers`; `bool get hasRequiredContainers` (≥ 1 dosímetro e ≥ 1 copinho).
    - `double? get registrableGrams` → `session.stableGrams` se conectado e ≥ 1,0; senão `null`.
    - `List<ScaleContainer> nearRegistrable()` → `containersNear(containers, registrableGrams!, within: tuning.conflictWithin)` ou vazio.
    - `Future<void> addContainer(String name, ContainerKind kind)` (usa `registrableGrams`, `StateError` se `null`; id = `now().microsecondsSinceEpoch.toString()`); `Future<void> rename(String id, String name)`; `Future<void> remove(String id)` — todos salvam no store e atualizam `session.containers`.
    - `void startTimer()`, `void useBeansAsDose()`, `void cancel()`; `Duration? elapsed()` = `now() − session.timerStartedAt` em `preInfusion`/`extracting`, senão `null`.
  - `class ContainersPage extends StatelessWidget { const ContainersPage({required EspressoController controller}) }`: texto curto sobre o zero ("Os recipientes são reconhecidos pelo peso. Ligue a balança vazia; se o zero estiver errado, use Tarar com ela vazia."); lista (nome, label do tipo, `formatGrams`); botão "Cadastrar recipiente" habilitado só com `registrableGrams != null`, abre diálogo com nome, tipo e o peso; se `nearRegistrable()` não for vazio, o diálogo mostra "Atenção: parecido com <nomes>; podem ser confundidos."; renomear e apagar por item.

- [ ] **Step 1: testes que falham**
  - format: `formatRatio(36, 18) == '1:2.0'`, `formatSeconds(Duration(milliseconds: 27400)) == '27.4 s'`.
  - controller (relógio falso que avança 100 ms por leitura): `'load traz recipientes do store'`; `'leituras chegam à sessão'` (dosímetro reconhecido); `'addContainer usa o peso estável e salva'`; `'addContainer sem peso estável lança StateError'`; `'queda da conexão com xícara tarada liga o aviso'`; `'hasRequiredContainers'`; `'elapsed corre na pré-infusão'`.
  - página: `'cadastrar desabilitado sem peso estável'`; `'cadastrar grava nome e tipo'`; `'diálogo avisa de recipiente parecido'`; `'apagar remove da lista'`.
- [ ] **Step 2:** `flutter test test/ui` → FAIL nos novos.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `flutter test` → tudo PASS; analyze limpo.
- [ ] **Step 5:** commit `feat: controller do espresso e tela de recipientes`.

### Task 6: Painel do espresso na tela principal + ligação no main

**Files:**
- Create: `lib/ui/espresso_panel.dart`
- Modify: `lib/ui/home_page.dart` (`_LiveView` usa o painel; `HomePage` recebe `espresso`), `lib/main.dart`, `README.md`
- Modify: `test/ui/home_page_test.dart`; Create: `test/ui/espresso_panel_test.dart`

**Interfaces:**
- Consumes: `EspressoController` (Task 5), `ScaleController` (v1).
- Produces: `HomePage({required ScaleController controller, required EspressoController espresso})`; `EspressoPanel({required EspressoController espresso})`.

Comportamento do painel (dentro do `_LiveView`, no lugar do número grande):
- instrução por step: idle sem resultado → "Coloque o dosímetro"; `weighingBeans` → "Grãos"; `awaitingGrounds` → "Coloque o copinho com o pó"; `awaitingCup` → "Coloque a xícara na Gaggia" (+ "Dose 17.8 g · retenção 0.2 g"); `cupReady` → "Pronto — inicie a extração" (+ nome da xícara se houver); `preInfusion` → "Pré-infusão"; `extracting` → "Extraindo".
- número grande = `netGrams` (em idle = bruto). Bruto pequeno embaixo quando o step ≠ idle.
- em `cupReady`/`preInfusion`/`extracting`: ratio (`formatRatio(net, dose)`), fluxo da Dot e cronômetro (`elapsed`) — um `Ticker`/`Timer.periodic(100ms)` só nesses steps para atualizar o cronômetro; cancelado ao sair deles e no dispose.
- resultado (idle com `result`): tempo de extração, pré-infusão e total se houver, dose, bebida, ratio.
- botões: "Usar peso dos grãos" (`awaitingGrounds`), "Iniciar" (`cupReady`), "Cancelar" (qualquer step ≠ idle). "Tarar" só habilitado em idle.
- `reconnectWarning` → o texto do aviso em cor de erro.
- sem `hasRequiredContainers`: "Cadastre o dosímetro e o copinho do moedor para o espresso automático." + botão "Recipientes".
- AppBar: ícone de ação que abre `ContainersPage`.
- `main.dart`: cria `PrefsContainerStore`, `EspressoController(connection, store)`, chama `load()` antes de `runApp`.
- README: seção curta "Espresso" (cadastrar recipientes, fluxo).

- [ ] **Step 1: testes que falham** (`espresso_panel_test.dart` com fake connection, store em memória com dosímetro e copinho, relógio falso):
  - `'sem recipientes mostra o aviso de cadastro'`;
  - `'idle mostra Coloque o dosímetro e Tarar habilitado'`;
  - `'fluxo até a xícara mostra Iniciar e Tarar desabilitado'`;
  - `'durante a extração mostra ratio e cronômetro'`;
  - `'resultado final mostra tempo, dose, bebida e ratio'` (`'1:2.0'`, `'18.0 g'`, `'36.0 g'`);
  - `'aviso de desconexão aparece'`;
  - `'Cancelar volta para Coloque o dosímetro'`.
  - Ajustar `home_page_test.dart` para construir `HomePage` com `EspressoController`; manter os testes existentes passando.
- [ ] **Step 2:** `flutter test test/ui` → FAIL nos novos.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `flutter test` → tudo PASS; `flutter analyze` → No issues; `flutter build apk --release` → sucesso.
- [ ] **Step 5:** commit `feat: painel do espresso na tela principal`.
- [ ] **Step 6 (usuário, no hardware):** instalar (`adb install -r build/app/outputs/flutter-apk/app-release.apk`), cadastrar dosímetro, copinho e uma xícara, fazer um espresso real. Registrar no spec o resultado e qualquer limiar ajustado.
