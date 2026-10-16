namespace :ai do
  namespace :eval do
    desc "Print per-field OCR accuracy on the golden set (GOLDEN_DIR, default eval/golden), hard cases separately"
    task ocr: :environment do
      golden_dir = ENV.fetch("GOLDEN_DIR", Rails.root.join("eval/golden").to_s)
      report = Eval::OcrScorer.new(golden_dir: golden_dir).call

      puts "OCR golden set: #{report[:counts][:all]} documents in #{golden_dir}"
      puts "Engine: #{Ocr::Extractor.version || 'tesseract not found'}"
      { "All documents" => :all, "Hard cases" => :hard }.each do |title, key|
        puts "#{title} (#{report[:counts][key]})"
        report[key].each { |field, accuracy| puts format("  %-14s %5.1f%%", field, accuracy * 100) }
      end
      next if report[:misses].empty?

      puts "Misses"
      report[:misses].each do |miss|
        puts "  #{miss[:id]} #{miss[:field]}: expected #{miss[:expected].inspect}, read #{miss[:read].inspect}"
      end
    end
  end
end

namespace :ai do
  desc "Score OCR and the chat sets on LLM_PROVIDER, or on every candidate with PROVIDERS=all; " \
       "writes a results file to eval/results (RESULTS_DIR)"
  task eval: :environment do
    golden_dir = ENV.fetch("GOLDEN_DIR", Rails.root.join("eval/golden").to_s)
    Eval::Harness.new(
      env: ENV.to_h,
      ocr_scorer: Eval::OcrScorer.new(golden_dir: golden_dir),
      results_dir: ENV.fetch("RESULTS_DIR", Eval::Harness::DEFAULT_RESULTS_DIR.to_s),
      pacing: Eval::Harness::FREE_TIER_PACING
    ).call
  end
end
