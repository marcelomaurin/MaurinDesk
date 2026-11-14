# Histórico

## 0.6.8 — 14/11/2026

- Botão **Transferir arquivos** na barra do visualizador, com layout que acompanha a largura da janela, e no painel da sessão ativa da tela principal.
- O acesso ao gerenciador deixa de depender do cartão de descoberta, que pode ser ocultado conforme o tamanho da janela.
- Mensagem específica quando uma sessão foi aceita sem a permissão de arquivos, sem pedir para conectar novamente quando já está conectada.
- Verificado o acesso visível e clicável em larguras de 640, 800, 1024 e 1280 pixels, preservando o tratamento do teclado remoto.
- Segurança: somente quem iniciou a conexão com a chave lista, cria pastas e pede arquivos do outro computador. O computador atendido apenas atende a esses pedidos e só envia arquivos solicitados, para o destino solicitado; a regra vale na API e no aplicativo.
- Segurança: o envio de diagnóstico exige credencial válida de dispositivo registrado, com limite de 20 envios por hora e 256 KiB por relatório; a sessão só é associada quando o dispositivo participa dela.

## 0.6.7 — 14/11/2026

- Gerenciador de arquivos em dois painéis (local/remoto), navegação por unidades e pastas, filtro, paginação e criação de pastas.
- Enviar e receber múltiplos arquivos ou pastas para a pasta escolhida no painel de destino, com progresso e confirmação de gravação no disco.
- Arquivos existentes preservados por padrão; substituição explícita mescla pastas e mantém os outros arquivos. Transferência sem executar os arquivos recebidos.
- Permissão `files.transfer` no aceite de controle; visualização sozinha não dá acesso aos arquivos. Mensagens e partes binárias isoladas por sessão na API 0.9, com limpeza ao encerrar.
- Testes da API e dos dois serviços nativos contra o PHP local, incluindo binários, Unicode, pastas vazias, destinos finais e erros remotos.

## 0.6.6 — 14/11/2026
- Reproduzida e corrigida a desconexão acidental ao pressionar Enter no visualizador: foco dedicado à imagem remota e consumo das teclas remotas, evitando acionamento dos botões locais. Teclas pressionadas são liberadas ao perder foco.
- Ícone MaurinDesk multi-resolução incorporado ao executável e carregado explicitamente na área do relógio. O programa não fica oculto caso o Windows não confirme o ícone.
- Menu “Arquivos e pastas” no visualizador e na janela principal: selecionar múltiplos arquivos, enviar uma pasta e abrir a pasta local de recebidos, com estado da transferência visível.
- Confirmação de recebimento após preparar o clipboard no destino; arquivos aguardam essa confirmação antes de serem substituídos por outra cópia, quando ambos os clientes suportam o protocolo. Compatibilidade com a API/cliente anterior para transferência sem confirmação.
- Migração 0.8 para os comprovantes e atualização da versão instalada no heartbeat. Sessões encerradas informam autor e motivo aos dois participantes.
- Relatórios de diagnóstico deixam de alterar o estado de ocupação do worker principal de sessão.
- Testes: regressão de teclado (falhava com Enter antes da correção), ícones embutidos em 16/32/48 px, pacote com arquivo binário de 10 MiB, diretórios, confirmação de entrega e encerramento com origem identificada.

## 0.6.5 — 14/11/2026
- Layout claro com cartões, navegação entre conexões/favoritos/histórico, cópia de chave e diagnóstico recolhível; adaptação para janelas menores.
- Clipboard bidirecional de texto Unicode, arquivos, múltiplos itens e pastas com envio em partes e verificação de integridade. Novas rotas autenticadas e migração de banco `0.7`.
- Consentimento explícito `clipboard.sync`, incluído no aceite de controle; apenas visualização não compartilha clipboard. Prevenção de eco e preservação de cópias locais feitas durante o recebimento.
- Nome opcional associado à chave ao encerrar a sessão. Sem nome, a chave permanece como identificação.
- Adaptação de `TSetMain` para configurações persistentes em `Setmain.cfg`, mantendo tokens separados e importando o INI anterior.
- Ícone na área do relógio, reabertura e saída pelo menu; opções de iniciar ao entrar no Windows e de instalação na pasta do usuário com atalho no menu Iniciar.
- `update.json` publicado junto ao executável padrão. O aplicativo verifica versão numérica, origem fixa no GitHub, tamanho, SHA-256 e versão interna antes da substituição; aguarda o encerramento da sessão e preserva uma cópia anterior.
- `build.ps1` mantém `bin/MaurinDesk.exe`, `bin/manifest.json` e `update.json` consistentes. Removidos nomes de executáveis e manifestos com sufixo de versão.
- Testes de API/clipboard, esquema SQLite, pacote de arquivos Unicode/binários, configurações, atualização com substituição e reinício de executável de teste, e renderização do layout em dois tamanhos.

## 0.6.4 — 14/11/2026
- Corrigida a geração de JPEGs pretos: as operações nativas GDI de captura e desenho do cursor não notificavam o bitmap LCL, deixando o cache de pixels desatualizado na compactação.
- Sincronização das operações GDI e invalidação do cache após captura e antes da conversão para JPEG, nos fluxos relay e P2P.
- Teste nativo `tests/capture_regression.lpi`: imagem conhecida convertida para JPEG e decodificada com verificação das cores. Antes da correção, retornava RGB 0,0,0; após, RGB 231,40,21 para RGB esperado 230,40,20.
- Executável Windows x64: `bin/MaurinDesk.exe`. Nome de distribuição fixo para todas as versões, com metadados em `bin/manifest.json`. Atualizar o computador que compartilha a tela para corrigir a imagem enviada; recomendado usar a mesma versão nos dois participantes.

