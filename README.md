# MaurinDesk

**Versão 0.6.6:** ícone próprio na área do relógio, correção de desconexão por Enter/espaço e comandos para enviar arquivos/pastas e abrir os recebidos. Mantém layout moderno, clipboard bidirecional, histórico, `fsetmain`, instalação e atualização pelo GitHub. Executável: [bin/MaurinDesk.exe](bin/MaurinDesk.exe). Veja [como usar e atualizar](docs/14-recursos-desktop.md).

Acesso remoto assistido, inspirado no fluxo de uso do AnyDesk, com cliente desktop Lazarus/Free Pascal nativo e servidor PHP exclusivamente de APIs e sinalização/relay.

**Estado atual (v0.6.6):** transmissão de tela e controle autenticado por HTTPS Relay/P2P, clipboard e envio de arquivos/pastas após consentimento, histórico com apelidos e atualização verificada por SHA-256. O nome distribuído é sempre `MaurinDesk.exe`.

## Funcionamento

1. Cada instalação registra sua identidade e recebe uma chave única de **10 dígitos**.
2. A aplicação mostra a própria chave e permite informar a chave de outro computador.
3. O computador de destino recebe uma solicitação e seu usuário aceita com controle total ou apenas visualização.
4. Somente após aceitar na API, o canal de streaming P2P é liberado:
   - O canal exige autenticação mandatória no handshake (`PKT_HELLO`) com verificação estrita do `SessionId` e token da sessão.
   - Conexões não autenticadas ou com chave/sessão divergentes são descartadas imediatamente com fechamento de socket.
   - Se o consentimento concedido foi "apenas visualização", o host bloqueia qualquer comando de entrada na raiz.
5. Conectividade robusta (P2P + Ponte):
   - Probing automático de portas TCP (`7071`, `8080`, `9876`) com criação automática de regras no Firewall do Windows.
   - Caso o host e o controlador estejam atrás de NATs sem loopback ou bloqueios estritos, o sistema entra automaticamente em **Modo Ponte (Server Relay)** pelo servidor HTTPS.
6. O solicitante pode salvar a chave com um apelido para reconectar. Cada nova sessão exige nova autorização.
7. Qualquer participante pode encerrar; o fechamento da aplicação é imediato e não bloqueante.

**Endereço oficial de conexão:** https://maurinsoft.com.br/MaurinDesk/api/  
**Base versionada:** https://maurinsoft.com.br/MaurinDesk/api/v1/

## Servidor Atualizado

Servidor oficial: `https://maurinsoft.com.br/MaurinDesk/api/`. Copie os arquivos da pasta `server/api/` para `public_html/MaurinDesk/api/`, preservando o `.env`. As migrações (`0.1` a `0.8`) são automáticas e idempotentes. O clipboard básico requer esquema `0.7`; a confirmação de recebimento usa `0.8`.

Veja também o [mapeamento do banco para a interface](docs/12-banco-interface.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [Visão e escopo](docs/01-visao-escopo.md) | Produto, atores e limites |
| [Requisitos funcionais](docs/02-requisitos-funcionais.md) | Comportamentos e critérios de aceite |
| [Requisitos não funcionais](docs/03-requisitos-nao-funcionais.md) | Segurança, desempenho e operação |
| [Arquitetura](docs/04-arquitetura.md) | Componentes, estados, transporte e persistência |
| [Contrato das APIs](docs/05-contrato-api.md) | Rotas, autenticação, exemplos e erros |
| [Integração CHATGPT](docs/06-integracao-chatgpt.md) | Reuso existente e componentes a desenvolver |
| [Plano e validação](docs/07-plano-validacao.md) | Etapas e testes de aceite |
| [Implantação](docs/08-implantacao.md) | Requisitos do servidor e publicação futura |
| [Registro de decisões](docs/09-decisoes.md) | Motivos e pendências técnicas |
| [Implementação 0.2.0](docs/10-implementacao.md) | Código entregue, evidências e pendências atuais |

## Código e compilação

- `desktop/`: projeto Lazarus, formulários, favoritos e identidade visual MaurinDesk.
- `server/api/`: API, migrações, configuração e testes.
- `docs/`: especificação e evidências de validação.
- [CHATGPT](https://github.com/marcelomaurin/CHATGPT): componentes Pascal reutilizáveis de captura, entrada remota, transporte e sessão.

Consulte [desktop/README.md](desktop/README.md) para compilar e [docs/08-implantacao.md](docs/08-implantacao.md) para executar a API. O [andamento](docs/10-implementacao.md) distingue código validado e pendências. A biblioteca CHATGPT é um framework de componentes Lazarus; o acesso remoto não depende de um modelo de IA nem do envio da tela a um provedor de IA.

## Estado da infraestrutura

O endereço oficial foi definido pelo proprietário. Sua disponibilidade e o suporte de hospedagem a PHP, banco, TURN e conexões persistentes ainda precisam de validação; esta documentação não representa implantação.

## Executável Windows

A pasta [bin](bin/) contém o [MaurinDesk.exe](bin/MaurinDesk.exe) para Windows x64, com versão e SHA-256 em [manifest.json](bin/manifest.json).

O [update.json](update.json) informa ao aplicativo qual versão está publicada na branch `fila`. Execute `./build.ps1` para compilar o nome padrão e atualizar os dois JSONs com o tamanho e o hash reais do executável.
