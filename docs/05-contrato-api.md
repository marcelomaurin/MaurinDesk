# Contrato proposto de API v1

**Contrato alvo. A implementação 0.2.0 cobre um subconjunto; veja [andamento](10-implementacao.md). A API oficial ainda não foi publicada.** Base: `https://maurinsoft.com.br/maurindesk/api/v1/`.

## Convenções
JSON UTF-8, HTTPS, sem cookies de sessão web. `Authorization: Bearer <token>` nas rotas privadas. Token nunca vai em URL. Chave pública: string com regex `^[0-9]{10}$`. IDs de dispositivo/sessão são UUIDs opacos. Horários RFC3339 UTC. Respostas privadas: `Cache-Control: no-store`. CORS desabilitado por padrão (cliente nativo). SQL parametrizado.

Sucesso: `{"data":{...},"request_id":"uuid"}`. Erro: `{"error":{"code":"SESSION_EXPIRED","message":"Pedido expirado."},"request_id":"uuid"}`. Nunca retornar stack trace ou SQL.

## Rotas
Todas as rotas abaixo são relativas à base v1.

| Método/rota | Autenticação | Entrada / resposta principal |
|---|---|---|
| GET health | Pública | Estado mínimo e versão; 503 quando dependência essencial indisponível |
| POST devices | Pública, limitada | registration_id, registration_secret, display_name, platform, app_version → device_id, public_key, device_token, expires_at |
| POST devices/token/rotate | Dispositivo | Emite novo token; revoga anterior atomicamente |
| POST devices/heartbeat | Dispositivo | capabilities → server_time e next_heartbeat_seconds |
| DELETE devices/me | Dispositivo | Desativa identidade, revoga tokens e encerra sessões; 204 |
| POST sessions | Dispositivo controlador | target_key, requested_permissions → id, state=pending, expires_at; 201 |
| GET sessions/incoming?after=cursor | Dispositivo host | Pedidos destinados ao próprio host, cursor e server_time |
| GET sessions/{id} | Participante com token de dispositivo | Estado, participantes, permissões e prazos |
| POST sessions/{id}/decision | Dispositivo host | decision=accept/reject, granted_permissions → estado |
| POST sessions/{id}/cancel | Dispositivo controlador | Cancela pedido pendente |
| POST sessions/{id}/credentials | Dispositivo participante | Emite token do próprio papel após aceite, nunca o do outro participante |
| POST sessions/{id}/signals | Sessão do participante | type=offer/answer/ice, payload → signal_id; 201 |
| GET sessions/{id}/signals?after=id | Sessão do participante | Sinais do outro participante, next_cursor |
| POST sessions/{id}/ready | Sessão do participante | Declara canal validado; active somente após ambos |
| POST sessions/{id}/heartbeat | Sessão do participante | Confirma liveness; retorna estado e prazos |
| POST sessions/{id}/close | Dispositivo ou sessão do participante | reason → estado terminal e revogação |
| GET sessions/{id}/ice-config | Sessão do participante | Lista ICE; credenciais TURN efêmeras, se configurado |

Tokens de dispositivo só acessam os próprios dispositivos e sessões em que participam. Tokens de sessão só acessam sua sessão e não aceitam pedidos, não registram dispositivos e não criam novas sessões.

## Registro e repetição segura
Antes do primeiro POST devices, cliente gera e salva `registration_id` aleatório de 128 bits e `registration_secret` de 256 bits usando CSPRNG. Servidor armazena só o hash do segredo de registro. Em repetição com mesmo ID e segredo, mantém a chave e substitui o token de dispositivo (o anterior é revogado). ID igual com segredo diferente é conflito sem revelar dados. O segredo de registro é credencial de recuperação, protegido como o token e nunca logado. Registro repetido é limitado e auditado.

Nas mutações autenticadas, exigir `Idempotency-Key` UUID, com retenção de 24 h. Mesma chave e mesmo corpo devolvem o mesmo resultado; corpo diferente devolve 409. Tokens devolvidos em registro/rotação não podem ser armazenados em claro no cache genérico de idempotência: usar o fluxo específico de reemissão com revogação. Repetição de decisão nunca amplia permissão nem ressuscita sessão terminal.

## Exemplos fictícios
Criar pedido, com token do controlador e Idempotency-Key:

```json
{"target_key":"0123456789","requested_permissions":["screen.view","input.mouse","input.keyboard"]}
```

Resposta 201:

```json
{"data":{"id":"11111111-1111-4111-8111-111111111111","state":"pending","expires_at":"2026-11-11T15:01:00Z"},"request_id":"22222222-2222-4222-8222-222222222222"}
```

Aceite pelo host, permitindo só visualizar:

```json
{"decision":"accept","granted_permissions":["screen.view"]}
```

Permissões concedidas devem ser subconjunto das solicitadas e incluir screen.view. Mouse e teclado são independentes; eventos sem a respectiva permissão são descartados no host. Alterar permissões durante uma sessão não faz parte do MVP: encerrar e criar novo pedido.

## Sinalização e identidade do canal
Offer/answer contêm SDP com fingerprint DTLS. API aceita offer do controlador e answer do host, uma negociação por sessão; ICE pode vir dos dois. Não aceitar tipo arbitrário. SDP e ICE só ficam disponíveis após aceite e apenas ao outro participante. O token não é enviado dentro do SDP nem do DataChannel. Credenciais TURN não incluem segredo permanente do servidor.

Cada sinal tem sequência do servidor. Leitura não apaga sinal: cursor permite repetição e cliente deduplica pelo id. Limite: 100 sinais por página, payload de sinal até 64 KiB, 256 candidatos por participante, corpo HTTP até 128 KiB. Validar campos, tipos e tamanho antes de persistir. Expiração aplica-se mesmo antes do job de limpeza.

## Códigos HTTP
| HTTP | Código típico | Uso |
|---|---|---|
| 400 | VALIDATION_ERROR | JSON/campos/chave inválidos |
| 401 | UNAUTHORIZED | Token ausente, expirado ou revogado |
| 403 | FORBIDDEN | Papel/permissão inadequados |
| 404 | NOT_FOUND / TARGET_UNAVAILABLE | Recurso alheio ou destino inexistente/offline; não expor diretório público |
| 409 | INVALID_STATE / HOST_BUSY / IDEMPOTENCY_CONFLICT | Transição ou concorrência inválida |
| 410 | SESSION_EXPIRED | Sessão do participante já expirada |
| 413 | PAYLOAD_TOO_LARGE | Corpo excedente |
| 429 | RATE_LIMITED | Retornar Retry-After |
| 503 | SERVICE_UNAVAILABLE | API, banco ou relay essencial indisponível |

## Término e validade
Close é idempotente, permitido aos dois participantes e torna inválidos tokens e sinais. Resposta ao próprio close é calculada antes de revogar o token usado; repetições autenticadas com token de dispositivo retornam o estado terminal. Recusa/cancelamento/expiração impedem emissão de credenciais. Heartbeat não reabre sessão nem estende o limite máximo de 2 h.

Contrato OpenAPI e testes de conformidade serão produzidos junto da implementação da API; este documento é a referência funcional inicial.
