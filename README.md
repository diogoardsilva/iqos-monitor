# IQOS Monitor

App para Windows que se liga por Bluetooth a um ou mais IQOS ao mesmo tempo e:

- mostra a bateria do carregador (ou do dispositivo, nos modelos ONE) e do holder;
- conta os cigarros fumados hoje e desde a última carga;
- estima quantos cigarros ainda dá para fumar com a carga atual, e aprende o consumo real de cada dispositivo;
- avisa quando cada cigarro termina, quando o holder tem de voltar ao carregador, quando a bateria está fraca e quando a carga fica completa;
- fica na área de notificação do Windows e reconecta-se sozinha;
- procura atualizações nas releases do GitHub e instala-as sozinha.

## Instalar

1. Descarregue `IqosMonitor.exe` da [última release](../../releases/latest).
2. Abra-o. Na primeira vez, o Windows pode mostrar o aviso do SmartScreen porque o executável não está assinado: carregue em **Mais informações → Executar mesmo assim**.
3. Ative o Bluetooth no Windows.
4. Ponha o IQOS em modo de emparelhamento (veja o manual do seu modelo) e carregue em **Adicionar IQOS**.

O IQOS só aceita uma ligação de cada vez. Se a app IQOS do telemóvel estiver ligada, desligue-a primeiro.

Os dados ficam em `%APPDATA%\IqosMonitor\` (`state.json` e `iqos-monitor.log`).

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

O GitHub Actions corre os testes, gera o `.exe` no Windows, calcula o SHA-256 e cria a release. As apps instaladas encontram-na em até 6 horas (ou logo, em **Procurar atualizações**), confirmam o SHA-256, trocam o executável e reiniciam.

## Como funciona o protocolo

O protocolo do IQOS não é público. Esta app usa o que a comunidade descobriu por engenharia inversa:

- **Bateria**: notificações da característica `f8a54120-b041-11e4-9be7-0002a5d5c51b`. O byte 2 é a bateria do carregador; quando a trama tem 7 bytes o holder está no carregador e o byte 6 é a bateria dele. ([iQOS.js](https://github.com/mluis/iQOS.js), [iqos-api](https://github.com/iYasha/iqos-api))
- **Contador de utilizações e voltagem**: pedidos na característica SCP `e16c6e20-b041-11e4-a4c3-0002a5d5c51b`. O contador total (tag `0x8E`) sobe 1 por cada cigarro, e é assim que a app sabe que um cigarro terminou. ([V-VX/iqos](https://github.com/V-VX/iqos))
- Se o dispositivo não responder ao contador, a app conta pelo holder: sai do carregador e volta com menos 25% de bateria, conta como um cigarro.

Pode variar entre modelos e firmwares. Foi feito a pensar na família ILUMA, e nos IQOS 3 / DUO com Bluetooth só a bateria é garantida.

## Licença

GPL-3.0, como os projetos em que o protocolo se baseia. Projeto independente, sem ligação à Philip Morris International.
