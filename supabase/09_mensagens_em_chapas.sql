-- 09 — As mensagens de erro do estoque falavam em "peças"; a fábrica conta em chapas.
-- Reescreve as três funções com o texto trocado, sem mudar mais nada do corpo.
-- (Os formulários de apontamento de produção mantêm a unidade de cada setor.)
do $$
declare f oid; d text;
begin
  for f in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname in ('registrar_lancamento','reservar','concluir_processo')
       and pg_get_functiondef(p.oid) like '%peças%'
  loop
    d := replace(replace(pg_get_functiondef(f), 'peças', 'chapas'), 'Peças', 'Chapas');
    execute d;
  end loop;
end $$;

do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%peças%';
  if n <> 0 then raise exception 'Ainda restam % funções com "peças".', n; end if;
end $$;
