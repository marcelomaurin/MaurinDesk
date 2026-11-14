# MaurinDesk 0.6.7

## Gerenciador de arquivos 0.6.7

Publicar `server/api/` na hospedagem preservando o `.env` (migração automática para 0.9), atualizar os dois computadores e abrir uma nova sessão com **Controle + arquivos**. O GitHub distribui o aplicativo, mas não publica o PHP na hospedagem.

Em **Arquivos e pastas**, o painel esquerdo mostra este computador e o direito mostra o outro participante da sessão. Abra uma pasta com duplo clique ou digite seu caminho e pressione Enter. **Acima** permite chegar à lista de unidades. Há filtro por nome, paginação, atualização e criação de pastas nos dois lados.

1. Para enviar, selecione arquivos ou pastas à esquerda, abra a pasta final à direita e clique **Enviar →**.
2. Para receber, selecione à direita, abra a pasta final à esquerda e clique **← Receber**.
3. A fila mostra origem, destino, progresso e resultado. A conclusão indica gravação confirmada pelo destino; upload no PHP ainda não significa entrega.

Por padrão um nome existente provoca erro sem sobrescrever o item. Ative **Substituir arquivos existentes (mesclar pastas)** para substituir arquivos e mesclar diretórios, preservando outros arquivos da pasta. A gravação de cada arquivo usa substituição local de um temporário; um erro de disco durante uma pasta grande pode deixar parte dos arquivos já concluídos.

Suporta até 128 itens selecionados, 255 MiB de conteúdo por pacote, 10 mil entradas e profundidade 64. Pastas vazias e nomes Unicode são preservados. Links, junções e unidades de rede são recusados. Só são acessadas pastas permitidas ao usuário Windows. Erros de acesso e de preparação remota aparecem na fila. Fechar a janela mantém a fila; encerrar a sessão interrompe as transferências. Os arquivos temporários de recebimento são removidos após a tentativa de gravação, sem apagar a pasta final.

O Ctrl+C/Ctrl+V continua funcionando separadamente. No gerenciador os arquivos são gravados diretamente na pasta final escolhida, sem alterar a área de transferência.

## Atualização 0.6.6

Usar **Arquivos e pastas** no visualizador ou na janela principal para **Enviar arquivos...**, **Enviar pasta...** ou **Abrir arquivos recebidos**. Os envios explícitos não precisam alterar o clipboard local. O Ctrl+C/Ctrl+V continua disponível nos dois sentidos.

O envio ao servidor e o recebimento no destino são estados diferentes. Com a API 0.8 e os dois aplicativos em 0.6.6, o destino confirma somente após preparar a área de transferência; o remetente então mostra **Recebimento confirmado**. Arquivos recebidos também podem ser acessados pelo menu, mesmo que se prefira copiá-los manualmente do cache. Com versões antigas, a transferência básica continua disponível, mas o remetente não presume que o download tenha terminado.

A migração para 0.8 é automática ao publicar `server/api`, preservando o `.env`. Não basta enviar os arquivos ao GitHub para atualizar a hospedagem PHP.

Foi reproduzido que Enter podia ativar o botão local “Desconectar” na 0.6.5. A 0.6.6 mantém o foco na área remota e consome essas teclas. Os logs passam a registrar o autor do encerramento (`host` ou `controller`) e o motivo, distinguindo botão de desconectar, fechamento do visualizador e encerramento do aplicativo. O log antigo com `state=closed` não identifica sozinho qual gesto causou o fechamento.

O ícone próprio está incorporado em vários tamanhos. Se o Windows não confirmar sua criação, a janela não é escondida ao fechar/minimizar; o aplicativo registra o motivo e tenta novamente. Clique no ícone para abrir o programa.

## Atualização inicial

1. Publicar todo o conteúdo de `server/api/` na hospedagem, preservando o `.env`. O banco migra automaticamente para `0.9`, incluindo as tabelas do clipboard.
2. Fechar a versão anterior e usar `bin/MaurinDesk.exe` nos dois computadores. Aplicativos anteriores à 0.6.5 precisam dessa atualização manual inicial, pois ainda não contêm o atualizador.
3. Fazer uma nova solicitação e aceitar **Controle + área de transferência** no destino.

Os arquivos da API estão preparados no repositório; enviar ao GitHub não publica o PHP na hospedagem.

## Texto e arquivos com Ctrl+C / Ctrl+V

Durante a sessão autorizada, copiar texto, arquivos ou pastas em qualquer participante envia o conteúdo para o outro. Após o recebimento, colar normalmente com Ctrl+V. Arquivos grandes exigem aguardar o estado “Pronto para colar”.

- Texto Unicode em formato simples, até 1 MiB. Formatação HTML/RTF não é preservada.
- Arquivos de qualquer extensão, múltiplos itens e pastas, incluindo pastas vazias: até 255 MiB de conteúdo por cópia, 10 mil entradas e profundidade 64. A extensão não é alterada.
- Imagens copiadas como **arquivos** são suportadas. Bitmaps copiados diretamente como imagem (`CF_DIB`) não fazem parte desta versão.
- Links/junções de arquivos e pastas são recusados; arquivos com nomes raiz repetidos devem ser copiados separadamente.
- São observadas alterações a partir do início da sincronização. O conteúdo anterior ao aceite não é enviado automaticamente.
- Apenas visualização não autoriza clipboard. O servidor também valida `clipboard.sync`, participantes e estado da sessão em cada operação.
- O conteúdo recebido não é reenviado em ciclo. Uma nova cópia local durante o download é preservada.

