# AI use and actual prompts

Codex assisted with R code, geographic data acquisition, debugging, report drafting, figures and validation. All numerical findings in the report are computed from the committed RDS inputs and official 2024 Census boundary archives. The report is a generated artifact of `R/homework6.R`.

## Examples from the conversation

- Homework 5 request: “你可以帮我完成吗” (Can you help me complete it?), following the assignment instructions and screenshots. The work prepared the JSON import, New Orleans filtering and RDS outputs.
- Review request: “这里面事已经符合要求了吗。你帮我在检查一次” (Does this meet the requirements? Please check again.) This prompted checks of filtering, review IDs, readable RDS files and GitHub contents.
- Homework 6 context: “现在老师要求这个” (The teacher now requires this), with the Homework 6 screenshot: choose and defend a geographic area through Step 6, with a table and/or maps.
- Follow-up: “你可以帮我完成这个嘛” (Can you help me complete this?). Codex reused the Homework 5 data, selected a coherent category theme, compared tracts and block groups, and drafted the analysis.

## Decisions and revisions during this work

The user did not prescribe the categories or geographic system. Codex proposed Seafood, Cajun/Creole and Southern and chose tracts after checking area counts and sparsity. Broad substring inspection initially counted 332 Seafood-related labels; exact comma-separated category matching yields 331 businesses labeled Seafood, avoiding inclusion of a different label such as Seafood Markets merely because it contains that word.

An initial area-summary run failed because a summed review-count column shadowed the original weights inside `summarise()`. The calculation order was corrected so the weighted rating uses each restaurant's review count before that column is aggregated. The final script was rerun successfully.

Boundary mismatches were retained in audit tables rather than discarded. The resulting report distinguishes Yelp city labels, official place polygons and Orleans Parish statistical areas. No reviewer-normalized score or final recommendation is claimed at this stage.
