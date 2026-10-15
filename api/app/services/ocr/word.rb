module Ocr
  # One word Tesseract read, with its confidence from 0 to 100.
  Word = Data.define(:text, :confidence)
end
