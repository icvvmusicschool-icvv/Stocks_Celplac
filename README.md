# Celplac — Estoque e Apontamento de Produção

Sistema web com duas soluções, no mesmo endereço e no mesmo login:

- **Controle de Estoque** — produto acabado: entradas de produção, saídas (venda, recuperação, transformação), reservas, pendências, ajustes, estornos, histórico permanente, painel e exportação Excel/PDF.
- **Apontamento de Produção** — apontamento diário dos setores da fábrica, metas, conferência entre setores e exportação. Feito para celular e tablet no chão de fábrica.
- **Indicadores e custos** — dentro da solução de produção: a leitura gerencial do mês, etapa por etapa, com abertura em detalhe de cada setor, custo por setor e por modelo de chapa, energia, caldeira e o fechamento mensal.

Depois do login o usuário escolhe a solução; quem só tem acesso a uma entra direto nela.

## Estrutura

| Arquivo | O que é |
|---|---|
| `index.html` | O sistema inteiro (abre no navegador; publica no Cloudflare Pages) |
| `supabase/01_estrutura.sql` | Tabelas, código automático dos produtos, bloqueio de alteração do histórico |
| `supabase/02_regras_e_permissoes.sql` | Lançamento atômico, estorno, perfis, permissões (RLS), tempo real |
| `supabase/03_carga_inicial.sql` | Cadastros iniciais + 102 itens da listagem de 09/11/2026 |
| `supabase/04_ajuste_permissoes_gatilhos.sql` | Ajuste de permissões dos gatilhos |
| `supabase/05_reservas_processos_cadastro_rapido.sql` | Reservas, processos pendentes, lançamento v2, cadastro rápido de produto |
| `supabase/06_reserva_destino_por_setor.sql` | Destino da reserva vindo da lista de setores |
| `supabase/07a_apontamento_estrutura.sql` | Setores, máquinas, metas, calendário e tabelas de apontamento |
| `supabase/07b_formularios.sql` | Os formulários de cada setor (campos em JSON) |
| `supabase/07c_funcoes_apontamento.sql` | Registrar, corrigir e cancelar apontamento, com validação no servidor |
| `supabase/07d_visoes_permissoes_apontamento.sql` | Visões, resumos do painel, RLS e permissões |
| `supabase/08_descricao_sem_camadas.sql` | Descrição do produto sem as camadas (viraram coluna própria) |
| `supabase/09_mensagens_em_chapas.sql` | Mensagens do estoque falando em chapas, não em peças |
| `supabase/LEIA-ME.md` | Mapa das migrações e como exportar as de indicadores do Supabase |
| `supabase/functions/admin-usuarios` | Criação de usuários e troca de senha pelo administrador |
| `modelos/modelo_importacao_laminas.xlsx` | Modelo para o estoque de lâminas |

Banco: projeto Supabase `celplac-estoque` (região São Paulo). Os scripts SQL já foram aplicados; ficam aqui como registro.

## Primeiro acesso

1. No painel do Supabase, em **Authentication › Users**, clique em **Add user**, informe seu e-mail e senha e marque **Auto Confirm User**. O primeiro usuário criado vira **Administrador** automaticamente.
2. Em **Authentication › Sign In / Providers**, desative **Allow new users to sign up**. Os demais usuários são criados pelo próprio sistema (menu Usuários).
3. Abra o `index.html` no navegador (ou o endereço publicado) e entre. O sistema não tem modo de demonstração: o acesso é sempre com usuário e senha.

## Publicar

Suba a pasta num repositório GitHub e conecte ao Cloudflare Pages (sem comando de build; diretório de saída `/`).

## Consulta guiada (tela inicial após o login)

Espécie › Bitola › Dimensões › Estoque. As opções saem do cadastro de produtos (`vw_estoque`) e o saldo por localização sai de `saldos` + `locais`. Nada é fixo no código e o banco não foi alterado. As seleções ficam só na memória da sessão.

## Reservas, recuperação/transformação e chapa nova (migração 05)

