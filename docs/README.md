# Documentação técnica — MaurinDesk

Referência para quem desenvolve, compila, publica ou mantém o MaurinDesk. Para a apresentação do produto, veja o [README principal](../README.md); para aprender a usar o programa, o [guia do usuário](14-recursos-desktop.md).

## Por onde começar

| Preciso de… | Documento |
|---|---|
| Compilar e executar o aplicativo Windows | [desktop/README.md](../desktop/README.md) |
| Conferir o executável publicado e seus metadados | [bin/README.md](../bin/README.md) |
| Publicar a API na hospedagem | [08 — Implantação](08-implantacao.md) e [11 — Servidor](11-servidor-hostinger.md) |
| Investigar uma conexão que não mostra imagem | [13 — Diagnóstico de comunicação](13-diagnostico-comunicacao.md) |
| Entender o que mudou em cada versão | [15 — Notas de implementação](15-notas-desktop.md) e [histórico](../CHANGELOG.md) |

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `desktop/` | Aplicativo Windows em Lazarus/Free Pascal. |
| `server/api/` | API em PHP, com as migrações do banco (MySQL/MariaDB na hospedagem, SQLite nos testes). |
| `bin/` | Executável publicado, bibliotecas OpenSSL x64, instalador `MaurinDesk-Setup.exe` e `manifest.json`. |
| `installer/` | Script Inno Setup (`MaurinDesk.iss`) e automação (`build-installer.ps1`). |
| `tests/` | Testes da API (`tests/server/`), da fronteira HTTP e testes nativos do aplicativo. |
| `docs/` | Especificação, decisões, guias e imagens. |
| `dependencies/` | Versão validada da biblioteca compartilhada do repositório CHATGPT. |

## Especificação e projeto

1. [Visão e escopo](01-visao-escopo.md)
2. [Requisitos funcionais](02-requisitos-funcionais.md)
3. [Requisitos não funcionais](03-requisitos-nao-funcionais.md)
4. [Arquitetura](04-arquitetura.md)
5. [Contrato da API](05-contrato-api.md)
6. [Integração com o repositório CHATGPT](06-integracao-chatgpt.md)
7. [Plano de validação](07-plano-validacao.md)
8. [Decisões](09-decisoes.md)

## Implementação e operação

- [Andamento da implementação](10-implementacao.md)
- [Implantação](08-implantacao.md)
- [Servidor na hospedagem](11-servidor-hostinger.md)
- [Banco de dados da interface](12-banco-interface.md)
- [Diagnóstico de comunicação](13-diagnostico-comunicacao.md)
- [Notas de implementação e manutenção](15-notas-desktop.md)
- [Registro do início do projeto](log/2026-11-11-inicio.md)

## Regras de acesso em vigor

- Toda rota da API, exceto a verificação de estado e o registro inicial, exige a credencial do dispositivo; o envio de diagnóstico também, com limite de 20 envios por hora e 256 KiB por relatório.
- Uma sessão só existe entre dois dispositivos e depende do aceite do computador atendido, que define as permissões.
- No gerenciador de arquivos, somente quem iniciou a conexão com a chave lista, cria pastas e pede arquivos do outro computador. O computador atendido só envia o que foi pedido, para o destino pedido. A regra é aplicada na API (`server/api/FileExchange.php`) e no aplicativo (`desktop/uDeskFiles.pas`).

## Compilação e testes, em resumo

```powershell
./build.ps1                      # gera bin/MaurinDesk.exe e atualiza manifest.json e update.json
./installer/build-installer.ps1  # gera bin/MaurinDesk-Setup.exe com OpenSSL e autostart
php tests/server/files.php       # API: identidade, consentimento, área de transferência e arquivos
php tests/server/schema.php      # migrações do banco
python tests/http_smoke.py       # fronteira HTTP
```

Feche o MaurinDesk antes de compilar: com o executável aberto, a etapa final falha por acesso negado.
