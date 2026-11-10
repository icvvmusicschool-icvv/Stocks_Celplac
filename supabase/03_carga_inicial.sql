grant execute on function public.criar_perfil() to supabase_auth_admin;

insert into public.categorias (nome, sigla) values ('Compensado','CP'),('Assoalho','AS'),('Lâmina','LM');
insert into public.especies (nome, sigla) values ('Pinus','PI'),('Eucalipto','EU'),('Tropical','TR');
insert into public.classificacoes (nome, ordem) values ('1°',1),('2°',2),('3°',3),('C+/C+',4),('C/C',5),('Shop',6),('Faldown',7);
insert into public.acabamentos (nome) values ('Plastificado'),('Calibrado Oleado'),('Cola MR'),('LVL'),('Pré-corte'),('Resinado');
insert into public.locais (nome) values ('Produto Acabado');
insert into public.motivos (tipo, nome) values
  ('ENTRADA','Produção do dia'),
  ('SAIDA','Venda'),('SAIDA','Saída para reaproveitamento'),('SAIDA','Saída para transformação'),
  ('AJUSTE','Inventário / contagem física'),('AJUSTE','Correção de lançamento');

create temporary table carga (n int, cat text, esp text, espessura numeric, comp numeric, larg numeric,
  camadas smallint, classif text, acab text, qtd int) on commit drop;