- **Reservas:** o encarregado separa chapas para um processo futuro. A venda não usa a quantidade reservada. Recuperação e transformação usam o saldo livre primeiro e depois consomem a reserva mais antiga.
- **Recuperação e transformação:** saem pela tela Saída com setor de destino (Esquadrejadeira, Lixadeira, Pré-Corte, Classificação — editáveis em Cadastros). Cada saída abre uma pendência, que avisa quem lançou (contador no menu Pendências). A conclusão pode ser em partes, gerar um ou mais produtos no novo formato e registrar a perda.
- **Chapa sem cadastro:** o encarregado cadastra na hora (Entrada, consulta guiada ou conclusão de pendência). O administrador revisa depois em Cadastros › Produtos.

## Apontamento de produção (migração 07)

Dez setores, um por aba da planilha de apontamento: Laminação, Secagem, Montagem, Prep. Cola,
Controle de Cola, Prensagem, Esquad. e Lixad., Classificação, Assoalho e Junt(Benecke).

- **Apontar:** o operador escolhe o setor e preenche o formulário daquele setor. Botões grandes,
  uma coluna no celular, sem rolagem lateral. Depois de gravar, turno, mesa e espécie continuam
  marcados e só a quantidade é limpa, para lançar a próxima linha sem repetir tudo.
- **Campos por setor:** ficam em `formularios_producao.campos` (JSON). A tela e o servidor leem a
  mesma definição — para mudar um formulário basta alterar essa linha, sem mexer no `index.html`.
- **m³ calculado:** na montagem, classificação e plastificado, o volume sai de
  chapas × espessura ÷ 1000 × comprimento × largura. Conferido contra a planilha de novembro.
- **Painel:** realizado contra meta por setor e por mesa. A meta considera só os dias úteis do
  período (calendário editável). Setor sem meta aparece na unidade dele (chapas, kg, m³).
- **Conferência:** cruza montagem × prensagem (chapas a prensar) e laminação × secagem, que é o
  papel da aba PIN_EUCA_TRP da planilha.
- **Lançamentos:** todos os apontamentos com filtro por período, setor e pessoa, com exportação Excel.
- **Correção:** quem lançou corrige ou cancela no mesmo dia; o administrador, sempre. Toda alteração
  fica no histórico, que não pode ser apagado.
- **Perfil Apontador:** só enxerga a produção, não vê o estoque.

A classificação **não** gera entrada de estoque automaticamente — a entrada continua sendo lançada
pela tela de Entrada do Controle de Estoque. É uma ligação a fazer depois, quando a rotina estiver rodando.

## Listagem de estoque

Colunas: Código · Descrição · Camadas · Classificação · Acabamento · Chapas · Reservado · m³ · Situação.

A descrição é só **Compensado + Espécie + Espessura + Comprimento x Largura**. Camadas, classificação
e acabamento são colunas próprias, para filtrar e ordenar. Nas listas em que o produto é escolhido
(entrada, saída, transferência) e no detalhe do item, as camadas voltam ao lado da descrição — sem
isso dois produtos iguais em medida e qualidade ficariam idênticos na tela. A busca continua achando
por "5 camadas".

No Controle de Estoque a unidade é **chapa** em toda a solução — telas, totais, exportações e mensagens
do banco. O Apontamento de Produção mantém a unidade de cada setor (m³, kg, chapas, pç), porque ela é
configurável em Setores e metas.

## Indicadores e custos (migrações 10a–10p)

Três telas novas dentro da produção, mais a visão gerencial do estoque.

**Indicadores** — a cadeia do cozimento à lixadeira em uma tabela: realizado, meta do mês,
dias com produção, média por dia, projeção do fechamento e situação (OK / Atenção / Crítico).
A projeção é o realizado mais a média dos dias com produção vezes os dias úteis que faltam.
Clicar numa etapa abre o detalhe: dia a dia do mês com a meta diária marcada, quanto entrou
e quanto saiu da etapa com o rendimento, produção por mesa ou máquina, e a composição do
custo daquela etapa. Abaixo, qualidade da classificação por espécie, pontos de atenção que o
próprio banco levanta, e nove indicadores de capa (energia por m³, produtividade, manutenção,
chapas por m³, lâmina comprada, cobertura do estoque, cavaco, consumo de lâmina, resina por chapa).

