# Histórico

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
