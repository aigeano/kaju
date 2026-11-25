# Homebrew formula for kaju, for the tap github.com/aigeano/homebrew-tap
# (copy to Formula/kaju.rb there). Install with: brew install aigeano/tap/kaju
#
# kaju is built from source on the user's Mac, so Gatekeeper does not get
# involved and no Apple Developer account is needed.
class Kaju < Formula
  include Language::Python::Virtualenv

  desc "Annotate, comment and collaborate with Claude Code from your terminal"
  homepage "https://github.com/aigeano/kaju"
  url "https://github.com/aigeano/kaju/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "Apache-2.0"

  depends_on macos: :ventura
  depends_on "python@3.13"

  # Python packages for the iTerm2 helper; installed into a private
  # virtualenv, never bundled. iterm2 is GPL-2.0-or-later.
  resource "iterm2" do
    url "https://files.pythonhosted.org/packages/36/a8/e88133c8b7418bd0905859a2f9dd0f5388c5a394434790e46e54cf15678c/iterm2-2.30.tar.gz"
    sha256 "eaa814b64f11d58984dfa02e790016983e7c4eb4f41cceae174ba361708200ec"
  end

  resource "protobuf" do
    url "https://files.pythonhosted.org/packages/66/70/e908e9c5e52ef7c3a6c7902c9dfbb34c7e29c25d2f81ade3856445fd5c94/protobuf-6.33.6.tar.gz"
    sha256 "a6768d25248312c297558af96a9f9c929e8c4cee0659cb07e780731095f38135"
  end

  resource "websockets" do
    url "https://files.pythonhosted.org/packages/21/e6/26d09fab466b7ca9c7737474c52be4f76a40301b08362eb2dbc19dcc16c1/websockets-15.0.1.tar.gz"
    sha256 "82544de02076bafba038ce055ee6412d68da13ab47f0c60cab827346de828dee"
  end

  def install
    venv = virtualenv_create(libexec/"venv", "python3.13")
    venv.pip_install resources
    # SwiftPM's own sandbox clashes with Homebrew's build sandbox.
    system "make", "app", "VERSION=#{version}", "PYTHON_PATH=#{opt_libexec}/venv/bin/python"
    prefix.install "build/kaju.app"
    bin.write_exec_script prefix/"kaju.app/Contents/MacOS/kaju"
  end

  service do
    run opt_prefix/"kaju.app/Contents/MacOS/kaju"
    environment_variables PATH: std_service_path_env
    run_type :immediate
    keep_alive crashed: true
    process_type :interactive
  end

  def caveats
    <<~EOS
      Start kaju now and at login:
        brew services start kaju

      After `brew upgrade kaju`, restart it (the old build keeps running otherwise):
        brew services restart kaju

      macOS asks again for Automation (iTerm2, Terminal) and Accessibility
      (Terminal.app and other terminals) after each upgrade: kaju clears its
      old approvals on the first start of a new build. If a permission still
      looks enabled but kaju cannot use it, choose "Reset permissions" in
      kaju's menu.

      iTerm2 users: enable iTerm2 > Settings > General > Magic > Enable Python API.
    EOS
  end

  test do
    assert_predicate prefix/"kaju.app/Contents/MacOS/kaju", :executable?
    assert_match "io.github.aigeano.kaju", shell_output("/usr/bin/codesign -dv #{prefix}/kaju.app 2>&1")
  end
end
