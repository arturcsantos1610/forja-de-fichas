-- Forja de Fichas: sessão ao vivo (mapas, tokens e rolagens compartilhadas)
-- Rode depois do supabase-campanhas.sql (cole no SQL Editor do Supabase e clique em Run).
-- Pode rodar de novo sem problema: nada é apagado.

-- 1) Mapas da campanha. Só um fica "ativo" (o que os jogadores veem).
create table if not exists public.campanha_mapas (
  id          uuid primary key default gen_random_uuid(),
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  nome        text not null default '' check (char_length(nome) <= 60),
  largura     int  not null check (largura between 50 and 4000),
  altura      int  not null check (altura between 50 and 4000),
  grade       int  not null default 70 check (grade = 0 or grade between 10 and 400),
  ativo       boolean not null default false,
  criada_em   timestamptz not null default now()
);
create index if not exists campanha_mapas_camp_idx on public.campanha_mapas (campanha_id);

-- 2) A imagem de cada mapa fica separada, para não pesar nas atualizações ao vivo.
create table if not exists public.campanha_mapa_imagens (
  mapa_id     uuid primary key references public.campanha_mapas (id) on delete cascade,
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  imagem      text not null check (char_length(imagem) <= 4000000 and imagem ~ '^data:image/(jpeg|png|webp);base64,')
);

-- 3) Tokens: personagens dos jogadores e criaturas do mestre.
create table if not exists public.campanha_tokens (
  id            uuid primary key default gen_random_uuid(),
  campanha_id   uuid not null references public.campanhas (id) on delete cascade,
  mapa_id       uuid not null references public.campanha_mapas (id) on delete cascade,
  dono          uuid references auth.users (id) on delete cascade,  -- jogador que move; vazio = só o mestre
  nome          text not null default '' check (char_length(nome) <= 40),
  imagem        text not null default '' check (char_length(imagem) <= 200000 and (imagem = '' or imagem ~ '^data:image/(jpeg|png|webp);base64,')),
  cor           text not null default '#c1121f' check (cor ~ '^#[0-9a-fA-F]{6}$'),
  tamanho       real not null default 1 check (tamanho between 0.5 and 4),
  x             real not null default 0 check (x between -1000 and 5000),
  y             real not null default 0 check (y between -1000 and 5000),
  oculto        boolean not null default false,
  atualizado_em timestamptz not null default now()
);
create index if not exists campanha_tokens_camp_idx on public.campanha_tokens (campanha_id);
-- cada jogador tem um token por mapa
create unique index if not exists campanha_tokens_um_por_jogador on public.campanha_tokens (mapa_id, dono) where dono is not null;

-- 4) Rolagens da mesa (o feed que todo mundo vê).
create table if not exists public.campanha_rolagens (
  id          bigint generated always as identity primary key,
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  autor       text not null check (char_length(autor) between 1 and 60),
  rotulo      text not null check (char_length(rotulo) <= 120),
  total       int  not null check (total between -100 and 100000),
  nat         int  check (nat between 1 and 20),
  detalhe     text not null default '' check (char_length(detalhe) <= 300),
  tipo        text not null default 'd20' check (tipo in ('d20','dano')),
  secreta     boolean not null default false,
  criada_em   timestamptz not null default now()
);
create index if not exists campanha_rolagens_camp_idx on public.campanha_rolagens (campanha_id, id desc);

-- guarda só as 200 rolagens mais recentes de cada campanha
create or replace function public.cf_limpa_rolagens() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.campanha_rolagens
   where campanha_id = new.campanha_id
     and id < (select id from public.campanha_rolagens where campanha_id = new.campanha_id order by id desc offset 199 limit 1);
  return null;
end;
$$;
revoke all on function public.cf_limpa_rolagens() from public;
drop trigger if exists limpa_rolagens on public.campanha_rolagens;
create trigger limpa_rolagens after insert on public.campanha_rolagens
  for each row execute function public.cf_limpa_rolagens();

-- mapa ativo visível para um membro
create or replace function public.cf_mapa_visivel(m uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.campanha_mapas p
    join public.campanha_membros b on b.campanha_id = p.campanha_id and b.user_id = auth.uid()
    where p.id = m and p.ativo
  );
$$;
revoke all on function public.cf_mapa_visivel(uuid) from public;
grant execute on function public.cf_mapa_visivel(uuid) to authenticated;

