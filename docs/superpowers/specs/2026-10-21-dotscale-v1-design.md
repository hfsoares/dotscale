# DotScale v1 — peso ao vivo da Timemore Dot

Data: 2026-10-21

## Intenção e o porquê

O usuário prepara espresso (Gaggia + moedor Starseeker 55, depois do almoço) e
coados (Fellow/V60, AeroPress, OXO, fim da tarde). Hoje usa uma Timemore Basic 3
e acabou de comprar uma **Timemore Dot** (BLE).

A dor que motiva o projeto: no espresso, acompanhar o ratio exige tarar na hora
certa. Tarar logo após pesar os grãos falha porque a balança costuma "resetar"
antes da extração. Hoje ele tara com o puck/porta-filtro em cima, o que é
desconfortável. A visão de longo prazo é um app no estilo **Oscalla**: que
conhece o peso dos recipientes e desconta a tara sozinho, identifica o estágio
do preparo pelo peso (pesando grãos, aguardando, extraindo, terminado), calcula
o ratio e, mais adiante, integra com uma tomada inteligente na Gaggia.

A **v1** é só a fundação: provar a conexão com a Dot e mostrar o peso ao vivo.
Tudo o que vem depois depende de um parser de protocolo confiável, e é isso que
a v1 entrega e valida em hardware real.

## Objetivos (v1)

- Escanear e listar balanças Timemore Dot por perto.
- Conectar (incluindo o pareamento/criptografia que a Dot exige).
- Mostrar o peso ao vivo em destaque, com resolução de 0,1 g.
- Mostrar também fluxo (g/s) e bateria (%), que já vêm nos mesmos pacotes.
- Mostrar o estado da conexão e reconectar sozinho se a conexão cair.
- Painel de debug com os frames crus em hex (RX e TX), para validar o protocolo
  na balança real.
- Rodar em Android agora. O código deve ser multiplataforma (iOS será compilado
  depois num Mac que o usuário tem).

## Não-objetivos (v1)

Tara pelo app, controle de timer, cadastro de recipientes, receitas, detecção de
fases, ratio, histórico, gráficos, integração com Gaggia/tomada, suporte a
outras balanças (Black Mirror, Basic 3 Link, Acaia…), publicação em lojas.

## Anti-objetivos

- O parser de protocolo **não** pode ficar misturado com o código de Bluetooth
  ou de UI. Ele é a base da detecção de fases futura e precisa ser testável sem
  hardware.
- Não copiar os comandos do driver antigo do GaggiMate (branch `main`), que
  trocava "tara" por "consulta" (ver Protocolo).

## Decisões tomadas

- **Plataforma (decisão do usuário):** Flutter, para ter Android e iOS com um
  único código. O usuário tem um Mac para gerar o build de iOS.
- **Escopo da v1 (decisão do usuário):** só o peso ao vivo.
- **BLE (minha decisão):** `flutter_blue_plus`.
- **Ambiente de build (minha decisão):** Linux, JDK 21 já instalado em
  `/usr/lib/jvm/java-21-openjdk-amd64`. O Flutter SDK e o Android SDK serão
  instalados pela linha de comando (Android SDK em `~/Android/Sdk`, reaproveitável
  por um Android Studio no futuro). O APK vai para o celular via `adb` (cabo ou
  depuração por Wi-Fi).
- **Android mínimo (minha decisão, a versão do celular do usuário não foi
  confirmada):** manter o minSdk padrão do Flutter/`flutter_blue_plus` e tratar
  as permissões dos dois regimes: `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` no
  Android 12+, e localização no Android ≤ 11.
- **iOS:** declarar `NSBluetoothAlwaysUsageDescription` no `Info.plist`. A v1 não
  precisa ser testada em iOS, mas não pode usar APIs que só existem no Android
  sem um caminho alternativo. A exceção é o pedido explícito de bond, que é
  específico do Android: no iOS o pareamento acontece sozinho na primeira
  operação que exige criptografia.
- **Repositório:** git local em `/home/humberto/pessoal/dotscale`.

## Protocolo da Timemore Dot (o que se sabe)

Fonte principal: driver do GaggiMate na tag **v1.0.7** de
`github.com/gaggimate/esp-arduino-ble-scales` (`src/scales/dot.cpp`), que
corresponde ao que o GaggiMate usa em produção. Ela concorda com o Beanconqueror
(`src/classes/devices/timemoreDotScale.ts`) e com um documento de protocolo com
cara de documento do fabricante
(`github.com/george-ags/coffee-by-weight/.../Timemore/protocols.md`).

**Identificação:** o nome anunciado começa com `TIMEMORE_Dot` ou contém `tes017`
(ignorando maiúsculas e minúsculas). TES017 é o código de modelo da Dot.

**GATT:** serviço `0xFFF0`.

- `0xFFF1`: entrada (o app assina notify; se falhar, tenta indicate).
- `0xFFF2`: comandos (write without response).

UUIDs completos: `0000fff0-0000-1000-8000-00805f9b34fb`, etc.

