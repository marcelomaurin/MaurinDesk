# MaurinDesk

Acesso remoto assistido, inspirado no fluxo de uso do AnyDesk, com cliente desktop Lazarus/Free Pascal e servidor PHP exclusivamente de APIs.

**Estado em 11/11/2026: versão inicial 0.2.0 implementada. API de identidade/presença/consentimento e desktop Lazarus compilado. Transmissão de tela e controle remoto ainda não implementados.**

## Funcionamento previsto

1. Cada instalação registra sua identidade e recebe uma chave única de **10 dígitos**.
2. A aplicação mostra a própria chave e permite informar a chave de outro computador.
3. O computador de destino recebe uma solicitação e seu usuário aceita ou recusa.
4. Somente após aceitar são liberados compartilhamento da área de trabalho e controle de mouse/teclado, conforme permissões concedidas.
5. O solicitante pode salvar a chave com um apelido para reconectar. Cada nova sessão exige nova autorização.
6. Qualquer participante pode encerrar; o usuário local pode suspender imediatamente o controle.

**Endereço oficial de conexão:** https://maurinsoft.com.br/maurindesk/api/  
**Base versionada proposta:** https://maurinsoft.com.br/maurindesk/api/v1/

O servidor PHP não terá páginas, painel ou interface de acesso remoto no navegador. As telas de conexão, consentimento e visualização pertencem ao desktop.

## Documentação

| Documento | Conteúdo |
|---|---|
| [Visão e escopo](docs/01-visao-escopo.md) | Produto, atores e limites |
| [Requisitos funcionais](docs/02-requisitos-funcionais.md) | Comportamentos e critérios de aceite |
| [Requisitos não funcionais](docs/03-requisitos-nao-funcionais.md) | Segurança, desempenho e operação |
| [Arquitetura](docs/04-arquitetura.md) | Componentes, estados, transporte e persistência |
| [Contrato das APIs](docs/05-contrato-api.md) | Rotas, autenticação, exemplos e erros |
| [Integração CHATGPT](docs/06-integracao-chatgpt.md) | Reuso existente e componentes a desenvolver |
| [Plano e validação](docs/07-plano-validacao.md) | Etapas e testes de aceite |
| [Implantação](docs/08-implantacao.md) | Requisitos do servidor e publicação futura |
| [Registro de decisões](docs/09-decisoes.md) | Motivos e pendências técnicas |
| [Implementação 0.2.0](docs/10-implementacao.md) | Código entregue, evidências e pendências atuais |

## Código e compilação

- `desktop/`: projeto Lazarus, formulários, favoritos e identidade visual MaurinDesk.
- `server/php/`: API, migrações, configuração e testes.
- `docs/`: especificação e evidências de validação.
- [CHATGPT](https://github.com/marcelomaurin/CHATGPT): componentes Pascal reutilizáveis de captura, entrada remota, transporte e sessão.

Consulte [desktop/README.md](desktop/README.md) para compilar e [server/php/README.md](server/php/README.md) para executar a API. O [andamento](docs/10-implementacao.md) distingue código validado e pendências. A biblioteca CHATGPT é um framework de componentes Lazarus; o acesso remoto não depende de um modelo de IA nem do envio da tela a um provedor de IA.

## Estado da infraestrutura

O endereço oficial foi definido pelo proprietário. Sua disponibilidade e o suporte de hospedagem a PHP, banco, TURN e conexões persistentes ainda precisam de validação; esta documentação não representa implantação.