insert into carga values
(1,'CP','EU',9,2.44,1.22,null,'2°',null,260),
(2,'CP','EU',12,2.44,1.22,null,'2°',null,720),
(3,'CP','EU',15,2.44,1.22,null,'2°',null,480),
(4,'CP','EU',18,2.44,1.22,null,'2°',null,350),
(5,'CP','EU',18,2.5,1.44,null,'2°',null,183),
(6,'CP','EU',21,2.44,1.22,null,'2°',null,326),
(7,'CP','PI',6,2.44,1.22,null,'1°',null,112),
(8,'CP','PI',6,2.44,1.22,null,'Shop',null,102),
(9,'CP','PI',7,2.44,1.22,null,'C/C',null,300),
(10,'CP','PI',9,2.44,1.22,null,'1°',null,550),
(11,'CP','PI',9,2.44,1.22,null,'2°',null,40),
(12,'CP','PI',9,2.2,1.6,null,'2°','Plastificado',15),
(13,'CP','PI',10,2.5,0.6,null,'1°',null,400),
(14,'CP','PI',10,3.0,0.6,null,'1°',null,780),
(15,'CP','PI',12,2.44,1.22,null,'1°',null,452),
(16,'CP','PI',12,2.44,1.0,null,'2°',null,195),
(17,'CP','PI',12,2.44,1.22,null,'2°',null,215),
(18,'CP','PI',12,2.44,1.22,null,'2°','Plastificado',63),
(19,'CP','PI',12,2.44,1.22,null,'Faldown',null,75),
(20,'CP','PI',12,2.44,1.22,null,null,'LVL',248),
(21,'CP','PI',12,2.44,1.0,null,null,'Pré-corte',245),
(22,'CP','PI',13,2.2,1.1,null,null,'Resinado',560),
(23,'CP','PI',15,2.2,1.52,null,'1°',null,30),
(24,'CP','PI',15,2.44,1.22,5,'1°',null,360),
(25,'CP','PI',15,2.44,1.22,null,'1°','Plastificado',150),
(26,'CP','PI',15,2.44,1.22,null,'2°',null,180),
(27,'CP','PI',15,2.2,1.1,null,'2°','Plastificado',399),
(28,'CP','PI',15,2.44,1.22,null,'2°','Plastificado',365),
(29,'CP','PI',15,2.44,1.22,null,'C+/C+',null,1680),
(30,'CP','PI',15,2.44,1.22,null,null,'Cola MR',180),
(31,'CP','PI',17,2.44,1.22,null,'1°','Plastificado',100),
(32,'CP','PI',18,2.44,1.22,5,'1°',null,560),
(33,'CP','PI',18,2.44,1.22,7,'1°',null,250),
(34,'CP','PI',18,2.2,1.1,null,'1°','Plastificado',50),
(35,'CP','PI',18,2.44,1.22,null,'1°','Plastificado',250),
(36,'CP','PI',18,2.44,1.22,null,'2°','Calibrado Oleado',400),
(37,'CP','PI',18,2.2,1.1,null,'2°','Plastificado',195),
(38,'CP','PI',18,2.44,1.22,null,'2°','Plastificado',59),
(39,'CP','PI',18,2.2,1.1,null,'3°','Plastificado',16),
(40,'CP','PI',18,2.44,1.2,null,'3°','Plastificado',50),
(41,'CP','PI',18,2.44,1.22,7,'C+/C+',null,2500),
(42,'CP','PI',18,2.44,1.22,null,null,'Cola MR',320),
(43,'CP','PI',18,2.44,1.22,null,'Faldown',null,1500),
(44,'CP','PI',20,2.44,1.22,null,'1°',null,64),
(45,'CP','PI',20,2.53,1.63,null,'1°',null,160),
(46,'CP','PI',20,2.44,1.22,null,null,'Cola MR',550),
(47,'CP','PI',22,2.44,1.22,null,'1°',null,28),
(48,'CP','PI',24,2.44,1.22,null,'2°',null,252),
(49,'CP','PI',25,2.44,1.22,null,null,'Cola MR',370),
(50,'CP','PI',28,2.009,1.295,null,'2°',null,193),
(51,'CP','PI',30,2.44,1.22,null,null,'Cola MR',73),
(52,'CP','TR',12,2.5,1.6,null,'1°',null,15),
(53,'CP','TR',12,2.5,1.6,null,'2°',null,8),
(54,'CP','TR',15,2.5,1.6,null,'1°',null,240),
(55,'CP','TR',15,2.1,1.6,null,'2°',null,10),
(56,'CP','TR',15,2.2,1.6,null,'2°',null,93),
(57,'CP','TR',15,2.5,1.25,null,'2°',null,139),
(58,'CP','TR',15,2.5,1.6,null,'2°',null,108),
(59,'CP','TR',18,2.2,1.6,null,'1°',null,20),
(60,'CP','TR',18,2.2,1.6,null,'2°',null,81),
(61,'CP','TR',18,2.24,1.63,null,'2°',null,14),
(62,'CP','TR',18,2.25,1.6,null,'2°',null,18),
(63,'CP','TR',18,2.44,1.63,null,'2°',null,39),
(64,'CP','TR',18,2.5,1.25,null,'2°',null,100),
(65,'CP','TR',18,2.5,1.6,null,'2°',null,67),
(66,'CP','TR',20,2.2,1.6,null,'2°',null,14),
(67,'CP','TR',22,2.44,1.22,null,'1°',null,32),
(68,'CP','TR',22,2.5,1.6,null,'1°',null,62),
(69,'CP','TR',22,2.2,1.6,null,'2°',null,15),
(70,'CP','TR',25,2.2,1.0,null,'2°',null,136),
(71,'CP','TR',25,2.2,1.6,null,'2°',null,10),
(72,'AS','TR',12,3.0,1.6,null,'1°',null,5),
(73,'AS','TR',12,5.9,2.22,null,'1°',null,1),
(74,'AS','TR',15,3.0,1.6,null,'1°',null,30),
(75,'AS','TR',15,4.5,1.6,null,'1°',null,1),
(76,'AS','TR',15,4.5,2.2,null,'1°',null,2),
(77,'AS','TR',15,3.0,1.6,null,'2°',null,23),
(78,'AS','TR',18,5.0,2.5,null,'1°',null,2),
(79,'AS','TR',18,5.5,2.5,null,'1°',null,1),
(80,'AS','TR',18,6.2,2.5,null,'1°',null,18),
(81,'AS','TR',18,7.15,2.5,null,'1°',null,1),
(82,'AS','TR',18,7.5,2.5,null,'1°',null,1),
(83,'AS','TR',18,5.0,2.5,null,'2°',null,1),
(84,'AS','TR',18,6.0,2.48,null,'2°',null,1),
(85,'AS','TR',18,6.2,2.5,null,'2°',null,1),
(86,'AS','TR',18,6.0,2.46,null,'3°',null,1),
(87,'AS','TR',20,4.0,2.5,null,'1°',null,1),
(88,'AS','TR',20,6.2,2.2,null,'1°',null,1),
(89,'AS','TR',20,4.0,2.5,null,'2°',null,1),
(90,'AS','TR',20,4.5,2.5,null,'2°',null,1),
(91,'AS','TR',20,6.2,2.5,null,'2°',null,2),
(92,'AS','TR',20,7.15,2.5,null,'2°',null,1),
(93,'AS','TR',20,5.92,2.2,null,'3°',null,6),
(94,'AS','TR',20,5.985,2.305,null,'3°',null,2),
(95,'AS','TR',24,6.1,2.48,null,'2°',null,1),
(96,'AS','TR',24,7.0,2.5,null,'2°',null,1),
(97,'AS','TR',24,6.2,2.5,null,'3°',null,1),
(98,'AS','TR',25,6.2,2.5,null,'1°',null,4),
(99,'AS','TR',25,7.5,2.5,null,'1°',null,1),
(100,'AS','TR',25,6.2,2.5,null,'2°',null,1),
(101,'AS','TR',25,7.15,2.5,null,'2°',null,1),
(102,'AS','TR',25,7.5,2.5,null,'2°',null,2);