**Custos** — seis abas: custo por setor com a composição do mês, custo acumulado etapa a etapa
com o rendimento usado, custo da lâmina por espécie (própria e comprada), custo por modelo de
chapa, rateio de energia por setor e o balanço térmico da caldeira.

**Fechamento do mês** — onde a diretoria digita o que muda todo mês: notas de tora e de lâmina
por espécie, preço de resina e trigo, conta e kWh de energia, cavaco, indiretos, manutenção, e
por setor a folha, o número de funcionários, o valor das máquinas e a vida útil.

**Visão gerencial do estoque** — m³ por tipo, espécie, faixa de espessura e qualidade, os dez
maiores itens e a cobertura em dias de montagem.

### De onde vem cada número

- **Volume de cada etapa**: do apontamento. A prensagem conta as chapas dela, mas mede o m³ pelo
  que a montagem montou, como na planilha. Um mês sem apontamento aceita volume informado no fechamento.
- **Energia**: potência de placa de cada um dos 62 motores × fator de carga × horas/dia × dias úteis,
  conciliada com o kWh da fatura e rateada entre os setores incluídos no custo.
- **Caldeira**: balanço térmico a partir do volume secado e prensado. É estimativa, não medição.
  O custo total da caldeira é rateado como vapor para cozimento, secagem e prensagem.
- **Manutenção**: o percentual informado por setor é fixo; o que sobra rateia pela potência instalada.
- **Custo da lâmina**: a própria carrega tora, cozimento, laminação e secagem; a comprada é a nota
  sem o imposto creditado mais o frete.
- **Custo por modelo**: consumo de lâmina por espécie × custo médio da espécie × fator de perda,
  mais a cola (linhas de cola × gramatura × preço da mistura da classe) e a transformação.

### Perfis

| Perfil | Estoque | Apontar | Indicadores | Custos | Fechamento | Cadastros |
|---|---|---|---|---|---|---|
| Administrador | sim | sim | sim | sim | edita | sim |
| Diretoria | consulta | não | sim | sim | edita | não |
| Encarregado | lança e conta | sim | sim | sim | só lê | não |
| Apontador | não vê | sim | não | não | não | não |
| Consulta | consulta | não | não | não | não | não |

As três últimas colunas valem também fora da tela: as funções de indicadores e custo rodam com a
permissão de quem chama, então o RLS do banco barra o acesso mesmo que alguém chame a API direto.
Testado: perfil Consulta lê zero linhas de custo; Encarregado lê normalmente.

## Contagem de estoque

Tela própria para o encarregado corrigir o saldo depois de uma contagem física,
sem precisar calcular a diferença de cabeça.

- Busca o produto e adiciona à lista, ou adiciona de uma vez todos os itens que a busca trouxe.
- Para cada item mostra o **saldo do sistema** e um campo **Contado**. A diferença aparece na hora,
  marcada em verde quando sobra e em vermelho quando falta; item que bate exibe "confere" e não gera lançamento.
- **Justificativa obrigatória** (mínimo 10 letras na tela, cobrada também pelo banco). Sem ela o botão
  de gravar fica desligado.
- A tela de confirmação mostra item por item: saldo, contado e diferença, mais a justificativa, antes de gravar.
- Sobra e falta na mesma contagem viram dois lançamentos (um de aumento, um de redução), cada um
  com a mesma justificativa e referência.
- O saldo anterior e todo o histórico continuam intactos — ajuste não apaga movimento.

A tela **Ajuste de estoque** continua existindo e continua só do administrador: ela serve para
corrigir para mais ou para menos direto, sem contagem.

## Regras implementadas

- Saldo em chapas; m³ = chapas × espessura × comprimento × largura.
- Saída maior que o saldo é recusada pelo banco (só o administrador autoriza).
- Lançamento com vários itens é atômico: grava tudo ou nada.
- Cada saldo é travado durante a gravação — dois usuários não corrompem o mesmo saldo.
- Clique duplo / reenvio não duplica (chave única por lançamento).
- Histórico não pode ser alterado nem apagado; correções por ajuste ou estorno.
- Encarregado lança até 7 dias para trás; datas futuras são recusadas.
