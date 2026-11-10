-- =====================================================================
-- CELPLAC — Controle de Estoque  |  01 — Estrutura do banco
-- =====================================================================

-- ---------- Funções utilitárias ----------
create or replace function public.fmt_br(n numeric)
returns text language sql immutable set search_path = '' as $$
  select replace(
    case when n = trunc(n) then trunc(n)::text
         else rtrim(rtrim(n::text, '0'), '.') end,
    '.', ',')
$$;

create or replace function public.hoje_sp()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

-- ---------- Cadastros configuráveis ----------
create table public.categorias (
  id      smallint generated always as identity primary key,
  nome    text not null unique,
  sigla   text not null unique check (sigla ~ '^[A-Z]{2,3}$'),
  ativo   boolean not null default true
);

create table public.especies (
  id      smallint generated always as identity primary key,
  nome    text not null unique,
  sigla   text not null unique check (sigla ~ '^[A-Z]{2,3}$'),
  ativo   boolean not null default true
);

create table public.classificacoes (
  id      smallint generated always as identity primary key,
  nome    text not null unique,
  ordem   smallint not null default 0,
  ativo   boolean not null default true
);

create table public.acabamentos (
  id      smallint generated always as identity primary key,
  nome    text not null unique,
  ativo   boolean not null default true
);

create table public.locais (
  id      smallint generated always as identity primary key,
  nome    text not null unique,
  ativo   boolean not null default true
);

create table public.motivos (
  id      smallint generated always as identity primary key,
  tipo    text not null check (tipo in ('ENTRADA','SAIDA','AJUSTE')),
  nome    text not null,
  ativo   boolean not null default true,
  unique (tipo, nome)
);

-- ---------- Usuários ----------
create table public.perfis (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text not null,
  email       text,
  papel       text not null default 'CONSULTA' check (papel in ('ADMIN','ENCARREGADO','CONSULTA')),
  ativo       boolean not null default false,
  criado_em   timestamptz not null default now()
);

-- ---------- Produtos ----------
create table public.produtos (
  id                integer generated always as identity primary key,
  codigo            text not null unique,
  categoria_id      smallint not null references public.categorias(id),
  especie_id        smallint not null references public.especies(id),
  espessura_mm      numeric(6,2) not null check (espessura_mm > 0),
  comprimento_m     numeric(7,3) not null check (comprimento_m > 0),
  largura_m         numeric(7,3) not null check (largura_m > 0),
  camadas           smallint check (camadas > 0),
  classificacao_id  smallint references public.classificacoes(id),
  acabamento_id     smallint references public.acabamentos(id),
  m3_peca           numeric(14,8) generated always as (espessura_mm / 1000 * comprimento_m * largura_m) stored,
  estoque_minimo    integer not null default 0 check (estoque_minimo >= 0),
  estoque_maximo    integer check (estoque_maximo is null or estoque_maximo >= estoque_minimo),
  custo_unitario    numeric(14,2) check (custo_unitario is null or custo_unitario >= 0),
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);

-- Impede dois cadastros do mesmo item (mesma espécie, espessura, medida, camadas, classificação e acabamento)
create unique index produtos_combinacao_uk on public.produtos
  (categoria_id, especie_id, espessura_mm, comprimento_m, largura_m, camadas, classificacao_id, acabamento_id)
  nulls not distinct;

-- Código automático: CATEGORIA-ESPÉCIE-ESPESSURA-SEQUÊNCIA  (ex.: CP-PI-18-004)
create or replace function public.gerar_codigo_produto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_prefixo text;
  v_seq int;