-- Produtos na ordem da listagem (gera os códigos em sequência)
do $$
declare r record;
begin
  for r in select * from carga order by n loop
    insert into public.produtos (codigo, categoria_id, especie_id, espessura_mm, comprimento_m, largura_m, camadas,
                                 classificacao_id, acabamento_id)
    values (null,
      (select id from public.categorias where sigla = r.cat),
      (select id from public.especies where sigla = r.esp),
      r.espessura, r.comp, r.larg, r.camadas,
      (select id from public.classificacoes where nome = r.classif),
      (select id from public.acabamentos where nome = r.acab));
  end loop;
end $$;

-- Lançamento de implantação (saldo inicial de 09/11/2026)
do $$
declare
  v_lanc uuid := gen_random_uuid();
  v_local smallint := (select id from public.locais where nome = 'Produto Acabado');
begin
  insert into public.lancamentos (id, tipo, local_id, data_referencia, referencia, observacao, usuario_nome)
  values (v_lanc, 'IMPLANTACAO', v_local, date '2026-11-09', 'Lista de Estoque 09/11/2026',
          'Saldo inicial importado da listagem de estoque (102 itens).', 'Carga inicial do sistema');

  insert into public.saldos (produto_id, local_id, quantidade)
  select p.id, v_local, c.qtd
    from carga c
    join public.produtos p
      on p.categoria_id = (select id from public.categorias where sigla = c.cat)
     and p.especie_id   = (select id from public.especies where sigla = c.esp)
     and p.espessura_mm = c.espessura and p.comprimento_m = c.comp and p.largura_m = c.larg
     and p.camadas is not distinct from c.camadas
     and p.classificacao_id is not distinct from (select id from public.classificacoes where nome = c.classif)
     and p.acabamento_id    is not distinct from (select id from public.acabamentos where nome = c.acab);

  insert into public.movimentacoes (lancamento_id, produto_id, local_id, sinal, quantidade, m3, saldo_anterior, saldo_posterior)
  select v_lanc, s.produto_id, s.local_id, 1, s.quantidade, round(s.quantidade * p.m3_peca, 6), 0, s.quantidade
    from public.saldos s join public.produtos p on p.id = s.produto_id;

  if (select count(*) from public.saldos) <> 102 or (select sum(quantidade) from public.saldos) <> 19292 then
    raise exception 'Conferência da carga falhou';
  end if;
end $$;
