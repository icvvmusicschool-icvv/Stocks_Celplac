-- 07d — Visões, resumos para o painel, RLS e permissões do apontamento.

create or replace view public.vw_apontamentos with (security_invoker = true) as
select a.id, a.numero, a.setor_id, s.codigo as setor_codigo, s.nome as setor, s.unidade,
       a.formulario_id, f.codigo as formulario_codigo, f.nome as formulario,
       a.data, a.turno, a.hora, a.recurso_id, r.nome as recurso,
       a.especie_id, e.nome as especie,
       a.quantidade, a.m3, a.horas, a.dados, a.observacao,
       a.usuario_id, a.usuario_nome, a.criado_em, a.atualizado_em,
       a.cancelado, a.cancelado_em, a.cancelado_por, a.motivo_cancelamento,
       (select count(*) from public.apontamento_historico h where h.apontamento_id = a.id and h.acao = 'EDITADO') as edicoes
from public.apontamentos a
join public.setores_producao s on s.id = a.setor_id
join public.formularios_producao f on f.id = a.formulario_id
left join public.recursos_producao r on r.id = a.recurso_id
left join public.especies e on e.id = a.especie_id;

create or replace function public.meta_de(p_setor smallint, p_recurso smallint, p_data date)
returns numeric language sql stable security definer set search_path = '' as $$
  select m.meta_diaria from public.metas_producao m
   where m.setor_id = p_setor and m.recurso_id is not distinct from p_recurso
     and m.ativo and m.vigencia_inicio <= p_data
   order by m.vigencia_inicio desc limit 1
$$;

create or replace function public.resumo_producao(p_de date, p_ate date)
returns table (setor_id smallint, setor text, setor_codigo text, unidade text, ordem smallint,
               data date, util boolean, m3 numeric, quantidade numeric, horas numeric,
               meta numeric, campo_meta text, lancamentos bigint)
language sql stable security definer set search_path = '' as $$
  select s.id, s.nome, s.codigo, s.unidade, s.ordem,
         d.dia::date, public.dia_util(d.dia::date),
         coalesce(sum(a.m3), 0), coalesce(sum(a.quantidade), 0), coalesce(sum(a.horas), 0),
         case when public.dia_util(d.dia::date) then public.meta_de(s.id, null, d.dia::date) else 0 end,
         coalesce((select m.campo from public.metas_producao m
                    where m.setor_id = s.id and m.recurso_id is null and m.ativo
                    order by m.vigencia_inicio desc limit 1), 'm3'),
         count(a.id)
    from public.setores_producao s
    cross join generate_series(p_de::timestamp, p_ate::timestamp, interval '1 day') as d(dia)
    left join public.apontamentos a
           on a.setor_id = s.id and a.data = d.dia::date and not a.cancelado
   where s.ativo and p_ate >= p_de and p_ate - p_de <= 400
   group by s.id, s.nome, s.codigo, s.unidade, s.ordem, d.dia
$$;

create or replace function public.resumo_recurso(p_setor smallint, p_de date, p_ate date)
returns table (recurso_id smallint, recurso text, data date, m3 numeric, quantidade numeric, meta numeric)
language sql stable security definer set search_path = '' as $$
  select r.id, r.nome, d.dia::date,
         coalesce(sum(a.m3), 0), coalesce(sum(a.quantidade), 0),
         case when public.dia_util(d.dia::date) then public.meta_de(p_setor, r.id, d.dia::date) else 0 end
    from public.recursos_producao r
    cross join generate_series(p_de::timestamp, p_ate::timestamp, interval '1 day') as d(dia)
    left join public.apontamentos a
           on a.recurso_id = r.id and a.data = d.dia::date and not a.cancelado
   where r.setor_id = p_setor and r.ativo and p_ate >= p_de and p_ate - p_de <= 400
   group by r.id, r.nome, d.dia
$$;

alter table public.setores_producao      enable row level security;
alter table public.recursos_producao     enable row level security;
alter table public.formularios_producao  enable row level security;
alter table public.metas_producao        enable row level security;
alter table public.calendario_producao   enable row level security;
alter table public.apontamentos          enable row level security;
alter table public.apontamento_historico enable row level security;

do $$
declare t text;
begin
  foreach t in array array['setores_producao','recursos_producao','formularios_producao','metas_producao',
                           'calendario_producao','apontamentos','apontamento_historico'] loop
    execute format('create policy "leitura_usuarios_ativos" on public.%I for select to authenticated
                    using ((select public.meu_papel()) is not null)', t);
  end loop;
  foreach t in array array['setores_producao','recursos_producao','formularios_producao','metas_producao','calendario_producao'] loop
    execute format('create policy "admin_insere" on public.%I for insert to authenticated
                    with check ((select public.meu_papel()) = ''ADMIN'')', t);
    execute format('create policy "admin_edita" on public.%I for update to authenticated
                    using ((select public.meu_papel()) = ''ADMIN'') with check ((select public.meu_papel()) = ''ADMIN'')', t);
    execute format('create policy "admin_exclui" on public.%I for delete to authenticated
                    using ((select public.meu_papel()) = ''ADMIN'')', t);
  end loop;
end $$;

revoke all on public.setores_producao, public.recursos_producao, public.formularios_producao,
  public.metas_producao, public.calendario_producao, public.apontamentos, public.apontamento_historico from anon;
revoke all on public.vw_apontamentos from anon;
revoke all on public.apontamentos, public.apontamento_historico from authenticated;
grant select on public.apontamentos, public.apontamento_historico to authenticated;

revoke execute on function public.montar_apontamento(record, jsonb, public.apontamentos),
  public.num_json(jsonb), public.meta_de(smallint, smallint, date) from public, anon, authenticated;
revoke execute on function public.registrar_apontamento(uuid, smallint, date, jsonb, text),
  public.editar_apontamento(uuid, date, jsonb, text), public.cancelar_apontamento(uuid, text),
  public.pode_apontar(), public.dia_util(date),
  public.resumo_producao(date, date), public.resumo_recurso(smallint, date, date) from public, anon;
grant execute on function public.registrar_apontamento(uuid, smallint, date, jsonb, text),
  public.editar_apontamento(uuid, date, jsonb, text), public.cancelar_apontamento(uuid, text),
  public.pode_apontar(), public.dia_util(date),
  public.resumo_producao(date, date), public.resumo_recurso(smallint, date, date) to authenticated;

alter publication supabase_realtime add table public.apontamentos;
