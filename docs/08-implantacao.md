# Implantação na Hostinger

O endereço oficial do servidor é **https://maurinsoft.com.br/maurindesk/**. A API fica em **https://maurinsoft.com.br/maurindesk/api/v1/** e seus métodos HTTP estão em `server/php/api/`.

O procedimento atualizado está em [Servidor e instalação](../server/php/README.md). Publique o conteúdo de `server/php/` em `public_html/maurindesk/`, preserve `.htaccess` e configure `.env` com os dados de um banco MySQL vazio criado no hPanel.

No primeiro acesso o sistema cria as tabelas e inicializa `params` com `VERSAO=0.1`. Nas versões seguintes consulta esse parâmetro, aplica as migrações pendentes, registra mudanças em `schema_migrations` e atualiza a versão por último. Não há importação SQL manual nem instalador público.

O PHP oferece registro, presença, consentimento e descoberta de IP/porta entre participantes autorizados. Tela e entrada trafegarão diretamente entre desktops. Esta entrega não publica nem comprova conexão P2P real.
