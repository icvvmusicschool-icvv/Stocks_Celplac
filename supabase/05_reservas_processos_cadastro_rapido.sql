-- =====================================================================
-- CELPLAC — Controle de Estoque  |  05 — Reservas, recuperação/transformação
--                                     com setor e pendência, cadastro rápido
-- =====================================================================

-- ---------- Setores de destino (configuráveis) ----------
create table public.setores (
  id     smallint generated always as identity primary key,
  nome   text not null unique,
  ativo  boolean not null default true
);
insert into public.setores (nome) values ('Esquadrejadeira'), ('Lixadeira'), ('Pré-Corte'), ('Classificação');

-- ---------- Motivos: comportamento configurável ----------
alter table public.motivos
  add column processo text check (processo in ('RECUPERACAO', 'TRANSFORMACAO')),
  add column respeita_reserva boolean not null default false,
  add column interno boolean not null default false;

update public.motivos set nome = 'Recuperação', processo = 'RECUPERACAO'
 where tipo = 'SAIDA' and nome = 'Saída para reaproveitamento';
update public.motivos set nome = 'Transformação', processo = 'TRANSFORMACAO'
 where tipo = 'SAIDA' and nome = 'Saída para transformação';
update public.motivos set respeita_reserva = true where tipo = 'SAIDA' and nome = 'Venda';
insert into public.motivos (tipo, nome, interno) values
  ('ENTRADA', 'Retorno de recuperação', true),
  ('ENTRADA', 'Retorno de transformação', true);

-- ---------- Produtos: cadastro rápido para revisão do administrador ----------
alter table public.produtos
  add column revisado boolean not null default true,
  add column criado_por_nome text;

-- ---------- Reservas ----------
create table public.reservas (
  id            bigint generated always as identity primary key,
  produto_id    integer  not null references public.produtos(id),
  local_id      smallint not null references public.locais(id),
  quantidade    integer  not null check (quantidade > 0),
  consumida     integer  not null default 0 check (consumida >= 0),
  liberada      integer  not null default 0 check (liberada >= 0),
  destino       text     not null,
  referencia    text,
  observacao    text,
  status        text     not null default 'ATIVA' check (status in ('ATIVA', 'ENCERRADA')),
  usuario_id    uuid     references public.perfis(id),
  usuario_nome  text     not null,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (consumida + liberada <= quantidade)
);
create index reservas_ativas_idx on public.reservas (produto_id, local_id) where status = 'ATIVA';

create table public.reserva_eventos (
  id            bigint generated always as identity primary key,
  reserva_id    bigint not null references public.reservas(id),
  tipo          text   not null check (tipo in ('CRIADA', 'LIBERADA', 'CONSUMIDA')),
  quantidade    integer not null,
  lancamento_id uuid references public.lancamentos(id),
  motivo        text,
  usuario_nome  text not null,
  criado_em     timestamptz not null default now()
);

-- ---------- Recuperação / transformação: pendências ----------
create table public.processos (
  id             uuid primary key,
  numero         bigint generated always as identity unique,
  tipo           text not null check (tipo in ('RECUPERACAO', 'TRANSFORMACAO')),
  setor_id       smallint not null references public.setores(id),
  lancamento_id  uuid not null unique references public.lancamentos(id),
  responsavel_id uuid references public.perfis(id),
  responsavel_nome text not null,
  status         text not null default 'ABERTO' check (status in ('ABERTO', 'CONCLUIDO', 'CANCELADO')),
  criado_em      timestamptz not null default now(),
  concluido_em   timestamptz
);
create index processos_abertos_idx on public.processos (status, responsavel_id);

create table public.processo_itens (
  id           bigint generated always as identity primary key,
  processo_id  uuid not null references public.processos(id),
  produto_id   integer not null references public.produtos(id),
  quantidade   integer not null check (quantidade > 0),
  processada   integer not null default 0 check (processada >= 0),
  perda        integer not null default 0 check (perda >= 0),
  check (processada <= quantidade and perda <= processada),
  unique (processo_id, produto_id)
);

