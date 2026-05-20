alter table app_users
  add column if not exists can_manage_api_keys boolean not null default false;
