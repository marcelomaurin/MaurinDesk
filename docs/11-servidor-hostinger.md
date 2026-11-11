# Ajuste do servidor — 11/11/2026

> Publicação simplificada: server/ contém somente api/, sem subpastas. Copie api/ para public_html/maurindesk/api/. Veja [instalação atual](08-implantacao.md).

> Atualização posterior: [banco para a interface, versão 0.2](12-banco-interface.md). A base inicial 0.1 deste documento é preservada no histórico.

## Decisões atuais

- Servidor oficial: `https://maurinsoft.com.br/maurindesk/`.
- API versionada: `/maurindesk/api/v1/`; entrada HTTP em `server/api/index.php`.
- MySQL/MariaDB para Hostinger; SQLite para testes locais.
- Criação automática das tabelas. `params(chave, valor)` recebe `VERSAO=0.1` inicialmente.
- Atualização: ler versão atual, aplicar SQL pendente, registrar descrição/data em `schema_migrations`, atualizar `VERSAO` por último. Falhas mantêm a versão anterior.
- PHP registra os endpoints e os entrega exclusivamente aos dois participantes após consentimento. Imagens e eventos não passam pela API.

## Contrato acrescentado

| Método e rota relativa à API | Comportamento |
|---|---|
| GET health | Inicializa/atualiza o schema e retorna status e versão do banco |
| POST devices/endpoint | Bearer + Idempotency-Key; corpo port inteiro 1024–65535 e transport=tcp; registra REMOTE_ADDR e porta por 45 s |
| GET sessions/{id}/peer | Bearer do participante; somente após aceite devolve endpoint recente do outro participante e permissões |

Erros novos: `CONSENT_REQUIRED` (403), `PEER_UNAVAILABLE` (409), `SESSION_ENDED` (410), `INVALID_SOURCE_ADDRESS` (400). O campo `reachability=unverified` informa que a porta não foi testada pelo servidor. A autorização de sessão não substitui a autenticação e a criptografia do futuro canal desktop.

## Evidências desta alteração

- 52 verificações de identidade, consentimento e descoberta P2P aprovadas em PHP 8.3.36/PDO SQLite.
- 13 verificações de schema aprovadas, incluindo criação, reparo, preservação, falha de migração, repetição e bloqueio de downgrade.
- Fronteira HTTP com instalação automática, prefixo /maurindesk/api/v1, raiz do servidor, formato JSON, autenticação e rejeição de IP forjado por cabeçalho.
- Workflow preparado para MySQL 8.0 e MariaDB 11.4; execução nesses dois bancos e validação Apache/LiteSpeed ainda pendentes.
- Desktop e binário permanecem 0.2.0; listener, tela e controle ainda pendentes. Nenhum upload na hospedagem foi realizado.

Os documentos originais 01–07 e 09–10 registram a proposta/entrega anterior. Para o servidor, este documento e docs/08-implantacao.md prevalecem sobre propostas de TURN/WebRTC ou instalação manual de banco.