create table public.processo_baixas (
  id                   uuid primary key,          -- chave anti-duplicidade gerada no navegador
  processo_item_id     bigint not null references public.processo_itens(id),
  quantidade_processada integer not null check (quantidade_processada > 0),
  perda                integer not null default 0 check (perda >= 0),
  lancamento_entrada_id uuid references public.lancamentos(id),
  observacao           text,
  usuario_id           uuid references public.perfis(id),
  usuario_nome         text not null,
  criado_em            timestamptz not null default now()
);

-- histórico de baixas e eventos também é permanente
create trigger processo_baixas_imutavel before update or delete on public.processo_baixas
  for each row execute function public.bloquear_alteracao();
create trigger reserva_eventos_imutavel before update or delete on public.reserva_eventos
  for each row execute function public.bloquear_alteracao();

-- ---------- Funções de apoio ----------
create or replace function public.reservado_de(p_produto integer, p_local smallint)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(sum(quantidade - consumida - liberada), 0)::int
    from public.reservas where produto_id = p_produto and local_id = p_local and status = 'ATIVA'
$$;

-- Se o saldo ficou menor que o reservado (por saída de recuperação, transformação,
-- ajuste ou venda autorizada), consome as reservas mais antigas até caber no saldo.
create or replace function public.normalizar_reservas(p_produto integer, p_local smallint, p_lancamento uuid, p_usuario text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_saldo   integer;
  v_excesso integer;
  v_r       record;
  v_usa     integer;
begin
  select quantidade into v_saldo from public.saldos where produto_id = p_produto and local_id = p_local;
  v_excesso := public.reservado_de(p_produto, p_local) - greatest(coalesce(v_saldo, 0), 0);
  if v_excesso <= 0 then return; end if;
  for v_r in
    select * from public.reservas
     where produto_id = p_produto and local_id = p_local and status = 'ATIVA'
     order by criado_em, id for update
  loop
    exit when v_excesso <= 0;
    v_usa := least(v_excesso, v_r.quantidade - v_r.consumida - v_r.liberada);
    update public.reservas
       set consumida = consumida + v_usa, atualizado_em = now(),
           status = case when quantidade - consumida - v_usa - liberada = 0 then 'ENCERRADA' else status end
     where id = v_r.id;
    insert into public.reserva_eventos (reserva_id, tipo, quantidade, lancamento_id, motivo, usuario_nome)
    values (v_r.id, 'CONSUMIDA', v_usa, p_lancamento, 'Saldo usado por movimentação', p_usuario);
    v_excesso := v_excesso - v_usa;
  end loop;
end $$;

-- ---------- Lançamento (versão com reservas e setor de destino) ----------
drop function public.registrar_lancamento(uuid, text, smallint, date, jsonb, text, text, smallint, boolean);

create or replace function public.registrar_lancamento(
  p_id                   uuid,
  p_tipo                 text,
  p_motivo_id            smallint,
  p_data_referencia      date,
  p_itens                jsonb,
  p_referencia           text     default null,
  p_observacao           text     default null,
  p_local_id             smallint default null,
  p_autorizar_sem_saldo  boolean  default false,
  p_setor_id             smallint default null
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
  v_reservado integer;
  v_faltas   jsonb := '[]'::jsonb;
  v_qtd_itens integer := 0;
  v_total_pc integer := 0;
  v_total_m3 numeric := 0;
  v_motivo   record;
  v_esperado text;
  v_proc_num bigint;
  v_proc_id  uuid;
  v_setor    text;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null then
    raise exception 'Usuário não identificado ou inativo.' using errcode = '42501';
  end if;
  if v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite lançar movimentações.' using errcode = '42501';
  end if;
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

  if p_tipo in ('ENTRADA', 'SAIDA') and p_motivo_id is null then
    raise exception 'Informe o motivo da movimentação.';
  end if;
  select * into v_motivo from public.motivos where id = p_motivo_id and ativo;   -- sem linha: campos nulos
  v_esperado := (case when p_tipo like 'AJUSTE%' then 'AJUSTE' else p_tipo end);
  if p_motivo_id is not null and (v_motivo.id is null or v_motivo.tipo <> v_esperado) then
    raise exception 'Motivo inválido para este tipo de movimentação.';
  end if;

  -- Recuperação / transformação exigem setor de destino
  if v_motivo.processo is not null then
    if p_setor_id is null then
      raise exception 'Informe o setor de destino.';
    end if;
    select nome into v_setor from public.setores where id = p_setor_id and ativo;
    if v_setor is null then
      raise exception 'Setor de destino inválido.';
    end if;
  end if;

  if p_data_referencia is null then
    raise exception 'Informe a data de referência.';
  end if;
  if p_data_referencia > public.hoje_sp() then
    raise exception 'A data de referência não pode ser futura.';
  end if;
  if v_papel <> 'ADMIN' and p_data_referencia < public.hoje_sp() - 7 then
    raise exception 'Encarregados podem lançar até 7 dias para trás. Para datas anteriores, procure o administrador.';
  end if;
  if p_tipo like 'AJUSTE%' and length(btrim(coalesce(p_observacao, ''))) < 5 then
    raise exception 'Ajustes exigem justificativa (mínimo 5 caracteres).';
  end if;

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

  v_local := coalesce(p_local_id, (select id from public.locais where ativo order by id limit 1));
  if not exists (select 1 from public.locais where id = v_local and ativo) then
    raise exception 'Local de estoque inválido.';
  end if;

  insert into public.lancamentos (id, tipo, motivo_id, local_id, data_referencia, referencia, observacao,
                                  usuario_id, usuario_nome, autorizado_sem_saldo)
  values (p_id, p_tipo, p_motivo_id, v_local, p_data_referencia,
          nullif(btrim(p_referencia), ''), nullif(btrim(p_observacao), ''),
          auth.uid(), v_nome, coalesce(p_autorizar_sem_saldo, false))
  on conflict (id) do nothing
  returning numero into v_numero;

  if v_numero is null then
    select numero into v_numero from public.lancamentos where id = p_id;
    select numero into v_proc_num from public.processos where lancamento_id = p_id;
    return jsonb_build_object('duplicado', true, 'numero', v_numero, 'processo', v_proc_num);
  end if;

  v_sinal := (case when p_tipo in ('ENTRADA', 'AJUSTE_POSITIVO') then 1 else -1 end);

  if v_motivo.processo is not null then
    v_proc_id := gen_random_uuid();
    insert into public.processos (id, tipo, setor_id, lancamento_id, responsavel_id, responsavel_nome)
    values (v_proc_id, v_motivo.processo, p_setor_id, p_id, auth.uid(), v_nome)
    returning numero into v_proc_num;
  end if;

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

    if v_sinal = -1 and not coalesce(p_autorizar_sem_saldo, false) then
      v_reservado := (case when coalesce(v_motivo.respeita_reserva, false) then public.reservado_de(v_item.produto_id, v_local) else 0 end);
      if v_saldo - v_reservado - v_item.qtd < 0 then
        v_faltas := v_faltas || jsonb_build_object('codigo', v_prod.codigo, 'saldo', v_saldo, 'reservado', v_reservado,
                                                   'disponivel', v_saldo - v_reservado, 'solicitado', v_item.qtd);
      end if;
    end if;

    update public.saldos
       set quantidade = v_saldo + v_sinal * v_item.qtd,
           atualizado_em = now()
     where produto_id = v_item.produto_id and local_id = v_local;

    insert into public.movimentacoes (lancamento_id, produto_id, local_id, sinal, quantidade, m3,
                                      saldo_anterior, saldo_posterior)
    values (p_id, v_item.produto_id, v_local, v_sinal, v_item.qtd,
            round(v_item.qtd * v_prod.m3_peca, 6), v_saldo, v_saldo + v_sinal * v_item.qtd);

    if v_sinal = -1 then
      perform public.normalizar_reservas(v_item.produto_id, v_local, p_id, v_nome);
    end if;

    if v_proc_id is not null then
      insert into public.processo_itens (processo_id, produto_id, quantidade) values (v_proc_id, v_item.produto_id, v_item.qtd);
    end if;

    v_qtd_itens := v_qtd_itens + 1;
    v_total_pc  := v_total_pc + v_item.qtd;
    v_total_m3  := v_total_m3 + v_item.qtd * v_prod.m3_peca;
  end loop;

  if jsonb_array_length(v_faltas) > 0 then
    raise exception 'SALDO_INSUFICIENTE' using detail = v_faltas::text, errcode = 'P0001';
  end if;

  return jsonb_build_object('duplicado', false, 'numero', v_numero, 'itens', v_qtd_itens,
                            'pecas', v_total_pc, 'm3', round(v_total_m3, 3),
                            'processo', v_proc_num, 'setor', v_setor);
end $$;

-- ---------- Estorno (bloqueia o que já virou pendência trabalhada) ----------
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
  v_proc   record;
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
  if exists (select 1 from public.processo_baixas where lancamento_entrada_id = p_lancamento_id) then
    raise exception 'Este lançamento é a conclusão de uma recuperação/transformação e não pode ser estornado. Corrija com um ajuste.';
  end if;
  select * into v_proc from public.processos where lancamento_id = p_lancamento_id for update;
  if v_proc.id is not null then
    if exists (select 1 from public.processo_itens where processo_id = v_proc.id and processada > 0) then
      raise exception 'A pendência nº % já teve itens concluídos; esta saída não pode mais ser estornada.', v_proc.numero;
    end if;
    update public.processos set status = 'CANCELADO', concluido_em = now() where id = v_proc.id;
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

    if v_mov.sinal = 1 and v_saldo - v_mov.quantidade < 0 then
      v_faltas := v_faltas || jsonb_build_object('codigo', v_mov.codigo, 'saldo', v_saldo, 'solicitado', v_mov.quantidade);
    end if;

    update public.saldos set quantidade = v_saldo - v_mov.sinal * v_mov.quantidade, atualizado_em = now()
     where produto_id = v_mov.produto_id and local_id = v_mov.local_id;

    insert into public.movimentacoes (lancamento_id, produto_id, local_id, sinal, quantidade, m3,
                                      saldo_anterior, saldo_posterior)
    values (v_novo, v_mov.produto_id, v_mov.local_id, -v_mov.sinal, v_mov.quantidade, v_mov.m3,
            v_saldo, v_saldo - v_mov.sinal * v_mov.quantidade);

    if v_mov.sinal = 1 then
      perform public.normalizar_reservas(v_mov.produto_id, v_mov.local_id, v_novo, v_nome);
    end if;
  end loop;

  if jsonb_array_length(v_faltas) > 0 then
    raise exception 'SALDO_INSUFICIENTE' using detail = v_faltas::text, errcode = 'P0001';
  end if;

  return jsonb_build_object('numero', v_numero, 'processo_cancelado', v_proc.numero);
end $$;

-- ---------- Reservar / liberar ----------
create or replace function public.reservar(p_produto_id integer, p_quantidade integer, p_destino text,
                                           p_referencia text default null, p_observacao text default null,
                                           p_local_id smallint default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_local smallint; v_saldo integer; v_res integer; v_id bigint; v_cod text;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null or v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite reservar estoque.' using errcode = '42501';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Informe a quantidade a reservar (peças, maior que zero).';
  end if;
  if length(btrim(coalesce(p_destino, ''))) < 3 then
    raise exception 'Informe para qual processo ou destino é a reserva.';
  end if;
  select codigo into v_cod from public.produtos where id = p_produto_id and ativo;
  if v_cod is null then raise exception 'Produto não encontrado ou inativo.'; end if;
  v_local := coalesce(p_local_id, (select id from public.locais where ativo order by id limit 1));

  select quantidade into v_saldo from public.saldos where produto_id = p_produto_id and local_id = v_local for update;
  v_res := public.reservado_de(p_produto_id, v_local);
  if coalesce(v_saldo, 0) - v_res < p_quantidade then
    raise exception 'Só há % peças livres de %: saldo %, já reservadas %.', greatest(coalesce(v_saldo, 0) - v_res, 0), v_cod, coalesce(v_saldo, 0), v_res;
  end if;

  insert into public.reservas (produto_id, local_id, quantidade, destino, referencia, observacao, usuario_id, usuario_nome)
  values (p_produto_id, v_local, p_quantidade, btrim(p_destino), nullif(btrim(p_referencia), ''), nullif(btrim(p_observacao), ''), auth.uid(), v_nome)
  returning id into v_id;
  insert into public.reserva_eventos (reserva_id, tipo, quantidade, usuario_nome) values (v_id, 'CRIADA', p_quantidade, v_nome);
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.liberar_reserva(p_reserva_id bigint, p_quantidade integer default null, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_r record; v_rest integer; v_q integer;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null or v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite liberar reservas.' using errcode = '42501';
  end if;
  select * into v_r from public.reservas where id = p_reserva_id for update;
  if v_r.id is null or v_r.status <> 'ATIVA' then raise exception 'Reserva não encontrada ou já encerrada.'; end if;
  if v_papel <> 'ADMIN' and v_r.usuario_id is distinct from auth.uid() then
    raise exception 'Só quem fez a reserva ou o administrador pode liberá-la.' using errcode = '42501';
  end if;
  v_rest := v_r.quantidade - v_r.consumida - v_r.liberada;
  v_q := coalesce(p_quantidade, v_rest);
  if v_q <= 0 or v_q > v_rest then raise exception 'Quantidade a liberar deve ser entre 1 e %.', v_rest; end if;
  update public.reservas
     set liberada = liberada + v_q, atualizado_em = now(),
         status = case when v_rest - v_q = 0 then 'ENCERRADA' else 'ATIVA' end
   where id = p_reserva_id;
  insert into public.reserva_eventos (reserva_id, tipo, quantidade, motivo, usuario_nome)
  values (p_reserva_id, 'LIBERADA', v_q, nullif(btrim(p_motivo), ''), v_nome);
  return jsonb_build_object('restante', v_rest - v_q);
end $$;

-- ---------- Cadastro rápido de chapa (encarregado ou administrador) ----------
create or replace function public.cadastrar_produto_rapido(
  p_categoria_id smallint, p_especie_id smallint, p_espessura_mm numeric, p_comprimento_m numeric, p_largura_m numeric,
  p_camadas smallint default null, p_classificacao_id smallint default null, p_acabamento_id smallint default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_id integer; v_cod text;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null or v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite cadastrar chapas.' using errcode = '42501';
  end if;
  if p_espessura_mm is null or p_espessura_mm <= 0 or p_espessura_mm > 100 then raise exception 'Bitola inválida (mm).'; end if;
  if p_comprimento_m is null or p_comprimento_m <= 0 or p_comprimento_m > 20 then raise exception 'Comprimento inválido.'; end if;
  if p_largura_m is null or p_largura_m <= 0 or p_largura_m > 20 then raise exception 'Largura inválida.'; end if;
  if not exists (select 1 from public.categorias where id = p_categoria_id and ativo)
     or not exists (select 1 from public.especies where id = p_especie_id and ativo) then
    raise exception 'Tipo ou espécie inválidos.';
  end if;

  select id, codigo into v_id, v_cod from public.produtos
   where categoria_id = p_categoria_id and especie_id = p_especie_id and espessura_mm = p_espessura_mm
     and comprimento_m = p_comprimento_m and largura_m = p_largura_m
     and camadas is not distinct from p_camadas
     and classificacao_id is not distinct from p_classificacao_id
     and acabamento_id is not distinct from p_acabamento_id;
  if v_id is not null then
    update public.produtos set ativo = true where id = v_id and not ativo;
    return jsonb_build_object('id', v_id, 'codigo', v_cod, 'existente', true);
  end if;

  insert into public.produtos (codigo, categoria_id, especie_id, espessura_mm, comprimento_m, largura_m, camadas,
                               classificacao_id, acabamento_id, revisado, criado_por_nome)
  values ('', p_categoria_id, p_especie_id, p_espessura_mm, p_comprimento_m, p_largura_m, p_camadas,
          p_classificacao_id, p_acabamento_id, v_papel = 'ADMIN', v_nome)
  returning id, codigo into v_id, v_cod;
  return jsonb_build_object('id', v_id, 'codigo', v_cod, 'existente', false);
end $$;

-- ---------- Concluir recuperação / transformação (pode ser em partes) ----------
create or replace function public.concluir_processo(
  p_id uuid, p_item_id bigint, p_processado integer, p_perda integer, p_saidas jsonb,
  p_data date default null, p_observacao text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_item record; v_proc record; v_pend integer; v_motivo smallint; v_res jsonb := null;
  v_ok uuid; v_restam integer;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null or v_papel not in ('ADMIN', 'ENCARREGADO') then
    raise exception 'Seu perfil não permite concluir pendências.' using errcode = '42501';
  end if;

  select * into v_item from public.processo_itens where id = p_item_id for update;
  if v_item.id is null then raise exception 'Item da pendência não encontrado.'; end if;
  select * into v_proc from public.processos where id = v_item.processo_id for update;

  -- anti-duplicidade (reenvio do mesmo lançamento)
  if exists (select 1 from public.processo_baixas where id = p_id) then
    return jsonb_build_object('duplicado', true, 'processo', v_proc.numero);
  end if;
  if v_proc.status <> 'ABERTO' then raise exception 'Esta pendência não está mais aberta.'; end if;

  v_pend := v_item.quantidade - v_item.processada;
  if p_processado is null or p_processado <= 0 or p_processado > v_pend then
    raise exception 'Quantidade processada deve ser entre 1 e % peças.', v_pend;
  end if;
  if coalesce(p_perda, 0) < 0 or coalesce(p_perda, 0) > p_processado then
    raise exception 'A perda não pode ser maior que a quantidade processada.';
  end if;
  if (p_saidas is null or jsonb_array_length(p_saidas) = 0) and coalesce(p_perda, 0) < p_processado then
    raise exception 'Informe o produto resultante (novo formato), ou lance toda a quantidade como perda.';
  end if;

  if p_saidas is not null and jsonb_array_length(p_saidas) > 0 then
    select id into v_motivo from public.motivos
     where tipo = 'ENTRADA' and interno and ativo
       and nome = (case when v_proc.tipo = 'RECUPERACAO' then 'Retorno de recuperação' else 'Retorno de transformação' end);
    v_res := public.registrar_lancamento(p_id, 'ENTRADA', v_motivo, coalesce(p_data, public.hoje_sp()), p_saidas,
                                         'Pendência nº ' || v_proc.numero, p_observacao);
    if (v_res->>'duplicado')::boolean then
      return jsonb_build_object('duplicado', true, 'processo', v_proc.numero);
    end if;
  end if;

  insert into public.processo_baixas (id, processo_item_id, quantidade_processada, perda, lancamento_entrada_id, observacao, usuario_id, usuario_nome)
  values (p_id, p_item_id, p_processado, coalesce(p_perda, 0), case when v_res is null then null else p_id end,
          nullif(btrim(p_observacao), ''), auth.uid(), v_nome)
  on conflict (id) do nothing
  returning id into v_ok;
  if v_ok is null then
    return jsonb_build_object('duplicado', true, 'processo', v_proc.numero);
  end if;

  update public.processo_itens set processada = processada + p_processado, perda = perda + coalesce(p_perda, 0) where id = p_item_id;

  select coalesce(sum(quantidade - processada), 0) into v_restam from public.processo_itens where processo_id = v_proc.id;
  if v_restam = 0 then
    update public.processos set status = 'CONCLUIDO', concluido_em = now() where id = v_proc.id;
  end if;

  return jsonb_build_object('duplicado', false, 'processo', v_proc.numero, 'entrada', v_res, 'restam', v_restam);
end $$;

-- ---------- Visões ----------
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

create or replace view public.vw_reservas with (security_invoker = true) as
select r.id, r.produto_id, v.codigo, v.descricao, v.classificacao, v.acabamento, v.especie, v.espessura_mm, v.comprimento_m, v.largura_m,
       r.local_id, l.nome as local, r.quantidade, r.consumida, r.liberada, r.quantidade - r.consumida - r.liberada as restante,
       r.destino, r.referencia, r.observacao, r.status, r.usuario_id, r.usuario_nome, r.criado_em, r.atualizado_em,
       v.saldo, v.reservado as reservado_total
from public.reservas r
join public.vw_estoque v on v.id = r.produto_id
join public.locais l on l.id = r.local_id;

create or replace view public.vw_processo_itens with (security_invoker = true) as
select i.id, i.processo_id, pr.numero, pr.tipo, pr.status, pr.setor_id, s.nome as setor, pr.lancamento_id,
       l.numero as lancamento_numero, l.data_referencia, l.referencia, l.observacao,
       pr.responsavel_id, pr.responsavel_nome, pr.criado_em, pr.concluido_em,
       i.produto_id, v.codigo, v.descricao, v.classificacao, v.acabamento, v.m3_peca,
       i.quantidade, i.processada, i.perda, i.quantidade - i.processada as pendente
from public.processo_itens i
join public.processos pr on pr.id = i.processo_id
join public.setores s on s.id = pr.setor_id
join public.lancamentos l on l.id = pr.lancamento_id
join public.vw_estoque v on v.id = i.produto_id;

-- ---------- Segurança ----------
alter table public.setores enable row level security;
alter table public.reservas enable row level security;
alter table public.reserva_eventos enable row level security;
alter table public.processos enable row level security;
alter table public.processo_itens enable row level security;
alter table public.processo_baixas enable row level security;

do $$
declare t text;
begin
  foreach t in array array['setores','reservas','reserva_eventos','processos','processo_itens','processo_baixas'] loop
    execute format('create policy "leitura_usuarios_ativos" on public.%I for select to authenticated
                    using ((select public.meu_papel()) is not null)', t);
  end loop;
end $$;
create policy "admin_insere" on public.setores for insert to authenticated with check ((select public.meu_papel()) = 'ADMIN');
create policy "admin_edita" on public.setores for update to authenticated using ((select public.meu_papel()) = 'ADMIN') with check ((select public.meu_papel()) = 'ADMIN');
create policy "admin_exclui" on public.setores for delete to authenticated using ((select public.meu_papel()) = 'ADMIN');

revoke all on public.setores, public.reservas, public.reserva_eventos, public.processos, public.processo_itens, public.processo_baixas from anon;
revoke all on public.reservas, public.reserva_eventos, public.processos, public.processo_itens, public.processo_baixas from authenticated;
grant select on public.reservas, public.reserva_eventos, public.processos, public.processo_itens, public.processo_baixas to authenticated;
revoke all on public.vw_reservas, public.vw_processo_itens from anon;

revoke execute on function public.reservado_de(integer, smallint), public.normalizar_reservas(integer, smallint, uuid, text) from public, anon, authenticated;
revoke execute on function public.registrar_lancamento(uuid,text,smallint,date,jsonb,text,text,smallint,boolean,smallint),
  public.reservar(integer,integer,text,text,text,smallint), public.liberar_reserva(bigint,integer,text),
  public.cadastrar_produto_rapido(smallint,smallint,numeric,numeric,numeric,smallint,smallint,smallint),
  public.concluir_processo(uuid,bigint,integer,integer,jsonb,date,text) from public, anon;
grant execute on function public.registrar_lancamento(uuid,text,smallint,date,jsonb,text,text,smallint,boolean,smallint),
  public.reservar(integer,integer,text,text,text,smallint), public.liberar_reserva(bigint,integer,text),
  public.cadastrar_produto_rapido(smallint,smallint,numeric,numeric,numeric,smallint,smallint,smallint),
  public.concluir_processo(uuid,bigint,integer,integer,jsonb,date,text) to authenticated;

alter publication supabase_realtime add table public.reservas, public.processos, public.processo_itens;
