# frozen_string_literal: true

require "json"
require "time"
require "date"
require "uri"
require "net/http"

# Build a single .ics feed of everything happening AT Wrigley Field:
#   - Chicago Cubs HOME games (filtered to the Wrigley venue, road games excluded)
#   - Concerts and special events (Ticketmaster Discovery API)
#
# Network I/O is isolated in `.fetch` methods; all parsing/formatting is pure
# and unit-tested.
module WrigleyCalendar
  WRIGLEY_ADDR = "Wrigley Field, 1060 W Addison St, Chicago, IL 60613"
  CAL_NAME     = "Wrigley Field Events"

  # `end` is reserved, so the end time is named `finish`.
  Event = Struct.new(
    :uid, :start, :finish, :all_day, :summary, :description, :url,
    keyword_init: true
  )

  # Shared tiny HTTP helper (only used by the I/O `.fetch` methods).
  module Http
    module_function

    def get(uri, timeout: 30)
      uri = URI(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: timeout, read_timeout: timeout) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "wrigley-cal/1.0"
        res = http.request(req)
        raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        res.body
      end
    end
  end

  # ----------------------------- ICS -----------------------------
  module IcsBuilder
    module_function

    # Escape a TEXT value per RFC 5545. Block form avoids gsub's
    # replacement-string backslash interpretation.
    def escape(text)
      return "" if text.nil?

      text.to_s.gsub(/[\\;,\n]/) do |ch|
        case ch
        when "\\" then "\\\\"
        when ";"  then "\\;"
        when ","  then "\\,"
        when "\n" then "\\n"
        end
      end
    end

    # Fold content lines longer than 75 octets (RFC 5545). Continuation
    # lines begin with a single space.
    def fold(line)
      return line if line.bytesize <= 75

      chunks = []
      current = +""
      line.each_char do |ch|
        if current.bytesize + ch.bytesize > 73
          chunks << current
          current = +ch
        else
          current << ch
        end
      end
      chunks << current
      chunks.join("\r\n ")
    end

    def utc_stamp(time)
      time.getutc.strftime("%Y%m%dT%H%M%SZ")
    end

    def build(events, now: Time.now.utc)
      stamp = utc_stamp(now)
      lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//wrigley-cal//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:#{escape(CAL_NAME)}",
        "X-WR-TIMEZONE:America/Chicago"
      ]

      # Both sources can list the same event at Wrigley (e.g. Ticketmaster
      # sells tickets to Cubs games too, and sometimes lists one concert
      # multiple times for different ticket packages). Two events starting
      # at the exact same instant are the same real-world event, regardless
      # of how each source titled it. MLB events are concatenated first and
      # `sort_by` is stable, so on a collision the MLB entry (richer
      # description) wins; among Ticketmaster duplicates, the first listing
      # wins.
      seen = {}
      events.sort_by(&:start).each do |e|
        key = e.start.getutc.to_i
        next if seen[key]

        seen[key] = true
        lines.concat(event_lines(e, stamp))
      end

      lines << "END:VCALENDAR"
      lines.map { |l| fold(l) }.join("\r\n") + "\r\n"
    end

    def event_lines(e, stamp)
      out = ["BEGIN:VEVENT", "UID:#{e.uid}", "DTSTAMP:#{stamp}"]

      if e.all_day
        d = e.start.getutc.to_date
        out << "DTSTART;VALUE=DATE:#{d.strftime('%Y%m%d')}"
        out << "DTEND;VALUE=DATE:#{(d + 1).strftime('%Y%m%d')}"
      else
        out << "DTSTART:#{utc_stamp(e.start)}"
        out << "DTEND:#{utc_stamp(e.finish)}" if e.finish
      end

      out << "SUMMARY:#{escape(e.summary)}"
      out << "LOCATION:#{escape(WRIGLEY_ADDR)}"
      out << "DESCRIPTION:#{escape(e.description)}" unless e.description.to_s.empty?
      out << "URL:#{escape(e.url)}" unless e.url.to_s.empty?
      out << "END:VEVENT"
      out
    end
  end

  # ------------------------- Cubs games --------------------------
  module MlbSource
    TEAM_ID          = 112 # Chicago Cubs
    WRIGLEY_VENUE_ID = 17  # Wrigley Field, in the MLB StatsAPI
    GAME_DURATION    = (3 * 3600) + (30 * 60) # 3h30m in seconds

    module_function

    # Pure: parsed StatsAPI hash -> [Event]. Keeps only games at Wrigley.
    def parse(data)
      events = []
      Array(data["dates"]).each do |day|
        Array(day["games"]).each do |g|
          venue = g["venue"] || {}
          next unless venue["id"] == WRIGLEY_VENUE_ID

          start = safe_time(g["gameDate"])
          next if start.nil?

          home   = g.dig("teams", "home", "team", "name")
          away   = g.dig("teams", "away", "team", "name")
          status = g.dig("status", "detailedState").to_s

          events << Event.new(
            uid:         "mlb-#{g['gamePk']}@wrigley-cal",
            start:       start,
            finish:      start + GAME_DURATION,
            all_day:     false,
            summary:     "#{away} at #{home}",
            description: "MLB regular season. Status: #{status}".strip,
            url:         "https://www.mlb.com/cubs/schedule"
          )
        end
      end
      events
    end

    def safe_time(str)
      Time.iso8601(str.to_s).getutc
    rescue ArgumentError, TypeError
      nil
    end

    # I/O: hit the free MLB StatsAPI (no key required).
    def fetch(lookahead_days: 400)
      start = Date.today
      stop  = start + lookahead_days
      params = URI.encode_www_form(
        sportId: 1, teamId: TEAM_ID,
        startDate: start.iso8601, endDate: stop.iso8601, hydrate: "venue"
      )
      uri  = "https://statsapi.mlb.com/api/v1/schedule?#{params}"
      evts = parse(JSON.parse(Http.get(uri)))
      warn "[info] #{evts.size} Cubs home games"
      evts
    rescue StandardError => e
      warn "[warn] MLB fetch failed: #{e}"
      []
    end
  end

  # ------------------ Concerts / special events ------------------
  module TicketmasterSource
    VENUE_ID       = "KovZpZAFlktA" # Wrigley Field, in the Discovery API
    EVENT_DURATION = 3 * 3600       # 3h in seconds

    module_function

    # Pure: parsed Discovery API hash -> [Event].
    def parse(data)
      events = []
      Array(data.dig("_embedded", "events")).each do |ev|
        start_info = ev.dig("dates", "start") || {}
        all_day = false

        if start_info["dateTime"]
          start = safe_time(start_info["dateTime"])
        elsif start_info["localDate"]
          start   = safe_date_midnight(start_info["localDate"])
          all_day = true
        else
          next
        end
        next if start.nil?

        events << Event.new(
          uid:         "tm-#{ev['id']}@wrigley-cal",
          start:       start,
          finish:      all_day ? nil : start + EVENT_DURATION,
          all_day:     all_day,
          summary:     ev["name"] || "Event at Wrigley Field",
          description: "Concert / special event at Wrigley Field.",
          url:         ev["url"].to_s
        )
      end
      events
    end

    def safe_time(str)
      Time.iso8601(str.to_s).getutc
    rescue ArgumentError, TypeError
      nil
    end

    def safe_date_midnight(str)
      y, m, d = str.to_s.split("-").map(&:to_i)
      Time.utc(y, m, d)
    rescue ArgumentError, TypeError
      nil
    end

    # I/O: paginate the Discovery API for this venue.
    def fetch(api_key: ENV["TM_API_KEY"].to_s.strip, max_pages: 5)
      if api_key.empty?
        warn "[warn] TM_API_KEY not set -- skipping concerts/special events"
        return []
      end

      events = []
      page = 0
      total_pages = 1
      while page < total_pages && page < max_pages
        params = URI.encode_www_form(
          apikey: api_key, venueId: VENUE_ID,
          size: 200, page: page, sort: "date,asc"
        )
        uri  = "https://app.ticketmaster.com/discovery/v2/events.json?#{params}"
        data = JSON.parse(Http.get(uri))
        total_pages = data.dig("page", "totalPages") || 1
        events.concat(parse(data))
        page += 1
        sleep 0.2
      end

      warn "[info] #{events.size} Ticketmaster events"
      events
    rescue StandardError => e
      warn "[warn] Ticketmaster fetch failed: #{e}"
      events || []
    end
  end
end
