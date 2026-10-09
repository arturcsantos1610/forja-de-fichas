-- Forja de Fichas: campanhas na Mesa
-- Rode depois do supabase-setup.sql (cole no SQL Editor do Supabase e clique em Run).
-- Pode rodar de novo sem problema: nada é apagado.

-- 1) Campanhas. O código de convite é o que o mestre passa para os jogadores.
create table if not exists public.campanhas (
  id         uuid primary key default gen_random_uuid(),
  dono       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome       text not null check (char_length(nome) between 1 and 80),
  descricao  text not null default '' check (char_length(descricao) <= 2000),
  mestre     text not null default '' check (char_length(mestre) <= 40),
  codigo     text not null unique check (codigo ~ '^[A-Z0-9]{10,16}$'),
  criada_em  timestamptz not null default now()
);

-- 2) Quem joga em cada campanha e com qual ficha.
create table if not exists public.campanha_membros (
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  ficha_id    text references public.fichas (id) on delete set null,
  apelido     text not null default '' check (char_length(apelido) <= 40),
  entrou_em   timestamptz not null default now(),
  primary key (campanha_id, user_id)
);
create index if not exists campanha_membros_user_idx on public.campanha_membros (user_id);
create index if not exists campanha_membros_ficha_idx on public.campanha_membros (ficha_id);

-- 3) Anotações do mestre (combate, criaturas próprias). Só o mestre vê.
create table if not exists public.campanha_mestre (
  campanha_id   uuid primary key references public.campanhas (id) on delete cascade,
  dados         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- 4) Itens e moedas que o mestre entrega. O jogador aceita ou recusa.
create table if not exists public.campanha_entregas (
  id           uuid primary key default gen_random_uuid(),
  campanha_id  uuid not null references public.campanhas (id) on delete cascade,
  para_user    uuid not null references auth.users (id) on delete cascade,
  item         jsonb not null,
  status       text not null default 'pendente' check (status in ('pendente','aceito','recusado')),
  criada_em    timestamptz not null default now(),
  respondida_em timestamptz
);
create index if not exists campanha_entregas_para_idx on public.campanha_entregas (para_user, status);

-- Funções de apoio. Rodam com permissão própria para as regras abaixo não
-- consultarem umas às outras em círculo.
create or replace function public.cf_dono(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.campanhas where id = c and dono = auth.uid());
$$;
create or replace function public.cf_membro(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.campanha_membros where campanha_id = c and user_id = auth.uid());
$$;
create or replace function public.cf_mestre_da_ficha(f text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.campanha_membros m join public.campanhas c on c.id = m.campanha_id
    where m.ficha_id = f and c.dono = auth.uid()
  );
$$;

