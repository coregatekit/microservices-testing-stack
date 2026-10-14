# Agent Rules

## Secrets and environment files

- Do NOT read the contents of any `.env` file (e.g. `.env`, `.env.local`, `.env.*`, `*.env`) or any `mise` config file that holds local or secret values (`mise.local.toml`, `mise.<env>.toml`, e.g. `mise.dev.toml`, `mise.prod.toml`), or any other file that holds secret configuration, using any tool (Read, Grep, cat, head, tail, less, sed, awk, or similar).
- Do NOT print, echo, log, copy, or quote values from these files in responses, commits, PR descriptions, or files you write.
- Do NOT source or load `.env` files into the shell to inspect their values (e.g. `source .env`, `export $(cat .env)`). Do not run `mise` commands that dump the env or config values of these files (e.g. `mise env`, `mise config`) to inspect them.
- To find out which variables a project expects, use the committed template files instead (e.g. `.env.example`, `.env.sample`, `.env.template`, or a committed `mise.toml`) or the code that reads the variables. Do not infer secret values from them.
- If a task needs a value that is only defined in a `.env` or `mise.<env>.toml` file, stop and ask the user to provide the value or confirm the variable name. Do not work around this restriction.
- Do NOT list or search inside these files with `grep`/`rtk grep` or similar, even for variable names. Searching for a variable name in source code is allowed.
- Never stage, commit, or push `.env` or `mise.local.toml` / `mise.<env>.toml` files. Confirm they are covered by `.gitignore` before committing new config files.

**Why:** `.env` files contain credentials and secrets. Reading them exposes those values to the conversation, logs, and model context.
