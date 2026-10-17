require "rails_helper"

# R22, R23, R24: the percentile and summary math behind the numbers in docs/performance.md.
RSpec.describe Perf::Stats do
  describe ".percentile (nearest rank)" do
    it "returns nil for no samples" do
      expect(described_class.percentile([], 95)).to be_nil
    end

    it "returns the only sample for one sample" do
      expect(described_class.percentile([ 42 ], 95)).to eq(42)
    end

    it "takes the 19th of 20 sorted samples as the p95" do
      samples = (1..20).to_a.shuffle(random: Random.new(1))
      expect(described_class.percentile(samples, 95)).to eq(19)
    end

    it "takes the 95th of 100 samples as the p95 and the 50th as the p50" do
      samples = (1..100).to_a.reverse
      expect(described_class.percentile(samples, 95)).to eq(95)
      expect(described_class.percentile(samples, 50)).to eq(50)
    end

    it "rounds the rank up between samples" do
      # 95% of 10 is 9.5, so the nearest rank is the 10th sample.
      expect(described_class.percentile((1..10).to_a, 95)).to eq(10)
    end

    it "returns the largest sample for p100 and the smallest for a tiny percentile" do
      expect(described_class.percentile([ 5, 1, 9 ], 100)).to eq(9)
      expect(described_class.percentile([ 5, 1, 9 ], 1)).to eq(1)
    end

    it "agrees with the eval harness's p95 on the same samples" do
      samples = [ 812.0, 1_204.5, 950.2, 3_100.0, 640.1, 1_999.9, 720.0 ]
      expect(described_class.percentile(samples, 95)).to eq(samples.sort[((samples.size * 95) + 99) / 100 - 1])
    end

    it "rejects a percentile outside 0 to 100" do
      expect { described_class.percentile([ 1 ], 0) }.to raise_error(ArgumentError)
      expect { described_class.percentile([ 1 ], 101) }.to raise_error(ArgumentError)
    end
  end

  describe ".summary" do
    it "reports count, min, mean, p50, p95 and max, rounded to 0.1" do
      summary = described_class.summary([ 100.04, 200.0, 300.0, 400.0 ])
      expect(summary).to eq(count: 4, min: 100.0, mean: 250.0, p50: 200.0, p95: 400.0, max: 400.0)
    end

    it "reports only a zero count for no samples" do
      expect(described_class.summary([])).to eq(count: 0, min: nil, mean: nil, p50: nil, p95: nil, max: nil)
    end
  end

  describe ".rate" do
    it "is the share of failures, or 0 with no requests" do
      expect(described_class.rate(1, 20)).to eq(0.05)
      expect(described_class.rate(0, 0)).to eq(0.0)
    end
  end
end
