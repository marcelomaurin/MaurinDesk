# Diagnóstico de comunicação — 0.6.3

Atualização 0.6.4: quando os quadros são recebidos e decodificados, mas a imagem aparece preta, atualizar o host com `bin/MaurinDesk.exe`. Foi corrigido o cache de pixels da captura GDI antes da codificação JPEG, com teste nativo que reproduziu a falha. Recomenda-se atualizar os dois participantes.

O estado `accepted` confirma que o PHP recebeu uma decisão de aceite do destino. Não confirma transmissão ou exibição de imagens.

## Atualização

1. Copiar os arquivos atualizados de `server/api/` para `public_html/MaurinDesk/api/`, preservando o `.env` do servidor.
2. Fechar a versão anterior e executar `bin/MaurinDesk.exe` atualizado nos dois computadores. O nome é fixo; conferir a versão na interface e em `bin/manifest.json`. A identidade permanece no perfil existente.
3. Solicitar e aceitar uma nova sessão. Conferir `[PHP COMUNICACAO]`, `[PHP REDE]` e `[PHP ETAPA]` nos logs dos dois computadores.

As alterações estão preparadas localmente; não representam publicação no servidor.

## Status compartilhado pelo PHP

`GET /sessions/{id}`, autenticado com o token do participante, passa a retornar `data.communication` após o aceite e enquanto a sessão estiver autorizada. Esse objeto contém:

- `host` e `requester`: IP público observado pelo PHP no anúncio de rede, IP local informado pelo aplicativo, porta anunciada, versão, último heartbeat, `online` e `endpoint_fresh`.
- `status`: `waiting_host_frame` quando o PHP ainda não recebeu imagens; `frame_available` quando há uma imagem recente; `frame_stalled` quando a última imagem foi enviada há 15 segundos ou mais.
- `frame_id`, `frame_uploaded_at`, `server_time`: último quadro e horários Unix em UTC.
- `events`: sequência de marcos da comunicação registrados pelo servidor.

IPs são informações de diagnóstico, não prova de que uma porta seja acessível. IPs antigos permanecem identificados por `endpoint_fresh=false`. O IP local é informado pelo aplicativo; o IP público vem de `REMOTE_ADDR`, sem confiar em `X-Forwarded-For`. A ponte HTTPS não depende da abertura da porta P2P.

## Marcos da sessão

| Evento | O que o PHP observou |
|---|---|
| `session.requested` | Pedido gravado pelo PHP |
| `session.delivered` | Pedido incluído em uma resposta de consulta do destino |
| `session.accepted` | Aceite recebido do destino |
| `relay.viewer_polling` | Controlador consultou imagens na ponte |
| `relay.first_frame_uploaded` | Primeiro quadro gravado pelo PHP |
| `relay.first_frame_served` | PHP preparou a primeira resposta com imagem para o controlador |

`session.delivered` e `relay.first_frame_served` indicam respostas produzidas pela API. A exibição da imagem é confirmada no aplicativo pelo log `[PONTE CLIENTE] Primeiro JPEG recebido e decodificado`, que informa também o número do quadro. O servidor não declara que uma resposta foi renderizada na tela.

Se houver aceite e consultas, mas nenhum `relay.first_frame_uploaded`, conferir o log `[PONTE HOST]` no destino: captura, compactação ou envio podem estar falhando. Se o quadro foi disponibilizado e o visualizador não o decodificou, conferir `[PONTE CLIENTE ERRO]` no controlador.

## Consulta do log PHP

Os marcos ficam persistidos em `audit_events` e aparecem no `error_log` configurado pela hospedagem com o prefixo `[MaurinDesk]`, em formato JSON. Cada linha informa evento, sessão, participante, IP de origem, horário e `request_id`. Falhas incluem rota, código e status HTTP. Cabeçalhos de autorização e dados JPEG não são registrados por essa instrumentação.

O arquivo efetivo do `error_log` depende da configuração PHP da hospedagem. Na Hostinger, consultar os logs PHP disponibilizados pelo painel. Não criar um arquivo público de log dentro de `public_html`.

Exemplo de consulta no banco, substituindo o identificador pela sessão desejada:

```sql
SELECT event_type, actor_id, occurred_at
FROM audit_events
WHERE session_id = 'ID-DA-SESSAO'
ORDER BY occurred_at, id;
```

Nenhuma migração nova é necessária. A verificação do banco agora detecta tabelas ausentes mesmo quando `VERSAO` já marca `0.6` e executa o reparo existente.
