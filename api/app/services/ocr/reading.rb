module Ocr
  # One field value exactly as read, its confidence (0 to 100) and its level (:high or :low).
  Reading = Data.define(:value, :confidence, :level)
end
