# frozen_string_literal: true

RSpec.describe WrigleyCalendar::TicketmasterSource do
  def payload(*events)
    { "_embedded" => { "events" => events } }
  end

  describe ".parse" do
    it "parses a timed event with a 3h finish" do
      data = payload(
        "id" => "abc",
        "name" => "Mumford & Sons",
        "url" => "https://tm/abc",
        "dates" => { "start" => { "dateTime" => "2026-06-11T23:30:00Z" } }
      )
      e = described_class.parse(data).first
      expect(e.all_day).to be(false)
      expect(e.start).to eq(Time.utc(2026, 6, 11, 23, 30, 0))
      expect(e.finish - e.start).to eq(3 * 3600)
      expect(e.uid).to eq("tm-abc@wrigley-cal")
      expect(e.summary).to eq("Mumford & Sons")
    end

    it "treats date-only events as all-day with no finish" do
      data = payload(
        "id" => "tba",
        "name" => "TBA Show",
        "dates" => { "start" => { "localDate" => "2026-07-04" } }
      )
      e = described_class.parse(data).first
      expect(e.all_day).to be(true)
      expect(e.finish).to be_nil
      expect(e.start).to eq(Time.utc(2026, 7, 4))
    end

    it "skips events with no start date at all" do
      data = payload("id" => "x", "name" => "No Date", "dates" => { "start" => {} })
      expect(described_class.parse(data)).to be_empty
    end

    it "falls back to a default name when none is present" do
      data = payload(
        "id" => "y",
        "dates" => { "start" => { "dateTime" => "2026-06-11T23:30:00Z" } }
      )
      expect(described_class.parse(data).first.summary).to eq("Event at Wrigley Field")
    end

    it "handles an empty payload gracefully" do
      expect(described_class.parse({})).to eq([])
    end
  end
end
