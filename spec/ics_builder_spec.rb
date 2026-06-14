# frozen_string_literal: true

RSpec.describe WrigleyCalendar::IcsBuilder do
  let(:now) { Time.utc(2026, 1, 1, 12, 0, 0) }

  def event(**overrides)
    defaults = {
      uid: "x@wrigley-cal",
      start: Time.utc(2026, 6, 15, 0, 5, 0),
      finish: Time.utc(2026, 6, 15, 3, 35, 0),
      all_day: false,
      summary: "Rockies at Cubs",
      description: "desc",
      url: "https://example.com"
    }
    WrigleyCalendar::Event.new(**defaults.merge(overrides))
  end

  describe ".escape" do
    it "returns empty string for nil" do
      expect(described_class.escape(nil)).to eq("")
    end

    it "escapes commas, semicolons, and backslashes" do
      expect(described_class.escape('a,b;c\d')).to eq('a\\,b\\;c\\\\d')
    end

    it "escapes newlines into literal backslash-n" do
      expect(described_class.escape("a\nb")).to eq('a\\nb')
    end
  end

  describe ".fold" do
    it "leaves short lines untouched" do
      expect(described_class.fold("SUMMARY:hi")).to eq("SUMMARY:hi")
    end

    it "folds long lines with CRLF + leading space" do
      long = "SUMMARY:" + ("x" * 100)
      folded = described_class.fold(long)
      expect(folded).to include("\r\n ")
      # Every physical line must be <= 75 octets.
      folded.split("\r\n").each do |physical|
        expect(physical.bytesize).to be <= 75
      end
    end

    it "round-trips to the original content when unfolded" do
      long = "SUMMARY:" + ("y" * 90)
      unfolded = described_class.fold(long).gsub("\r\n ", "")
      expect(unfolded).to eq(long)
    end
  end

  describe ".utc_stamp" do
    it "formats as a UTC basic timestamp" do
      t = Time.new(2026, 6, 15, 20, 5, 0, "-05:00") # 8:05pm Chicago
      expect(described_class.utc_stamp(t)).to eq("20260616T010500Z")
    end
  end

  describe ".build" do
    it "wraps events in a VCALENDAR with CRLF line endings" do
      ics = described_class.build([event], now: now)
      expect(ics).to start_with("BEGIN:VCALENDAR\r\n")
      expect(ics).to end_with("END:VCALENDAR\r\n")
      expect(ics).to include("X-WR-CALNAME:Wrigley Field Events")
    end

    it "emits DTSTART/DTEND as UTC stamps for timed events" do
      ics = described_class.build([event], now: now)
      expect(ics).to include("DTSTART:20260615T000500Z")
      expect(ics).to include("DTEND:20260615T033500Z")
    end

    it "uses VALUE=DATE and a next-day DTEND for all-day events" do
      ics = described_class.build(
        [event(all_day: true, start: Time.utc(2026, 7, 4), finish: nil)],
        now: now
      )
      expect(ics).to include("DTSTART;VALUE=DATE:20260704")
      expect(ics).to include("DTEND;VALUE=DATE:20260705")
    end

    it "stamps DTSTAMP from the injected now" do
      ics = described_class.build([event], now: now)
      expect(ics).to include("DTSTAMP:20260101T120000Z")
    end

    it "sorts events chronologically regardless of input order" do
      later = event(uid: "later@x", start: Time.utc(2026, 8, 1, 0, 0, 0),
                    finish: Time.utc(2026, 8, 1, 3, 0, 0), summary: "Later")
      earlier = event(uid: "earlier@x", start: Time.utc(2026, 5, 1, 0, 0, 0),
                      finish: Time.utc(2026, 5, 1, 3, 0, 0), summary: "Earlier")
      ics = described_class.build([later, earlier], now: now)
      expect(ics.index("Earlier")).to be < ics.index("Later")
    end

    it "de-duplicates events with the same date and summary" do
      a = event(uid: "a@x")
      b = event(uid: "b@x") # same date + summary as a
      ics = described_class.build([a, b], now: now)
      expect(ics.scan("UID:").size).to eq(1)
    end

    it "omits empty description and url lines" do
      ics = described_class.build(
        [event(description: "", url: "")], now: now
      )
      expect(ics).not_to include("DESCRIPTION:")
      expect(ics).not_to include("URL:")
    end
  end
end
