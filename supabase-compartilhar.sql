-- Forja de Fichas: compartilhar ficha por link e modo mestre
-- Rode este arquivo uma vez no SQL Editor do Supabase (depois do supabase-setup.sql).

-- Código secreto do link. Fica vazio enquanto a ficha não é compartilhada.
alter table public.fichas add column if not exists share_id uuid unique;

-- Função pública que entrega UMA ficha compartilhada, só para quem tem o código.
-- Não existe forma de listar todas as fichas compartilhadas.
create or replace function public.ficha_compartilhada(p_share uuid)
returns table (data jsonb, saved_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select f.data, f.saved_at
  from public.fichas f
  where p_share is not null and f.share_id = p_share
  limit 1;
$$;

revoke all on function public.ficha_compartilhada(uuid) from public;
grant execute on function public.ficha_compartilhada(uuid) to anon, authenticated;
