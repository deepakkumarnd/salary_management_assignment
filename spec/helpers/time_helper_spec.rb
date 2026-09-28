require "rails_helper"

RSpec.describe TimeHelper, type: :helper do
  describe "#local_time" do
    it "renders a <time> in UTC that the browser rewrites in the viewer's time zone" do
      html = helper.local_time(Time.utc(2026, 9, 28, 9, 40))

      expect(html).to eq(
        '<time datetime="2026-09-28T09:40:00Z" data-controller="local-time">28 Sep 2026, 09:40 UTC</time>'
      )
    end

    it "converts times from any zone to UTC" do
      time = Time.find_zone("Asia/Kolkata").local(2026, 9, 28, 15, 10)
      expect(helper.local_time(time)).to include('datetime="2026-09-28T09:40:00Z"', "28 Sep 2026, 09:40 UTC")
    end
  end
end
