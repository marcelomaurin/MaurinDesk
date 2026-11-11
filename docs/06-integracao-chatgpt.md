# Integração com a biblioteca CHATGPT

## Regra de propriedade
Código Pascal genérico com utilidade fora do MaurinDesk deve ser implementado em [CHATGPT](https://github.com/marcelomaurin/CHATGPT). O MaurinDesk consome os pacotes; não mantém cópias divergentes. O servidor PHP e as regras específicas do produto permanecem no MaurinDesk.

## Inspeção realizada em 11/11/2026
Na branch main foram consultados README, árvore e código do componente WebRTC:
- [aiwebrtc_client.pas](https://github.com/marcelomaurin/CHATGPT/blob/main/pacote/AI%20Communication/AIWebRTC/aiwebrtc_client.pas), blob `b0bfe7e8cfc8464a9bc3986cd3846e5135272ee7`.
- [README WebRTC](https://github.com/marcelomaurin/CHATGPT/blob/main/pacote/AI%20Communication/AIWebRTC/README.md), blob `d3e6f878238dffec751dd51ebe5366d86195a04b`.
- Pacote existente `pacote/packages/openai_webrtc.lpk`.

O TAIWebRTCClient já carrega libdatachannel, cria peer e DataChannel, emite SDP/ICE, recebe mensagens e configura um STUN. Isso não constitui acesso remoto pronto.

## Lacunas observadas
O código mantém um único FDataChannel. Precisa suportar canais separados e capacidade binária explícita. A configuração exposta possui um STUN; precisa lista ICE e autenticação TURN temporária.

Callbacks escrevem em campos FPendingMessage/FPendingCandidate/FPendingSDP compartilhados e enfileiram métodos sem cópia individual do payload. É necessário verificar/corrigir perda ou sobrescrita em rajadas com uma fila segura por evento antes de confiar em ICE e entrada remota. Validar também o ciclo de destruição e callbacks pendentes.

O README menciona TAICaptureSource para captura existente, mas não foi validado backend de captura da área de trabalho. Captura de webcam/VFW não deve ser tratada como captura de desktop. Localizar interfaces existentes antes de estender; não duplicar backends de câmera.

## Componentes propostos — ainda não criados
| Componente | Contrato e responsabilidade |
|---|---|
| TAIDesktopCapture | Enumerar monitores, capturar quadros, geometria/DPI, start/stop; backend Windows inicial |
| TAIRemoteInput | Validar/aplicar eventos, liberar teclas/botões e respeitar permissões locais |
| TAIRemoteDesktopProtocol | Tipos, versão, limites, fragmentação, sequência e rejeição de pacote inválido |
| TAIRemoteDesktopSession | Máquina de estados, autorização explícita fornecida pelo aplicativo e liveness |
| TAIRemoteSignalingClient | Cliente HTTP desacoplado, URL configurável, autenticação, polling e erros |
| TAIWebRTCClient existente | Evoluir fila segura, múltiplos canais, envio binário e ICE/TURN configurável |

Nomes e pacote `openai_remote_desktop.lpk` são propostas sujeitas à revisão do padrão da biblioteca. URL maurinsoft fica na configuração do MaurinDesk, não fixa no componente genérico. A biblioteca não pode presumir consentimento: começa bloqueada e só recebe autorização explícita do aplicativo para a sessão correspondente.

## Fronteira do produto
| CHATGPT | MaurinDesk |
|---|---|
| Captura, protocolo, entrada e transporte | Formulário principal, diálogo de consentimento e visualizador |
| Cliente de sinalização parametrizável | URL oficial e regras do produto |
| Eventos genéricos de estado/erro | Textos PT-BR, favoritos, atalhos e configuração |
| Demo mínima sem marca do produto | Instalador e integração de versão |
| Testes de componentes | Testes de API e cenário completo |

## Forma de integração
Fixar commit da biblioteca por release (submodule ou dependência externa documentada, a escolher na fase de build), registrar runtimes e licenças. Mudança comum entra primeiro no CHATGPT com demo e testes pertinentes; depois atualizar referência no MaurinDesk. Não introduzir dependência obrigatória de APIs de IA.

A licença atualmente indicada pelo CHATGPT é GPLv3. Registrar compatibilidade das dependências e definir a licença do MaurinDesk antes da distribuição; esta especificação não altera licenças.
