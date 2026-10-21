# DotScale — espresso com tara automática por recipiente

Data: 2026-10-21. Base: v1 (peso ao vivo) + botão Tarar, já na `main`.
Protocolo e fatos de hardware: ver `2026-10-21-dotscale-v1-design.md`.

## Intenção e o porquê

A dor que originou o projeto: no espresso, para saber o ratio, o usuário
precisa tarar o recipiente certo na hora certa, e sempre esquece. Hoje ele
pesa o porta-filtro vazio, depois cheio, faz a conta, e só então leva a balança
para a Gaggia. O objetivo desta etapa é que o app **conheça os recipientes pelo
peso** e conduza o espresso inteiro sem que ele precise tarar nada: dose de pó,
bebida, ratio e tempo saem sozinhos.

## O fluxo real do usuário (o que ele descreveu)

1. Liga a Gaggia ~10 min antes para aquecer.
2. Pesa os **grãos** num **dosímetro de porcelana**.
3. Joga os grãos na Starseeker 55, que mói num **copinho**.
4. Passa o pó do copinho para o **porta-filtro**. O porta-filtro é desajeitado
   demais para a Dot (pequena) e **fica fora do fluxo**.
5. Coloca a Dot na grade da Gaggia, uma **xícara** em cima, e começa:
   - abre o vapor (isso faz uma pré-infusão), depois fecha o vapor;
   - só então o líquido começa a cair.
6. No fim, tira **a balança e a xícara juntas** da Gaggia (para não pingar café
   na balança).

## Objetivos

- **Cadastro de recipientes** com nome, tipo e peso:
  - tipos: dosímetro, copinho do moedor, xícara;
  - cadastrar = pôr o recipiente vazio na balança, tocar em "Cadastrar
    recipiente", dar nome e tipo; o app grava o peso estável medido;
  - dá para renomear e apagar; persistido no aparelho;
  - pode haver mais de um de cada tipo.
- **Fluxo de espresso guiado pelo peso** (detalhado abaixo):
  - dosímetro vazio reconhecido → começa um espresso, tara automática;
  - peso dos grãos registrado;
  - copinho com pó reconhecido → dose de pó registrada, com a diferença em
    relação aos grãos (retenção);
  - próximo objeto na balança vazia → tara automática; é a xícara;
  - bebida, ratio e fluxo ao vivo; cronômetro automático;
  - fim detectado → resultado congelado.
- **Xícara cadastrada é opcional** (decisão do usuário): sem cadastro, o
  próximo objeto depois da dose é tarado de qualquer forma; com cadastro, o app
  mostra o nome da xícara.
- **Dose = pó** (decisão do usuário). Se o passo do copinho for pulado, a dose
  passa a ser o peso dos grãos (o usuário confirmou que são praticamente
  iguais).
- **Resultado final** (decisão do usuário): tempo de extração, dose, peso final
  da bebida e ratio final. Fica na tela até começar o próximo espresso.

## Não-objetivos (ficam para depois, o usuário quer todos no futuro)

- Histórico/log de extrações e consulta.
- Fotos dos recipientes.
- Gráfico da extração e edição do gráfico (corrigir início falso etc.).
- Coados (V60, AeroPress, OXO).
- Tomada inteligente na Gaggia (dará o sinal real de "bomba ligada").
- Resultado sobreviver a fechar o app (entra com o histórico).
- Ajustes finos de UX/layout: o usuário vai criticar o visual depois; agora
  basta funcional e legível de longe.

## Anti-objetivos

- **Não mandar o comando de tara para a Dot durante o fluxo.** Toda tara do
  fluxo é feita **no app** (subtração de um offset). Assim, uma reconexão ou
  um comando perdido não estraga a sessão. O botão "Tarar" manual da v1
  continua existindo e continua mandando `03 0D` (serve para acertar o zero
  com a balança vazia).
- **Cronômetro não pode disparar com vibração ou toque na Gaggia.** É o defeito
  que o usuário vê na Basic 3 e que ele quer evitar.
- **Tirar a balança da Gaggia não pode mudar o resultado** depois que a
  extração terminou.
- A lógica do fluxo **não pode depender de Flutter nem de BLE**: deve ser Dart
  puro, alimentada por leituras de peso com timestamp, e testável sem hardware
  (mesmo princípio do parser na v1). Isso é a base da futura detecção de fases
  dos coados.

## Referência de peso

Todos os reconhecimentos usam o **peso absoluto** que a Dot reporta. A Dot zera
sozinha ao ligar, e o usuário a liga vazia (só com a capinha de silicone, que
portanto vira o zero). Se o zero estiver errado (balança ligada com algo em
cima), os recipientes não serão reconhecidos; o remédio é o botão "Tarar" com a
balança vazia. Isso fica explicado num texto curto na tela de recipientes.

