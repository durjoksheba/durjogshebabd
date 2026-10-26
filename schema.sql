-- দুর্যোগ সেবা: Supabase schema. Run once in Supabase > SQL Editor. NOT TESTED yet.
create table sectors(id serial primary key,name_bn text not null,name_en text not null,s float8 not null,w float8 not null,n float8 not null,e float8 not null);
create table teams(id serial primary key,name_bn text not null,name_en text not null,sector_id int references sectors(id),leader_id uuid);
create table profiles(id uuid primary key references auth.users(id) on delete cascade,role text not null default 'volunteer' check(role in('volunteer','leader','admin')),name text not null,team_id int references teams(id),sector_id int references sectors(id));
alter table teams add foreign key(leader_id) references profiles(id);
create table map_points(id bigserial primary key,kind text not null check(kind in('ws','wu','sh','hg')),lat float8 not null check(lat between 20 and 27),lng float8 not null check(lng between 87 and 93),name text not null check(char_length(name) between 1 and 120),created_by uuid default auth.uid(),created_at timestamptz default now());
create table alerts(id bigserial primary key,severity text not null default 'md' check(severity in('hi','md')),text_bn text not null,text_en text,source text not null,created_at timestamptz default now());
create table help_requests(id bigserial primary key,type text not null check(type in('med','food','other')),note text check(char_length(note)<=500),lat float8 not null check(lat between 20 and 27),lng float8 not null check(lng between 87 and 93),phone text check(phone is null or phone ~ '^(\+?88)?01[3-9][0-9]{8}$'),place text check(char_length(place)<=200),status text not null default 'new' check(status in('new','helped','false')),sector_id int references sectors(id),handled_by uuid references profiles(id),handled_at timestamptz,created_at timestamptz default now());
create table volunteer_applications(id bigserial primary key,full_name text not null check(char_length(full_name) between 2 and 100),address text not null check(char_length(address)<=300),phone text not null check(phone ~ '^(\+?88)?01[3-9][0-9]{8}$'),email text,doc_type text not null check(doc_type in('nid','birth')),doc_path text not null,status text not null default 'pending' check(status in('pending','approved','rejected')),created_at timestamptz default now());

-- helpers
create function me_role() returns text language sql stable security definer set search_path=public as $$ select role from profiles where id=auth.uid() $$;
create function me_sector() returns int language sql stable security definer set search_path=public as $$ select sector_id from profiles where id=auth.uid() $$;
create function me_team() returns int language sql stable security definer set search_path=public as $$ select team_id from profiles where id=auth.uid() $$;
-- a new request is routed to the sector whose box contains it (outside every sector = admins only)
create function set_sector() returns trigger language plpgsql security definer set search_path=public as $$ begin new.sector_id:=(select id from sectors where new.lat between s and n and new.lng between w and e limit 1); return new; end $$;
create trigger t_sector before insert on help_requests for each row execute function set_sector();

alter table sectors enable row level security; alter table teams enable row level security; alter table profiles enable row level security;
alter table map_points enable row level security; alter table alerts enable row level security;
alter table help_requests enable row level security; alter table volunteer_applications enable row level security;

create policy sec_r on sectors for select to authenticated using(true);
create policy sec_a on sectors for all to authenticated using(me_role()='admin') with check(me_role()='admin');
create policy team_r on teams for select to authenticated using(true);
create policy team_a on teams for all to authenticated using(me_role()='admin') with check(me_role()='admin');
create policy prof_r on profiles for select to authenticated using(id=auth.uid() or team_id=me_team() or me_role()='admin');
create policy prof_a on profiles for all to authenticated using(me_role()='admin') with check(me_role()='admin');
create policy mp_r on map_points for select to anon,authenticated using(true);
create policy mp_w on map_points for all to authenticated using(me_role() in('volunteer','leader','admin')) with check(me_role() in('volunteer','leader','admin'));
create policy al_r on alerts for select to anon,authenticated using(true);
create policy al_w on alerts for all to authenticated using(me_role()='admin') with check(me_role()='admin');
create policy hr_i on help_requests for insert to anon,authenticated with check(status='new' and handled_by is null);
create policy hr_r on help_requests for select to authenticated using(me_role()='admin' or (me_role() in('volunteer','leader') and sector_id=me_sector()));
create policy hr_u on help_requests for update to authenticated using(me_role()='admin' or (me_role() in('volunteer','leader') and sector_id=me_sector())) with check(me_role()='admin' or (me_role() in('volunteer','leader') and sector_id=me_sector()));
revoke update on help_requests from authenticated; grant update(status,handled_by,handled_at) on help_requests to authenticated;
create policy va_i on volunteer_applications for insert to anon,authenticated with check(status='pending');
create policy va_a on volunteer_applications for all to authenticated using(me_role()='admin') with check(me_role()='admin');

-- private bucket for ID photos: anyone can upload, only admins can read or delete (delete after verifying)
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('ids','ids',false,3145728,array['image/jpeg','image/png','image/webp']);
create policy ids_i on storage.objects for insert to anon,authenticated with check(bucket_id='ids');
create policy ids_r on storage.objects for select to authenticated using(bucket_id='ids' and me_role()='admin');
create policy ids_d on storage.objects for delete to authenticated using(bucket_id='ids' and me_role()='admin');

-- sample sectors (same boxes as the demo). Edit to your pilot area.
insert into sectors(name_bn,name_en,s,w,n,e) values('সেক্টর ১','Sector 1',23.68,90.37,23.73,90.42),('সেক্টর ২','Sector 2',23.68,90.42,23.73,90.47),('সেক্টর ৩','Sector 3',23.73,90.37,23.78,90.47);
-- FIRST ADMIN: Authentication > Users > Add user, copy its UUID, then run:
-- insert into profiles(id,role,name) values('PASTE-UUID','admin','Your Name');
