-- Torre do Mago: homebrew (subclasses escritas por cada jogador)
-- Rode depois do supabase-setup.sql (cole no SQL Editor do Supabase e clique em Run).
-- Pode rodar de novo sem problema: nada é apagado.
-- Cada pessoa só vê e altera o próprio homebrew; não existe lista pública.

create table if not exists public.homebrew (
  id            text primary key check (char_length(id) between 1 and 40),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo          text not null default 'subclasse' check (tipo in ('subclasse')),
  dados         jsonb not null check (pg_column_size(dados) < 200000),
  atualizado_em timestamptz not null default now()
);
create index if not exists homebrew_user_idx on public.homebrew (user_id, atualizado_em desc);

revoke all on public.homebrew from anon, authenticated;
grant select, insert, update, delete on public.homebrew to authenticated;
alter table public.homebrew enable row level security;

drop policy if exists "ver o próprio homebrew" on public.homebrew;
create policy "ver o próprio homebrew" on public.homebrew for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "criar o próprio homebrew" on public.homebrew;
create policy "criar o próprio homebrew" on public.homebrew for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists "editar o próprio homebrew" on public.homebrew;
create policy "editar o próprio homebrew" on public.homebrew for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "apagar o próprio homebrew" on public.homebrew;
create policy "apagar o próprio homebrew" on public.homebrew for delete to authenticated
  using ((select auth.uid()) = user_id);
