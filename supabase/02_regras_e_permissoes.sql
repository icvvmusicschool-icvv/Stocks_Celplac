-- =====================================================================
-- CELPLAC — Controle de Estoque  |  02 — Regras de movimentação e permissões
-- =====================================================================

-- ---------- Perfil do usuário logado ----------
create or replace function public.meu_papel()
returns text language sql stable security definer set search_path = '' as $$
  select papel from public.perfis where id = auth.uid() and ativo
$$;

-- Cria o perfil quando um usuário é criado no Supabase Auth.
-- O primeiro usuário vira ADMIN ativo; os demais nascem INATIVOS e só passam
-- a acessar quando um administrador os cria/ativa pelo sistema.
create or replace function public.criar_perfil()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_primeiro boolean;
begin
  perform pg_advisory_xact_lock(hashtext('primeiro_admin'));
  select not exists (select 1 from public.perfis where papel = 'ADMIN') into v_primeiro;
  insert into public.perfis (id, nome, email, papel, ativo)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
    new.email,
    case when v_primeiro then 'ADMIN' else 'CONSULTA' end,
    v_primeiro
  );
  return new;
end $$;

create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.criar_perfil();

-- ---------- Lançamento de entradas, saídas e ajustes ----------
-- Tudo em uma única transação: ou todos os itens são gravados e os saldos
-- atualizados, ou nada é alterado. Cada saldo é travado (FOR UPDATE) antes
-- da alteração, impedindo que dois usuários derrubem o mesmo saldo errado.
create or replace function public.registrar_lancamento(
  p_id                   uuid,
  p_tipo                 text,
  p_motivo_id            smallint,
  p_data_referencia      date,
  p_itens                jsonb,
  p_referencia           text    default null,
  p_observacao           text    default null,
  p_local_id             smallint default null,
  p_autorizar_sem_saldo  boolean default false
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel    text;
  v_nome     text;
  v_local    smallint;
  v_sinal    smallint;
  v_numero   bigint;
  v_item     record;
  v_prod     record;
  v_saldo    integer;
  v_faltas   jsonb := '[]'::jsonb;
  v_qtd_itens integer := 0;
  v_total_pc integer := 0;
  v_total_m3 numeric := 0;
  v_motivo_tipo text;
begin
  -- Quem está lançando
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null then
    raise exception 'Usuário não identificado ou inativo.' using errcode = '42501';
  end if;
  if v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite lançar movimentações.' using errcode = '42501';
  end if;

  -- Tipo e permissões especiais
  if p_tipo not in ('ENTRADA', 'SAIDA', 'AJUSTE_POSITIVO', 'AJUSTE_NEGATIVO') then
    raise exception 'Tipo de movimentação inválido.';
  end if;
  if p_tipo like 'AJUSTE%' and v_papel <> 'ADMIN' then
    raise exception 'Somente o administrador pode lançar ajustes.' using errcode = '42501';
  end if;
  if coalesce(p_autorizar_sem_saldo, false) and v_papel <> 'ADMIN' then
    raise exception 'Somente o administrador pode autorizar saída sem saldo.' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'Identificador do lançamento ausente.';
  end if;

  -- Motivo
  if p_tipo in ('ENTRADA', 'SAIDA') and p_motivo_id is null then
    raise exception 'Informe o motivo da movimentação.';
  end if;
  if p_motivo_id is not null then
    select tipo into v_motivo_tipo from public.motivos where id = p_motivo_id and ativo;
    if v_motivo_tipo is null or v_motivo_tipo <> (case when p_tipo like 'AJUSTE%' then 'AJUSTE' else p_tipo end) then
      raise exception 'Motivo inválido para este tipo de movimentação.';
    end if;
  end if;

  -- Data de referência (data da produção / venda)
  if p_data_referencia is null then
    raise exception 'Informe a data de referência.';
  end if;
  if p_data_referencia > public.hoje_sp() then
    raise exception 'A data de referência não pode ser futura.';
  end if;
  if v_papel <> 'ADMIN' and p_data_referencia < public.hoje_sp() - 7 then
    raise exception 'Encarregados podem lançar até 7 dias para trás. Para datas anteriores, procure o administrador.';
  end if;

  -- Justificativa obrigatória em ajustes
  if p_tipo like 'AJUSTE%' and length(btrim(coalesce(p_observacao, ''))) < 5 then
    raise exception 'Ajustes exigem justificativa (mínimo 5 caracteres).';
  end if;

  -- Itens
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item.';
  end if;
  if jsonb_array_length(p_itens) > 300 then
    raise exception 'Máximo de 300 itens por lançamento.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_itens) e
     where jsonb_typeof(e->'produto_id') <> 'number'
        or jsonb_typeof(e->'quantidade') <> 'number'
        or (e->>'quantidade')::numeric <= 0
        or (e->>'quantidade')::numeric <> trunc((e->>'quantidade')::numeric)
        or (e->>'quantidade')::numeric > 1000000
  ) then
    raise exception 'Quantidade deve ser um número inteiro de peças, maior que zero.';
  end if;

  -- Local (v1: local padrão = primeiro local ativo)
  v_local := coalesce(p_local_id, (select id from public.locais where ativo order by id limit 1));
  if not exists (select 1 from public.locais where id = v_local and ativo) then
    raise exception 'Local de estoque inválido.';
  end if;

  -- Cabeçalho (proteção contra lançamento duplicado: o mesmo p_id nunca grava duas vezes)
  insert into public.lancamentos (id, tipo, motivo_id, local_id, data_referencia, referencia, observacao,
                                  usuario_id, usuario_nome, autorizado_sem_saldo)
  values (p_id, p_tipo, p_motivo_id, v_local, p_data_referencia,
          nullif(btrim(p_referencia), ''), nullif(btrim(p_observacao), ''),
          auth.uid(), v_nome, coalesce(p_autorizar_sem_saldo, false))
  on conflict (id) do nothing
  returning numero into v_numero;

  if v_numero is null then
    select numero into v_numero from public.lancamentos where id = p_id;
    return jsonb_build_object('duplicado', true, 'numero', v_numero);
  end if;

  v_sinal := case when p_tipo in ('ENTRADA', 'AJUSTE_POSITIVO') then 1 else -1 end;

  -- Itens em ordem de produto (evita travamento cruzado entre usuários)
  for v_item in
    select (e->>'produto_id')::int as produto_id, sum((e->>'quantidade')::int)::int as qtd
      from jsonb_array_elements(p_itens) e
     group by 1
     order by 1
  loop
    select id, codigo, m3_peca, ativo into v_prod from public.produtos where id = v_item.produto_id;
    if v_prod.id is null then
      raise exception 'Produto % não encontrado.', v_item.produto_id;
    end if;
    if not v_prod.ativo then
      raise exception 'O produto % está inativo.', v_prod.codigo;
    end if;

    insert into public.saldos (produto_id, local_id, quantidade)
    values (v_item.produto_id, v_local, 0)
    on conflict do nothing;

    select quantidade into v_saldo
      from public.saldos
     where produto_id = v_item.produto_id and local_id = v_local
       for update;

    if v_sinal = -1 and v_saldo - v_item.qtd < 0 and not coalesce(p_autorizar_sem_saldo, false) then
      v_faltas := v_faltas || jsonb_build_object(
        'codigo', v_prod.codigo, 'saldo', v_saldo, 'solicitado', v_item.qtd);
    end if;

    update public.saldos
       set quantidade = v_saldo + v_sinal * v_item.qtd,
           atualizado_em = now()
     where produto_id = v_item.produto_id and local_id = v_local;

    insert into public.movimentacoes (lancamento_id, produto_id, local_id, sinal, quantidade, m3,
                                      saldo_anterior, saldo_posterior)
    values (p_id, v_item.produto_id, v_local, v_sinal, v_item.qtd,
            round(v_item.qtd * v_prod.m3_peca, 6), v_saldo, v_saldo + v_sinal * v_item.qtd);

    v_qtd_itens := v_qtd_itens + 1;
    v_total_pc  := v_total_pc + v_item.qtd;
    v_total_m3  := v_total_m3 + v_item.qtd * v_prod.m3_peca;
  end loop;

  -- Saída maior que o saldo: desfaz TUDO e informa os itens
  if jsonb_array_length(v_faltas) > 0 then
    raise exception 'SALDO_INSUFICIENTE' using detail = v_faltas::text, errcode = 'P0001';
  end if;

  return jsonb_build_object('duplicado', false, 'numero', v_numero, 'itens', v_qtd_itens,
                            'pecas', v_total_pc, 'm3', round(v_total_m3, 3));
