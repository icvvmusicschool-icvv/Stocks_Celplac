-- =====================================================================
-- CELPLAC — Controle de Estoque  |  06 — Destino da reserva = setor cadastrado
-- (já aplicado no banco; mantido como registro)
-- =====================================================================
alter table public.reservas add column setor_id smallint not null references public.setores(id);
-- public.reservar(...) passou a aceitar em p_destino apenas o nome de um setor ativo,
-- gravando destino = nome do setor e setor_id. Corpo completo no histórico de migrações do Supabase.
