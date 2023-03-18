load("//flatbuffers/toolchain_defs:toolchain_defs.bzl", "toolchain_target_for_repo")

RUST_LANG_REPO = "rules_flatbuffers_rust_toolchain"
RUST_LANG_TOOLCHAIN = toolchain_target_for_repo(RUST_LANG_REPO)
RUST_LANG_SHORTNAME = "rust"
RUST_LANG_DEFAULT_RUNTIME = "@com_github_google_flatbuffers//:flatbuffers"
RUST_LANG_FLATC_ARGS = [
    "--rust",
    # This is necessary to preserve the directory hierarchy for generated headers to be relative to
    # the workspace root as bazel expects.
    "--keep-prefix",
]
RUST_LANG_DEFAULT_EXTRA_FLATC_ARGS = [
    "--gen-mutable",
    "--gen-name-strings",
    "--reflect-names",
]