begin
  new.atualizado_em := now();
  if tg_op = 'INSERT' and (new.codigo is null or btrim(new.codigo) = '') then
    select c.sigla || '-' || e.sigla || '-' ||
           case when new.espessura_mm = trunc(new.espessura_mm)
                then lpad(trunc(new.espessura_mm)::int::text, 2, '0')
                else replace(public.fmt_br(new.espessura_mm), ',', 'P') end
      into v_prefixo
      from public.categorias c, public.especies e
     where c.id = new.categoria_id and e.id = new.especie_id;

    perform pg_advisory_xact_lock(hashtext('codigo:' || v_prefixo));

    select coalesce(max(nullif(split_part(codigo, '-', 4), '')::int), 0) + 1
      into v_seq
      from public.produtos
     where codigo like v_prefixo || '-%'
       and split_part(codigo, '-', 4) ~ '^\d+$';

    new.codigo := v_prefixo || '-' || lpad(v_seq::text, 3, '0');
  end if;
  new.codigo := upper(btrim(new.codigo));
  return new;
end $$;

create trigger produtos_codigo before insert or update on public.produtos
  for each row execute function public.gerar_codigo_produto();

-- ---------- Saldos ----------
create table public.saldos (
  produto_id     integer  not null references public.produtos(id),
  local_id       smallint not null references public.locais(id),
  quantidade     integer  not null default 0,
  atualizado_em  timestamptz not null default now(),
  primary key (produto_id, local_id)
);

-- ---------- Lançamentos (cabeçalho) e movimentações (itens) ----------
create table public.lancamentos (
  id                    uuid primary key,              -- gerado no navegador: chave anti-duplicidade
  numero                bigint generated always as identity unique,
  tipo                  text not null check (tipo in ('ENTRADA','SAIDA','AJUSTE_POSITIVO','AJUSTE_NEGATIVO','ESTORNO','IMPLANTACAO')),
  motivo_id             smallint references public.motivos(id),
  local_id              smallint not null references public.locais(id),
  data_referencia       date not null,
  referencia            text,
  observacao            text,
  usuario_id            uuid references public.perfis(id),
  usuario_nome          text not null,
  autorizado_sem_saldo  boolean not null default false,
  estorno_de            uuid unique references public.lancamentos(id),
  criado_em             timestamptz not null default now(),
  constraint lanc_usuario_obrigatorio check (usuario_id is not null or tipo = 'IMPLANTACAO'),
  constraint lanc_justificativa check (
    tipo not in ('AJUSTE_POSITIVO','AJUSTE_NEGATIVO','ESTORNO')
    or length(btrim(coalesce(observacao, ''))) >= 5),
  constraint lanc_estorno check ((tipo = 'ESTORNO') = (estorno_de is not null))
);

create table public.movimentacoes (
  id               bigint generated always as identity primary key,
  lancamento_id    uuid not null references public.lancamentos(id),
  produto_id       integer not null references public.produtos(id),
  local_id         smallint not null references public.locais(id),
  sinal            smallint not null check (sinal in (1, -1)),
  quantidade       integer not null check (quantidade > 0),
  m3               numeric(14,6) not null,
  saldo_anterior   integer not null,
  saldo_posterior  integer not null,
  criado_em        timestamptz not null default now(),
  unique (lancamento_id, produto_id)
);

create index mov_produto_idx on public.movimentacoes (produto_id, criado_em desc);
create index mov_criado_idx on public.movimentacoes (criado_em desc);
create index lanc_data_idx on public.lancamentos (data_referencia desc);
create index lanc_usuario_idx on public.lancamentos (usuario_id);

-- Histórico permanente: nada é alterado ou apagado
create or replace function public.bloquear_alteracao()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Registros de movimentação são permanentes. Para corrigir, faça um ajuste ou estorno.';
end $$;

create trigger lancamentos_imutavel before update or delete on public.lancamentos
  for each row execute function public.bloquear_alteracao();
create trigger movimentacoes_imutavel before update or delete on public.movimentacoes
  for each row execute function public.bloquear_alteracao();
create trigger lancamentos_sem_truncate before truncate on public.lancamentos
  for each statement execute function public.bloquear_alteracao();
create trigger movimentacoes_sem_truncate before truncate on public.movimentacoes
  for each statement execute function public.bloquear_alteracao();
