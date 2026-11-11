# Instalar a API na Hostinger

Dentro de `server/` existe somente a pasta **api/**. Ela não tem subpastas nem depende de arquivos fora dela para executar o servidor.

1. Copie a pasta `server/api/` inteira para `public_html/maurindesk/api/` na Hostinger, incluindo `.htaccess` e `.env.sample`.
2. Crie um banco MySQL vazio e seu usuário no hPanel.
3. Dentro de `api/`, copie `.env.sample` para `.env` e preencha DB_HOST, DB_PORT, DB_NAME, DB_USER e DB_PASSWORD. Preserve esse arquivo nas atualizações.
4. Use PHP 8.3+ com PDO MySQL e HTTPS.
5. Abra **https://maurinsoft.com.br/maurindesk/api/** ou **https://maurinsoft.com.br/maurindesk/api/v1/health**. A resposta esperada é status=ok, version=0.2.

Não é necessário importar SQL, executar migração manual, enviar testes ou instalar Composer. No primeiro acesso o servidor cria as tabelas, registra a base 0.1 e aplica a atualização 0.2. Nas atualizações seguintes ele consulta params.VERSAO, aplica alterações pendentes, registra o histórico e atualiza VERSAO por último.

## Arquivos publicados

- index.php: entrada dos métodos HTTP.
- bootstrap.php: configuração e conexão com o banco.
- Api.php e DesktopData.php: implementação das APIs.
- Schema.php e arquivos *.sql: criação/atualização automática do banco.
- .env.sample e .htaccess: modelo da configuração e proteção do diretório.

Os arquivos auxiliares PHP, SQL e .env são privados e bloqueados por .htaccess; apenas index.php é acessível como script HTTP. Após publicar, confira que /maurindesk/api/.env, /maurindesk/api/Schema.php e /maurindesk/api/001_initial.mysql.sql retornam 403. O servidor deve aplicar regras Apache/LiteSpeed e reescrita de URL.

As URLs continuam sob /maurindesk/api/v1/. A remoção de pastas do servidor não altera o desktop, os documentos nem a chave de acesso.

A API recebe cadastro, presença, consentimento e endpoints P2P. As rotas da interface são descritas em [banco para a interface](12-banco-interface.md). Tela, miniaturas e eventos de entrada permanecem no desktop/P2P.

## Desenvolvimento

Os testes ficam fora da pasta de publicação, em tests/server/. Para teste SQLite local, use APP_ENV=development, DB_DRIVER=sqlite e MAURINDESK_DB_PATH absoluto em um diretório privado existente fora de server/api/.

```text
php -S 127.0.0.1:18765 -t server/api server/api/index.php
php tests/server/desktop_ui.php
php tests/server/schema.php
python tests/http_smoke.py
```
