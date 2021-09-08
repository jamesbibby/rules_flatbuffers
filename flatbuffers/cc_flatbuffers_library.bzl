load("//flatbuffers:flatbuffers_lang_toolchain.bzl", "FlatbuffersLangToolchainInfo")
load("//flatbuffers:flatbuffers_library.bzl", "FlatbuffersInfo")
load("//flatbuffers/private:run_flatc.bzl", "run_flatc")
load("//flatbuffers/toolchains:cc_flatbuffers_toolchain.bzl", "DEFAULT_TOOLCHAIN")

DEFAULT_SUFFIX = "_generated"
CC_HEADER_FILE_EXTENSION = "h"

FlatbuffersCcInfo = provider(fields = {
    "headers": "header files for this target (non-transitive)",
    "headers_transitive": "depset of generated headers",
    "includes": "includes for this target (non-transitive)",
    "includes_transitive": "depset of includes",
})

def _cc_filename(string, old_extension, new_extension, suffix):
    return string.rpartition(old_extension)[0][:-1] + suffix + "." + new_extension

def _flatbuffers_cc_info_aspect_impl(target, ctx):
    headers = [
        ctx.actions.declare_file(_cc_filename(
            string = src.basename,
            old_extension = src.extension,
            new_extension = CC_HEADER_FILE_EXTENSION,
            suffix = DEFAULT_SUFFIX,
        ))
        for src in target[FlatbuffersInfo].srcs
    ]
    includes_transitive = depset(
        transitive = [dep[FlatbuffersInfo].includes_transitive for dep in ctx.rule.attr.deps],
    )
    headers_transitive = depset(
        direct = headers,
        transitive = [dep[FlatbuffersCcInfo].headers_transitive for dep in ctx.rule.attr.deps],
    )
    run_flatc(
        ctx = ctx,
        toolchain = ctx.attr._toolchain[FlatbuffersLangToolchainInfo],
        srcs = target[FlatbuffersInfo].srcs,
        srcs_transitive = target[FlatbuffersInfo].srcs_transitive,
        includes_transitive = includes_transitive,
        outputs = headers,
    )

    # NOTE: It just so happens that we can re-use the flatbuffer includes for our cc target too.
    return FlatbuffersCcInfo(
        headers = headers,
        headers_transitive = headers_transitive,
        includes = target[FlatbuffersInfo].includes,
        includes_transitive = target[FlatbuffersInfo].includes_transitive,
    )

def _cc_flatbuffers_genrule_impl(ctx):
    # Merge the outputs from the hard work already done by the aspect.
    toolchain = ctx.attr._toolchain[FlatbuffersLangToolchainInfo]
    headers_transitive = depset(
        transitive = [dep[FlatbuffersCcInfo].headers_transitive for dep in ctx.attr.deps],
    )
    includes_transitive = depset(
        transitive = [dep[FlatbuffersCcInfo].includes_transitive for dep in ctx.attr.deps],
    )
    cc_info = CcInfo(
        compilation_context = cc_common.create_compilation_context(
            headers = headers_transitive,
            includes = includes_transitive,
        ),
    )
    return [
        cc_common.merge_cc_infos(
            direct_cc_infos = [cc_info],
            cc_infos = [toolchain.runtime[CcInfo]],
        ),
    ]

# TODO(kgreenek): Figure out a way to explicitly pass the toolchain here. Currently, only an
# explicit attribute is allowed here.
flatbuffers_cc_info_aspect = aspect(
    implementation = _flatbuffers_cc_info_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_toolchain": attr.label(
            providers = [FlatbuffersLangToolchainInfo],
            default = DEFAULT_TOOLCHAIN,
        ),
    },
)

cc_flatbuffers_genrule = rule(
    attrs = {
        "deps": attr.label_list(
            aspects = [flatbuffers_cc_info_aspect],
            providers = [FlatbuffersInfo],
        ),
        "_toolchain": attr.label(
            providers = [FlatbuffersLangToolchainInfo],
            default = DEFAULT_TOOLCHAIN,
        ),
    },
    output_to_genfiles = True,
    implementation = _cc_flatbuffers_genrule_impl,
)

# TODO(kgreenek): Support passing a custom toolchain here. This is currently a limitation of
# using bazel aspects.
def cc_flatbuffers_library(name, deps, **kwargs):
    genrule_name = name + "_genrule"
    cc_flatbuffers_genrule(
        name = genrule_name,
        deps = deps,
    )
    native.cc_library(
        name = name,
        deps = [":" + genrule_name],
        **kwargs
    )
