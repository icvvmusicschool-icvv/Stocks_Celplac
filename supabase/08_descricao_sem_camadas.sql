-- 08 — A descrição do produto passa a ser só:
--     Compensado + Espécie + Espessura + Comprimento x Largura.
-- As camadas saíram do texto e viraram coluna própria na tela
-- (vw_estoque.camadas já existia; nada mudou na tabela produtos).
-- vw_reservas e vw_movimentos leem a descrição daqui, então herdam a mudança.

create or replace view public.vw_estoque with (security_invoker = true) as
select
  p.id, p.codigo, p.ativo,
  c.nome as categoria, c.sigla as categoria_sigla,
  e.nome as especie,
  p.espessura_mm, p.comprimento_m, p.largura_m, p.camadas,
  cl.nome as classificacao, cl.ordem as classificacao_ordem,
  a.nome as acabamento,
  p.classificacao_id, p.acabamento_id, p.categoria_id, p.especie_id,
  c.nome || ' ' || e.nome || ' ' || public.fmt_br(p.espessura_mm) || ' mm – ' ||
    public.fmt_br(p.comprimento_m) || ' x ' || public.fmt_br(p.largura_m) || ' m' as descricao,
  p.m3_peca, p.estoque_minimo, p.estoque_maximo, p.custo_unitario,
  coalesce(s.saldo, 0) as saldo,
  round(coalesce(s.saldo, 0) * p.m3_peca, 3) as m3_total,
  case when p.custo_unitario is null then null else round(coalesce(s.saldo, 0) * p.custo_unitario, 2) end as valor_total,
  case
    when coalesce(s.saldo, 0) < 0 then 'NEGATIVO'
    when coalesce(s.saldo, 0) = 0 then 'ZERADO'
    when p.estoque_minimo > 0 and s.saldo < p.estoque_minimo then 'ABAIXO_MINIMO'
    when p.estoque_maximo is not null and s.saldo > p.estoque_maximo then 'ACIMA_MAXIMO'
    else 'OK'
  end as status,
  s.atualizado_em as saldo_atualizado_em,
  coalesce(r.reservado, 0) as reservado,
  coalesce(s.saldo, 0) - coalesce(r.reservado, 0) as disponivel,
  p.revisado, p.criado_por_nome
from public.produtos p
join public.categorias c on c.id = p.categoria_id
join public.especies e on e.id = p.especie_id
left join public.classificacoes cl on cl.id = p.classificacao_id
left join public.acabamentos a on a.id = p.acabamento_id
left join (select produto_id, sum(quantidade)::int as saldo, max(atualizado_em) as atualizado_em
             from public.saldos group by produto_id) s on s.produto_id = p.id
left join (select produto_id, sum(quantidade - consumida - liberada)::int as reservado
             from public.reservas where status = 'ATIVA' group by produto_id) r on r.produto_id = p.id;
