![CrowdStrike Falcon](/images/cs-logo.png?raw=true)

[![CrowdStrike Subreddit](https://img.shields.io/badge/-r%2Fcrowdstrike-white?logo=reddit&labelColor=gray&link=https%3A%2F%2Freddit.com%2Fr%2Fcrowdstrike)](https://reddit.com/r/crowdstrike)

# Contributing to this repository

![Hollywood Adversaries](/images/hollywood-adversaries.jpg?raw=true)

Please review this document for details regarding getting started with your first contribution, packages you'll need to install as a developer, and our Pull Request process. If you have any questions, please let us know by posting your question as an [issue](https://github.com/CrowdStrike/foundry-skills/issues).

> **Before you begin**: Have you read the [Code of Conduct](CODE_OF_CONDUCT.md)?
> The Code of Conduct helps us establish community norms and how they'll be enforced.

## Issues

Issues are very valuable to this project.

- Ideas are a valuable source of contributions others can make
- Problems show where this project is lacking
- With a question you show where contributors can improve the user
  experience

Thank you for creating them.

## Pull Requests

Pull requests are a great way to get your ideas into this repository.

When deciding if we merge in a pull request we look at the following
things:

### Does it state intent

You should be clear which problem you're trying to solve with your
contribution.

For example:

> Add link to code of conduct in README.md

Doesn't tell me anything about why you're doing that

> Add link to code of conduct in README.md because users don't always
> look in the CONTRIBUTING.md

Tells us the problem that you have found, and the pull request shows us
the action you have taken to solve it.

### Is it of good quality

- There are no spelling mistakes
- It reads well
- For english language contributions: Has a good score on
  [Grammarly](https://www.grammarly.com) or [Hemingway
  App](https://www.hemingwayapp.com/)

### Does it move this repository closer to our vision for the repository

The aim of this repository is:

- To provide AI coding assistant skills for building Falcon Foundry apps
- The content is usable by someone who hasn't built a Foundry app before
- Foster a culture of respect and gratitude in the open source
  community.

### Does it follow the contributor covenant

This repository has a [code of conduct](CODE_OF_CONDUCT.md), we will
remove things that do not respect it.

### PR title and description style

PR titles should be short (under 70 characters) and describe the change, not the process. Descriptions should lead with *why* the change exists, not summarize what files were touched. A reader should understand the motivation from the first sentence.

Write in natural flowing sentences. Avoid artificial line breaks, bullet-heavy formatting, and filler phrases like "This PR introduces" or "Changes include." Bullet points are fine when listing multiple discrete items, but default to prose.

Keep it concise. If you can say it in one paragraph, don't use three. Skip "Summary" headings, "Test plan" sections, and reviewer @mentions in the body. The diff speaks for itself. Here's what a good PR description looks like, followed by what to avoid:

Good:
> Foundry CLI v2.0.1 auto-detects headless environments, eliminating the need for `FOUNDRY_UI_HEADLESS_MODE`. This removes the env var handling from the SessionStart hook and CLI guard check, plus all command-line prefixes from test scripts. The hook now checks the CLI version and offers an upgrade prompt for users below 2.0.1, with a fallback for older versions.

Bad:
> ## Summary
> This PR introduces several important updates to the hook scripts, enhancing reliability and improving the overall developer experience.
>
> ## Changes
> - Updated set-foundry-env.sh
> - Updated foundry-cli-guard.sh
> - Updated test-hooks.sh
>
> ## Test plan
> - [ ] Verify hooks work correctly

## AI-Assisted Contributions

AI coding assistants are welcome for developing contributions to this project. If your tool needs project context, see [`AGENTS.md`](AGENTS.md) for orientation or [`CLAUDE.md`](CLAUDE.md) for Claude Code-specific plugin guidance. The bar for pull requests is the same regardless of how code was written. Pay extra attention to the [PR title and description style](#pr-title-and-description-style) section since AI tools tend to generate verbose, formulaic PR descriptions that don't match the style we're looking for.

---

<p align="center"><img src="/images/cs-logo-footer.png"><br/><img width="300px" src="/images/turbine-panda.png"></p>
<h3><p align="center">WE STOP BREACHES</p></h3>
