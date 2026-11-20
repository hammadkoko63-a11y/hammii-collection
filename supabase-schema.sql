create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  category text not null check (category in ('Shoes','Tracksuits','Pants','Shirts','Ladies Pakistani Suits')),
  price numeric(12,2) not null check (price >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_name text not null,
  phone text not null,
  delivery_address text not null,
  notes text not null default '',
  total numeric(12,2) not null check (total >= 0),
  status text not null default 'pending' check (status in ('pending','confirmed','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0)
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.admin_users a where a.id = auth.uid()) $$;

alter table public.admin_users enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "public can read available products" on public.products;
create policy "public can read available products" on public.products
  for select to anon,authenticated using (active = true and stock_quantity > 0);

drop policy if exists "admins manage all products" on public.products;
create policy "admins manage all products" on public.products
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins read orders" on public.orders;
create policy "admins read orders" on public.orders
  for select to authenticated using (public.is_admin());

drop policy if exists "admins update orders" on public.orders;
create policy "admins update orders" on public.orders
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins read order items" on public.order_items;
create policy "admins read order items" on public.order_items
  for select to authenticated using (public.is_admin());

create or replace function public.submit_order(
  p_customer_name text,
  p_phone text,
  p_delivery_address text,
  p_notes text,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_total numeric(12,2) := 0;
  v_item jsonb;
  v_product record;
  v_quantity integer;
begin
  if char_length(coalesce(p_customer_name,'')) < 1 or char_length(coalesce(p_phone,'')) < 7
     or char_length(coalesce(p_delivery_address,'')) < 5 or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) < 1 then
    raise exception 'Invalid order details';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity is null or v_quantity < 1 then raise exception 'Invalid quantity'; end if;

    select * into v_product from public.products
      where id = (v_item->>'product_id')::uuid and active = true
      for update;
    if not found then raise exception 'Product unavailable'; end if;
    if v_product.stock_quantity < v_quantity then raise exception 'Insufficient stock for %', v_product.name; end if;

    v_total := v_total + (v_product.price * v_quantity);
  end loop;

  v_order_number := 'HC-' || to_char(now(),'YYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.orders(order_number,customer_name,phone,delivery_address,notes,total)
  values(v_order_number,p_customer_name,p_phone,p_delivery_address,coalesce(p_notes,''),v_total)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item->>'quantity')::integer;
    select * into v_product from public.products
      where id = (v_item->>'product_id')::uuid and active = true
      for update;

    update public.products set stock_quantity = stock_quantity - v_quantity, updated_at = now()
      where id = v_product.id;
    insert into public.order_items(order_id,product_id,product_name,unit_price,quantity)
      values(v_order_id,v_product.id,v_product.name,v_product.price,v_quantity);
  end loop;

  return jsonb_build_object('order_id',v_order_id,'order_number',v_order_number);
end;
$$;

revoke all on function public.submit_order(text,text,text,text,jsonb) from public;
grant execute on function public.submit_order(text,text,text,text,jsonb) to anon,authenticated;

create or replace function public.update_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end;
$$;
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products
  for each row execute function public.update_updated_at();
drop trigger if exists orders_updated_at on public.orders;
create trigger orders_updated_at before update on public.orders
  for each row execute function public.update_updated_at();
