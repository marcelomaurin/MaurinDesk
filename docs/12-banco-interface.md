# Banco para a interface desktop — versão 0.2

> Publicação simplificada: server/ contém somente api/, sem subpastas. Copie api/ para public_html/maurindesk/api/. Veja [instalação atual](08-implantacao.md).

11/11/2026. A imagem de referência orienta a organização dos dados; não altera a chave de acesso de 10 dígitos nem o consentimento por sessão.

| Elemento da interface | Tabela / origem | Campos ou regra |
|---|---|---|
| Minha identificação | devices | public_key, string com 10 dígitos, preservando zeros |
| Nome deste computador | devices | display_name, editável e preservado na recuperação |
| Cartões e agenda | device_contacts | remote_key, alias, group_name, color, sort_order |
| Favoritos | device_contacts | is_favorite; único por owner_device_id + remote_key |
| Recentes | sessions + devices + apelido próprio | até 50 pedidos/sessões, direção, estado e datas |
| Estado do computador remoto | devices + autorização anterior | online por heartbeat recente, offline após 45 s, unknown sem relação autorizada |
| Idioma e aparência | device_preferences | language, theme, view_mode, sort_by |
| Pedidos recebidos | sessions | rota incoming existente; autorizar continua obrigatório |
| Versão e histórico do banco | params / schema_migrations | VERSAO: 0.1 → 0.2, histórico antes de atualizar a versão |

Miniaturas e captura de tela permanecem no desktop. Favoritos não armazenam autorização, senhas ou IPs. O agrupamento é apenas visual e não compartilha a agenda com outras máquinas.

## Contrato de API

Rotas relativas a `https://maurinsoft.com.br/maurindesk/api/v1/`. Exigem Bearer do próprio dispositivo. PATCH, POST e DELETE exigem Idempotency-Key UUID.

| Método / rota | Uso |
|---|---|
| GET desktop | Dados para montar a tela inicial: device, preferences, contacts, favorites, recent_devices, recent_sessions |
| PATCH devices/me | Alterar display_name, até 80 bytes UTF-8 |
| PATCH desktop/preferences | language (ex. pt-BR), theme=system/light/dark, view_mode=cards/list, sort_by=last_used/name |
| GET contacts | Até 500 contatos da instalação; favoritos primeiro, depois sort_order e alias |
| POST contacts | Criar ou atualizar pela remote_key; não exige que a chave esteja online |
| PATCH contacts/{id} | Alterar apelido/grupo/favorito/cor/ordem de um contato próprio |
| DELETE contacts/{id} | Remover contato; mantém o histórico de sessões |
| GET sessions/recent | Últimas 50 sessões do solicitante autenticado |

Exemplo de contato:

```json
{"remote_key":"0123456789","alias":"Computador trabalho","group_name":"Saúde","is_favorite":true,"color":"#3B82F6","sort_order":0}
```

Grupos e apelidos aceitam até 80 bytes UTF-8. is_favorite deve ser booleano. A cor deve ser #RRGGBB. sort_order deve ser inteiro entre 0 e 1000000. A própria chave não pode ser adicionada como contato remoto. Credenciais de outro dispositivo não consultam ou modificam esses registros.

Recentes usam o estado real da negociação: um pedido aceito não é apresentado como prova de transporte conectado. O campo was_authorized informa somente que houve concessão de permissões. O histórico não concede acesso nem reutiliza consentimento.

## Migração automática

Instalação nova registra primeiro a base 0.1 e depois a migração 0.2. Instalação em 0.1 aplica apenas a mudança pendente. A migração cria preferências para as máquinas existentes e a tabela de contatos, preservando identidades, tokens, sessões e parâmetros. As novas tabelas são recriadas se estiverem ausentes, sem apagar as existentes.

Mudanças de cada versão ficam em schema_migrations. O parâmetro VERSAO só avança após o SQL e o registro da mudança concluírem. SQL MySQL idempotente permite retomar após DDL parcialmente aplicado; no SQLite a migração é transacional.

## Validação

95 verificações de API aprovadas, incluindo isolamento da agenda, persistência, recuperação de nome, favoritos, presença e ausência de IPs/credenciais nos cartões. 20 verificações de schema aprovadas, incluindo banco legado 0.1, migração interrompida, repetição e preservação de dados. 9 cenários HTTP aprovados, incluindo PATCH de preferências e carga da tela inicial.

MySQL/MariaDB e Apache/LiteSpeed permanecem com execução pendente no ambiente da hospedagem/CI. A interface desktop e a importação de favorites.ini ainda não foram alteradas. O pacote e o patch são a entrega; a pasta D:/projetos/maurinsoft/MaurinDesk não foi modificada nesta sessão por restrição de escrita.
