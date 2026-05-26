-- Track word count and audio length per usage event so the Usage tab can
-- show "words transcribed", "talk time", and a "time saved at 100 WPM" metric.
-- Both columns are nullable so existing rows and non-transcribe routes
-- (which have no audio) remain valid.

alter table api_usage_events
  add column if not exists word_count integer,
  add column if not exists audio_duration_seconds numeric(10, 2);