## Definições (minhas decisões; valores ajustáveis numa constante só)

- **Estável:** a amplitude (máx − mín) do peso na última 1,0 s é ≤ 0,3 g, e
  houve pelo menos 5 leituras nesse intervalo (a Dot manda ~10/s).
- **Vazia:** peso estável com |peso| < 1,0 g.
- **Bate com o recipiente R:** peso estável dentro de R.peso ± 1,5 g.
- **Bate com copinho + pó:** peso estável entre
  `copinho + grãos − 3,0 g` e `copinho + grãos + 1,0 g` (a retenção só tira pó;
  a folga para cima cobre ruído).
- Ao cadastrar, se o peso novo ficar a menos de 3,0 g de um recipiente já
  cadastrado, o app avisa que os dois podem ser confundidos (não impede).
- O reconhecimento usa o **primeiro peso estável depois da balança sair do
  vazio** (um objeto foi colocado). Objetos sendo enchidos não são
  re-reconhecidos a cada estabilização.

## O fluxo (máquina de estados)

Estados e o que a tela mostra como instrução principal:

1. **Ocioso** — "Coloque o dosímetro". Se houver um resultado anterior, ele
   continua visível.
2. **Dosímetro reconhecido** (primeiro estável após o vazio bate com um
   dosímetro): começa um espresso novo, apaga o resultado anterior, offset =
   peso do dosímetro. Mostra o **peso dos grãos** (peso − offset).
3. **Grãos registrados:** quando a balança volta a ficar vazia, os grãos
   = último peso líquido estável antes de tirar o dosímetro. Se for < 3 g,
   considera que não houve pesagem e volta para Ocioso.
   Instrução: "Coloque o copinho com o pó".
4. **Dose registrada**, por um destes caminhos:
   - primeiro estável bate com **copinho + pó** → dose = peso − copinho;
     mostra "Dose 17.8 g · retenção 0.2 g";
   - primeiro estável bate só com o **copinho vazio** → ignora e continua
     esperando (o usuário pode estar no meio do caminho);
   - primeiro estável é **qualquer outra coisa** (não bate com dosímetro) →
     dose = grãos, e esse objeto já é tratado como a xícara (passo 5);
   - botão **"Usar peso dos grãos"** → dose = grãos.
   Instrução: "Coloque a xícara na Gaggia".
5. **Xícara tarada:** primeiro estável após o vazio → offset = esse peso. Se
   bater com uma xícara cadastrada, mostra o nome. Um dosímetro reinicia o
   espresso; um copinho do moedor vazio é ignorado (minha decisão). Se a
   balança voltar a ficar vazia **antes** das primeiras gotas (o usuário
   tirou a xícara para ajeitar), o próximo objeto é tarado de novo.
   Mostra bebida 0.0 g, ratio, botão **"Iniciar"**.
6. **Pré-infusão** (só se o usuário tocar em "Iniciar"): cronômetro corre
   desde o toque.
7. **Extraindo:** começa quando aparecem as primeiras gotas (minha decisão
   sobre a regra exata, calculada só a partir de `(instante, peso)`; o fluxo
   que a Dot manda não entra na máquina):
   - numa janela de 1,0 s, o peso líquido nunca cai mais que 0,2 g em relação
     ao máximo da janela (sem recuo, o que elimina picos de vibração que voltam);
   - o peso subiu ≥ 0,3 g de uma ponta à outra da janela;
   - o peso líquido no fim da janela é > 1,0 g.
   O instante de início é o da primeira leitura dessa janela, não o fim dela. Se houve "Iniciar", esse instante
   separa a pré-infusão da extração. Mostra ao vivo: bebida (g), ratio
   (`1:2.0` = bebida ÷ dose), fluxo (g/s), cronômetro.
8. **Terminado:** o peso líquido não sobe mais que 0,2 g em 4,0 s. O peso final
   é o maior peso líquido observado. O fim é o instante da última subida, não o
   fim da espera. Resultado congelado:
   - tempo de extração (gotas → fim);
   - se houve "Iniciar": pré-infusão e total;
   - dose, bebida final, ratio final.
   Tudo o que acontece depois (tirar a balança, pingar, encostar) não altera
   o resultado. Volta para **Ocioso** mostrando o resultado.

Outras regras:

- **Dosímetro reconhecido em qualquer estado que não seja Extraindo** reinicia o
  espresso (o usuário recomeçou).
- Botão **"Cancelar"** volta para Ocioso, sem resultado.
- **Botão "Tarar" (manual, v1)** só aparece/fica habilitado em Ocioso (com ou
  sem resultado na tela). Durante o fluxo ele mudaria o zero de que todo o
  reconhecimento depende (minha decisão).
