module Perf
  # Percentiles and summaries for the performance runs (R22, R23, R24). Nearest rank, the same
  # method as the eval harness's p95: the smallest sample with at least pct% of samples at or below
  # it, so a reported p95 is always a time that was actually measured.
  module Stats
    module_function

    def percentile(samples, pct)
      raise ArgumentError, "percentile must be in (0, 100], got #{pct}" unless pct.positive? && pct <= 100
      return if samples.empty?

      rank = ((samples.size * pct) / 100.0).ceil
      samples.sort[rank - 1]
    end

    def summary(samples)
      return { count: 0, min: nil, mean: nil, p50: nil, p95: nil, max: nil } if samples.empty?

      {
        count: samples.size,
        min: samples.min.round(1),
        mean: (samples.sum.to_f / samples.size).round(1),
        p50: percentile(samples, 50).round(1),
        p95: percentile(samples, 95).round(1),
        max: samples.max.round(1)
      }
    end

    def rate(failures, total)
      total.zero? ? 0.0 : failures.to_f / total
    end
  end
end