## 0.6.3 — 14/11/2026
- Diagnóstico PHP da sessão: IP público observado, IP local anunciado, presença, versão dos participantes e estado dos quadros, disponível aos dois participantes após o aceite.
- Eventos persistidos em `audit_events` e no log de erros do PHP: pedido, entrega pela API, aceite, consulta do visualizador, primeiro quadro recebido e primeira resposta com imagem.
- Erros da API registrados com identificador da requisição e IP de origem, sem tokens ou conteúdo da tela.
- Ponte HTTPS inicia independentemente do anúncio de porta P2P; visualizador respeita a permissão concedida.
- Aviso de espera sem quadros, confirmação do primeiro JPEG mesmo com sequência diferente de 1 e tratamento de falhas de captura, compactação e envio de comandos.
- Verificação de estrutura do banco antes de aceitar a versão como atual, restaurando tabelas ausentes da ponte.
- Binário de correção Windows x64; a distribuição usa o nome fixo `bin/MaurinDesk.exe`.
- Validação local: compilação Windows x64, testes de API/relay, migrações SQLite e fronteira HTTP. Conexão entre duas máquinas reais permanece pendente.

## 0.6.2 — 14/11/2026
- Inicialização da visualização remota com prioridade no HTTPS Relay antes da tentativa P2P.
- Aplicação rigorosa de autorizações de entrada (mouse e teclado) também no canal relay do servidor.
- Proteção de todos os endpoints de relay por sessão ativa e permissão concedida de tela.
- Registro em log do recebimento do primeiro frame de streaming e de falhas no envio da captura.
- Atualização da versão do desktop para v0.6.2 nos idiomas PT, EN e ES, na barra de status e nos logs de inicialização.
- Binário Windows x64 recompilado nativamente com Lazarus 4.6 / FPC 3.2.2 e manifesto atualizado.

## 0.6.1 — 12/11/2026
- Handshake obrigatório `PKT_HELLO` no canal P2P com conferência estrita de SessionId e token.
- Descarte imediato e fechamento de conexões não autenticadas ou com permissões divergentes.
- Compatibilidade do parser SQL com comentários multilinhas e sintaxe MariaDB/MySQL 8.


## Organização de publicação — 11/11/2026
- server/ contém somente api/, sem subpastas internas e com todos os arquivos de execução.
- Removidas a estrutura php/, CLI de migração e script de empacotamento do servidor.
- Testes movidos para tests/server/; publicação é copiar api/ para public_html/maurindesk/api/.
- Dependências privadas protegidas por .htaccess e carregadas pelo caminho local.
- Corrigida a expressão da coluna gerada active_host para normalizar CHAR com RTRIM no MariaDB.

## Banco 0.2 — suporte à interface desktop em 11/11/2026
- Migração ordenada da base 0.1, com histórico e versão atualizada por último.
- Preferências por instalação: idioma, tema, visualização e ordenação.
- Agenda e cartões com chave remota, apelido, grupo, favorito, cor e posição.
- APIs autenticadas para tela inicial, contatos, preferências, nome e sessões recentes.
- Nome escolhido preservado na recuperação; agenda isolada por dispositivo.
- Presença expira em 45 s; miniaturas e tráfego de tela permanecem locais/P2P.

## Servidor / schema 0.1 — ajuste Hostinger em 11/11/2026
- Métodos HTTP centralizados em server/api; domínio oficial /maurindesk/.
- Configuração .env e suporte MySQL/MariaDB, preservando SQLite para desenvolvimento.
- Criação automática de tabelas, params com VERSAO=0.1 e histórico em schema_migrations.
- Migrações consultam versão atual e só atualizam VERSAO após aplicar e registrar mudanças.
- Registro de IP observado/porta TCP e descoberta entre pares após consentimento.
- Anúncios expiram em 45 s; nenhum endereço entregue antes do aceite ou após encerramento.
- Desktop e binário permanecem 0.2.0; listener e transmissão continuam pendentes.

## 0.2.0 — 11/11/2026
- API PHP executável com SQLite: identidade única, registro recuperável, tokens com hash, presença, pedidos, consentimento, cancelamento e encerramento.
- Transações, host único, expiração, rate limits e idempotência nas mutações autenticadas.
- Desktop Lazarus Windows x64: registro, própria chave, solicitação, decisões locais, favoritos e polling fora da thread visual.
- Componentes comuns implementados no CHATGPT: CSPRNG, DPAPI e cliente JSON com HTTPS WinHTTP.
- Testes de API, fronteira HTTP, componentes e integração Windows/PHP.
- Captura, vídeo, entrada remota, sinalização WebRTC e TURN permanecem pendentes.

## 0.1.0-docs — 11/11/2026
- Definição do MaurinDesk como acesso remoto assistido em Lazarus e APIs PHP.
- Especificação de chave única de 10 dígitos, consentimento local e favoritos.
- Requisitos funcionais e não funcionais com critérios de aceite.
- Arquitetura, estados, persistência, contrato de API e plano de reuso CHATGPT.
- Plano de implementação, validação, implantação e decisões.
- Entrega exclusivamente documental; sem binários ou servidor implantado.
