-- Preserve usage attribution even after an owner deletes a revoked API key.

alter table public.api_usage_events
  add column if not exists api_key_label text,
  add column if not exists api_key_tag text,
  add column if not exists api_key_prefix text;

update public.api_usage_events usage
set
  api_key_label = coalesce(usage.api_key_label, keys.label),
  api_key_tag = coalesce(usage.api_key_tag, keys.tag),
  api_key_prefix = coalesce(usage.api_key_prefix, keys.key_prefix)
from public.app_api_keys keys
where usage.api_key_id = keys.id;
