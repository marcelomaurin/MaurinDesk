# Registro de decisões
11/11/2026 — versão documental inicial.

| ID | Decisão | Motivo e consequência |
|---|---|---|
| D01 | Desktop Lazarus e servidor PHP sem interface | Atende ao ambiente solicitado; consentimento e visualização ficam no desktop |
| D02 | Chave pública decimal de 10 posições | Facilita informar acesso; segredo de autenticação separado é obrigatório |
| D03 | Consentimento novo por sessão | Favorito é conveniência, não autorização permanente |
| D04 | Alocação de chave central com UNIQUE | Evita prometer unicidade por hash de hardware ou endereço de rede |
| D05 | PHP coordena e WebRTC transporta | Evita fluxo de imagens por requisições PHP e permite conexão entre redes |
| D06 | TURN separado | Acesso direto pode falhar; hospedagem PHP não garante retransmissão |
| D07 | Reuso em CHATGPT | Componentes genéricos terão uma origem; MaurinDesk concentra produto e servidor |
| D08 | Windows x64 primeiro | Escopo verificável para captura/entrada antes de prometer outros sistemas |
| D09 | JPEG por DataChannel no MVP | Permite provar o fluxo; codecs/trilhas de vídeo podem evoluir após medir limites |
| D10 | Perda de conexão encerra | Evita retorno de controle sem nova autorização |
| D11 | Identidade persistida, sem chave por IP/MAC | Atualização mantém identidade; reinstalação sem credencial recebe outra |
| D12 | Branch padrão existente: fila | Inicializar documentação sem renomear ou criar main/master sem necessidade |

## Pendências antes da implementação
- Confirmar versão do compilador e forma de fixar dependência CHATGPT.
- Definir licença do MaurinDesk e inventário de licenças dos runtimes.
- Confirmar PHP, banco, limites e recursos de rede da hospedagem.
- Escolher operação e endereço TURN; não inventar serviço disponível.
- Revisar fila de callbacks WebRTC, múltiplos canais e formato binário.
- Confirmar compatibilidade de captura/input com monitor/DPI nas VMs e máquinas alvo.
- Produzir OpenAPI e migrações durante M1.

## Evidências e limites desta entrega
MaurinDesk estava vazio na inspeção inicial e sua branch padrão era fila. A biblioteca CHATGPT continha implementação inicial de WebRTC; foram lidos README e código e identificadas extensões necessárias. Os nomes dos novos componentes são propostas, não classes existentes.

A execução local por terminal não esteve disponível no ambiente desta sessão; a publicação documental foi feita pela integração GitHub. Não há alegação de compilação, teste de PHP ou conexão real.

## Referências técnicas para implementação
- Biblioteca CHATGPT: https://github.com/marcelomaurin/CHATGPT
- Free Pascal: https://www.freepascal.org/docs.html
- Lazarus: https://www.lazarus-ide.org/
- PHP: https://www.php.net/docs.php
- libdatachannel: https://github.com/paullouisageneau/libdatachannel
- TURN/coturn: https://github.com/coturn/coturn
- WebRTC: https://www.w3.org/TR/webrtc/
- Windows SendInput: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput

As referências orientam as etapas futuras; não constituem evidência de compatibilidade já testada.
