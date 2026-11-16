# Desktop Lazarus — 0.6.8

Documento técnico; a apresentação do produto está no [README principal](../README.md) e o índice técnico em [docs/README.md](../docs/README.md).

Cliente Windows x64 com tela remota, controle, gerenciador de arquivos local/remoto, clipboard de texto/arquivos, favoritos, histórico, área do relógio, instalação por usuário e atualizações pelo GitHub.

## Compilação

Manter este repositório e `CHATGPT` como diretórios irmãos. Requisito validado: Lazarus 4.6 / FPC 3.2.2.

```powershell
./build.ps1
```

A saída é sempre `bin/MaurinDesk.exe`. O script atualiza `bin/manifest.json` e `update.json` com o tamanho e o SHA-256 reais. Fechar o executável antes de recompilar. Não gerar nomes com versão no nome do arquivo.

Para gerar o instalador Windows (`bin/MaurinDesk-Setup.exe`) com Inno Setup 6, bibliotecas OpenSSL (`libssl-3-x64.dll` e `libcrypto-3-x64.dll` em `bin/`) e inicialização automática com o Windows:

```powershell
powershell -ExecutionPolicy Bypass -File installer/build-installer.ps1
```

Na inicialização (`MaurinDesk.lpr`), `uDeskInstall.LoadLocalOpenSSL` prioriza e carrega as DLLs OpenSSL diretamente da pasta do executável. Em sessões remotas, `uScreenCapture` e `uRemoteViewer` suportam seleção de múltiplos monitores pelo visualizador (tanto via Ponte HTTPS quanto P2P), indicador visual verde/vermelho no topo mantendo o último quadro válido e desconexão automática após 20 segundos ininterruptos de erro de comunicação.

Para a IDE, abrir `desktop/MaurinDesk.lpi`. A biblioteca compartilhada fica em `CHATGPT/pacote/AI Communication/AIRemoteDesktop`.

## Execução e configurações

O primeiro uso registra a identidade automaticamente. Configurações: `%LOCALAPPDATA%\MaurinDesk\Setmain.cfg`, geridas por `TSetMain`. Tokens permanecem protegidos por DPAPI nos perfis do usuário separados por servidor.

O endereço de produção é `https://maurinsoft.com.br/MaurinDesk/api`. O clipboard requer a API com esquema `0.7` e o gerenciador de arquivos, o esquema `0.9`. Consulte [recursos da versão](../docs/14-recursos-desktop.md).

Para desenvolvimento, HTTP local só é aceito quando iniciado explicitamente:

```powershell
bin/MaurinDesk.exe --dev-local-api=http://127.0.0.1:18765/v1
```

`--minimized` inicia na área do relógio. `--self-test` verifica a criação e destruição da interface sem firewall nem rede. As opções de renderização de prévia também usam um perfil de teste em `build/ui-preview`.

Testes nativos: `tests/capture_regression.lpi`, `tests/desktop_features.lpi` e `tests/update_probe.lpi`. Testes do servidor: `tests/server/clipboard.php`, `tests/server/schema.php` e `tests/http_smoke.py`.
