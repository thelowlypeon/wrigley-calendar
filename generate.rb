# frozen_string_literal: true

require_relative "lib/wrigley_calendar"

events = WrigleyCalendar::MlbSource.fetch +
         WrigleyCalendar::TicketmasterSource.fetch

if events.empty?
  warn "[error] No events fetched; refusing to overwrite output."
  exit 1
end

ics = WrigleyCalendar::IcsBuilder.build(events)
out = ENV.fetch("OUTPUT_PATH", "wrigley.ics")
File.write(out, ics)
warn "[done] wrote #{out} with #{events.size} raw events"