- **Desconexão no meio:** o estado do espresso é mantido; ao voltar o peso, o
  fluxo continua de onde estava. Se a extração estava em andamento, os tempos
  são mantidos e o fim é detectado normalmente quando o peso voltar.
- **Desligamento automático da Dot:** sozinha ela desliga após ~1 min parada
  (README do projeto `Sofronio/dot-scale-mate`), mas o usuário testou em
  2026-10-21: **conectada ao app, vazia, ficou ligada por mais de 3 min**.
  Então o fluxo assume que ela não desliga durante o uso. Mesmo assim, se ela
  religar no meio, o zero muda (ela zera ao ligar) e não dá para saber se o
  objeto continuou em cima. Por isso (minha decisão): se a conexão cair e
  voltar num estado com objeto na balança (dosímetro com grãos, xícara tarada,
  extraindo), o app mostra um aviso "A balança desconectou. Se ela reiniciou,
  os pesos podem estar errados — cancele e recomece." e não tenta compensar.
- **Série da extração:** guardar em memória as leituras (tempo, peso líquido)
  do passo 5 ao 8, junto do resultado. Não é exibida agora; existe para o
  gráfico, a edição e o histórico futuros.

## Tela

Continua uma tela principal (a v1), com o painel do espresso ocupando o centro
quando há balança conectada:

- instrução do estado atual em texto grande;
- o número grande passa a ser o **peso líquido** do passo atual (grãos, pó ou
  bebida); o peso bruto da balança aparece pequeno, embaixo;
- durante a extração: bebida, ratio, fluxo e cronômetro, legíveis de longe;
- resultado final em destaque após o fim;
- botões contextuais: "Iniciar", "Usar peso dos grãos", "Cancelar";
- o botão "Tarar" (só em Ocioso) e o "Desconectar" da v1 continuam;
- acesso à tela **Recipientes** (lista com nome, tipo, peso; cadastrar,
  renomear, apagar). Cadastrar exige balança ao vivo, peso estável e ≥ 1,0 g.
- sem recipientes cadastrados, a tela diz que é preciso cadastrar ao menos o
  dosímetro e o copinho, com atalho para Recipientes.

## Arquitetura (orientação)

- **`lib/espresso/` (Dart puro):**
  - modelo de recipiente;
  - detector de estabilidade;
  - máquina de estados do espresso, que recebe `(instante, peso)` e ações
    ("Iniciar", "Usar grãos", "Cancelar") e expõe estado, valores e resultado;
  - o relógio vem de fora (timestamps das leituras / um `now` injetável), para
    os testes cobrirem tempos sem esperar.
- **Persistência dos recipientes:** `shared_preferences` (já é dependência),
  como JSON.
- **UI:** o `ScaleController` (ou um controller novo ao lado dele) alimenta a
  máquina com cada `WeightReading`; widgets consomem.
- O protocolo e a camada BLE não mudam.

## Testes exigidos

Cenários da máquina de estados com sequências de leituras sintéticas:

- caminho feliz completo (dosímetro → grãos → copinho + pó → xícara → gotas →
  fim) com tempos e ratio conferidos;
- copinho pulado (dose = grãos, objeto vira xícara);
- copinho vazio colocado antes do pó (ignorado);
- botão "Iniciar" com pré-infusão;
- vibração: picos curtos de +2 g que voltam não iniciam o cronômetro;
- tirar a balança depois do fim (peso cai/oscila) não muda o resultado;
- dosímetro no meio do fluxo reinicia;
- grãos < 3 g voltam para Ocioso;
- desconexão no meio da extração (lacuna nas leituras).

## Deixado para quem for construir

- Estrutura exata dos arquivos e nomes.
- Se o controller do espresso é novo ou parte do `ScaleController`.
- Layout e navegação para a tela de recipientes.
- Ajustar os limiares acima se os testes no hardware mostrarem necessidade
  (registrar a mudança no documento).

## Ajustes feitos na implementação (2026-10-21)

- **Objeto mínimo de 5 g:** entre "vazia" (< 1 g) e 5 g o peso não rearma nem é reconhecido, para ruído não virar xícara.
- **Gotas:** a janela de 1 s começa quando o líquido passa de 1,0 g (e não termina nele), senão um pico de vibração
  dispararia antes de voltar. O início registrado é a primeira leitura que se descola da linha de base (mediana do
  peso antes), olhando no máximo 2 s para trás; gotas soltas da pré-infusão não puxam o início.
- **Tranco:** variação > 3 g entre duas leituras (~100 ms) na extração é a balança sendo levantada ou a xícara
  retirada: encerra no último ponto plausível. A bebida é a mediana do patamar final, não o máximo.
- **Desconexão na extração:** o resultado sai marcado como interrompido, com aviso no card.
