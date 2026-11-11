# Plano de implementação e validação

## Marcos
| Etapa | Entregável | Condição para concluir |
|---|---|---|
| M0 — especificação | Documentos desta entrega | Revisão de coerência, links e publicação no Git |
| M1 — API PHP | Registro, tokens, presença, sessões, consentimento, sinais, migrações, OpenAPI | Testes de autenticação, concorrência, expiração, idempotência e autorização |
| M2 — CHATGPT | Captura Windows, entrada, protocolo, extensões WebRTC, cliente API e demo | Compilar pacote e demo; testes de fila, limites e revogação |
| M3 — desktop | Projeto Lazarus, própria chave, favoritos e autorização | Duas instalações conectam em LAN com consentimento explícito |
| M4 — redes reais | TURN e configuração de produção | Acesso entre redes diferentes e NAT restritivo, sem abrir portas manualmente no cliente |
| M5 — distribuição | Instalador, dependências, versão e manual | Instalação limpa em Windows 10/11 x64 e validação completa |

M1 e M2 podem avançar independentemente após congelar contrato v1. M3 depende dos dois. Não marcar requisito como concluído apenas pela presença de um método ou tela. Registrar commit, ambiente e evidência de execução.

## Testes de aceite
| Teste | Requisitos | Procedimento e resultado esperado |
|---|---|---|
| T01 — unicidade | RF01/02, RNF14 | Cadastros concorrentes e colisão simulada; nenhuma chave duplicada; reinício mantém identidade |
| T02 — registro repetido | RF01/02 | Perder resposta de registro e repetir com identidade/segredo iguais; mesma chave, token antigo revogado |
| T03 — consentimento | RF04/06/07 | Pedir conexão e não aceitar; nenhum quadro nem entrada trafega; expira em 60 s |
| T04 — recusa/cancelamento | RF09 | Recusar e tentar obter token/enviar sinal; rejeitado; cancelar não gera sessão ativa |
| T05 — papéis | RF07/08, RNF04 | Controlador tenta aceitar; terceiro tenta consultar; ambos bloqueados |
| T06 — visualização | RF08/10 | Aceitar só screen.view; imagem chega e todos os eventos de entrada são descartados |
| T07 — controle | RF11/12/22 | Testar botões, rolagem, Unicode, modificadores, DPI e monitores com origem negativa |
| T08 — parada | RF13/14, RNF19 | Encerrar host com tecla pressionada e quadros pendentes; liberar tecla, limpar fila e parar acesso |
| T09 — favoritos | RF15/16 | Salvar/reiniciar/reconectar; mantém chave/apelido e solicita nova autorização |
| T10 — presença | RF05, RNF09 | Parar heartbeat; após 45 s indisponível, mesmo sem job de limpeza |
| T11 — queda de rede | RF14/18, RNF10 | Cortar API e canal separadamente; respeitar watchdog de 10 s, exigir pedido novo |
| T12 — replay e expiração | RF09, RNF04/08 | Repetir token expirado, sinal ou entrada de sessão encerrada; nenhuma execução |
| T13 — concorrência | RF23 | Dois aceites simultâneos no mesmo host; apenas uma sessão autorizada |
| T14 — NAT | RF17 | Duas redes com conexão direta bloqueada; TURN transporta; sem TURN informar indisponibilidade |
| T15 — rajada e limites | RNF08 | ICE/mensagens simultâneas, quadros incompletos e payload gigante; sem sobrescrita, travamento ou crescimento ilimitado |
| T16 — sigilo | RNF01/13/18 | Certificado inválido rejeitado; busca em logs/banco sem imagem, texto digitado e tokens em claro |
| T17 — bloqueio do SO | RF24 | Bloquear estação; encerrar; desbloquear não retoma |
| T18 — desempenho | RNF07/20 | Medir cenário de referência e carga; publicar p50/p95, fps, CPU/RAM e tráfego, com hardware e RTT |
| T19 — instalação limpa | RNF11/12 | Instalar sem IDE; verificar runtimes e arquitetura corretos nas duas versões de Windows |
| T20 — identidade clonada | RF01/02 | Provisionar imagem clonada sem copiar segredos; duas máquinas recebem identidades distintas |
| T21 — idempotência | RNF14/17 | Repetir mutação e alterar corpo com a mesma chave; resultado estável e conflito respectivamente |

## Registro de evidências
Cada marco terá relatório com data, versões, commits dos dois repositórios, procedimento, resultado esperado/obtido e limitações. Testes automatizados devem cobrir protocolo/API; captura e entrada exigem também validação em desktop real ou VM interativa. Não declarar suporte a UAC, Wayland ou outro backend por inferência.

## Estado atual
M0: documentos preparados nesta entrega. M1–M5: pendentes. Nenhuma compilação ou teste de acesso remoto foi realizado nesta etapa documental.