-- Entrar numa campanha pelo código, escolhendo uma ficha própria.
create or replace function public.entrar_campanha(p_codigo text, p_ficha text, p_apelido text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  if auth.uid() is null then raise exception 'login necessario'; end if;
  select id into c from public.campanhas
    where codigo = upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if c is null then raise exception 'codigo invalido'; end if;
  if p_ficha is not null and not exists (select 1 from public.fichas where id = p_ficha and user_id = auth.uid()) then
    raise exception 'ficha invalida';
  end if;
  insert into public.campanha_membros (campanha_id, user_id, ficha_id, apelido)
    values (c, auth.uid(), p_ficha, left(coalesce(p_apelido, ''), 40))
    on conflict (campanha_id, user_id) do update set ficha_id = excluded.ficha_id, apelido = excluded.apelido;
  return c;
end;
$$;

revoke all on function public.cf_dono(uuid) from public;
revoke all on function public.cf_membro(uuid) from public;
revoke all on function public.cf_mestre_da_ficha(text) from public;
revoke all on function public.entrar_campanha(text, text, text) from public;
grant execute on function public.cf_dono(uuid) to authenticated;
grant execute on function public.cf_membro(uuid) to authenticated;
grant execute on function public.cf_mestre_da_ficha(text) to authenticated;
grant execute on function public.entrar_campanha(text, text, text) to authenticated;

-- Acesso pela API só para quem está logado.
revoke all on public.campanhas, public.campanha_membros, public.campanha_mestre, public.campanha_entregas from anon, authenticated;
grant select, insert, update, delete on public.campanhas to authenticated;
grant select, delete on public.campanha_membros to authenticated;
-- o jogador só troca a ficha e o apelido, nunca a campanha da linha
grant update (ficha_id, apelido) on public.campanha_membros to authenticated;
grant select, insert, update, delete on public.campanha_mestre to authenticated;
grant select, insert, delete on public.campanha_entregas to authenticated;
grant update (status, respondida_em) on public.campanha_entregas to authenticated;

alter table public.campanhas enable row level security;
alter table public.campanha_membros enable row level security;
alter table public.campanha_mestre enable row level security;
alter table public.campanha_entregas enable row level security;

-- campanhas: o mestre faz tudo; os membros só leem.
drop policy if exists "ver campanhas" on public.campanhas;
create policy "ver campanhas" on public.campanhas for select to authenticated
  using (dono = (select auth.uid()) or public.cf_membro(id));
drop policy if exists "criar campanhas" on public.campanhas;
create policy "criar campanhas" on public.campanhas for insert to authenticated
  with check (dono = (select auth.uid()));
drop policy if exists "editar campanhas" on public.campanhas;
create policy "editar campanhas" on public.campanhas for update to authenticated
  using (dono = (select auth.uid())) with check (dono = (select auth.uid()));
drop policy if exists "apagar campanhas" on public.campanhas;
create policy "apagar campanhas" on public.campanhas for delete to authenticated
  using (dono = (select auth.uid()));

-- membros: entrar só pela função entrar_campanha. O jogador troca a própria
-- ficha (só por uma ficha dele) ou sai; o mestre pode tirar alguém.
drop policy if exists "ver membros" on public.campanha_membros;
create policy "ver membros" on public.campanha_membros for select to authenticated
  using (user_id = (select auth.uid()) or public.cf_dono(campanha_id) or public.cf_membro(campanha_id));
drop policy if exists "trocar ficha" on public.campanha_membros;
create policy "trocar ficha" on public.campanha_membros for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and (ficha_id is null or exists (
    select 1 from public.fichas f where f.id = ficha_id and f.user_id = (select auth.uid()))));
drop policy if exists "sair ou tirar" on public.campanha_membros;
create policy "sair ou tirar" on public.campanha_membros for delete to authenticated
  using (user_id = (select auth.uid()) or public.cf_dono(campanha_id));

-- anotações do mestre: só o mestre.
drop policy if exists "mestre anota" on public.campanha_mestre;
create policy "mestre anota" on public.campanha_mestre for all to authenticated
  using (public.cf_dono(campanha_id)) with check (public.cf_dono(campanha_id));

-- entregas: o mestre entrega para membros; o jogador vê as dele e responde.
drop policy if exists "ver entregas" on public.campanha_entregas;
create policy "ver entregas" on public.campanha_entregas for select to authenticated
  using (para_user = (select auth.uid()) or public.cf_dono(campanha_id));
drop policy if exists "mestre entrega" on public.campanha_entregas;
create policy "mestre entrega" on public.campanha_entregas for insert to authenticated
  with check (public.cf_dono(campanha_id) and status = 'pendente' and exists (
    select 1 from public.campanha_membros m where m.campanha_id = campanha_entregas.campanha_id and m.user_id = para_user));
drop policy if exists "jogador responde" on public.campanha_entregas;
create policy "jogador responde" on public.campanha_entregas for update to authenticated
  using (para_user = (select auth.uid()) and status = 'pendente')
  with check (para_user = (select auth.uid()) and status in ('aceito','recusado'));
drop policy if exists "mestre cancela" on public.campanha_entregas;
create policy "mestre cancela" on public.campanha_entregas for delete to authenticated
  using (public.cf_dono(campanha_id));

-- fichas: o mestre pode LER (nunca alterar) as fichas ligadas às campanhas dele.
drop policy if exists "mestre vê fichas da campanha" on public.fichas;
create policy "mestre vê fichas da campanha" on public.fichas for select to authenticated
  using (public.cf_mestre_da_ficha(id));
