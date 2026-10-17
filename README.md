# E aí? Você conhece a nossa história? — dinâmica do noivado

Link público: https://josyalvs-ia.github.io/noivado-andre-josy/

App de uma página só (`index.html`), sem framework e sem build, hospedado no GitHub Pages. O banco (lista de convidados,
palpites, ordem correta e placar) fica no projeto Supabase "Noivado André e Josy". O schema está em `supabase.sql`.

## Como funciona para o convidado
1. Abre o link, toca no próprio nome na lista (ou digita para filtrar) e confirma "Sou eu".
2. Vê as 15 fotos com letras (A a O), iguais às etiquetas das fotos impressas.
3. Toca nas fotos para montar a ordem cronológica. Pode trocar, subir, descer e tirar.
4. **Enviar meu palpite** → confirmação → pontuação, frase e posição no placar. A ordem certa não é revelada.
5. O **placar ao vivo** fica no fim da mesma página e atualiza sozinho.

Cada foto no lugar certo vale 1 ponto. Um palpite por nome. Empate: menor tempo. A ordem correta fica só no banco.

## Área dos noivos
Toque 5 vezes no monograma A|J no topo e digite o PIN. Dá para liberar o palpite de um nome (a pessoa joga de novo)
ou zerar o placar inteiro. O PIN fica na tabela `app_settings`.

## Trocar fotos ou convidados
- Fotos: arquivos em `fotos/` (foto cheia) e `fotos/t/` (miniatura), com nomes aleatórios de propósito.
  No bloco `CONFIG` do `index.html`, `fotos` liga cada letra a um arquivo, em ordem alfabética. A ordem cronológica
  correta é definida só no banco (`secret_order`).
- Convidados: `CONFIG.convidados` no `index.html` e a tabela `guests` no banco (a página usa a do banco quando consegue ler).
- Etiquetas das impressas: a tabela letra → foto → data fica fora deste repositório, com os noivos.
