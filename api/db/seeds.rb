# Loads open slots, the demo users and the golden set check, and prints the demo credentials.
# Idempotent: run it again at any time with bin/rails db:seed. See Seeds::DemoData.
Seeds::DemoData.default.call
