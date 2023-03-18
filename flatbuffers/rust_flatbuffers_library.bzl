load("//flatbuffers/internal:flatbuffers_lang_toolchain.bzl", "FlatbuffersLangToolchainInfo")
load("//flatbuffers/internal:flatbuffers_toolchain.bzl", "FlatbuffersToolchainInfo")
load("//flatbuffers/internal:run_flatc.bzl", "run_flatc")
load("//flatbuffers/internal:string_utils.bzl", "replace_extension")
load("//flatbuffers/toolchain_defs:rust_defs.bzl", "RUST_LANG_TOOLCHAIN")
load("//flatbuffers/toolchain_defs:toolchain_defs.bzl", "FLATBUFFERS_TOOLCHAIN")
load("//flatbuffers:flatbuffers_library.bzl", "FlatbuffersInfo")

DEFAULT_SUFFIX = "_generated"
RUST_HEADER_FILE_EXTENSION = "h"

FlatbuffersRustInfo = provider(fields = {
    "headers": "header files for this target (non-transitive)",
    "headers_transitive": "depset of generated headers",
    "includes": "includes for this target (non-transitive)",
    "includes_transitive": "depset of includes",
})

def _flatbuffers_rust_info_aspect_impl(target, ctx):
    headers = [
        ctx.actions.declare_file(replace_extension(
            string = src.basename,
            old_extension = src.extension,
            new_extension = RUST_HEADER_FILE_EXTENSION,
            suffix = DEFAULT_SUFFIX,
        ))
        for src in target[FlatbuffersInfo].srcs
    ]
    headers_transitive = depset(
        direct = headers,
        transitive = [dep[FlatbuffersRustInfo].headers_transitive for dep in ctx.rule.attr.deps],
    )
    run_flatc(
        ctx = ctx,
        fbs_toolchain = ctx.attr._fbs_toolchain[FlatbuffersToolchainInfo],
        fbs_lang_toolchain = ctx.attr._fbs_lang_toolchain[FlatbuffersLangToolchainInfo],
        srcs = target[FlatbuffersInfo].srcs,
        srcs_transitive = target[FlatbuffersInfo].srcs_transitive,
        includes_transitive = target[FlatbuffersInfo].includes_transitive,
        outputs = headers,
    )

    # NOTE: It just so happens that we can re-use the flatbuffer includes for our rust target too.
    return FlatbuffersRustInfo(
        headers = headers,
        headers_transitive = headers_transitive,
        includes = target[FlatbuffersInfo].includes,
        includes_transitive = target[FlatbuffersInfo].includes_transitive,
    )

def _rust_flatbuffers_genrule_impl(ctx):
    # Merge the outputs from the hard work already done by the aspect.
    toolchain = ctx.attr._fbs_lang_toolchain[FlatbuffersLangToolchainInfo]
    headers_transitive = depset(
        transitive = [dep[FlatbuffersRustInfo].headers_transitive for dep in ctx.attr.deps],
    )
    includes_transitive = depset(
        transitive = [dep[FlatbuffersRustInfo].includes_transitive for dep in ctx.attr.deps],
    )
    rust_info = RustInfo(
        compilation_context = rust_common.create_compilation_context(
            headers = headers_transitive,
            includes = includes_transitive,
        ),
    )
    return [
        DefaultInfo(files = headers_transitive),
        rust_common.merge_rust_infos(
            direct_rust_infos = [rust_info],
            rust_infos = [toolchain.runtime[RustInfo]],
        ),
    ]

flatbuffers_rust_info_aspect = aspect(
    implementation = _flatbuffers_rust_info_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_fbs_toolchain": attr.label(
            providers = [FlatbuffersToolchainInfo],
            default = FLATBUFFERS_TOOLCHAIN,
        ),
        "_fbs_lang_toolchain": attr.label(
            providers = [FlatbuffersLangToolchainInfo],
            default = RUST_LANG_TOOLCHAIN,
        ),
    },
)

rust_flatbuffers_genrule = rule(
    attrs = {
        "deps": attr.label_list(
            aspects = [flatbuffers_rust_info_aspect],
            providers = [FlatbuffersInfo],
        ),
        "_fbs_toolchain": attr.label(
            providers = [FlatbuffersToolchainInfo],
            default = FLATBUFFERS_TOOLCHAIN,
        ),
        "_fbs_lang_toolchain": attr.label(
            providers = [FlatbuffersLangToolchainInfo],
            default = RUST_LANG_TOOLCHAIN,
        ),
    },
    output_to_genfiles = True,
    implementation = _rust_flatbuffers_genrule_impl,
)

def rust_flatbuffers_library(name, deps, **kwargs):
    genrule_name = name + "_genrule"
    rust_flatbuffers_genrule(
        name = genrule_name,
        deps = deps,
    )
    native.rust_library(
        name = name,
        deps = [":" + genrule_name],
        **kwargs
    )
