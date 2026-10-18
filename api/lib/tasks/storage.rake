namespace :storage do
  desc "Create the private STORAGE_BUCKET in Supabase Storage unless it exists (runs on every deploy)"
  task ensure_bucket: :environment do
    bucket = ENV.fetch("STORAGE_BUCKET")
    result = Storage::Client.default.ensure_bucket
    message = { created: "created (private)", exists: "already exists", made_private: "existed as public; made private" }
    puts "storage: bucket #{bucket} #{message.fetch(result)}"
  end
end
