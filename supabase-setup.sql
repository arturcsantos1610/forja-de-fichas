-- Forja de Fichas: banco de dados do login
-- Cole tudo isto no SQL Editor do Supabase e clique em Run.

-- Tabela onde ficam as fichas. Cada ficha pertence a um usuário.
create table if not exists public.fichas (
  id        text primary key,
  user_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  data      jsonb not null,
  saved_at  timestamptz not null default now()
);

create index if not exists fichas_user_saved_idx on public.fichas (user_id, saved_at desc);

-- Libera a tabela para a API do site apenas para quem está logado
-- (necessário quando "Automatically expose new tables" está desmarcado).
revoke all on public.fichas from anon;
grant select, insert, update, delete on public.fichas to authenticated;

-- Segurança: cada pessoa só enxerga e altera as próprias fichas.
alter table public.fichas enable row level security;

drop policy if exists "ver as próprias fichas" on public.fichas;
create policy "ver as próprias fichas" on public.fichas
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "criar as próprias fichas" on public.fichas;
create policy "criar as próprias fichas" on public.fichas
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "editar as próprias fichas" on public.fichas;
create policy "editar as próprias fichas" on public.fichas
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "apagar as próprias fichas" on public.fichas;
create policy "apagar as próprias fichas" on public.fichas
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Compartilhar ficha por link e modo mestre
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
