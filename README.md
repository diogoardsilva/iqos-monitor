# IQOS Monitor

App para Windows e macOS que se liga por Bluetooth a um ou mais IQOS ao mesmo tempo e:

- mostra a bateria do carregador (ou do dispositivo, nos modelos ONE) e do holder;
- conta os cigarros fumados hoje e desde a última carga;
- estima quantos cigarros ainda dá para fumar com a carga atual, e aprende o consumo real de cada dispositivo;
- avisa quando cada cigarro termina, quando o holder tem de voltar ao carregador, quando a bateria está fraca e quando a carga fica completa;
- fica na área de notificação do Windows (ou na barra de menus do Mac) e reconecta-se sozinha;
- procura atualizações nas releases do GitHub e instala-as sozinha.

## Instalar

1. Descarregue `IqosMonitor.exe` da [última release](../../releases/latest).
2. Abra-o. Na primeira vez, o Windows pode mostrar o aviso do SmartScreen porque o executável não está assinado: carregue em **Mais informações → Executar mesmo assim**.
3. Ative o Bluetooth no Windows.
4. Ponha o IQOS em modo de emparelhamento (veja o manual do seu modelo) e carregue em **Adicionar IQOS**.

O IQOS só aceita uma ligação de cada vez. Se a app IQOS do telemóvel estiver ligada, desligue-a primeiro.

Os dados ficam em `%APPDATA%\IqosMonitor\` (`state.json` e `iqos-monitor.log`).

## macOS

A versão para Mac é uma app nativa em SwiftUI que vive só na barra de menus, sem ícone no Dock. Ao clicar no ícone abre-se um painel no vidro do sistema (Liquid Glass no macOS 26 ou mais recente), como o Centro de Controlo:

- um módulo por IQOS, com anéis de bateria no estilo do widget Baterias (o aparelho desenhado ao centro), cigarros restantes e de hoje;
- adicionar, mudar o nome, repor e remover IQOS sem sair do painel;
- avisos no Centro de Notificações e a janela no canto quando tira o holder;
- Definições com "Abrir ao iniciar sessão". Se o ícone ficar escondido, abrir a app outra vez mostra as Definições.

O desenho segue as Human Interface Guidelines: o vidro fica só na camada que flutua (o painel e a janela do canto) e o conteúdo usa preenchimentos neutros, cores do sistema e tipo do sistema, em claro e escuro. Funciona a partir do macOS 14.

### Instalar

1. Descarregue `IqosMonitor-macOS.zip` da [última release](../../releases/latest) e arraste o `IqosMonitor.app` para Aplicações.
2. A app não está assinada com uma conta de programador da Apple, por isso o macOS bloqueia-a da primeira vez. Abra-a, feche o aviso e vá a **Definições do Sistema → Privacidade e segurança → Abrir mesmo assim**. (Ou no Terminal: `xattr -dr com.apple.quarantine "/Applications/IqosMonitor.app"`.)
3. Aceite o acesso ao Bluetooth e às notificações quando o macOS perguntar.

Os dados ficam em `~/Library/Application Support/IqosMonitor/`. O formato do `state.json` é o mesmo do Windows.

No Mac a app avisa quando há uma versão nova e abre a página da release, mas não se substitui sozinha.

### Compilar

Precisa do Xcode 26 (para o Liquid Glass).

```
cd macos
swift test                     # testes do protocolo e da contagem
swift run IqosMonitor --demo   # experimentar com IQOS simulados
./build-app.sh                 # gera build/IqosMonitor.app e build/IqosMonitor-macOS.zip
open build/IqosMonitor.app --args --demo
```

Para o Bluetooth e as notificações use o `.app` gerado pelo `build-app.sh`: o macOS só os autoriza a apps com `Info.plist`.

| Ficheiro | O quê |
|---|---|
| `macos/Sources/IqosCore/` | protocolo, contagem e alertas (tradução de `protocol.py` e `tracker.py`) |
| `macos/Sources/IqosMonitor/Bluetooth.swift` | ligação CoreBluetooth, reconexão e telemetria |
| `macos/Sources/IqosMonitor/Views.swift` | painel da barra de menus, anéis de bateria e definições |
| `macos/Sources/IqosMonitor/CornerPopup.swift` | janela no canto com a animação do holder |
| `macos/Sources/IqosMonitor/Glass.swift` | cores e estilos partilhados (fundos dos módulos, linhas de menu) |

Quem mexer nas regras de contagem em `tracker.py` deve fazer a mesma alteração em `macos/Sources/IqosCore/Tracker.swift` (os testes dos dois lados são os mesmos).

## Experimentar sem IQOS

```
IqosMonitor.exe --demo
```

Abre dois IQOS simulados que vão "fumando" e carregando, para ver os avisos a funcionar.

## Desenvolvimento

```
pip install -r requirements.txt pytest
python -m iqos_monitor --demo
python -m pytest
build.bat            # gera dist\IqosMonitor.exe
```

| Ficheiro | O quê |
|---|---|
| `iqos_monitor/protocol.py` | UUIDs BLE, comandos e interpretação das tramas |
| `iqos_monitor/ble.py` | ligação via [bleak](https://github.com/hbldh/bleak), reconexão, simulador |
| `iqos_monitor/tracker.py` | contagem, estimativa e alertas (sem Bluetooth, testável) |
| `iqos_monitor/gui.py` | janela PySide6, ícone na barra e notificações |
| `iqos_monitor/updater.py` | atualizações a partir das releases do GitHub |

## Publicar uma versão nova

Na página do repositório: **Releases → Draft a new release**, escreva uma tag nova (por exemplo `v0.2.0`) e carregue em **Publish release**. Ou, na linha de comandos:

```
git tag v0.2.0
git push origin v0.2.0
```

O GitHub Actions corre os testes, gera o `.exe` no Windows, calcula o SHA-256 e cria a release. Junta também o `IqosMonitor-macOS.zip`, compilado num Mac do GitHub. As apps instaladas encontram-na em até 6 horas (ou logo, em **Procurar atualizações**), confirmam o SHA-256, trocam o executável e reiniciam.

## Como funciona o protocolo

O protocolo do IQOS não é público. Esta app usa o que a comunidade descobriu por engenharia inversa:

- **Bateria**: notificações da característica `f8a54120-b041-11e4-9be7-0002a5d5c51b`. O byte 2 é a bateria do carregador; quando a trama tem 7 bytes o holder está no carregador e o byte 6 é a bateria dele. ([iQOS.js](https://github.com/mluis/iQOS.js), [iqos-api](https://github.com/iYasha/iqos-api))
- **Contador de utilizações e voltagem**: pedidos na característica SCP `e16c6e20-b041-11e4-a4c3-0002a5d5c51b`. O contador total (tag `0x8E`) sobe 1 por cada cigarro, e é assim que a app sabe que um cigarro terminou. ([V-VX/iqos](https://github.com/V-VX/iqos))
- Se o dispositivo não responder ao contador, a app conta pelo holder: sai do carregador e volta com menos 25% de bateria, conta como um cigarro.

Pode variar entre modelos e firmwares. Foi feito a pensar na família ILUMA, e nos IQOS 3 / DUO com Bluetooth só a bateria é garantida.

## Licença

GPL-3.0, como os projetos em que o protocolo se baseia. Projeto independente, sem ligação à Philip Morris International.
