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
