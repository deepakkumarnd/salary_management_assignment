module TimeHelper
  # A point in time, shown in the viewer's time zone: the server renders UTC, and the local-time Stimulus
  # controller rewrites the text in the browser's zone (without JavaScript the UTC text stays, labelled as such).
  #   local_time(record.updated_at) → <time datetime="2026-09-28T09:40:00Z" …>28 Sep 2026, 09:40 UTC</time>
  def local_time(time)
    utc = time.utc
    tag.time(utc.strftime("%-d %b %Y, %H:%M UTC"), datetime: utc.iso8601, data: { controller: "local-time" })
  end
end
