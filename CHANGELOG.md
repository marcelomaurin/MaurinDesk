# Histórico

## Banco 0.2 — suporte à interface desktop em 11/11/2026
- Migração ordenada da base 0.1, com histórico e versão atualizada por último.
- Preferências por instalação: idioma, tema, visualização e ordenação.
- Agenda e cartões com chave remota, apelido, grupo, favorito, cor e posição.
- APIs autenticadas para tela inicial, contatos, preferências, nome e sessões recentes.
- Nome escolhido preservado na recuperação; agenda isolada por dispositivo.
- Presença expira em 45 s; miniaturas e tráfego de tela permanecem locais/P2P.

## Servidor / schema 0.1 — ajuste Hostinger em 11/11/2026
- Métodos HTTP centralizados em server/php/api; domínio oficial /maurindesk/.
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