**Segurança:** a Dot só transmite depois que o link está criptografado. No
Android, o app deve garantir o bond antes de assinar `FFF1` (por exemplo,
`createBond()` do `flutter_blue_plus`). O diálogo de pareamento do sistema pode
aparecer na primeira vez.

**Frame** (mesmo formato nos dois sentidos, big-endian):

```
A5 5A | classe (1) | tipo (1) | tamanho do payload (2) | payload | CRC (2)
```

O CRC é CRC-16/MODBUS (init 0xFFFF, poly refletido 0xA001) sobre todos os bytes
anteriores. Exemplo para conferir a implementação: tara = `A5 5A 03 0D 00 00 64 D1`.

**Classes:**

- `0x01`: notificação espontânea.
- `0x02`: consulta / resposta a consulta.
- `0x03`: comando/escrita.

**Peso** (classe 0x01 ou 0x02, tipo 0x01, payload de 9 bytes; aceitar ≥ 8):

- `payload[0..3]`: peso, int32 com sinal, em 0,1 g.
- `payload[4..5]`: fluxo, int16 com sinal, em 0,1 g/s.
- `payload[6..7]`: timer em segundos, uint16.
- `payload[8]`: flag de sobrecarga.

Os frames chegam a cada ~100 ms.

**Bateria** (tipo 0x05, payload de 2 bytes): `payload[1]` é a porcentagem.
Chega a cada ~30 s.

**Ao conectar:**

1. Assinar `FFF1`.
2. Esperar 500 ms e enviar unidade = gramas (`03 06 [00]`).
3. Esperar 200 ms e enviar modo padrão (`03 08 [01 00]`).

Não tarar na conexão. Não é preciso keep-alive.

**Remontagem do stream:** um frame pode vir dividido em várias notificações, ou
duas notificações podem vir juntas. O parser deve:

- Acumular os bytes.
- Ressincronizar procurando `A5 5A`.
- Descartar tamanhos de payload absurdos (> 64).

**CRC de entrada não confirmado:** o GaggiMate só registra divergência, sem
rejeitar o frame. A v1 faz o mesmo e mostra a divergência no painel de debug.

**Incertezas que a v1 deve esclarecer com hardware real:**

- se o CRC de entrada bate;
- o layout real do payload de peso;
- se o pareamento é pedido.

**Comandos conhecidos, para versões futuras:**

| Comando | Bytes |
|---|---|
| tara | `03 0D` |
| timer iniciar/parar/zerar | `03 02 [01/02/03]` |
| desligar | `03 0B` |

O driver antigo (branch `main`) trata `02 04` como tara. Isso está errado: é uma
consulta.

## Hardware e critério de pronto

A Dot já está com o usuário: ele a conectou pelo nRF Connect e viu os serviços.
Por isso não é preciso simulador de BLE; os testes em hardware real começam cedo.
Os testes unitários do parser usam frames sintéticos e, assim que existirem,
frames reais copiados do painel de debug.

**A v1 está pronta quando** (minha decisão):

- o app conecta na Dot pelo celular Android do usuário;
- o peso na tela acompanha o display da balança (mesmo valor com 0,1 g,
  conferido com um objeto de peso conhecido e com peso negativo após tarar
  pelo botão da balança), sem atraso perceptível;
- a reconexão funciona depois de desligar e religar a balança.

Se o protocolo real divergir do documentado, corrigir o parser faz parte da v1.

## Tela (v1)

Uma tela só.

- **Desconectado:** botão "Procurar balança" e lista das Dots encontradas (nome
  + RSSI). Tocar numa delas conecta. O app lembra a última balança e tenta
  reconectar a ela ao abrir.
- **Conectado:**
  - peso grande no centro (ex.: `18.4 g`);
  - abaixo, fluxo (`g/s`) e bateria (`%`);
  - estado da conexão;
  - botão para desconectar.
- **Debug:** painel recolhível com os últimos frames em hex, com direção (RX/TX)
  e marcação de CRC divergente.
- Tela sempre ligada enquanto conectado (o celular fica ao lado da máquina).

## Arquitetura (orientação)

Três camadas, nesta direção de dependência:

1. **Protocolo (Dart puro, sem Flutter):**
   - CRC;
   - montagem de frames de comando;
   - remontagem do stream e decodificação para eventos tipados (peso, bateria,
     desconhecido).
   - Testes unitários cobrem:
     - frames inteiros, divididos e concatenados;
     - lixo antes do magic;
     - tamanho absurdo;
     - peso negativo;
     - CRC divergente;
     - o vetor da tara acima.
2. **Conexão BLE:** scan, conexão, bond, descoberta, assinatura, sequência de
   configuração e reconexão. Expõe um stream de estado e de eventos.
3. **UI:** consome os streams.

## Deixado para quem for construir

- Estrutura de pastas e gerenciamento de estado (algo simples basta).
- Política de reconexão (backoff, número de tentativas).
- Visual. Deve ser limpo e legível de longe, com o número grande.
- Tamanho do buffer do painel de debug.
- Como persistir a última balança usada.
