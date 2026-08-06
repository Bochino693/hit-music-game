# PROMPT - CONTINUAR A REFATORACAO HIT MUSIC R6

Trabalhe diretamente neste projeto Godot 4. Nao apague nem altere a versao antiga antes de a versao R6 funcionar.

## Estrutura criada

- `res://scenes/hit_music/base/hit_music_base.tscn`
- `res://scenes/hit_music/carmine/carmine.tscn`
- `res://scripts/hit_music/`
- `res://songs/carmine/charts/facil.json`
- `res://songs/carmine/charts/dificil.json`

## Regras obrigatorias

1. Preserve `res://entities/tazo.tscn`.
2. O tazo e somente a nota movel. Nunca deixe um tazo parado nos oito destinos.
3. A borda do campo e uma linha branca continua com oito bolinhas fixas.
4. Tap nasce no centro, viaja ate a bolinha e desaparece no julgamento.
5. Acerto normal usa tres losangos nitidos e deterministicos.
6. Slide usa chevrons grandes, solidos, ciano, proximos e com sombra preta.
7. A estrela do slide e grande, vazada, com contornos preto, branco e tematico.
8. Hold e uma capsula fechada, amarela, grossa e com centro escuro.
9. O fundo possui video retangular e overlays geometricos que mudam por secoes.
10. Facil e dificil usam charts JSON diferentes. Nao use apenas multiplicador de velocidade.
11. Nao adicione particulas aleatorias que prejudiquem a leitura.
12. Nao coloque codigo serial dentro da scene. Use um servico persistente com estado desejado.
13. Corrija erros de tipagem GDScript. O projeto trata warnings como erros.
14. Entregue arquivos completos, nao apenas trechos.
15. Antes de afirmar que funciona, valide parsing e referencias de paths.

## Proxima tarefa

Abra e valide:

`res://scenes/hit_music/carmine/carmine.tscn`

Corrija todos os erros de parsing/importacao e deixe a scene executavel. Depois:

- aplique mascara circular ao video;
- posicione o video como retangulo horizontal no centro do circulo;
- adicione selecao de dificuldade;
- implemente hold real;
- implemente slide por touch;
- faca o chart dificil possuir caminhos cruzados;
- mantenha o chart facil simples e legivel.