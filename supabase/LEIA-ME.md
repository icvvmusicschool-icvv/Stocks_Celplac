# Migrações do banco

Os arquivos `01_` a `09_` desta pasta são o SQL aplicado, na ordem.

As migrações do **apontamento de produção** (`07a` a `07d`) estão aqui como arquivo.
As de **indicadores e custos** (`10a` a `10p`, 16 migrações, ~107 KB) estão aplicadas no
Supabase mas não foram copiadas para cá — o histórico do Supabase é a fonte, e copiar
tudo à mão arriscaria introduzir erro de digitação num SQL que já está validado.

Para trazer todas para a pasta, exatamente como estão no banco:

```bash
npx supabase login
npx supabase link --project-ref ymniuviyfcqnattelerj
npx supabase db pull            # grava em supabase/migrations/
npx supabase migration list     # confere o que está aplicado
```

Funciona igual no macOS e no Windows (PowerShell).

## O que cada bloco faz

| Migração | Assunto |
|---|---|
| `01`–`04` | Estrutura do estoque, regras, permissões e a carga dos 102 itens |
| `05`–`06` | Reservas, processos pendentes, cadastro rápido e destino por setor |
| `07a`–`07d` | Apontamento de produção: setores, formulários, funções e permissões |
| `08`–`09` | Descrição sem camadas e mensagens em chapas |
| `10a` | Perfil Diretoria e os 13 setores de custo |
| `10b` | Cadastro de motores (base do rateio de energia) |
| `10c` | Parâmetros da caldeira, IT 002 da cola e os 29 modelos de chapa |
| `10d` | Fechamento mensal: parâmetros, custos por setor e lâminas por espécie |
| `10e` | Volume por setor, rateio de energia e balanço térmico da caldeira |
| `10f`–`10h` | Custo por setor, custo acumulado por etapa, custo da lâmina e dos modelos |
| `10i`–`10l` | Calendário com feriados, metas por etapa e indicadores da cadeia |
| `10m`–`10n` | Consumo de cola, qualidade, base diária, resumo, estoque gerencial e alertas |
| `10o`–`10p` | Ajustes de quantidade e RLS/permissões das tabelas novas |
