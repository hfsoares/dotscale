# DotScale

App Flutter que conecta na balança Timemore Dot por Bluetooth LE, mostra o peso ao vivo e conduz o espresso
reconhecendo os recipientes pelo peso.

- Design: `docs/superpowers/specs/2026-10-21-dotscale-v1-design.md`, `docs/superpowers/specs/2026-10-21-espresso-auto-tare-design.md`
- Planos: `docs/superpowers/plans/`

## Espresso

1. Em **Recipientes** (ícone de xícara no topo), cadastre o dosímetro e o copinho do moedor: coloque cada um
   vazio na balança, espere o peso parar e toque em "Cadastrar recipiente". Xícaras são opcionais.
2. Coloque o dosímetro: o app desconta o peso dele e mostra os grãos. Tire-o para registrar.
3. Coloque o copinho com o pó: o app registra a dose e a retenção.
4. Leve a balança para a Gaggia com a xícara: ela é tarada sozinha. O cronômetro começa nas primeiras gotas
   (ou toque em "Iniciar" para contar a pré-infusão) e para quando o peso para de subir.

## Ambiente

```sh
export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
```

O Flutter já está configurado com `flutter config --android-sdk ~/Android/Sdk --jdk-dir /usr/lib/jvm/java-21-openjdk-amd64`.

## Testes

```sh
flutter analyze
flutter test
```

## Instalar no celular

Ative a "Depuração USB" nas opções de desenvolvedor do Android.

```sh
adb devices                  # o celular deve aparecer como "device"
flutter run --release        # compila, instala e abre
# ou
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### adb por Wi-Fi (Android 11+)

Em Opções do desenvolvedor → Depuração por Wi-Fi → "Parear dispositivo com código de pareamento":

```sh
adb pair <ip>:<porta-de-pareamento>   # digite o código mostrado no celular
adb connect <ip>:<porta>              # porta mostrada na tela principal da Depuração por Wi-Fi
```

## iOS

Requer um Mac com Xcode: `flutter build ios` / `flutter run` com o iPhone conectado.
