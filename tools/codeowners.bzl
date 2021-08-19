def _codeowners_impl(ctx):
    path = "/" + ctx.label.package + "/"

    # The PATH will be set to the empty string,
    # if the codeowners is defined in the ROOT of the WORKSPACE
    if ctx.label.package == "":
        path = ""

    if len(ctx.attr.team) == 0 and len(ctx.attr.teams) == 0:
        fail("Either team or teams must be set.")
    if len(ctx.attr.team) > 0 and len(ctx.attr.teams) > 0:
        fail("Both team and teams can not be set at the same time.")
    if len(ctx.attr.pattern) > 0 and len(ctx.attr.patterns) > 0:
        fail("Both pattern and patterns can not be set at the same time.")

    teams = ctx.attr.teams
    if len(ctx.attr.team) > 0:
        teams = [ctx.attr.team]

    # Default to empty pattern (matching path only)
    patterns = [""]
    if len(ctx.attr.patterns) > 0:
        patterns = ctx.attr.patterns
    elif len(ctx.attr.pattern) > 0:
        patterns = [ctx.attr.pattern]

    content = "\n".join(["%s%s %s" % (path, pattern, " ".join(teams)) for pattern in patterns])

    ctx.actions.write(
        output = ctx.outputs.outfile,
        content = content
    )

codeowners = rule(
    implementation = _codeowners_impl,
    doc = """
A codeowners-rule represents one or many rows in a CODEOWNERS file.

`team` and `teams` are mutually exclusive.
`pattern` and `patterns` are mutually exclusive.
""",
    attrs = {
        "team": attr.string(mandatory = False, doc = "The GitHub team that should get ownership of the matching files. One of team and teams must be set."),
        "teams": attr.string_list(mandatory = False, doc = "A list of the GitHub teams that should get ownership of the matching files. One of team and teams must be set."),
        "pattern": attr.string(mandatory = False, doc = "A pattern of files (eg: '*.bzl') that the team(s) should get ownership of. In the generated CODEOWNERS, the path to this target will be prepended to the pattern."),
        "patterns": attr.string_list(mandatory = False, doc = "A list of patterns, one row will be printed per pattern. See docs of `pattern` for more info."),
    },
    outputs = {
        "outfile": "%{name}.out",
    },
)

def _generate_codeowners_impl(ctx):
    all_ownership_files = [file for owner in ctx.attr.owners for file in owner.files.to_list()]

    args = []

    for file in all_ownership_files:
        args.append(file.path)

        # Use the path to the target, and validate that all rows in the output matches
        # this path.
        must_have_prefix = file.path[len(file.root.path):-len(file.basename)]

        if must_have_prefix == "/":
            must_have_prefix = ""

        args.append(must_have_prefix)

    ctx.actions.run_shell(
        outputs = [ctx.outputs.outfile],
        inputs = all_ownership_files,
        arguments = args,
        env = {
            "OUTFILE": ctx.outputs.outfile.path,
        },
        command = """
set -euo pipefail

echoerr() {
    echo "$@" 1>&2;
    exit 1
}

prevent_malicios_input () {
    must_have_prefix=$1
    INPUT=$(cat)
    set +e
    echo -n "$INPUT" | grep -E "${must_have_prefix}" || echoerr "Potentially malicious input detected, path did not match '${must_have_prefix}' (input = '${INPUT}')"
    set -e
}

skip_comments () {
    grep -v "#"
}

skip_empty_rows () {
    grep -v -E '^$'
}

echo "_GENERATED_COMMENT_" >> "$OUTFILE"
echo "" >> "$OUTFILE"

while [ "$#" -gt 0 ]; do
    file=$1
    must_have_prefix=$2
    shift
    shift

    cat "$file" | \
        skip_comments  | \
        skip_empty_rows | \
        prevent_malicios_input "$must_have_prefix" >> "$OUTFILE"
done
        """.replace("_GENERATED_COMMENT_", ctx.attr.generated_comment),
    )

generate_codeowners = rule(
    implementation = _generate_codeowners_impl,
    doc = """
Creates a GitHub-compatible CODEOWNERS file based on the `owners`.
""",
    attrs = {
        "generated_comment": attr.string(
            doc = "A comment to insert at the top of the generated file",
            default = "# This file was generated by rules_codeowners / Bazel. Don't edit it directly",
        ),
        "owners": attr.label_list(mandatory = True, doc = "A list of codeowners and generate_codeowners. One generate_codeowners can include another generate_codeowners to achieve nested rules."),
    },
    outputs = {
        "outfile": "%{name}.out",
    },
)
