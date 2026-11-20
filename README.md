# Hammii Collection online shop

This is a mobile-friendly PWA storefront with shared Supabase inventory and orders.

## Supabase setup

1. Create a free Supabase project.
2. In **SQL Editor**, run `supabase-schema.sql`.
3. In **Authentication → Users**, create the initial owner account.
4. In the SQL Editor, run this once with the owner's exact account ID and email:

```sql
insert into public.admin_users (id, email)
values ('OWNER_AUTH_USER_UUID', 'OWNER_EMAIL')
on conflict (id) do update set email = excluded.email;
```

5. Copy only the project URL and public anon/publishable key into `supabase-config.js`. Never add the service-role key to this repository.
6. In Supabase Authentication settings, add the GitHub Pages URL as a Site URL and allowed redirect URL. Email/password sign-in is used.

The public anon role can read only active products with stock and submit orders through the `submit_order` function. It cannot read order PII or modify products. The owner allowlist controls all admin access, and users cannot grant themselves membership through the database policies.

## Owner workflow

Open the site and choose **Owner**. Sign in with the allowlisted account. Use the dashboard to add/edit/delete products and stock, view submitted order PII, and change order status.

## Order privacy

Buyer name, phone, and address are sent to Supabase when an order request is submitted. They are not written to browser local storage or cookies by this app. Anonymous visitors cannot read orders. Service/provider retention and backup policies are controlled by the Supabase project.

## GitHub Pages

The existing static GitHub Pages deployment approach remains appropriate. Commit this repository, enable Pages from the repository settings, and point it to the branch and `/` (root). PWA installation works over HTTPS.
