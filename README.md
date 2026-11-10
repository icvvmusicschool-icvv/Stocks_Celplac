# Celplac Estoque — v1 (produto acabado)

Sistema web de controle de estoque de compensados e assoalhos: entradas de produção, saídas (venda, reaproveitamento, transformação), ajustes, estornos, histórico permanente, painel e exportação Excel/PDF.

## Estrutura

| Arquivo | O que é |
|---|---|
| `index.html` | O sistema inteiro (abre no navegador; publica no Cloudflare Pages) |
| `supabase/01_estrutura.sql` | Tabelas, código automático dos produtos, bloqueio de alteração do histórico |
| `supabase/02_regras_e_permissoes.sql` | Lançamento atômico, estorno, perfis, permissões (RLS), tempo real |
| `supabase/03_carga_inicial.sql` | Cadastros iniciais + 102 itens da listagem de 09/11/2026 |
| `supabase/functions/admin-usuarios` | Criação de usuários e troca de senha pelo administrador |
| `modelos/modelo_importacao_laminas.xlsx` | Modelo para o estoque de lâminas |

Banco: projeto Supabase `celplac-estoque` (região São Paulo). Os scripts SQL já foram aplicados; ficam aqui como registro.

## Primeiro acesso

1. No painel do Supabase, em **Authentication › Users**, clique em **Add user**, informe seu e-mail e senha e marque **Auto Confirm User**. O primeiro usuário criado vira **Administrador** automaticamente.
2. Em **Authentication › Sign In / Providers**, desative **Allow new users to sign up**. Os demais usuários são criados pelo próprio sistema (menu Usuários).
3. Abra o `index.html` no navegador e entre.

## Publicar

Suba a pasta num repositório GitHub e conecte ao Cloudflare Pages (sem comando de build; diretório de saída `/`).

## Regras implementadas

- Saldo em peças; m³ = peças × espessura × comprimento × largura.
- Saída maior que o saldo é recusada pelo banco (só o administrador autoriza).
- Lançamento com vários itens é atômico: grava tudo ou nada.
- Cada saldo é travado durante a gravação — dois usuários não corrompem o mesmo saldo.
- Clique duplo / reenvio não duplica (chave única por lançamento).
- Histórico não pode ser alterado nem apagado; correções por ajuste ou estorno.
- Encarregado lança até 7 dias para trás; datas futuras são recusadas.
