class Agentdesk < Formula
  desc "Run an AI agent on your Mac at the same time as you, on a hidden desk"
  homepage "https://github.com/makors/agentdesk"
  url "https://github.com/makors/agentdesk/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "08d48de06a5ba173d09163f358469d29642f99916abd6b7d4aa438cc8a313e6f"
  license "MIT"

  depends_on :macos

  def install
    %w[oracle axact agentdesk-daemon hidden-display].each do |t|
      system "clang", "-Wno-deprecated-declarations", "-fobjc-arc", "-fmodules",
             "-framework", "AppKit", "-framework", "ApplicationServices",
             "src/#{t}.m", "-o", "#{buildpath}/#{t}"
      libexec.install t
    end
    libexec.install "cli/agentdesk"
    libexec.install "mcp/agentdesk_mcp.py"
    (bin/"agentdesk").write <<~SH
      #!/bin/bash
      exec /usr/bin/python3 "#{libexec}/agentdesk" "$@"
    SH
    chmod 0755, bin/"agentdesk"
  end

  def caveats
    <<~EOS
      agentdesk needs Accessibility permission for whatever launches it
      (your terminal, or the ChatGPT app that runs its MCP server):
        System Settings > Privacy & Security > Accessibility

      To wire it into Codex / the ChatGPT app, run:
        agentdesk mcp
      and paste the block into ~/.codex/config.toml, then restart the app.
    EOS
  end

  test do
    assert_match "up", shell_output("#{bin}/agentdesk 2>&1", 0)
  end
end
