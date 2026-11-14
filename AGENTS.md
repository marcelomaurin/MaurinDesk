# Compilação e distribuição

- O executável Windows deve ser gerado sempre como `bin/MaurinDesk.exe`.
- Não gerar nomes de executável com versão, data ou sufixos. Registrar a versão em `bin/manifest.json`, na interface e no histórico.
- Compilar pelo destino padrão de `desktop/MaurinDesk.lpi`, sem sobrescrever o nome de saída.
- Se o executável estiver aberto e impedir a compilação, solicitar que seja fechado; manter o nome `MaurinDesk.exe`.
- Após recompilar, atualizar tamanho e SHA-256 em `bin/manifest.json`.
- Preferir `./build.ps1`: compila o destino padrão e atualiza também `update.json`, usado pelo atualizador do GitHub.
- Manter a versão de `DESK_VERSION` em `desktop/uDeskUpdate.pas`, os textos da interface e o recurso VersionInfo de `desktop/MaurinDesk.lpi` consistentes.
