# Ultra-low-quality restoration branch

Este diretório documenta o branch experimental `experiment/ultra-low-quality-restoration`.

## Objetivo

Investigar e validar técnicas de diagnóstico e restauração para fontes de qualidade extremamente baixa, com foco inicial nos vídeos 160x112 de `Viagens/Portugal/2004`.

O objetivo não é criar regras por câmera, ano ou pasta. O experimento existe para descobrir sinais mensuráveis que possam ser incorporados à camada de adaptabilidade do Restaurador Universal.

## Princípios

- `main` permanece como baseline estável.
- Nenhuma técnica experimental é promovida para `src/RestauradorUniversal.ps1` sem validação A/B.
- Modelo de câmera serve como rótulo de laboratório, não como regra de decisão.
- Qualidade visual e custo computacional são avaliados juntos.
- Fontes originais nunca são alteradas.
- IA generativa é opcional e deve competir com alternativas clássicas mais rápidas.
- A prioridade é recuperar informação real antes de introduzir reconstrução perceptual.

## Hipóteses atuais

Os vídeos 160x112 analisados apresentam aproximadamente 8 fps de informação temporal nova apesar de containers com cadência nominal maior. A linha experimental deve investigar, entre outros:

- recuperação de cadência;
- frames repetidos/quase repetidos;
- compressão e blockiness;
- denoise/deblock conservador;
- sensibilidade do tracking a pré-filtros;
- interpolação por movimento;
- fusão temporal/multi-frame;
- upscale espacial clássico e, posteriormente, VSR/IA quando justificável.

## Estrutura das rodadas A/B

### R1

- **A:** original apenas normalizado para 1080p/25 fps.
- **B:** primeira restauração clássica conservadora e rápida.
- Métricas visuais: preferência geral, detalhe, fluidez, naturalidade e artefatos.
- Métricas de custo: tempo real, x realtime e fps de processamento.

### R2+

Cada rodada deve alterar uma família de variáveis por vez, preservando o vencedor anterior como referência. Exemplos:

1. cadência/interpolação;
2. limpeza espacial;
3. fusão temporal;
4. otimização de velocidade;
5. IA/VSR opcional como comparação posterior.

## Critério de promoção

Uma técnica só deve migrar para o restaurador principal quando:

1. apresentar ganho visual consistente;
2. não introduzir regressões relevantes em naturalidade/artefatos;
3. tiver custo computacional aceitável ou puder ser acionada somente quando o diagnóstico justificar;
4. puder ser expressa como comportamento adaptativo baseado em sinais da fonte, e não como exceção específica para uma câmera ou coleção.

## Estado atual

Branch criado a partir de `main` em 2026-08-22. A primeira bancada A/B está focada nos seis vídeos 160x112 de Portugal/2004.
