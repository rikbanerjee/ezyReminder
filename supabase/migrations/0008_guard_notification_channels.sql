-- Normalize legacy/invalid reminder channel arrays before adding a constraint.
-- Unknown and NULL elements route to email; while repairing invalid arrays,
-- recognized channels retain their first-occurrence order with duplicates removed.
-- Empty arrays stay empty so
-- enqueue_due_notifications() continues to use the context default channel.
begin;

update reminders r
set channels = coalesce((
  select array_agg(mapped.channel order by mapped.first_position)
  from (
    select
      case when raw.channel = any (array['email', 'whatsapp', 'apns']::text[])
        then raw.channel else 'email' end as channel,
      min(raw.position) as first_position
    from unnest(coalesce(r.channels, '{}'::text[])) with ordinality as raw(channel, position)
    group by case when raw.channel = any (array['email', 'whatsapp', 'apns']::text[])
      then raw.channel else 'email' end
  ) as mapped
), '{}'::text[])
where r.channels is null or exists (
  select 1
  from unnest(r.channels) as current_channel(channel)
  where current_channel.channel is null
    or current_channel.channel <> all (array['email', 'whatsapp', 'apns']::text[])
);

alter table reminders
  add constraint reminders_channels_check
  check (
    channels is not null
    and array_position(channels, null) is null
    and channels <@ array['email', 'whatsapp', 'apns']::text[]
  );

commit;

-- Rollback (manual only):
-- The normalization is intentionally lossy: invalid legacy values and their
-- original positions cannot be reconstructed without a pre-migration backup.
-- Removing the constraint alone restores the old write behavior, including
-- the risk of poisoning the global notification sweep with invalid channels.
-- begin;
-- alter table reminders drop constraint reminders_channels_check;
-- commit;
