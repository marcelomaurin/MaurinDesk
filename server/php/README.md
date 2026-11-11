# Servidor MaurinDesk — Hostinger

Servidor: https://maurinsoft.com.br/maurindesk/

API: https://maurinsoft.com.br/maurindesk/api/v1/

Banco inicial: `params.chave = VERSAO`, `params.valor = 0.1`. A migração da interface atualiza automaticamente para **0.2**.

PHP 8.3+, PDO MySQL/MariaDB em produção; SQLite para desenvolvimento. Sem Composer, daemon ou serviço de retransmissão de tela na hospedagem.

## Publicar

1. Crie um banco MySQL vazio e seu usuário no hPanel. Anote nome completo, usuário e senha. O servidor cria as tabelas automaticamente; não importe SQL manualmente.
2. Envie o conteúdo desta pasta para `public_html/maurindesk/`, incluindo os dois arquivos `.htaccess`. Os métodos HTTP ficam em `api/index.php`; `src/` contém os serviços privados.
3. Copie `.env.sample` para `.env` e preencha `DB_NAME`, `DB_USER`, `DB_PASSWORD` e o host fornecido pelo painel. O padrão é `localhost:3306`. Não envie credenciais ao Git.
4. Confira PHP 8.3+ e PDO MySQL no painel. O usuário do banco precisa de permissões de criar/alterar tabelas e índices, além de ler e gravar dados para as atualizações automáticas.
5. Abra https://maurinsoft.com.br/maurindesk/ ou https://maurinsoft.com.br/maurindesk/api/v1/health. O primeiro acesso cria as tabelas, registra a migração e retorna `status=ok`, `version=0.2` após aplicar as migrações 0.1 e 0.2.
6. Confira que `/maurindesk/.env`, `/maurindesk/src/Api.php` e `/maurindesk/migrations/mysql/001_initial.sql` retornam 403. Não publique se o servidor entregar o conteúdo desses arquivos.

Use o pacote pronto, sem a pasta `.git`, executáveis, testes ou credenciais. Preserve seu `.env` nas próximas atualizações. As regras `.htaccess` requerem Apache/LiteSpeed com reescrita habilitada; não substitua o `.htaccess` da raiz do domínio.

## Configuração

O arquivo `.env` é carregado automaticamente; variáveis reais do ambiente têm prioridade. Valores entre aspas são literais, inclusive senhas com `#`, `$` e `=`. Também é possível apontar `MAURINDESK_ENV_FILE` para um arquivo fora de `public_html` pelo ambiente do servidor.

`API_BASE_PATH=/maurindesk/api/v1` mantém compatibilidade com o desktop atual. O endereço base do servidor permanece `/maurindesk/`.

Não há instalador público, execução de SQL enviada pelo navegador nem endpoint de administração. Falhas de configuração, banco e migração devolvem JSON genérico com HTTP 503, sem senha ou SQL.

## Migrações automáticas

O bootstrap consulta `params.VERSAO`. Em banco novo cria as tabelas e grava `0.1`. Em seguida aplica a migração 0.2 da interface. `schema_migrations` registra versão, descrição das mudanças e data UTC em timestamp Unix. Parâmetros e registros existentes são preservados.

Para uma nova versão, acrescente a migração na lista ordenada de `src/Schema.php`, crie os arquivos SQL para MySQL e SQLite e atualize `Schema::VERSION`. Use scripts reiniciáveis e mantenha os antigos. O sistema aplica somente versões superiores à atual, registra o histórico e atualiza `VERSAO` por último. Banco com versão superior à aplicação é recusado, evitando downgrade acidental.

No MySQL/MariaDB, um lock nomeado serializa as migrações. DDL pode realizar commit implícito: se houver falha, parte da estrutura pode já existir, mas a versão anterior permanece. A próxima tentativa repete o SQL idempotente. Histórico e versão são confirmados juntos após o DDL. No SQLite a transação também protege o DDL. Tabelas ausentes da base inicial são recriadas automaticamente.

A versão do banco não é a versão do executável desktop.

