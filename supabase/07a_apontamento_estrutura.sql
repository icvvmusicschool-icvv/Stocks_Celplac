-- 07a — Apontamento de produção: estrutura e carga dos setores
-- Aplicada em 12/11/2026. Não altera nada do Controle de Estoque.

alter table public.perfis drop constraint perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check
  check (papel in ('ADMIN','ENCARREGADO','APONTADOR','CONSULTA'));

create table public.setores_producao (
  id       smallint generated always as identity primary key,
  codigo   text not null unique check (codigo ~ '^[A-Z_]{3,24}$'),
  nome     text not null unique,
  unidade  text not null default 'm³',
  ordem    smallint not null default 0,
  ativo    boolean not null default true
);

create table public.recursos_producao (
  id       smallint generated always as identity primary key,
  setor_id smallint not null references public.setores_producao(id),
  codigo   text not null,
  nome     text not null,
  ordem    smallint not null default 0,
  ativo    boolean not null default true,
  unique (setor_id, codigo)
);

create table public.formularios_producao (
  id          smallint generated always as identity primary key,
  setor_id    smallint not null references public.setores_producao(id),
  codigo      text not null check (codigo ~ '^[A-Z_]{3,20}$'),
  nome        text not null,
  descricao   text,
  campos      jsonb not null default '[]',
  calcula_m3  boolean not null default false,
  ordem       smallint not null default 0,
  ativo       boolean not null default true,
  unique (setor_id, codigo)
);

create table public.metas_producao (
  id              smallint generated always as identity primary key,
  setor_id        smallint not null references public.setores_producao(id),
  recurso_id      smallint references public.recursos_producao(id),
  meta_diaria     numeric(14,3) not null check (meta_diaria >= 0),
  campo           text not null default 'm3' check (campo in ('m3','quantidade')),
  vigencia_inicio date not null default '2026-01-01',
  ativo           boolean not null default true,
  unique (setor_id, recurso_id, vigencia_inicio)
);

create table public.calendario_producao (
  data       date primary key,
  util       boolean not null,
  tipo       text not null default 'Útil',
  observacao text
);

create or replace function public.dia_util(p_data date)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select util from public.calendario_producao where data = p_data),
                  extract(isodow from p_data) <= 5)
$$;

create table public.apontamentos (
  id             uuid primary key,
  numero         bigint generated always as identity unique,
  setor_id       smallint not null references public.setores_producao(id),
  formulario_id  smallint not null references public.formularios_producao(id),
  data           date not null,
  turno          smallint check (turno between 1 and 3),
  hora           time,
  recurso_id     smallint references public.recursos_producao(id),
  especie_id     smallint references public.especies(id),
  quantidade     numeric(14,3) check (quantidade >= 0),
  m3             numeric(14,4) check (m3 >= 0),
  horas          numeric(6,2) check (horas >= 0 and horas <= 24),
  dados          jsonb not null default '{}',
  observacao     text,
  usuario_id     uuid references public.perfis(id),
  usuario_nome   text not null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  cancelado      boolean not null default false,
  cancelado_em   timestamptz,
  cancelado_por  text,
  motivo_cancelamento text
);
create index apont_setor_data_idx on public.apontamentos (setor_id, data desc) where not cancelado;
create index apont_data_idx on public.apontamentos (data desc);
create index apont_usuario_idx on public.apontamentos (usuario_id, criado_em desc);

create table public.apontamento_historico (
  id             bigint generated always as identity primary key,
  apontamento_id uuid not null references public.apontamentos(id),
  acao           text not null check (acao in ('CRIADO','EDITADO','CANCELADO')),
  antes          jsonb,
  depois         jsonb,
  usuario_nome   text not null,
  criado_em      timestamptz not null default now()
);
create trigger apont_hist_imutavel before update or delete on public.apontamento_historico
  for each row execute function public.bloquear_alteracao();

insert into public.setores_producao (codigo, nome, unidade, ordem) values
  ('LAMINACAO',    'Laminação',        'm³',     1),
  ('SECAGEM',      'Secagem',          'm³',     2),
  ('MONTAGEM',     'Montagem',         'm³',     3),
  ('PREP_COLA',    'Prep. Cola',       'kg',     4),
  ('CONTROLE_COLA','Controle de Cola', 'kg',     5),
  ('PRENSAGEM',    'Prensagem',        'chapas', 6),
  ('ESQUAD_LIXAD', 'Esquad. e Lixad.', 'm³',     7),
  ('CLASSIFICACAO','Classificação',    'chapas', 8),
  ('ASSOALHO',     'Assoalho',         'm³',     9),
  ('JUNTADEIRA',   'Junt(Benecke)',    'chapas', 10);

insert into public.recursos_producao (setor_id, codigo, nome, ordem)
select s.id, x.codigo, x.nome, x.ordem
  from (values
    ('MONTAGEM','M1','Mesa 1',1),('MONTAGEM','M2','Mesa 2',2),('MONTAGEM','M3','Mesa 3',3),
    ('MONTAGEM','M4','Mesa 4',4),('MONTAGEM','M5','Mesa 5',5),('MONTAGEM','M6','Mesa 6',6),
    ('PRENSAGEM','P1','Prensa 1',1),('PRENSAGEM','P2','Prensa 2',2),('PRENSAGEM','P3','Prensa 3',3),
    ('ESQUAD_LIXAD','ESQ','Esquadrejadeira',1),('ESQUAD_LIXAD','LIX','Lixadeira',2),
    ('CONTROLE_COLA','PS1','P1',1),('CONTROLE_COLA','PS2','P2 (Elevada)',2),('CONTROLE_COLA','PS3','P3 (MR)',3)
  ) as x(setor, codigo, nome, ordem)
  join public.setores_producao s on s.codigo = x.setor;

insert into public.metas_producao (setor_id, recurso_id, meta_diaria, campo)
select s.id, r.id, x.meta, x.campo
  from (values
    ('LAMINACAO',   null, 68.25, 'm3'),
    ('SECAGEM',     null, 55.0,  'm3'),
    ('MONTAGEM',    null, 60.0,  'm3'),
    ('MONTAGEM',    'M1', 15.0,  'm3'),
    ('MONTAGEM',    'M2', 15.0,  'm3'),
    ('MONTAGEM',    'M3', 15.0,  'm3'),
    ('MONTAGEM',    'M4', 15.0,  'm3'),
    ('ESQUAD_LIXAD','ESQ', 40.0, 'm3')
  ) as x(setor, recurso, meta, campo)
  join public.setores_producao s on s.codigo = x.setor
  left join public.recursos_producao r on r.setor_id = s.id and r.codigo = x.recurso
 where x.recurso is null or r.id is not null;
