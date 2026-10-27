-- Brand colours and logos (festive theme). Paste into Supabase → SQL Editor → Run.
update brands set theme = '{"accent":"#7A2318","accentInk":"#FFF8EC","accentDark":"#F08A3C","accentInkDark":"#1E1410","logo":"/brand/aryas-lockup.svg","logoStacked":"/brand/aryas-logo.svg"}'::jsonb
 where slug = 'aryas' and tenant_id = (select id from tenants where slug = 'aryas');
update brands set theme = '{"accent":"#2463B5","accentInk":"#FFFFFF","accentDark":"#7FB2F0","accentInkDark":"#0E1D33","logo":"/brand/ahil-lockup.svg","logoStacked":"/brand/ahil-logo.svg"}'::jsonb
 where slug = 'ahil' and tenant_id = (select id from tenants where slug = 'aryas');
select slug, theme from brands order by sort;
