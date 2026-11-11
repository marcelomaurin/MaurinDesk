# Requisitos funcionais

Todos os requisitos abaixo são planejados; nenhum é declarado implementado.

| ID | Requisito | Aceite verificável |
|---|---|---|
| RF01 | Registrar instalação com credencial privada e chave pública única de 10 dígitos | Dois cadastros concorrentes nunca recebem a mesma chave; zeros iniciais são preservados |
| RF02 | Persistir identidade por usuário/instalação | Reinício e atualização mantêm chave e credenciais; perda do segredo exige novo registro |
| RF03 | Mostrar e copiar a própria chave | Interface exibe as 10 posições e copia sem caracteres adicionais |
| RF04 | Solicitar conexão pela chave remota | Aceita apenas 10 algarismos após remover separadores de apresentação; rejeita a própria chave |
| RF05 | Atualizar presença por heartbeat | Host aparece disponível apenas enquanto sua presença for recente |
| RF06 | Notificar host sobre pedido | Exibe apelido declarado do solicitante, sua chave, horário e permissões; nome não é identidade verificada |
| RF07 | Exigir autorização local explícita | Sem clique de aceitação não sai imagem nem se aplica evento de entrada |
| RF08 | Permitir aceitar somente visualização ou visualização com controle | API registra permissões; host também as verifica antes de cada operação |
| RF09 | Recusar, cancelar e expirar pedidos | Recusa/expiração são terminais e não deixam abrir canal autorizado |
| RF10 | Compartilhar área de trabalho | Após consentimento e validação do canal, controlador recebe quadros do monitor selecionado |
| RF11 | Simular mouse | Movimento, clique, duplo clique, botões e rolagem respeitam tamanho, escala e limites do monitor |
| RF12 | Simular teclado | Pressionar/soltar, modificadores e texto Unicode são validados; desconexão libera teclas/botões presos |
| RF13 | Avisar sessão ativa | Host mostra indicador persistente, identidade do controlador e botão de encerrar |
| RF14 | Encerrar em qualquer ponta | Host para captura e entrada imediatamente ao encerrar localmente; servidor invalida sessão |
| RF15 | Salvar favoritos locais | Chave e apelido podem ser criados, listados, editados e excluídos sem guardar autorização |
| RF16 | Reconectar usando favorito | Cria pedido novo e exige consentimento novo, inclusive após falha da sessão anterior |
| RF17 | Negociar comunicação direta e relay | Em NAT restritivo usa TURN quando configurado; sem rota viável informa falha, sem fingir conexão |
| RF18 | Informar falhas e disponibilidade | Distingue erro de API, dependência ausente, pedido recusado/expirado e canal indisponível |
| RF19 | Auditar ciclo da sessão | Registra IDs, estados, consentimento, permissões e motivo do término; não registra imagens/teclas |
| RF20 | Separar biblioteca de produto | Captura, injeção, protocolo e transporte genéricos ficam no CHATGPT; formulários e favoritos no MaurinDesk |
| RF21 | Expor somente APIs no PHP | Todas as rotas de produto retornam JSON; não há login HTML nem painel web |
| RF22 | Selecionar monitor e suspender controle | Host escolhe monitor; mudanças de geometria invalidam eventos antigos; suspender bloqueia entrada já enfileirada |
| RF23 | Impedir controle concorrente | Aceitação transacional de dois pedidos para o mesmo host libera no máximo uma sessão |
| RF24 | Pausar ao bloquear a estação | Bloqueio encerra sessão no MVP; desbloquear não retoma sem novo pedido |

## Fluxo nominal
Host e controlador registram presença → controlador informa chave → API cria pedido pendente → host exibe diálogo → host aceita permissões → API registra decisão → pares negociam canal autenticado → host inicia captura → controlador visualiza e envia entrada autorizada → qualquer ponta encerra.

## Regras de consentimento
Pedido pendente não habilita captura nem entrada. Só o dispositivo host autenticado decide; o controlador não pode aceitar por ele. Autorização vincula IDs dos dois participantes, ID da sessão e permissões. Sessão fechada, expirada ou perdida exige novo pedido. Não reaproveitar tokens de sessão anterior.
