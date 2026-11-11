# Andamento — 0.2.0
11/11/2026. Primeira implementação em C:/projetos/maurinsoft/MaurinDesk.

## Entregue e validado
| Parte | Implementação |
|---|---|
| API PHP | Registro recuperável com chave decimal de 10 posições; segredo/token com hash no servidor |
| Presença | Heartbeat com expiração após 45 s sem atualização |
| Pedidos | Criar, listar para o host, consultar como participante, cancelar e encerrar |
| Consentimento | Só host decide; concessão como subconjunto; host não aceita duas sessões simultâneas |
| Integridade | Transações SQLite, índice UNIQUE de chave/host, idempotência de 24 h e expiração na leitura |
| Limites | Registro por IP, pedidos por dispositivo/destino e tamanho máximo de corpo |
| Desktop | Lazarus Windows x64; própria chave, solicitação, decisões, polling, favoritos e encerramento |
| Identidade local | CSPRNG e DPAPI, arquivos separados por servidor; token válido reutilizado |
| Transporte de API | WinHTTP HTTPS nativo, sem redirecionamento ou relaxamento de certificado |
| Código comum | Novo pacote runtime no CHATGPT; dependência fixada em dependencies/chatgpt.json |

A API usa SQLite nesta etapa. A seleção inicial de MySQL para produção permanece pendente.
O desktop consome diretamente unidades da biblioteca irmã; não há cópia dos componentes no MaurinDesk.

## Evidência executada no ambiente local
- PHP 8.3.36-1 portátil obtido da distribuição oficial Windows, checksum SHA-256 conferido.
- Sintaxe de todos os cinco arquivos PHP verificada.
- Suite server/php/tests/run.php: **29 verificações aprovadas**.
- Script tests/http_smoke.py: **4 cenários HTTP aprovados** (JSON inválido, array em vez de objeto, payload excessivo e rota privada).
- Suite CHATGPT test_airemote_foundation: **8 verificações aprovadas**, incluindo DPAPI e bloqueio de HTTP remoto.
- tests/signaling_probe.lpr: **7 cenários aprovados** com cliente Windows real e servidor PHP local.
- Pacote openai_remote_desktop.lpk compilado.
- Desktop compilado com Lazarus 4.6 e FPC 3.2.2 para Windows x64.
- Executável iniciado em modo --self-test: criação/destruição do formulário concluídas, saída 0.
- Integração de automação visual indisponível no ambiente: layout e cliques não foram validados visualmente.

Os testes de integração usaram loopback de desenvolvimento explicitamente habilitado. Não representam teste
de produção no domínio, TLS com certificado inválido, redes NAT ou controle de outra máquina.
O cliente de produção mantém verificação TLS padrão do WinHTTP e não habilita flags de ignorar certificado.

## Pendências
- Captura de desktop, visualizador, codificação e transmissão de quadros.
- Mouse/teclado com verificação local de permissões, geometria/DPI e limpeza de teclas.
- Sinalização SDP/ICE, tokens de sessão, canais WebRTC e TURN.
- Rotação/exclusão de dispositivo por endpoint; recuperação de registro já reemite e revoga token anterior.
- Heartbeat de sessão, ready, estado active e watchdog de canal.
- Incoming com cursor; nesta versão é snapshot limitado a 100 pedidos pendentes.
- MySQL e testes de concorrência em múltiplos processos/carga.
- Auditoria completa de expirações, limpeza periódica e retenção.
- OpenAPI completo, instalador, atualização automática e validação visual.
- Publicação da API oficial; nenhum acesso à hospedagem foi realizado.

## Estados nesta versão
pending → accepted/rejected/cancelled/expired; accepted → closed/expired.
Aceite reserva apenas 30 s de negociação. Sem os próximos módulos, não haverá active, imagem
nem entrada remota. Métodos de API ainda inexistentes retornam erro e não autorizam transporte alternativo.

## Reprodução
Consulte server/php/README.md, desktop/README.md e o teste de integração em tests/signaling_probe.lpr.
O workflow .github/workflows/php-tests.yml executa testes de PHP e fronteira HTTP no GitHub.
O executável fica em bin/MaurinDesk.exe e não é versionado junto dos fontes.
