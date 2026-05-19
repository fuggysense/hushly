-- Add audio_path to transcripts so we can re-transcribe later.
alter table public.transcripts
  add column if not exists audio_path text,
  add column if not exists audio_mime text;

-- Create the audio storage bucket, private (RLS-gated).
insert into storage.buckets (id, name, public)
values ('transcript-audio', 'transcript-audio', false)
on conflict (id) do nothing;

-- RLS: each user can read/write their own folder inside the bucket.
-- Path convention: <user_id>/<transcript_id>.<ext>
drop policy if exists "own audio read" on storage.objects;
drop policy if exists "own audio write" on storage.objects;
drop policy if exists "own audio delete" on storage.objects;

create policy "own audio read"
  on storage.objects for select
  using (
    bucket_id = 'transcript-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "own audio write"
  on storage.objects for insert
  with check (
    bucket_id = 'transcript-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "own audio delete"
  on storage.objects for delete
  using (
    bucket_id = 'transcript-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
