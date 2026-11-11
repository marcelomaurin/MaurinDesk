# Requisitos não funcionais

Metas propostas para validação; não são medições obtidas.

| ID | Requisito | Critério de validação |
|---|---|---|
| RNF01 | HTTPS obrigatório e certificado validado | Cliente rejeita HTTP, certificado inválido e redirecionamento para outro host |
| RNF02 | Canal de tela/entrada cifrado | WebRTC DTLS/SCTP, com fingerprint do peer vinculado à negociação autorizada; sem transporte em claro |
| RNF03 | Autenticação independente da chave pública | Tokens privados com ao menos 256 bits de entropia; no servidor apenas hash de token; comparação segura |
| RNF04 | Autorização em cada rota e no host | Participante alheio não lê sessão, mensagens ou decisões; pacote sem permissão não é executado |
| RNF05 | Resistência a abuso | Limites iniciais: registro 5/h por IP, pedidos 10/min por dispositivo e 5/min por host; ajustar por evidência e considerar NAT compartilhado |
| RNF06 | UI responsiva | Rede, captura e compressão fora da thread visual; janela continua respondendo durante timeout |
| RNF07 | Qualidade adaptativa | Perfil de referência: 1280×720, 10 quadros/s; medir latência p95 abaixo de 500 ms em LAN com RTT até 20 ms, hardware identificado e desktop em movimento moderado |
| RNF08 | Filas limitadas | Até dois quadros pendentes, descarte do quadro antigo; entrada com sequência e validade, sem execução tardia após revogação |
| RNF09 | Presença verdadeira | Heartbeat a cada 15 s; indisponível após 45 s sem heartbeat, usando relógio UTC do servidor |
| RNF10 | Falha segura | Sem heartbeat de sessão/canal por 10 s, host suspende e encerra acesso; perda de API não permite sessão continuar indefinidamente |
| RNF11 | Compatibilidade declarada | Windows 10/11 x64 validado antes de release; outros SOs retornam capacidade indisponível até haver backend testado |
| RNF12 | Dependências reproduzíveis | Registrar versões Lazarus/FPC, commit CHATGPT, runtime libdatachannel, arquiteturas e licenças |
| RNF13 | Privacidade | Não armazenar tela, conteúdo digitado ou clipboard no servidor/logs; SDP/ICE têm retenção curta e acesso restrito |
| RNF14 | Persistência consistente | Transações para registro, consentimento e ocupação do host; índices UNIQUE para chave e identidade |
| RNF15 | Operação observável | Logs estruturados com request_id, session_id, duração e códigos; tokens e dados sensíveis redigidos |
| RNF16 | Recuperação | Backup cifrado do banco e teste de restauração em homologação antes de produção |
| RNF17 | API previsível | JSON UTF-8, versão v1, limites de payload, erros estáveis e horários RFC3339 UTC |
| RNF18 | Segredos protegidos | Credencial local em cofre do SO quando disponível; configuração privada fora do diretório público e do Git |
| RNF19 | Encerramento local imediato | Entrada desabilitada sincronicamente na decisão local; captura interrompida e filas limpas, meta até 1 s para fechamento visual |
| RNF20 | Capacidade medida | Antes de release, teste de 100 dispositivos online e 10 sessões simultâneas no ambiente escolhido; registrar CPU, memória, tráfego e latência p95 |

## Parâmetros iniciais
Pedido expira em 60 s; negociação em 30 s; sessão tem limite máximo de 2 h e renovação não automática. Credencial de dispositivo expira em 30 dias, com rotação autenticada antes do prazo e invalidação da anterior. Token de sessão é emitido após consentimento, limitado à sessão, papel e duração. Credencial TURN tem vida máxima de 10 min, renovável somente com sessão ainda autorizada.

Esses valores são configuração do servidor comunicada ao cliente; não mudar sem atualizar contrato e testes.

## Segurança de entrada e plataforma
Nunca contornar UAC, desktop seguro ou permissões do SO. O MVP executa com os privilégios do usuário e pode não controlar aplicativos elevados. Ao perder foco, revogar controle ou cair conexão, liberar estado de teclas e botões. Rejeitar eventos fora de ordem, sessão incorreta, coordenadas inválidas e payloads excedentes.

## Retenção proposta
Pedidos/SDP/ICE: apagar até 5 min após término/expiração. Auditoria sem conteúdo: 30 dias, configurável. Credenciais: somente hashes no servidor; jamais em respostas de listagem ou logs. Validade, exclusão e retenção deverão ser verificadas na implantação.
