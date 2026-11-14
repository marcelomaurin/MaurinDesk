# MaurinDesk 0.6.5

## Atualização inicial

1. Publicar todo o conteúdo de `server/api/` na hospedagem, preservando o `.env`. O banco migra automaticamente para `0.7`, incluindo as tabelas do clipboard.
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

- `tests/server/clipboard.php`: sinalização, permissões, isolamento por sessão, texto Unicode, partes binárias, integridade e remoção no encerramento.
- `tests/server/schema.php` e `tests/http_smoke.py`: migração e fronteiras HTTP.
- `tests/desktop_features.lpi`: pacotes de arquivos e diretórios, nomes Unicode, bloqueio de caminhos inválidos, SHA-256, versões e configurações.
- `tests/clipboard_windows.lpi`: teste opcional dos formatos nativos em estação de janelas isolada, sem tocar no clipboard do usuário. Retorna código 77 quando o Windows não permite criar a estação isolada; neste ambiente foi ignorado por erro 5 (acesso negado).
- `tests/update_probe.lpi` e `tests/update_fixture.lpr`: substituição e reinício de um executável de teste em pasta com espaço e apóstrofo, preservando backup.
- `--self-test`, `--render-preview` e `--render-settings`: inicialização e inspeção visual local sem registro, firewall ou atualização de rede.

A cópia e colagem entre duas máquinas reais e a publicação do PHP devem ser verificadas no ambiente do usuário.
