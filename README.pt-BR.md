# Restaurador Universal de Vídeos

[English](README.md)

**Versão pública atual: 1.0.0**  
Linhagem interna: `V1.6.3.2`

O Restaurador Universal de Vídeos é um pipeline em PowerShell + FFmpeg para restaurar e normalizar coleções pessoais ou arquivísticas de vídeo, produzindo masters 1080p reutilizáveis e mantendo rastreabilidade técnica e histórica.

O projeto nasceu do tratamento de acervos familiares reais e heterogêneos: MPEG-1, AVI/MJPEG, H.264, vídeos VFR, clipes muito curtos, metadados antigos, pillarbox incorporado à imagem e execuções longas sujeitas a interrupção. O objetivo não é inventar informação ausente nem aplicar restauração agressiva por IA. É produzir masters repetíveis, verificáveis e adequados para futuras compilações.

## O que ele faz

- mapeia e valida toda a pasta antes do processamento;
- normaliza VFR para CFR quando necessário;
- testa NVIDIA NVDEC/CUDA e Intel Quick Sync/QSV por arquivo;
- usa CPU como fallback quando hardware decode não é adequado;
- faz censo exato dos frames efetivamente decodificados;
- detecta pillarbox baked-in e refina transições por frame;
- estabiliza com `libvidstab`;
- compõe master 1920x1080, com fundo desfocado quando apropriado;
- aplica limpeza leve de áudio e normalização de loudness em duas passagens;
- retoma a execução por checkpoints;
- valida frame count final e faz smoke-decode;
- preserva e relata metadados históricos com fonte/proveniência, sem tratar timestamps automaticamente como verdade absoluta.

## Requisitos

Ambiente de referência:

- Windows 10/11
- PowerShell 7.6.4+
- FFmpeg full build com `libvidstab`
- NVIDIA NVENC/NVDEC opcional
- Intel Quick Sync/QSV opcional

A linha-base pública 1.0.0 foi exercitada com FFmpeg 9.0, NVIDIA RTX 2050 e Intel Iris Xe. Outros hardwares/codecs podem escolher rotas diferentes ou cair para CPU.

## Uso rápido

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\src\RestauradorUniversal.ps1
```

O script primeiro mapeia os vídeos e pede confirmação antes de iniciar o processamento autônomo. Os originais nunca são sobrescritos.

Para manutenção somente de metadados em masters já produzidos:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\src\RestauradorUniversal.ps1 `
  -SomenteMetadados
```

## Filosofia de preservação

Relógios de câmeras antigas nem sempre eram confiáveis. Timestamp do filesystem, data embutida pela câmera, sequência de nomes e ano da pasta são evidências; não são automaticamente a data verdadeira da filmagem. O Restaurador registra fonte e confiança da evidência temporal para que uma edição futura possa reconstruir a cronologia sem ter interpretações antigas incorporadas de forma irreversível ao acervo.

Veja [Política de metadados e proveniência](docs/FORENSIC_METADATA.md).

## Versionamento

`1.0.0` é a **primeira versão pública**. Todas as iterações internas anteriores são classificadas como builds alpha/beta e ficam preservadas em `legacy/`. Os banners e números internos desses scripts não são alterados, deliberadamente, para manter sua proveniência. Veja [VERSIONING.md](docs/VERSIONING.md).

## Contribuições e forks

Forks, relatos de codecs/hardware e melhorias são bem-vindos. Leia [CONTRIBUTING.md](CONTRIBUTING.md) e, preferencialmente, abra uma Issue antes de alterar o comportamento central de preservação. Uma contribuição útil informa codec/resolução/FPS, frame count esperado, trecho relevante do log, rota de hardware e descrição reproduzível do problema.

Não envie mídia familiar privada apenas para demonstrar um bug. Prefira amostras sintéticas ou não sensíveis.

## Estado do projeto

Este é um instrumento prático de restauração, não um produto comercial polido. A primeira versão pública representa a linha do pipeline que sobreviveu a múltiplos lotes reais, inclusive MPEG-1 VFR legado e clipes muito curtos. Ainda há áreas conhecidas para evolução; veja [ROADMAP.md](docs/ROADMAP.md).

## Licença

Ainda não foi escolhida uma licença open source. O repositório está público para avaliar interesse e colaboração técnica. Antes de incentivar reutilização e redistribuição mais ampla, uma licença deverá ser definida explicitamente.
