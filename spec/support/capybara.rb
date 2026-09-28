RSpec.configure do |config|
  # System specs render the real stylesheet, so compile Tailwind once per run (~0.2s) rather than rely on a
  # possibly stale app/assets/builds/tailwind.css.
  config.before(:suite) do
    if RSpec.world.example_groups.any? { it.metadata[:type] == :system }
      system("bin/rails tailwindcss:build", out: File::NULL, err: File::NULL, exception: true)
    end
  end

  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
  end
end
