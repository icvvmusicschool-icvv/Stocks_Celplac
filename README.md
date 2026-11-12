# Celplac — Estoque e Apontamento de Produção

Sistema web com duas soluções, no mesmo endereço e no mesmo login:

- **Controle de Estoque** — produto acabado: entradas de produção, saídas (venda, recuperação, transformação), reservas, pendências, ajustes, estornos, histórico permanente, painel e exportação Excel/PDF.
- **Apontamento de Produção** — apontamento diário dos setores da fábrica, metas, conferência entre setores e exportação. Feito para celular e tablet no chão de fábrica.

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

## Regras implementadas

- Saldo em peças; m³ = peças × espessura × comprimento × largura.
- Saída maior que o saldo é recusada pelo banco (só o administrador autoriza).
- Lançamento com vários itens é atômico: grava tudo ou nada.
- Cada saldo é travado durante a gravação — dois usuários não corrompem o mesmo saldo.
- Clique duplo / reenvio não duplica (chave única por lançamento).
- Histórico não pode ser alterado nem apagado; correções por ajuste ou estorno.
- Encarregado lança até 7 dias para trás; datas futuras são recusadas.