-- Acesso pela API só para quem está logado, com as colunas certas.
revoke all on public.campanha_mapas, public.campanha_mapa_imagens, public.campanha_tokens, public.campanha_rolagens from anon, authenticated;
grant select, insert, update, delete on public.campanha_mapas to authenticated;
grant select, insert, update, delete on public.campanha_mapa_imagens to authenticated;
grant select, insert, delete on public.campanha_tokens to authenticated;
grant update (nome, imagem, cor, tamanho, x, y, oculto, atualizado_em) on public.campanha_tokens to authenticated;
grant select, insert, delete on public.campanha_rolagens to authenticated;

alter table public.campanha_mapas enable row level security;
alter table public.campanha_mapa_imagens enable row level security;
alter table public.campanha_tokens enable row level security;
alter table public.campanha_rolagens enable row level security;

-- mapas: o mestre faz tudo; os jogadores só veem o mapa ativo.
drop policy if exists "ver mapas" on public.campanha_mapas;
create policy "ver mapas" on public.campanha_mapas for select to authenticated
  using (public.cf_dono(campanha_id) or (ativo and public.cf_membro(campanha_id)));
drop policy if exists "mestre mexe nos mapas" on public.campanha_mapas;
create policy "mestre mexe nos mapas" on public.campanha_mapas for all to authenticated
  using (public.cf_dono(campanha_id)) with check (public.cf_dono(campanha_id));

drop policy if exists "ver imagem do mapa" on public.campanha_mapa_imagens;
create policy "ver imagem do mapa" on public.campanha_mapa_imagens for select to authenticated
  using (public.cf_dono(campanha_id) or public.cf_mapa_visivel(mapa_id));
drop policy if exists "mestre envia imagem" on public.campanha_mapa_imagens;
create policy "mestre envia imagem" on public.campanha_mapa_imagens for all to authenticated
  using (public.cf_dono(campanha_id))
  with check (public.cf_dono(campanha_id) and exists (
    select 1 from public.campanha_mapas p where p.id = mapa_id and p.campanha_id = campanha_mapa_imagens.campanha_id));

-- tokens: o jogador vê os tokens visíveis do mapa ativo e move só o dele; o mestre faz tudo.
drop policy if exists "ver tokens" on public.campanha_tokens;
create policy "ver tokens" on public.campanha_tokens for select to authenticated
  using (public.cf_dono(campanha_id) or (not oculto and public.cf_mapa_visivel(mapa_id)) or dono = (select auth.uid()));
drop policy if exists "criar tokens" on public.campanha_tokens;
create policy "criar tokens" on public.campanha_tokens for insert to authenticated
  with check (
    exists (select 1 from public.campanha_mapas p where p.id = mapa_id and p.campanha_id = campanha_tokens.campanha_id)
    and (public.cf_dono(campanha_id)
      or (dono = (select auth.uid()) and not oculto and public.cf_mapa_visivel(mapa_id))));
drop policy if exists "mover tokens" on public.campanha_tokens;
create policy "mover tokens" on public.campanha_tokens for update to authenticated
  using (public.cf_dono(campanha_id) or dono = (select auth.uid()))
  with check (public.cf_dono(campanha_id) or dono = (select auth.uid()));
drop policy if exists "tirar tokens" on public.campanha_tokens;
create policy "tirar tokens" on public.campanha_tokens for delete to authenticated
  using (public.cf_dono(campanha_id) or dono = (select auth.uid()));

-- rolagens: quem está na campanha publica e vê; as secretas só o mestre e o autor veem.
drop policy if exists "ver rolagens" on public.campanha_rolagens;
create policy "ver rolagens" on public.campanha_rolagens for select to authenticated
  using (public.cf_dono(campanha_id) or user_id = (select auth.uid()) or (not secreta and public.cf_membro(campanha_id)));
drop policy if exists "rolar" on public.campanha_rolagens;
create policy "rolar" on public.campanha_rolagens for insert to authenticated
  with check (user_id = (select auth.uid()) and (public.cf_dono(campanha_id) or public.cf_membro(campanha_id)));
drop policy if exists "limpar rolagens" on public.campanha_rolagens;
create policy "limpar rolagens" on public.campanha_rolagens for delete to authenticated
  using (public.cf_dono(campanha_id));

-- Tempo real: avisa quem está na sessão quando algo muda.
-- (A imagem do mapa não entra: ela é baixada uma vez só.)
alter table public.campanha_tokens replica identity full;
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['campanha_mapas','campanha_tokens','campanha_rolagens','campanha_entregas'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end;
$$;
