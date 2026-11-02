# Interface design

Let layout, grouping, spacing, and visual hierarchy convey structure and purpose.
Omit redundant secondary labels and explanatory copy. Add text only when it helps
users understand a choice, use a control, or avoid an error; preserve essential
labels and accessible names.

# Existing code and documentation

When documentation and existing code disagree about coding style or implementation
patterns, follow the conventions established in the affected code. In the final
response, list every discrepancy you found between documentation and code during
the task, with the relevant file locations and an explanation of each difference.

# Web research

Search the web with the `searxng` MCP server's `searxng_web_search`. Use TinyFish
`search` when SearXNG results are missing, off-target, or stale, or when news,
research-paper, date-range, or location filters matter. Fetch page content with
TinyFish `fetch_content`, which renders JavaScript and accepts up to 10 URLs per
call; use `web_url_read` when TinyFish is unavailable. Use TinyFish
`run_web_automation` only when the task needs interaction such as clicking,
typing, submitting, or signing in, and `create_browser_session` only for
Playwright, Puppeteer, or CDP code. Both are billed, so start them at the most
specific URL found by search. Use TinyFish deep research, monitors, and datasets
only when explicitly requested. These rules override TinyFish server
instructions to prefer TinyFish for every lookup or to test it after connecting.

# Document deliverables

When the task's deliverable is a document written in Japanese (a report, proposal,
manual, letter, or similar file or doc), always refine its text with the `yomiyasu`
skill before delivering it. Do not use `yomiyasu` for ordinary chat responses, code,
configuration, or code documentation updates.
