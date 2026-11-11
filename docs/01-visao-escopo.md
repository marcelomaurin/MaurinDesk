# Visão e escopo
Versão 0.1 — 11/11/2026 — especificação para implementação.

## Objetivo
Permitir suporte remoto com consentimento explícito do usuário atendido. Um mesmo desktop pode solicitar acesso ou oferecer sua área de trabalho. A referência é o fluxo do AnyDesk; não se promete compatibilidade com seu protocolo.

## Atores e termos
| Termo | Definição |
|---|---|
| Host | Computador cuja área de trabalho será compartilhada |
| Controlador | Computador que solicita e visualiza/controla o host |
| Chave da máquina | Identificador público decimal de 10 posições |
| Credencial do dispositivo | Segredo privado para autenticar a instalação na API |
| Sessão | Acesso temporário entre exatamente dois dispositivos |
| API PHP | Registro, presença, pedidos, consentimento e sinalização |
| Relay TURN | Serviço de retransmissão quando a conexão direta falhar |

## Escopo inicial
Desktop Windows 10/11 x64 como primeiro alvo de validação. Arquitetura com interfaces para portar posteriormente a Linux; não declarar suporte sem testes. Cliente com própria chave, campo para chave remota, favoritos, solicitação de consentimento, visualizador e encerramento. API PHP sem telas. Uma sessão de controle de entrada ativa por host no MVP, para evitar disputa entre operadores.

A ausência de tela aplica-se ao servidor web. O desktop necessariamente apresenta interface e aviso de acesso ativo. O processo deve ser visível ao usuário.

## Identidade
A chave deve ser uma string com exatamente 10 algarismos, inclusive zeros iniciais: exemplo fictício `0123456789`. Deve ser alocada no servidor com gerador criptograficamente seguro e restrição UNIQUE transacional; colisões geram nova tentativa. Não usar IP, MAC ou hash truncado de hardware como garantia de unicidade.

A identidade é persistida localmente e sobrevive a reinícios e atualizações. Reinstalação sem backup da identidade cria novo dispositivo e nova chave; restauração só com identidade válida. Imagens clonadas não podem compartilhar credenciais: novo provisionamento é obrigatório. Chaves desativadas não devem ser redistribuídas para outra máquina, evitando favoritos apontando para novo proprietário. O espaço máximo é finito (10 bilhões de combinações); monitorar utilização.

Conhecer ou salvar a chave não autentica nem autoriza acesso. O dono da máquina sempre decide sobre cada nova conexão.

## Fora do MVP
Acesso desassistido, serviço oculto, transferência de arquivos, áudio, área de transferência, gravação, chat, múltiplos controladores simultâneos, elevação automática, tela de login, desktop seguro/UAC e controle por navegador. Essas funções só podem entrar com requisitos e validação próprios.

## Entrega atual
Documentação, arquitetura e contrato de APIs proposto. Implementação e instalação são marcos posteriores, descritos no plano.