end $$;

-- ---------- Estorno de um lançamento inteiro (somente administrador) ----------
-- Não apaga o original: grava um novo lançamento com os sinais invertidos.
create or replace function public.estornar_lancamento(p_lancamento_id uuid, p_justificativa text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel  text;
  v_nome   text;
  v_orig   record;
  v_novo   uuid := gen_random_uuid();
  v_numero bigint;
  v_mov    record;
  v_saldo  integer;
  v_faltas jsonb := '[]'::jsonb;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is distinct from 'ADMIN' then
    raise exception 'Somente o administrador pode estornar lançamentos.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception 'Informe a justificativa do estorno (mínimo 5 caracteres).';
  end if;

  select * into v_orig from public.lancamentos where id = p_lancamento_id;
  if v_orig.id is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_orig.tipo in ('ESTORNO', 'IMPLANTACAO') then
    raise exception 'Este tipo de lançamento não pode ser estornado.';
  end if;
  if exists (select 1 from public.lancamentos where estorno_de = p_lancamento_id) then
    raise exception 'Este lançamento já foi estornado.';
  end if;

  insert into public.lancamentos (id, tipo, motivo_id, local_id, data_referencia, referencia, observacao,
                                  usuario_id, usuario_nome, estorno_de)
  values (v_novo, 'ESTORNO', null, v_orig.local_id, public.hoje_sp(),
          'Estorno do lançamento nº ' || v_orig.numero, btrim(p_justificativa),
          auth.uid(), v_nome, p_lancamento_id)
  returning numero into v_numero;

  for v_mov in
    select m.*, p.codigo from public.movimentacoes m
      join public.produtos p on p.id = m.produto_id
     where m.lancamento_id = p_lancamento_id
     order by m.produto_id
  loop
    select quantidade into v_saldo from public.saldos
     where produto_id = v_mov.produto_id and local_id = v_mov.local_id for update;

    if -v_mov.sinal = -1 and v_saldo - v_mov.quantidade < 0 then
      v_faltas := v_faltas || jsonb_build_object('codigo', v_mov.codigo, 'saldo', v_saldo, 'solicitado', v_mov.quantidade);
    end if;

    update public.saldos set quantidade = v_saldo - v_mov.sinal * v_mov.quantidade, atualizado_em = now()
     where produto_id = v_mov.produto_id and local_id = v_mov.local_id;

    insert into public.movimentacoes (lancamento_id, produto_id, local_id, sinal, quantidade, m3,
                                      saldo_anterior, saldo_posterior)
    values (v_novo, v_mov.produto_id, v_mov.local_id, -v_mov.sinal, v_mov.quantidade, v_mov.m3,
            v_saldo, v_saldo - v_mov.sinal * v_mov.quantidade);
  end loop;

  if jsonb_array_length(v_faltas) > 0 then
    raise exception 'SALDO_INSUFICIENTE' using detail = v_faltas::text, errcode = 'P0001';
  end if;

  return jsonb_build_object('numero', v_numero);
end $$;

-- ---------- Gestão de usuários (somente administrador) ----------
create or replace function public.admin_atualizar_usuario(p_id uuid, p_nome text, p_papel text, p_ativo boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.meu_papel() is distinct from 'ADMIN' then
    raise exception 'Somente o administrador pode alterar usuários.' using errcode = '42501';
  end if;
  if p_papel not in ('ADMIN', 'ENCARREGADO', 'CONSULTA') then
    raise exception 'Perfil inválido.';
  end if;
  if p_id = auth.uid() and (p_papel <> 'ADMIN' or not p_ativo) then
    raise exception 'Você não pode remover seu próprio acesso de administrador.';
  end if;
  update public.perfis
     set nome = coalesce(nullif(btrim(p_nome), ''), nome), papel = p_papel, ativo = p_ativo
   where id = p_id;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

-- ---------- Visões (respeitam as permissões de quem consulta) ----------
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
    public.fmt_br(p.comprimento_m) || ' x ' || public.fmt_br(p.largura_m) || ' m' ||
    coalesce(' – ' || p.camadas || ' camadas', '') as descricao,
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
  s.atualizado_em as saldo_atualizado_em
from public.produtos p
join public.categorias c on c.id = p.categoria_id
join public.especies e on e.id = p.especie_id
left join public.classificacoes cl on cl.id = p.classificacao_id
left join public.acabamentos a on a.id = p.acabamento_id
left join (select produto_id, sum(quantidade)::int as saldo, max(atualizado_em) as atualizado_em
             from public.saldos group by produto_id) s on s.produto_id = p.id;

create or replace view public.vw_movimentacoes with (security_invoker = true) as
select
  m.id, m.lancamento_id, l.numero, l.tipo, mo.nome as motivo,
  l.data_referencia, l.referencia, l.observacao, l.usuario_id, l.usuario_nome,
  l.autorizado_sem_saldo, l.estorno_de, l.criado_em,
  (select x.numero from public.lancamentos x where x.estorno_de = l.id) as estornado_por_numero,
  m.produto_id, v.codigo, v.descricao, v.categoria, v.especie, v.espessura_mm,
  v.classificacao, v.acabamento, lo.nome as local,
  m.sinal, m.quantidade, m.sinal * m.quantidade as quantidade_assinada,
  m.m3, m.sinal * m.m3 as m3_assinado, m.saldo_anterior, m.saldo_posterior
from public.movimentacoes m
join public.lancamentos l on l.id = m.lancamento_id
join public.vw_estoque v on v.id = m.produto_id
join public.locais lo on lo.id = m.local_id
left join public.motivos mo on mo.id = l.motivo_id;

-- ---------- RLS: segurança no servidor ----------
alter table public.categorias     enable row level security;
alter table public.especies       enable row level security;
alter table public.classificacoes enable row level security;
alter table public.acabamentos    enable row level security;
alter table public.locais         enable row level security;
alter table public.motivos        enable row level security;
alter table public.perfis         enable row level security;
alter table public.produtos       enable row level security;
alter table public.saldos         enable row level security;
alter table public.lancamentos    enable row level security;
alter table public.movimentacoes  enable row level security;

-- Leitura: qualquer usuário ativo
do $$
declare t text;
begin
  foreach t in array array['categorias','especies','classificacoes','acabamentos','locais','motivos',
                           'perfis','produtos','saldos','lancamentos','movimentacoes'] loop
    execute format('create policy "leitura_usuarios_ativos" on public.%I for select to authenticated
                    using ((select public.meu_papel()) is not null)', t);
  end loop;
  -- Cadastros: somente administrador cria, edita e exclui
  foreach t in array array['categorias','especies','classificacoes','acabamentos','locais','motivos','produtos'] loop
    execute format('create policy "admin_insere" on public.%I for insert to authenticated
                    with check ((select public.meu_papel()) = ''ADMIN'')', t);
    execute format('create policy "admin_edita" on public.%I for update to authenticated
                    using ((select public.meu_papel()) = ''ADMIN'') with check ((select public.meu_papel()) = ''ADMIN'')', t);
    execute format('create policy "admin_exclui" on public.%I for delete to authenticated
                    using ((select public.meu_papel()) = ''ADMIN'')', t);
  end loop;
end $$;
-- saldos, lançamentos, movimentações e perfis: sem escrita direta.
-- Só as funções acima (com todas as validações) alteram esses dados.

-- Visitantes não autenticados não acessam nada
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon, public;
grant execute on function public.meu_papel(), public.registrar_lancamento(uuid,text,smallint,date,jsonb,text,text,smallint,boolean),
  public.estornar_lancamento(uuid,text), public.admin_atualizar_usuario(uuid,text,text,boolean),
  public.fmt_br(numeric), public.hoje_sp() to authenticated;
revoke all on public.saldos, public.lancamentos, public.movimentacoes, public.perfis from authenticated;
grant select on public.saldos, public.lancamentos, public.movimentacoes, public.perfis to authenticated;

-- ---------- Tempo real ----------
alter publication supabase_realtime add table public.saldos, public.lancamentos, public.movimentacoes, public.produtos;
