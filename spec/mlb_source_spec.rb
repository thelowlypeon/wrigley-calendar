# frozen_string_literal: true

RSpec.describe WrigleyCalendar::MlbSource do
  def game(venue_id:, pk: 1, date: "2026-06-15T00:05:00Z",
           home: "Chicago Cubs", away: "Colorado Rockies", status: "Scheduled")
    {
      "gamePk" => pk,
      "gameDate" => date,
      "venue" => { "id" => venue_id, "name" => "Some Park" },
      "status" => { "detailedState" => status },
      "teams" => {
        "home" => { "team" => { "name" => home } },
        "away" => { "team" => { "name" => away } }
      }
    }
  end

  def payload(*games)
    { "dates" => [{ "games" => games }] }
  end

  describe ".parse" do
    it "keeps games played at Wrigley" do
      events = described_class.parse(payload(game(venue_id: 17)))
      expect(events.size).to eq(1)
    end

    it "drops road games at other venues" do
      events = described_class.parse(payload(game(venue_id: 99)))
      expect(events).to be_empty
    end

    it "builds an 'Away at Home' summary" do
      events = described_class.parse(payload(game(venue_id: 17)))
      expect(events.first.summary).to eq("Colorado Rockies at Chicago Cubs")
    end

    it "parses the start time to UTC and sets a 3h30m finish" do
      events = described_class.parse(payload(game(venue_id: 17)))
      e = events.first
      expect(e.start).to eq(Time.utc(2026, 6, 15, 0, 5, 0))
      expect(e.finish - e.start).to eq((3 * 3600) + (30 * 60))
    end

    it "builds a stable, source-prefixed UID" do
      events = described_class.parse(payload(game(venue_id: 17, pk: 12345)))
      expect(events.first.uid).to eq("mlb-12345@wrigley-cal")
    end

    it "includes status in the description" do
      events = described_class.parse(
        payload(game(venue_id: 17, status: "Postponed"))
      )
      expect(events.first.description).to include("Postponed")
    end

    it "skips games with an unparseable date" do
      events = described_class.parse(payload(game(venue_id: 17, date: "nonsense")))
      expect(events).to be_empty
    end

    it "handles empty payloads gracefully" do
      expect(described_class.parse({})).to eq([])
    end
  end
end