## Descoberta P2P

- `POST devices/endpoint`: autenticado por Bearer, exige `Idempotency-Key` UUID e JSON `{"port":49152,"transport":"tcp"}`. Aceita portas de 1024 a 65535. O IP vem de `REMOTE_ADDR`, nunca do corpo ou de `X-Forwarded-For`.
- Cada desktop deve renovar esse anúncio a cada 15 segundos. Após 45 segundos ele deixa de ser válido. O heartbeat de presença sozinho não renova uma porta de escuta.
- `GET sessions/{id}/peer`: somente um dos dois participantes, após consentimento, recebe IP observado, porta e permissões do outro. Pedido pendente, recusado, encerrado ou expirado não entrega endereço.
- Não existe diretório público de IPs. O endereço é anunciado, com `reachability=unverified`: o servidor não abre porta no roteador nem garante passagem por NAT/CGNAT.
- O desktop ainda precisa implementar listener, canal cifrado/autenticado, captura e entrada. A hospedagem não retransmite tela ou comandos. O aceite continua com prazo de negociação de 30 segundos; ativação da sessão será integrada ao transporte posteriormente.

Se usar proxy reverso/CDN, configure a origem real no servidor web antes de ativá-lo; não habilite confiança indiscriminada em cabeçalhos enviados pelo cliente.

## Desenvolvimento e testes

Defina `APP_ENV=development`, `DB_DRIVER=sqlite`, `API_BASE_PATH=/maurindesk/api/v1` e `MAURINDESK_DB_PATH` absoluto fora desta pasta, em diretório existente. O arquivo do banco será criado automaticamente.

```text
php -S 127.0.0.1:18765 -t server/php/api server/php/api/index.php
php server/php/tests/desktop_ui.php
php server/php/tests/schema.php
python tests/http_smoke.py
```

`php server/php/bin/migrate.php` é uma alternativa opcional para executar o mesmo bootstrap por CLI. Não é necessária para instalar pela Hostinger.

O workflow inclui SQLite, MySQL 8.0 e MariaDB 11.4. Testes locais atualizados: 95 verificações de API (identidade, consentimento, P2P e dados da interface), 20 de schema/versionamento e 9 cenários HTTP. MySQL/MariaDB e as regras Apache/LiteSpeed precisam ser validados no ambiente de hospedagem ou no CI; não foram executados no ambiente Windows desta entrega.

Referências oficiais:
- https://www.hostinger.com/br/support/banco-de-dados-mysql/
- https://support.hostinger.com/pt/articles/1583552-como-localizar-os-detalhes-do-seu-banco-de-dados-mysql

## Dados da interface — banco 0.2

`GET desktop` entrega a própria identificação, preferências, contatos, favoritos e 50 sessões recentes, com cartões recentes agrupados por chave remota. `PATCH devices/me` altera o nome da máquina e a recuperação de registro preserva esse nome.

`device_preferences` guarda idioma, tema, modo cartões/lista e ordenação por nome/último uso. `device_contacts` guarda chave remota, apelido, grupo, favorito, cor do cartão e posição. Cada instalação tem seus próprios registros; cadastrar favorito não autoriza acesso.

Rotas: `GET/POST contacts`, `PATCH/DELETE contacts/{id}`, `PATCH desktop/preferences`, `GET sessions/recent`. Todas exigem Bearer; mutações exigem também Idempotency-Key. Há limite de 500 contatos por instalação. Criar novamente uma chave atualiza o mesmo contato. Não se pode alterar o proprietário de um contato.

Os contatos conhecidos por uma sessão antes autorizada recebem `availability=online/offline`, com presença válida por 45 segundos. Os demais retornam `unknown`, sem confirmar existência de máquinas ou revelar IPs. Miniaturas de tela permanecem locais; o servidor armazena somente os metadados dos cartões.

Consulte [mapeamento completo da interface](../../docs/12-banco-interface.md). O desktop ainda precisa consumir essas rotas; os favoritos INI existentes não são importados automaticamente nesta entrega.
