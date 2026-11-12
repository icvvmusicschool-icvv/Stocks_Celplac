-- 07c — Funções de apontamento: montar/validar, registrar, editar e cancelar.
-- Toda a validação é feita aqui no servidor, a partir da definição do formulário.

alter table public.formularios_producao add column quantidade_soma text[];
update public.formularios_producao set quantidade_soma = array['resina_kg','trigo_kg','agua_kg'] where codigo = 'BATIDA';

-- número vindo do JSON, aceitando vírgula decimal
create or replace function public.num_json(v jsonb)
returns numeric language plpgsql immutable set search_path = '' as $$
declare t text;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  if jsonb_typeof(v) = 'number' then return v::text::numeric; end if;
  t := btrim(replace(v #>> '{}', ',', '.'));
  if t = '' then return null; end if;
  return t::numeric;
exception when others then
  raise exception 'Valor numérico inválido: %', v #>> '{}';
end $$;

create or replace function public.pode_apontar()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.meu_papel() in ('ADMIN','ENCARREGADO','APONTADOR'), false)
$$;

-- Monta e valida um apontamento a partir da definição do formulário
create or replace function public.montar_apontamento(p_form record, p_valores jsonb, inout r public.apontamentos)
language plpgsql security definer set search_path = '' as $$
declare
  c        jsonb;
  chave    text;
  tipo     text;
  rotulo   text;
  v        jsonb;
  txt      text;
  n        numeric;
  dados    jsonb := '{}'::jsonb;
  soma     numeric := 0;
  tem_soma boolean := false;
begin
  r.dados := '{}'::jsonb;
  r.turno := null; r.hora := null; r.recurso_id := null; r.especie_id := null;
  r.quantidade := null; r.m3 := null; r.horas := null;

  for c in select * from jsonb_array_elements(p_form.campos) loop
    chave := c->>'chave'; tipo := c->>'tipo'; rotulo := coalesce(c->>'rotulo', chave);
    v := p_valores -> chave;
    if v is null or jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then
      if coalesce((c->>'obrigatorio')::boolean, false) then
        raise exception 'Informe %.', rotulo;
      end if;
      continue;
    end if;

    if tipo in ('numero','inteiro') then
      n := public.num_json(v);
      if n < 0 then raise exception '% não pode ser negativo.', rotulo; end if;
      if tipo = 'inteiro' and n <> trunc(n) then raise exception '% deve ser um número inteiro.', rotulo; end if;
      if n > 10000000 then raise exception '% está fora da faixa aceita.', rotulo; end if;
      case chave
        when 'quantidade' then r.quantidade := n;
        when 'm3'         then r.m3 := n;
        when 'horas'      then r.horas := n;
        else dados := dados || jsonb_build_object(chave, n);
      end case;

    elsif tipo = 'turno' then
      n := public.num_json(v);
      if n not in (1,2,3) then raise exception 'Turno inválido.'; end if;
      r.turno := n::smallint;

    elsif tipo = 'hora' then
      begin r.hora := (v #>> '{}')::time; exception when others then raise exception 'Horário inválido em %.', rotulo; end;

    elsif tipo = 'especie' then
      r.especie_id := public.num_json(v)::smallint;
      if not exists (select 1 from public.especies where id = r.especie_id and ativo) then
        raise exception 'Espécie inválida.';
      end if;

    elsif tipo = 'recurso' then
      r.recurso_id := public.num_json(v)::smallint;
      if not exists (select 1 from public.recursos_producao
                      where id = r.recurso_id and setor_id = p_form.setor_id and ativo) then
        raise exception '% inválido para este setor.', rotulo;
      end if;

    elsif tipo = 'lista' then
      txt := btrim(v #>> '{}');
      if not (to_jsonb(txt) <@ (c->'opcoes')) then raise exception 'Opção inválida em %.', rotulo; end if;
      dados := dados || jsonb_build_object(chave, txt);

    else   -- texto
      txt := btrim(v #>> '{}');
      if length(txt) > 200 then raise exception '% é longo demais (máximo 200 caracteres).', rotulo; end if;
      dados := dados || jsonb_build_object(chave, txt);
    end if;
  end loop;

  -- quantidade somada a partir de outros campos (ex.: batida de cola)
  if p_form.quantidade_soma is not null then
    foreach chave in array p_form.quantidade_soma loop
      if dados ? chave then soma := soma + (dados->>chave)::numeric; tem_soma := true; end if;
    end loop;
    if tem_soma then r.quantidade := soma; end if;
  end if;

  -- volume calculado a partir das medidas
  if p_form.calcula_m3 then
    if not (dados ? 'comprimento_m' and dados ? 'largura_m' and dados ? 'espessura_mm') or r.quantidade is null then
      raise exception 'Informe quantidade, comprimento, largura e espessura.';
    end if;
    r.m3 := round(r.quantidade * (dados->>'espessura_mm')::numeric / 1000
                  * (dados->>'comprimento_m')::numeric * (dados->>'largura_m')::numeric, 4);
  end if;

  -- separação por qualidade não pode passar do total classificado
  if dados ? 'q1' or dados ? 'q2' or dados ? 'q3' then
    if coalesce((dados->>'q1')::numeric,0) + coalesce((dados->>'q2')::numeric,0) + coalesce((dados->>'q3')::numeric,0)
       > coalesce(r.quantidade, 0) then
      raise exception 'A soma de 1ª, 2ª e 3ª qualidade não pode passar do total de chapas classificadas.';
    end if;
  end if;

  r.dados := dados;
end $$;

create or replace function public.registrar_apontamento(
  p_id uuid, p_formulario_id smallint, p_data date, p_valores jsonb, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_form record; v_r public.apontamentos; v_num bigint; v_setor text;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if v_papel is null then raise exception 'Usuário não identificado ou inativo.' using errcode = '42501'; end if;
  if not public.pode_apontar() then raise exception 'Seu perfil não permite apontar produção.' using errcode = '42501'; end if;
  if p_id is null then raise exception 'Identificador do apontamento ausente.'; end if;

  select f.*, s.nome as setor_nome into v_form
    from public.formularios_producao f join public.setores_producao s on s.id = f.setor_id
   where f.id = p_formulario_id and f.ativo and s.ativo;
  if v_form.id is null then raise exception 'Formulário de apontamento inválido.'; end if;
  v_setor := v_form.setor_nome;

  if p_data is null then raise exception 'Informe a data.'; end if;
  if p_data > public.hoje_sp() then raise exception 'A data não pode ser futura.'; end if;
  if v_papel <> 'ADMIN' and p_data < public.hoje_sp() - 7 then
    raise exception 'Apontamentos podem ser lançados até 7 dias para trás. Para datas anteriores, procure o administrador.';
  end if;

  if exists (select 1 from public.apontamentos where id = p_id) then
    select numero into v_num from public.apontamentos where id = p_id;
    return jsonb_build_object('duplicado', true, 'numero', v_num);
  end if;

  v_r.setor_id := v_form.setor_id;
  v_r := public.montar_apontamento(v_form, p_valores, v_r);

  insert into public.apontamentos (id, setor_id, formulario_id, data, turno, hora, recurso_id, especie_id,
                                   quantidade, m3, horas, dados, observacao, usuario_id, usuario_nome)
  values (p_id, v_form.setor_id, v_form.id, p_data, v_r.turno, v_r.hora, v_r.recurso_id, v_r.especie_id,
          v_r.quantidade, v_r.m3, v_r.horas, v_r.dados, nullif(btrim(p_observacao), ''), auth.uid(), v_nome)
  returning numero into v_num;

  insert into public.apontamento_historico (apontamento_id, acao, depois, usuario_nome)
  values (p_id, 'CRIADO', to_jsonb((select a from public.apontamentos a where a.id = p_id)), v_nome);

  return jsonb_build_object('duplicado', false, 'numero', v_num, 'setor', v_setor,
                            'm3', v_r.m3, 'quantidade', v_r.quantidade);
end $$;

create or replace function public.editar_apontamento(
  p_id uuid, p_data date, p_valores jsonb, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_papel text; v_nome text; v_form record; v_a public.apontamentos; v_r public.apontamentos; v_antes jsonb;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if not public.pode_apontar() then raise exception 'Seu perfil não permite editar apontamentos.' using errcode = '42501'; end if;

  select * into v_a from public.apontamentos where id = p_id for update;
  if v_a.id is null then raise exception 'Apontamento não encontrado.'; end if;
  if v_a.cancelado then raise exception 'Este apontamento foi cancelado e não pode ser editado.'; end if;
  if v_papel <> 'ADMIN' then
    if v_a.usuario_id is distinct from auth.uid() then
      raise exception 'Só quem lançou o apontamento ou o administrador pode corrigi-lo.' using errcode = '42501';
    end if;
    if (v_a.criado_em at time zone 'America/Sao_Paulo')::date < public.hoje_sp() then
      raise exception 'Apontamentos de dias anteriores só podem ser corrigidos pelo administrador.' using errcode = '42501';
    end if;
  end if;

  select f.* into v_form from public.formularios_producao f where f.id = v_a.formulario_id;
  if p_data is null then raise exception 'Informe a data.'; end if;
  if p_data > public.hoje_sp() then raise exception 'A data não pode ser futura.'; end if;
  if v_papel <> 'ADMIN' and p_data < public.hoje_sp() - 7 then
    raise exception 'Apontamentos podem ser lançados até 7 dias para trás.';
  end if;

  v_antes := to_jsonb(v_a);
  v_r.setor_id := v_a.setor_id;
  v_r := public.montar_apontamento(v_form, p_valores, v_r);

  update public.apontamentos
     set data = p_data, turno = v_r.turno, hora = v_r.hora, recurso_id = v_r.recurso_id, especie_id = v_r.especie_id,
         quantidade = v_r.quantidade, m3 = v_r.m3, horas = v_r.horas, dados = v_r.dados,
         observacao = nullif(btrim(p_observacao), ''), atualizado_em = now()
   where id = p_id;

  insert into public.apontamento_historico (apontamento_id, acao, antes, depois, usuario_nome)
  values (p_id, 'EDITADO', v_antes, to_jsonb((select a from public.apontamentos a where a.id = p_id)), v_nome);

  return jsonb_build_object('numero', v_a.numero, 'm3', v_r.m3, 'quantidade', v_r.quantidade);
end $$;

create or replace function public.cancelar_apontamento(p_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_papel text; v_nome text; v_a public.apontamentos;
begin
  select papel, nome into v_papel, v_nome from public.perfis where id = auth.uid() and ativo;
  if not public.pode_apontar() then raise exception 'Seu perfil não permite cancelar apontamentos.' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo do cancelamento (mínimo 5 caracteres).'; end if;

  select * into v_a from public.apontamentos where id = p_id for update;
  if v_a.id is null then raise exception 'Apontamento não encontrado.'; end if;
  if v_a.cancelado then raise exception 'Este apontamento já está cancelado.'; end if;
  if v_papel <> 'ADMIN' then
    if v_a.usuario_id is distinct from auth.uid() then
      raise exception 'Só quem lançou o apontamento ou o administrador pode cancelá-lo.' using errcode = '42501';
    end if;
    if (v_a.criado_em at time zone 'America/Sao_Paulo')::date < public.hoje_sp() then
      raise exception 'Apontamentos de dias anteriores só podem ser cancelados pelo administrador.' using errcode = '42501';
    end if;
  end if;

  update public.apontamentos
     set cancelado = true, cancelado_em = now(), cancelado_por = v_nome,
         motivo_cancelamento = btrim(p_motivo), atualizado_em = now()
   where id = p_id;

  insert into public.apontamento_historico (apontamento_id, acao, antes, usuario_nome)
  values (p_id, 'CANCELADO', to_jsonb(v_a), v_nome);

  return jsonb_build_object('numero', v_a.numero);
end $$;