No Windows, os arquivos recebidos ficam em `%LOCALAPPDATA%\MaurinDesk\Clipboard\<sessão>\<transferência>`. O clipboard recebe uma lista `CF_HDROP`, permitindo colar no Explorador como arquivos reais. Os arquivos permanecem no cache para permitir colagem após o encerramento e podem ser apagados manualmente quando não forem mais necessários.

No PHP, o conteúdo é transferido em partes de 256 KiB, validado antes de ficar disponível e removido ao encerrar a sessão. Transferências de sessões expiradas ou sem atividade por uma hora são removidas nas consultas seguintes à API. O transporte usa HTTPS; os dados não são incluídos nos logs de diagnóstico.

## Nomes e histórico

Depois de uma conexão aceita ser encerrada, o controlador oferece um nome opcional associado à chave de 10 dígitos. Vazio mantém a chave como identificação. O nome aparece nos cartões do histórico e nos favoritos já existentes. Cancelar mantém o nome anterior.

O histórico e os nomes são locais a este usuário e ao servidor configurado. As opções **Conexões**, **Favoritos** e **Histórico** navegam pelos cartões; não se presume que um favorito esteja online sem consultar presença.

## Configurações, instalação e área do relógio

As opções são guardadas pela classe `TSetMain` (instância `FSetMain`) em `%LOCALAPPDATA%\MaurinDesk\Setmain.cfg`. O `MaurinDesk.ini` anterior é importado no primeiro uso. Identidade e tokens continuam nos perfis separados por servidor, com a proteção DPAPI existente.

Em **Configurações**:

- **Iniciar com o Windows:** registra o aplicativo no início da sessão do usuário, em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, com `--minimized`.
- **Continuar na área do relógio:** fechar a janela oculta o aplicativo, mantendo a disponibilidade e a sessão. Duplo clique no ícone ou **Abrir MaurinDesk** restaura a janela. **Sair do MaurinDesk** encerra o processo e a sessão.
- **Instalar neste computador:** copia o executável para `%LOCALAPPDATA%\Programs\MaurinSoft\MaurinDesk\MaurinDesk.exe` e cria um atalho no menu Iniciar. A instalação é para o usuário atual, sem serviço de Windows e sem exigir uma pasta em `Program Files`.
- Servidor HTTPS, porta P2P, idioma e atualizações automáticas ficam no mesmo formulário. Alterações de configuração exigem encerrar a sessão ativa.

## Atualizações pelo GitHub

O descritor é lido de:

`https://raw.githubusercontent.com/marcelomaurin/MaurinDesk/fila/update.json`

O JSON inclui versão, plataforma, nome fixo `MaurinDesk.exe`, URL de download, tamanho, SHA-256, data e versão mínima de esquema da API. A comparação é numérica (`0.6.10` é maior que `0.6.9`).

O aplicativo consulta cerca de 30 segundos após abrir e depois diariamente, quando a opção estiver habilitada. Uma versão maior é baixada para a pasta privada de atualizações. Só é aceita a URL do executável deste mesmo repositório e branch; redirecionamentos são desabilitados e os certificados HTTPS são validados.

Antes de atualizar, são conferidos tamanho, SHA-256 e o recurso de versão interna do executável. A substituição aguarda não haver sessão nem diálogo ativo. Um auxiliar oculto espera o processo terminar, mantém `MaurinDesk.exe.previous`, substitui o arquivo e reinicia na área do relógio. Se a substituição ou a conferência falhar, tenta restaurar o arquivo anterior e registra `MaurinDesk.exe.update-error.log` ao lado do executável.

Para publicar uma próxima versão, ajustar a versão no código e no projeto e executar:

```powershell
./build.ps1
```

O script gera sempre `bin/MaurinDesk.exe` e atualiza `bin/manifest.json` e `update.json` com o hash e o tamanho reais. Publicar os três arquivos no mesmo commit da branch `fila`. Publicar mudanças necessárias da API na hospedagem antes de distribuir um cliente que dependa delas.

## Validação

- `tests/server/files.php`: navegação remota, consentimento de arquivos, destinos, isolamento, partes binárias e comprovantes; inclui a suíte anterior.
- `tests/file_service_probe.lpi` e `tests/file_service_smoke.py`: dois serviços nativos com PHP local, listagem, envio, recebimento, integridade no destino e falha de origem remota.
- `tests/server/clipboard.php`: sinalização, permissões, isolamento por sessão, texto Unicode, partes binárias, integridade e remoção no encerramento.
- `tests/server/schema.php` e `tests/http_smoke.py`: migração e fronteiras HTTP.
- `tests/desktop_features.lpi`: pacotes de arquivos e diretórios, nomes Unicode, bloqueio de caminhos inválidos, SHA-256, versões e configurações.
- `tests/clipboard_windows.lpi`: teste opcional dos formatos nativos em estação de janelas isolada, sem tocar no clipboard do usuário. Retorna código 77 quando o Windows não permite criar a estação isolada; neste ambiente foi ignorado por erro 5 (acesso negado).
- `tests/update_probe.lpi` e `tests/update_fixture.lpr`: substituição e reinício de um executável de teste em pasta com espaço e apóstrofo, preservando backup.
- `--self-test`, `--render-preview` e `--render-settings`: inicialização e inspeção visual local sem registro, firewall ou atualização de rede.

A cópia e colagem entre duas máquinas reais e a publicação do PHP devem ser verificadas no ambiente do usuário.
