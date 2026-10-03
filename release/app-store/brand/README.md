# Ícone

`app-icon-1024.png` é uma exportação determinística do vetor existente do AtendeBem, preservando os caminhos e as cores da marca. Formato verificado: PNG sRGB de 1024 × 1024, sem canal alpha. O arquivo foi inspecionado visualmente e copiado para `App/Assets.xcassets/AppIcon.appiconset`.

O catálogo foi incluído no projeto Xcode e em `project.yml`. A validação final do archive continua obrigatória. `reference-icon-512.png` é apenas uma referência do sistema web, não o arquivo destinado à App Store.

Reproduzir na raiz do projeto:

```sh
xcrun swift scripts/export_brand_icon.swift release/app-store/brand/atendebem-icon-source.svg release/app-store/brand/app-icon-1024.png
```

No pacote ZIP extraído, executar o script em `scripts/` usando os caminhos locais `brand/atendebem-icon-source.svg` e `brand/app-icon-1024.png`. Confirmar direitos da entidade publicadora sobre a marca no processo de publicação.
