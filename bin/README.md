# Executáveis MaurinDesk

- **MaurinDesk.exe** — Versão 0.6.2, Windows x64.
- Compilado com Lazarus 4.6 / FPC 3.2.2 nativo (sem DLLs externas).
- SHA-256 e metadados detalhados em [manifest.json](manifest.json).

Recursos disponíveis nesta versão:
1. **Identidade e Presença**: Registro automático com chave única de 10 dígitos e token criptográfico.
2. **Consentimento e Segurança**: Solicitação assistida de conexão; canal de streaming P2P com autenticação mandatória (`PKT_HELLO`), verificação de `SessionId`/`SessionToken` e bloqueio rigoroso de permissão ("Somente Visualizar" vs "Controle Total").
3. **Multi-Port Probing P2P**: Teste automático e negociação das portas TCP `7071`, `8080` e `9876` com abertura automática de regras de Firewall no Windows via UAC nativo.
4. **Modo Ponte Prioritário (HTTPS Relay)**: Conexão imediata via relay HTTPS com handshake rápido e fallback P2P sob demanda; validação estrita de permissões de mouse e teclado também no fluxo relay.
5. **Captura e Controle**: Renderização remota fluida com cursor visível na tela, injeção de mouse e teclado (com suporte a teclas estendidas), telemetria de primeiro quadro e diagnóstico integrado de falhas de envio.

O teste de inicialização `--self-test` foi executado e validado com sucesso.
