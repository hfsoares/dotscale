# DotScale

App Flutter que conecta na balança Timemore Dot por Bluetooth LE e mostra o peso ao vivo.

- Design: `docs/superpowers/specs/2026-10-21-dotscale-v1-design.md`
- Plano: `docs/superpowers/plans/2026-10-21-dotscale-v1.md`

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
