require "open3"

module Ocr
  # Reads the text of a document image: libvips preprocessing (grayscale, resize to a fixed
  # working width, glare and lighting flattening, deskew), then Tesseract with a confidence for
  # every word. Flattening divides by the local background, so Tesseract's own global threshold
  # acts as an adaptive one.
  # Never raises: any failure comes back as a failed Ocr::Extraction.
  class Extractor
    WORKING_WIDTH = 1600
    DESKEW_WIDTH = 600
    DESKEW_MAX_ANGLE = 6
    DESKEW_FINE_STEP = 0.25
    TIMEOUT_SECONDS = 20
    # Smallest paper-to-ink difference that gets stretched to full contrast, so plain paper
    # noise isn't amplified into specks.
    MIN_CONTRAST = 60

    # The Tesseract version line, such as "tesseract 5.5.3", or nil when it can't be run.
    def self.version
      output, status = Open3.capture2e("tesseract", "--version")
      status.success? ? output.lines.first.strip : nil
    rescue SystemCallError
      nil
    end

    def call(path)
      Dir.mktmpdir("ocr") do |dir|
        prepared = File.join(dir, "prepared.png")
        preprocess(path).write_to_file(prepared)
        Extraction.new(lines: tesseract(prepared))
      end
    rescue StandardError => error
      Extraction.failure("#{error.class}: #{error.message}".truncate(200))
    end

    private

    def preprocess(path)
      raise Errno::ENOENT, "no file at the given path" unless File.file?(path)

      image = Vips::Image.new_from_file(path).autorot
      image = image.flatten(background: 255) if image.has_alpha?
      image = image.colourspace(:b_w)[0].cast(:uchar)
      image = image.resize(WORKING_WIDTH.fdiv(image.width), kernel: :cubic)
      # Kept in memory: libvips is lazy, and deskew reads the image many times.
      deskew(flatten_lighting(image).copy_memory)
    end

    # Divides by a heavily blurred copy so glare and uneven light become an even white page.
    # Stretches contrast locally: the local paper level becomes white and the local ink level
    # black, so glare and uneven light don't wash text out. The paper and ink levels are
    # estimated at an eighth of the size, which is much faster and smooth enough.
    def flatten_lighting(image)
      small = image.resize(0.125)
      paper = small.gaussblur(WORKING_WIDTH / 320.0)
      ink = small.rank(9, 9, 0).gaussblur(WORKING_WIDTH / 320.0)
      paper, ink = [ paper, ink ].map do |level|
        level.resize(image.width.fdiv(small.width), vscale: image.height.fdiv(small.height), kernel: :linear)
      end
      range = paper - ink
      range = (range < MIN_CONTRAST).ifthenelse(MIN_CONTRAST, range)
      ((image - paper) * 255 / range + 255).cast(:uchar)
    end

    # Finds the rotation that makes text rows sharpest (the largest variance of row sums), first
    # in whole degrees and then in quarter degrees around the best one, and rotates the page.
    def deskew(image)
      ink = (image.resize(DESKEW_WIDTH.fdiv(image.width)) < 128).ifthenelse(1, 0).cast(:uchar).copy_memory
      sharpest = ->(angles) { angles.max_by { |angle| row_sharpness(ink.rotate(angle, background: [ 0 ])) } }
      coarse = sharpest.call((-DESKEW_MAX_ANGLE..DESKEW_MAX_ANGLE).to_a)
      angle = sharpest.call((-3..3).map { |step| coarse + step * DESKEW_FINE_STEP })
      return image if angle.zero?

      image.rotate(angle, background: [ 255 ])
    end

    def row_sharpness(ink)
      _columns, rows = ink.project
      sums = rows.to_a.flatten
      sums.each_cons(2).sum { |above, below| (below - above)**2 }
    end

    def tesseract(path)
      output = run("tesseract", path, "stdout", "--psm", "11", "-l", "eng", "tsv")
      # Columns: level page_num block_num par_num line_num word_num left top width height conf text.
      # Level 5 rows are words.
      rows = output.lines.drop(1).map { |line| line.chomp.split("\t", 12) }
      rows.select { |row| row[0] == "5" && row[11].to_s.strip.present? }
          .chunk_while { |a, b| a[1..4] == b[1..4] }
          .map { |line| line.map { |row| Word.new(text: row[11].strip, confidence: row[10].to_f.clamp(0, 100)) } }
    end

    def run(*command)
      Open3.popen3({ "OMP_THREAD_LIMIT" => "1" }, *command) do |stdin, stdout, stderr, wait|
        stdin.close
        out = Thread.new { stdout.read }
        err = Thread.new { stderr.read }
        timed_out = wait.join(TIMEOUT_SECONDS).nil?
        Process.kill("KILL", wait.pid) if timed_out
        # The readers finish once the process exits, so join them before the streams close.
        output = out.value
        errors = err.value
        raise "#{command.first} timed out" if timed_out
        raise "#{command.first} exited with status #{wait.value.exitstatus}: #{errors.lines.last}" unless wait.value.success?

        output
      end
    end
  end
end
