# Desktop Lazarus — 0.2.0

## Compilar no ambiente do projeto
Manter repositórios irmãos:
- C:/projetos/maurinsoft/MaurinDesk
- C:/projetos/maurinsoft/CHATGPT

```
C:\lazarus\lazbuild.exe desktop/MaurinDesk.lpi
```

Saída: bin/MaurinDesk.exe (Windows x64). Biblioteca: diretório
CHATGPT/pacote/AI Communication/AIRemoteDesktop. O arquivo dependencies/chatgpt.json
registra o commit validado. Não é preciso instalar o pacote na IDE para este projeto compilar.

## Uso inicial
Abrir o executável e clicar em Registrar / recuperar chave. Informar chave remota para solicitar acesso.
O destino lista pedidos e permite recusar, aceitar visualização ou aceitar controle.
Aceite ainda não transmite a tela nem injeta entrada: esta versão implementa a preparação da sessão.
É necessário ter a API correspondente publicada para usar o endereço oficial.

Favoritos guardam chave/apelido. Duplo clique preenche o campo remoto, sem iniciar acesso.
Identidade é cifrada por Windows DPAPI, vinculada ao usuário Windows, e separada por URL de servidor.
Ao reabrir, Registrar / recuperar chave reutiliza o token válido; recupera o registro somente quando necessário.

Rede roda em worker para manter a janela responsiva. Polling/heartbeat a cada 15 s nesta etapa inicial.
HTTP em claro só é permitido para loopback quando explicitamente iniciado em desenvolvimento:
```
bin/MaurinDesk.exe --dev-local-api=http://127.0.0.1:18765/v1
```

Produção usa https://maurinsoft.com.br/maurindesk/api/v1 com validação TLS nativa WinHTTP
e redirecionamento desabilitado. Sem dependência de OpenSSL para este cliente Windows.
Não copiar identity.dat para outra máquina.

## Limites
Ainda não implementa captura, visualizador remoto, mouse/teclado, TURN, serviço em segundo plano,
instalador ou suporte Linux. A lista de pedidos é atualizada por polling; a interface avisa que
compartilhamento ainda está em implementação.
