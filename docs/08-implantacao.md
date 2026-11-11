# Implantação futura

## URL e diretórios
Endereço oficial: https://maurinsoft.com.br/maurindesk/api/  
Rotas propostas sob /maurindesk/api/v1/.

Publicar somente o front controller e recursos estritamente públicos no document root. Configuração, logs, segredos, código privado e migrações ficam fora dele. O roteador precisa reconhecer o prefixo /maurindesk/api/ sem supor instalação na raiz do domínio.

## Requisitos propostos
- PHP 8.3 ou superior como baseline de implementação; confirmar versão e ciclo de suporte na implantação.
- Extensões PDO com driver do banco escolhido, JSON, OpenSSL e mecanismo CSPRNG.
- MySQL/MariaDB como primeira opção de hospedagem; escolher versão compatível e fixá-la no início de M1.
- HTTPS válido, cron para limpeza, backups e ambiente de homologação.
- Serviço TURN separado com TLS e credenciais temporárias para redes restritas; validar portas e capacidade do provedor.

WebSockets/daemon PHP não são pré-requisito da sinalização inicial: usar requisições curtas e polling. PHP compartilhado não deve ser usado como relay contínuo de quadros. Confirmar custos de banda, limites de requisições e concorrência antes de dimensionar.

## Configuração planejada
| Variável | Finalidade |
|---|---|
| APP_ENV | development, staging ou production |
| APP_BASE_URL | https://maurinsoft.com.br/maurindesk/api/ |
| DB_DSN / DB_USER / DB_PASSWORD | Conexão privada com banco |
| DEVICE_TOKEN_TTL_SECONDS | Prazo de credencial do dispositivo |
| REQUEST_TTL_SECONDS | Prazo de pedido, inicial 60 |
| DEVICE_OFFLINE_AFTER_SECONDS | Presença expirada, inicial 45 |
| SESSION_LIVENESS_SECONDS | Watchdog, inicial 10 |
| SESSION_MAX_SECONDS | Limite máximo, inicial 7200 |
| TURN_URLS / TURN_SHARED_SECRET | URLs e segredo privado para emitir credenciais efêmeras |
| AUDIT_RETENTION_DAYS | Retenção de auditoria, inicial 30 |

Criar .env.sample sem segredos ao implementar o servidor. Nunca publicar .env, dumps ou tokens no Git.

## Sequência de publicação
1. Confirmar recursos reais da hospedagem e escolher banco/TURN.
2. Construir API em homologação e executar migrações com backup.
3. Validar HTTPS, roteamento no subdiretório e erros JSON.
4. Executar testes de autorização, concorrência e expiração.
5. Testar dois desktops e NAT restritivo.
6. Publicar versão identificada e verificar health e uma sessão consentida.
7. Monitorar erros, presença, fila e utilização do relay.

Falha de migração exige procedimento de restauração ensaiado. Nunca resolver indisponibilidade desabilitando TLS, autorização ou expiração.

## Verificação atual
A consulta pública ao endereço oficial não conseguiu confirmar disponibilidade nesta etapa. Isso não comprova que o servidor está fora do ar. Não houve login na hospedagem, upload PHP, migração de banco ou alteração DNS. A URL é configuração de destino, e não evidência de API implantada.
