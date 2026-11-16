# Executáveis MaurinDesk

Documento técnico; a apresentação do produto está no [README principal](../README.md).

- **MaurinDesk.exe** — Windows x64; a versão publicada está em [manifest.json](manifest.json). Todas as versões usam este mesmo nome.
- **MaurinDesk-Setup.exe** — Instalador Windows x64 (Inno Setup 6) por usuário (`%LOCALAPPDATA%\Programs\MaurinSoft\MaurinDesk`), já incluindo o executável, as bibliotecas OpenSSL e a opção de iniciar minimizado com o Windows.
- **libssl-3-x64.dll** e **libcrypto-3-x64.dll** — Bibliotecas OpenSSL 3.5.2 (x64) distribuídas junto ao executável e carregadas explicitamente da pasta do `.exe`.
- Compilado com Lazarus 4.6 / FPC 3.2.2; metadados e SHA-256 em [manifest.json](manifest.json).

Recursos disponíveis nesta versão:
1. **Identidade e Presença**: Registro automático com chave única de 10 dígitos e token criptográfico.
2. **Consentimento e Segurança**: Solicitação assistida de conexão; canal de streaming P2P com autenticação mandatória (`PKT_HELLO`), verificação de `SessionId`/`SessionToken` e bloqueio rigoroso de permissão ("Somente Visualizar" vs "Controle Total").
3. **Multi-Port Probing P2P**: Teste automático e negociação das portas TCP `7071`, `8080` e `9876` com abertura automática de regras de Firewall no Windows via UAC nativo.
4. **Modo Ponte Prioritário (HTTPS Relay)**: Conexão imediata via relay HTTPS com handshake rápido e fallback P2P sob demanda; validação estrita de permissões de mouse e teclado também no fluxo relay.
5. **Captura e Controle**: Renderização remota fluida com cursor visível na tela, injeção de mouse e teclado (com suporte a teclas estendidas), telemetria de primeiro quadro e diagnóstico integrado de falhas de envio.

O teste de inicialização `--self-test` foi executado e validado com sucesso.

Novo nesta versão: layout com diagnóstico recolhível; clipboard de texto, arquivos e pastas; nomes no histórico; configurações `TSetMain`; instalação por usuário; início com o Windows; área do relógio; atualizações do GitHub com SHA-256 e validação da versão do arquivo. Veja [orientações](../docs/14-recursos-desktop.md).

Correções 0.6.6: ícone real embutido; proteção contra Enter/espaço acionarem “Desconectar”; menu “Arquivos e pastas” no visualizador e na janela principal; confirmação de recebimento na API 0.8; identificação da origem e motivo do encerramento.
