# API PHP — implementação inicial 0.2.0

Requer PHP 8.3+ e PDO SQLite. Sem Composer, páginas HTML, cookies ou painel web.

## Executar localmente
Configure variáveis de ambiente pelo terminal/serviço de sua preferência (o programa não carrega .env automaticamente):
- APP_ENV=development
- API_BASE_PATH=/v1
- MAURINDESK_DB_PATH=caminho absoluto para arquivo SQLite fora de public/

Crie o diretório privado do banco antes e execute:
```
php server/php/bin/migrate.php
php -S 127.0.0.1:18765 -t server/php/public server/php/public/index.php
```

Acesse /v1/health. O servidor de desenvolvimento não é adequado para produção.

## Implementado
POST devices; POST devices/heartbeat; POST sessions; GET sessions/incoming;
GET sessions/{id}; POST sessions/{id}/decision; POST sessions/{id}/cancel; POST sessions/{id}/close.

Identidades com chave de 10 dígitos e segredo separado, presença de 45 s, pedidos de 60 s,
consentimento exclusivo do host, subconjunto de permissões, bloqueio de host ocupado,
expiração na leitura, idempotência de mutações e rate limits de registro/pedidos.

Aceite só reserva a negociação por 30 s: ainda não existe transmissão. Sessões não chegam a active nesta versão.
Incoming retorna um snapshot dos primeiros 100 pedidos pendentes; cursor incremental ainda não foi implementado.

## Testes
```
php server/php/tests/run.php
python tests/http_smoke.py
```
No Windows portátil, forneça PHP_BIN e PHP_ARGS (array JSON com opções de extensões) ao teste Python.

## Publicação futura
Somente public/ no diretório HTTP; src, bootstrap, migrations e banco privados. Configurar o caminho
/maurindesk/api/v1, certificado HTTPS e limites do servidor. O código não confia em X-Forwarded-Proto:
terminação TLS por proxy exige configuração confiável no servidor web.
Copiar .htaccess não substitui configuração correta de document root e permissões.

SQLite é o backend desta primeira etapa. MySQL, rotação de token por endpoint, exclusão do dispositivo,
sinalização SDP/ICE, credenciais de sessão, heartbeat de canal, TURN, limpeza periódica e OpenAPI
completo permanecem pendentes. Não publicar como serviço de controle remoto concluído.
