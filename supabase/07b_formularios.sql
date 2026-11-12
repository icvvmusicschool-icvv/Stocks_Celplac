-- 07b — Formulários de apontamento (um por aba da planilha)
-- Os campos ficam em JSONB: o servidor e a tela leem a mesma definição.
-- Para mudar um formulário, basta atualizar formularios_producao.campos.

insert into public.formularios_producao (setor_id, codigo, nome, descricao, calcula_m3, ordem, campos)
select s.id, x.codigo, x.nome, x.descricao, x.calc, x.ordem, x.campos::jsonb
from (values
('LAMINACAO','PRODUCAO','Produção de lâminas','Volume útil de lâmina produzido no dia.', false, 1, $j$[
 {"chave":"especie_id","rotulo":"Espécie","tipo":"especie","obrigatorio":true},
 {"chave":"m3","rotulo":"Volume útil","tipo":"numero","obrigatorio":true,"sufixo":"m³"},
 {"chave":"horas","rotulo":"Horas trabalhadas","tipo":"numero","sufixo":"h"}
]$j$),
('LAMINACAO','TORAS','Entrada de toras','Carga de toras recebida na fábrica.', false, 2, $j$[
 {"chave":"especie_id","rotulo":"Espécie","tipo":"especie","obrigatorio":true},
 {"chave":"fornecedor","rotulo":"Fornecedor","tipo":"texto","obrigatorio":true},
 {"chave":"nf","rotulo":"Nota fiscal","tipo":"texto"},
 {"chave":"m3_tora","rotulo":"Volume de tora","tipo":"numero","obrigatorio":true,"sufixo":"m³"},
 {"chave":"toneladas","rotulo":"Peso","tipo":"numero","sufixo":"t"}
]$j$),
('SECAGEM','PRODUCAO','Secagem','Volume seco por turno e espécie.', false, 1, $j$[
 {"chave":"turno","rotulo":"Turno","tipo":"turno","obrigatorio":true},
 {"chave":"especie_id","rotulo":"Espécie","tipo":"especie","obrigatorio":true},
 {"chave":"m3","rotulo":"Volume seco","tipo":"numero","obrigatorio":true,"sufixo":"m³"},
 {"chave":"horas","rotulo":"Horas do turno","tipo":"numero","sufixo":"h"}
]$j$),
('MONTAGEM','PRODUCAO','Montagem de chapas','Uma linha por mesa, espécie e formato montado.', true, 1, $j$[
 {"chave":"recurso_id","rotulo":"Mesa","tipo":"recurso","obrigatorio":true},
 {"chave":"especie_id","rotulo":"Espécie","tipo":"especie","obrigatorio":true},
 {"chave":"comprimento_m","rotulo":"Comprimento","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"largura_m","rotulo":"Largura","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"espessura_mm","rotulo":"Espessura","tipo":"numero","obrigatorio":true,"sufixo":"mm"},
 {"chave":"quantidade","rotulo":"Chapas montadas","tipo":"inteiro","obrigatorio":true,"sufixo":"chapas"},
 {"chave":"tipo_cola","rotulo":"Tipo de cola","tipo":"lista","opcoes":["Fenólica","Branca"]},
 {"chave":"bitola_capa","rotulo":"Bitola capa","tipo":"numero","sufixo":"mm","grupo":"Bitolas das lâminas"},
 {"chave":"bitola_miolo_cola","rotulo":"Bitola miolo cola","tipo":"numero","sufixo":"mm","grupo":"Bitolas das lâminas"},
 {"chave":"bitola_miolo_seco","rotulo":"Bitola miolo seco","tipo":"numero","sufixo":"mm","grupo":"Bitolas das lâminas"},
 {"chave":"bitola_contracapa","rotulo":"Bitola contracapa","tipo":"numero","sufixo":"mm","grupo":"Bitolas das lâminas"},
 {"chave":"reaproveitamento","rotulo":"Reaproveitamento","tipo":"lista","opcoes":["Miolo cola","Miolo seco"],"grupo":"Bitolas das lâminas"}
]$j$),
('PREP_COLA','INSUMO','Resina, trigo e água','Entrada e consumo dos insumos da cola.', false, 1, $j$[
 {"chave":"insumo","rotulo":"Insumo","tipo":"lista","opcoes":["Resina","Trigo","Água"],"obrigatorio":true},
 {"chave":"quantidade","rotulo":"Consumo no dia","tipo":"numero","sufixo":"kg"},
 {"chave":"entrada_kg","rotulo":"Entrada recebida","tipo":"numero","sufixo":"kg"}
]$j$),
('CONTROLE_COLA','BATIDA','Batida de cola','Uma linha por batida preparada.', false, 1, $j$[
 {"chave":"hora","rotulo":"Horário","tipo":"hora","obrigatorio":true},
 {"chave":"tipo_cola","rotulo":"Tipo de cola","tipo":"lista","opcoes":["Fenólica","Branca"],"obrigatorio":true},
 {"chave":"resina_kg","rotulo":"Resina / cola","tipo":"numero","obrigatorio":true,"sufixo":"kg"},
 {"chave":"trigo_kg","rotulo":"Trigo","tipo":"numero","obrigatorio":true,"sufixo":"kg"},
 {"chave":"agua_kg","rotulo":"Água","tipo":"numero","obrigatorio":true,"sufixo":"kg"},
 {"chave":"viscosidade","rotulo":"Viscosidade","tipo":"numero"},
 {"chave":"visto","rotulo":"Responsável","tipo":"texto"}
]$j$),
('CONTROLE_COLA','GRAMATURA','Medição de gramatura','Gramatura medida na passadeira.', false, 2, $j$[
 {"chave":"hora","rotulo":"Horário da medição","tipo":"hora"},
 {"chave":"recurso_id","rotulo":"Passadeira","tipo":"recurso","obrigatorio":true},
 {"chave":"classe","rotulo":"Classe","tipo":"lista","opcoes":["Classe 1","Classe 2","Classe 3"]},
 {"chave":"bitola_mm","rotulo":"Bitola","tipo":"numero","sufixo":"mm"},
 {"chave":"quantidade","rotulo":"Gramatura","tipo":"numero","obrigatorio":true,"sufixo":"g/m²"},
 {"chave":"visto","rotulo":"Responsável","tipo":"texto"}
]$j$),
('PRENSAGEM','PRODUCAO','Prensagem','Chapas prensadas por prensa.', false, 1, $j$[
 {"chave":"recurso_id","rotulo":"Prensa","tipo":"recurso","obrigatorio":true},
 {"chave":"quantidade","rotulo":"Chapas prensadas","tipo":"inteiro","obrigatorio":true,"sufixo":"chapas"}
]$j$),
('PRENSAGEM','PLASTIFICADO','Plastificado','Produção de chapa plastificada.', true, 2, $j$[
 {"chave":"origem","rotulo":"Origem","tipo":"lista","opcoes":["Fabricada","Recuperada"],"obrigatorio":true},
 {"chave":"quantidade","rotulo":"Quantidade","tipo":"inteiro","obrigatorio":true,"sufixo":"chapas"},
 {"chave":"comprimento_m","rotulo":"Comprimento","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"largura_m","rotulo":"Largura","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"espessura_mm","rotulo":"Espessura","tipo":"numero","obrigatorio":true,"sufixo":"mm"}
]$j$),
('ESQUAD_LIXAD','PRODUCAO','Esquadrejadeira e lixadeira','Volume processado por máquina.', false, 1, $j$[
 {"chave":"recurso_id","rotulo":"Máquina","tipo":"recurso","obrigatorio":true},
 {"chave":"m3","rotulo":"Volume processado","tipo":"numero","obrigatorio":true,"sufixo":"m³"}
]$j$),
('CLASSIFICACAO','PRODUCAO','Classificação de chapas','Chapas classificadas por qualidade.', true, 1, $j$[
 {"chave":"especie_id","rotulo":"Espécie","tipo":"especie","obrigatorio":true},
 {"chave":"origem","rotulo":"Origem","tipo":"lista","opcoes":["Produção","Recuperação"],"obrigatorio":true},
 {"chave":"qualidade","rotulo":"Qualidade","tipo":"texto","ajuda":"Ex.: C+/C+"},
 {"chave":"quantidade","rotulo":"Chapas classificadas","tipo":"inteiro","obrigatorio":true,"sufixo":"chapas"},
 {"chave":"comprimento_m","rotulo":"Comprimento","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"largura_m","rotulo":"Largura","tipo":"numero","obrigatorio":true,"sufixo":"m"},
 {"chave":"espessura_mm","rotulo":"Espessura","tipo":"numero","obrigatorio":true,"sufixo":"mm"},
 {"chave":"q1","rotulo":"1ª qualidade","tipo":"inteiro","sufixo":"chapas","grupo":"Separação por qualidade"},
 {"chave":"q2","rotulo":"2ª qualidade","tipo":"inteiro","sufixo":"chapas","grupo":"Separação por qualidade"},
 {"chave":"q3","rotulo":"3ª qualidade","tipo":"inteiro","sufixo":"chapas","grupo":"Separação por qualidade"}
]$j$),
('ASSOALHO','PRODUCAO','Assoalho','Produção de assoalho no dia.', false, 1, $j$[
 {"chave":"quantidade","rotulo":"Peças","tipo":"inteiro","obrigatorio":true,"sufixo":"pç"},
 {"chave":"m3","rotulo":"Volume","tipo":"numero","obrigatorio":true,"sufixo":"m³"},
 {"chave":"quebra_m3","rotulo":"Quebra","tipo":"numero","sufixo":"m³"}
]$j$),
('JUNTADEIRA','PRODUCAO','Juntadeira (Benecke)','Chapas juntadas no dia.', false, 1, $j$[
 {"chave":"quantidade","rotulo":"Chapas juntadas","tipo":"inteiro","obrigatorio":true,"sufixo":"chapas"}
]$j$)
) as x(setor, codigo, nome, descricao, calc, ordem, campos)
join public.setores_producao s on s.codigo = x.setor;
